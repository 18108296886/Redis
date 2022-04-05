source "../tests/includes/init-tests.tcl"

# Initial slot distribution.
set ::slot0 [list 0 1000 1002 5459 5461 5461 10926 10926]
set ::slot1 [list 5460 5460 5462 10922 10925 10925]
set ::slot2 [list 10923 10924 10927 16383]
set ::slot3 [list 1001 1001]

proc cluster_create_with_split_slots {masters replicas} {
    for {set j 0} {$j < $masters} {incr j} {
        R $j cluster ADDSLOTSRANGE {*}[set ::slot${j}]
    }
    if {$replicas} {
        cluster_allocate_slaves $masters $replicas
    }
    set ::cluster_master_nodes $masters
    set ::cluster_replica_nodes $replicas
}

# Get the node info with the specific node_id from the
# given reference node. Valid type options are "node" and "shard"
proc get_node_info_from_shard {id reference {type node}} {
    set shards_response [R $reference CLUSTER SHARDS]
    foreach shard_response $shards_response {
        set shard_id [dict get $shard_response shard-id]
        set nodes [dict get $shard_response nodes]
        foreach node $nodes {
            if {[dict get $node id] eq $id} {
                if {$type eq "node"} {
                    return $node
                } elseif {$type eq "shard"} {
                    return $shard_response
                } elseif {$type eq "shard-id"} {
                    return $shard_id
                } else {
                    return {}
                }
            }
        }
    }
    # No shard found, return nothing
    return {}
}

proc cluster_ensure_master {id} {
    if { [regexp "master" [R $id role]] == 0 } {
        assert_equal {OK} [R $id CLUSTER FAILOVER]
        wait_for_condition 50 100 {
            [regexp "master" [R $id role]] == 1
        } else {
            fail "instance $id is not master"
        }
    }
}

test "Create a 8 nodes cluster with 4 shards" {
    cluster_create_with_split_slots 4 4
}

test "Cluster should start ok" {
    assert_cluster_state ok
}

test "Set cluster hostnames and verify they are propagated" {
    for {set j 0} {$j < $::cluster_master_nodes + $::cluster_replica_nodes} {incr j} {
        R $j config set cluster-announce-hostname "host-$j.com"
    }

    # Wait for everyone to agree about the state
    wait_for_cluster_propagation
}

test "Verify information about the shards" {
    set ids {}
    for {set j 0} {$j < $::cluster_master_nodes + $::cluster_replica_nodes} {incr j} {
        lappend ids [R $j CLUSTER MYID]
    }
    set slots [list $::slot0 $::slot1 $::slot2 $::slot3 $::slot0 $::slot1 $::slot2 $::slot3]

    # Verify on each node (primary/replica), the response of the `CLUSTER SLOTS` command is consistent.
    for {set ref 0} {$ref < $::cluster_master_nodes + $::cluster_replica_nodes} {incr ref} {
        for {set i 0} {$i < $::cluster_master_nodes + $::cluster_replica_nodes} {incr i} {
            assert_equal [lindex $slots $i] [dict get [get_node_info_from_shard [lindex $ids $i] $ref "shard"] slots]
            assert_equal "host-$i.com" [dict get [get_node_info_from_shard [lindex $ids $i] $ref "node"] hostname]
            assert_equal "127.0.0.1"  [dict get [get_node_info_from_shard [lindex $ids $i] $ref "node"] ip]
            # Default value of 'cluster-preferred-endpoint-type' is ip.
            assert_equal "127.0.0.1"  [dict get [get_node_info_from_shard [lindex $ids $i] $ref "node"] endpoint]

            if {$::tls} {
                assert_equal [get_instance_attrib redis $i plaintext-port] [dict get [get_node_info_from_shard [lindex $ids $i] $ref "node"] port]
                assert_equal [get_instance_attrib redis $i port] [dict get [get_node_info_from_shard [lindex $ids $i] $ref "node"] tls-port]
            } else {
                assert_equal [get_instance_attrib redis $i port] [dict get [get_node_info_from_shard [lindex $ids $i] $ref "node"] port]
            }

            if {$i < 4} {
                assert_equal "master" [dict get [get_node_info_from_shard [lindex $ids $i] $ref "node"] role]
                assert_equal "online" [dict get [get_node_info_from_shard [lindex $ids $i] $ref "node"] health]
            } else {
                assert_equal "replica" [dict get [get_node_info_from_shard [lindex $ids $i] $ref "node"] role]
                # Replica could be in online or loading
            }
        }
    }
}

test "Verify no slot shard" {
    # Node 8 has no slots assigned
    set node_8_id [R 8 CLUSTER MYID]
    assert_equal {} [dict get [get_node_info_from_shard $node_8_id 8 "shard"] slots]
    assert_equal {} [dict get [get_node_info_from_shard $node_8_id 0 "shard"] slots]
}

set node_0_id [R 0 CLUSTER MYID]

test "Kill a node and tell the replica to immediately takeover" {
    kill_instance redis 0
    R 4 cluster failover force
}

# Primary 0 node should report as fail, wait until the new primary acknowledges it.
test "Verify health as fail for killed node" {
    wait_for_condition 50 100 {
        "fail" eq [dict get [get_node_info_from_shard $node_0_id 4 "node"] "health"]
    } else {
        fail "New primary never detected the node failed"
    }
}

set primary_id 4
set replica_id 0

test "Restarting primary node" {
    restart_instance redis $replica_id
}

test "Instance #0 gets converted into a replica" {
    wait_for_condition 1000 50 {
        [RI $replica_id role] eq {slave}
    } else {
        fail "Old primary was not converted into replica"
    }
}

test "Test the replica reports a loading state while it's loading" {
    # Test the command is good for verifying everything moves to a happy state
    set replica_cluster_id [R $replica_id CLUSTER MYID]
    wait_for_condition 50 1000 {
        [dict get [get_node_info_from_shard $replica_cluster_id $primary_id "node"] health] eq "online"
    } else {
        fail "Replica never transitioned to online"
    }

    # Set 1 MB of data, so there is something to load on full sync
    R $primary_id debug populate 1000 key 1000

    # Kill replica client for primary and load new data to the primary
    R $primary_id config set repl-backlog-size 100

    # Set the key load delay so that it will take at least
    # 2 seconds to fully load the data.
    R $replica_id config set key-load-delay 4000

    # Trigger event loop processing every 1024 bytes, this trigger
    # allows us to send and receive cluster messages, so we are setting
    # it low so that the cluster messages are sent more frequently.
    R $replica_id config set loading-process-events-interval-bytes 1024

    R $primary_id multi
    R $primary_id client kill type replica
    # populate the correct data
    set num 100
    set value [string repeat A 1024]
    for {set j 0} {$j < $num} {incr j} {
        # Use hashtag valid for shard #0
        set key "{ch3}$j"
        R $primary_id set $key $value
    }
    R $primary_id exec

    # The replica should reconnect and start a full sync, it will gossip about it's health to the primary.
    wait_for_condition 50 1000 {
        "loading" eq [dict get [get_node_info_from_shard $replica_cluster_id $primary_id "node"] health]
    } else {
        fail "Replica never transitioned to loading"
    }

    # Speed up the key loading and verify everything resumes
    R $replica_id config set key-load-delay 0

    wait_for_condition 50 1000 {
        "online" eq [dict get [get_node_info_from_shard $replica_cluster_id $primary_id "node"] health]
    } else {
        fail "Replica never transitioned to online"
    }

    # Final sanity, the replica agrees it is online.
    assert_equal "online" [dict get [get_node_info_from_shard $replica_cluster_id $replica_id "node"] health]
}

test "Shard ids are unique" {
    set shard_ids {}
    for {set i 0} {$i < 4} {incr i} {
        set shard_id [R $i cluster myshardid]
        assert_equal [dict exists $shard_ids $shard_id] 0
        dict set shard_ids $shard_id 1
    }
}

test "CLUSTER MYSHARDID reports same id for both primary and replica" {
    for {set i 0} {$i < 4} {incr i} {
        assert_equal [R $i cluster myshardid] [R [expr $i+4] cluster myshardid]
        assert_equal [string length [R $i cluster myshardid]] 40
    }
}

test "CLUSTER SHARDS reports correct shard id" {
    for {set i 0} {$i < 8} {incr i} {
        set node_id [R $i CLUSTER MYID]
        assert_equal [get_node_info_from_shard $node_id $i "shard-id"] [R $i cluster myshardid]
    }
}

test "CLUSTER NODES reports correct shard id" {
    for {set i 0} {$i < 8} {incr i} {
        set nodes [get_cluster_nodes $i]
        set node_id_to_shardid_mapping []
        foreach n $nodes {
            set node_shard_id [dict get $n shard-id]
            set node_id [dict get $n id]
            assert_equal [string length $node_shard_id] 40
            if {[dict exists $node_id_to_shardid_mapping $node_id]} {
                assert_equal [dict get $node_id_to_shardid_mapping $node_id] $node_shard_id
            } else {
                dict set node_id_to_shardid_mapping $node_id $node_shard_id
            }
            if {[lindex [dict get $n flags] 0] eq "myself"} {
                assert_equal [R $i cluster myshardid] [dict get $n shard-id]
            }
        }
    }
}

test "New replica receives primary's shard id" {
    #find a primary
    set id 0
    for {} {$id < 8} {incr id} {
        if {[regexp "master" [R $id role]]} {
            break
        }
    }
    assert_not_equal [R 8 cluster myshardid] [R $id cluster myshardid]
    assert_equal {OK} [R 8 cluster replicate [R $id cluster myid]]
    assert_equal [R 8 cluster myshardid] [R $id cluster myshardid]
}

test "CLUSTER MYSHARDID reports same shard id after shard restart" {
    set node_ids {}
    for {set i 0} {$i < 8} {incr i 4} {
        dict set node_ids $i [R $i cluster myshardid]
        kill_instance redis $i
        wait_for_condition 50 100 {
            [instance_is_killed redis $i]
        } else {
            fail "instance $i is not killed"
        }
    }
    for {set i 0} {$i < 8} {incr i 4} {
        restart_instance redis $i
    }
    assert_cluster_state ok
    for {set i 0} {$i < 8} {incr i 4} {
        assert_equal [dict get $node_ids $i] [R $i cluster myshardid]
    }
}

test "CLUSTER MYSHARDID reports same shard id after cluster restart" {
    set node_ids {}
    for {set i 0} {$i < 8} {incr i} {
        dict set node_ids $i [R $i cluster myshardid]
    }
    for {set i 0} {$i < 8} {incr i} {
        kill_instance redis $i
        wait_for_condition 50 100 {
            [instance_is_killed redis $i]
        } else {
            fail "instance $i is not killed"
        }
    }
    for {set i 0} {$i < 8} {incr i} {
        restart_instance redis $i
    }
    assert_cluster_state ok
    for {set i 0} {$i < 8} {incr i} {
        assert_equal [dict get $node_ids $i] [R $i cluster myshardid]
    }
}

test "CLUSTER SHARDS handles empty shard properly" {
    assert_not_equal [R 10 CLUSTER MYSHARDID] [R 11 CLUSTER MYSHARDID]
    set node_10_id [R 10 CLUSTER MYID]
    set shard_id [R 10 CLUSTER MYSHARDID]
    R 11 CLUSTER REPLICATE $node_10_id
    assert_equal [R 10 CLUSTER MYSHARDID] [R 11 CLUSTER MYSHARDID]
    set shard_ids {}
    foreach shard [R 10 CLUSTER SHARDS] {
        set shard_id [dict get $shard shard-id]
        assert_equal [dict exists $shard_ids $shard_id] 0
        dict set shard_ids $shard_id 1
    }
    assert_equal [dict exists $shard_ids $shard_id] 1
}

test "CLUSTER SHARDS reports all nodes in the same shard when the entire shard failed" {
    set node_0_id [R 0 CLUSTER MYID]
    set node_4_id [R 4 CLUSTER MYID]
    assert_equal [R 0 CLUSTER MYSHARDID] [R 4 CLUSTER MYSHARDID]
    set shard_id [R 0 CLUSTER MYSHARDID]

    cluster_ensure_master 0
    kill_instance redis 0
    kill_instance redis 4

    set shard_ids {}
    set node_ids {}
    foreach shard_response [R 1 CLUSTER SHARDS] {
        if {[dict get $shard_response shard-id] eq $shard_id} {
            foreach node [dict get $shard_response nodes] {
                set id [dict get $node id]
                assert_not_equal [dict exists $node_ids $id] 1
                dict set node_ids $id 1
            }
            break
        }
    }

    assert_equal [dict size $node_ids] 2
    assert_equal [dict exists $node_ids $node_0_id] 1
    assert_equal [dict exists $node_ids $node_4_id] 1
    restart_instance redis 0
    restart_instance redis 4
}

test "CLUSTER SHARDS reports failed primary in new primary's shard" {
    cluster_ensure_master 0
    kill_instance redis 0

    set shard_ids {}
    foreach shard_response [R 1 CLUSTER SHARDS] {
        set shard_id [dict get $shard_response shard-id]
        assert_equal [dict exists $shard_ids $shard_id] 0
        dict set shard_ids $shard_id 1
    }

    restart_instance redis 0
}