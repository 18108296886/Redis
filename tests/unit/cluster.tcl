# Primitive tests on cluster-enabled redis using redis-cli

source tests/support/cli.tcl

proc cluster_info {r field} {
    # cluster_state is the first field, so we need to use ^ to match it.
    if {$field == "cluster_state"} {
        if {[regexp "^$field:(.*?)\r\n" [$r cluster info] _ value]} {
            set _ $value
        }
    } else {
        set _ [getInfoProperty [$r cluster info] $field]
    }
}

# Provide easy access to CLUSTER INFO properties. Same semantic as "proc s".
proc csi {args} {
    set level 0
    if {[string is integer [lindex $args 0]]} {
        set level [lindex $args 0]
        set args [lrange $args 1 end]
    }
    cluster_info [srv $level "client"] [lindex $args 0]
}

# make sure the test infra won't use SELECT
set ::singledb 1

# cluster creation is complicated with TLS, and the current tests don't really need that coverage
tags {tls:skip external:skip cluster} {

# start three servers
set base_conf [list cluster-enabled yes cluster-node-timeout 1]
start_server [list overrides $base_conf] {
start_server [list overrides $base_conf] {
start_server [list overrides $base_conf] {

    set node1 [srv 0 client]
    set node2 [srv -1 client]
    set node3 [srv -2 client]
    set node3_pid [srv -2 pid]

    test {Create 3 node cluster} {
        exec src/redis-cli --cluster-yes --cluster create \
                           127.0.0.1:[srv 0 port] \
                           127.0.0.1:[srv -1 port] \
                           127.0.0.1:[srv -2 port]

        wait_for_condition 1000 50 {
            [csi 0 cluster_state] eq {ok} &&
            [csi -1 cluster_state] eq {ok} &&
            [csi -2 cluster_state] eq {ok}
        } else {
            fail "Cluster doesn't stabilize"
        }
    }

    test "Run blocking command on cluster node3" {
        # key9184688 is mapped to slot 10923 (first slot of node 3)
        set node3_rd [redis_deferring_client -2]
        $node3_rd brpop key9184688 0
        $node3_rd flush

        wait_for_condition 50 100 {
            [s -2 blocked_clients] eq {1}
        } else {
            fail "Client not blocked"
        }
    }

    test "Perform a Resharding" {
        exec src/redis-cli --cluster-yes --cluster reshard 127.0.0.1:[srv -2 port] \
                           --cluster-to [$node1 cluster myid] \
                           --cluster-from [$node3 cluster myid] \
                           --cluster-slots 1
    }

    test "Verify command got unblocked after resharding" {
        # this (read) will wait for the node3 to realize the new topology
        assert_error {*MOVED*} {$node3_rd read}

        # verify there are no blocked clients
        assert_equal [s 0 blocked_clients]  {0}
        assert_equal [s -1 blocked_clients]  {0}
        assert_equal [s -2 blocked_clients]  {0}
    }

    test "Wait for cluster to be stable" {
       wait_for_condition 1000 50 {
            [catch {exec src/redis-cli --cluster \
            check 127.0.0.1:[srv 0 port] \
            }] == 0
        } else {
            fail "Cluster doesn't stabilize"
        }
    }

    test "Sanity test push cmd after resharding" {
        assert_error {*MOVED*} {$node3 lpush key9184688 v1}

        set node1_rd [redis_deferring_client 0]
        $node1_rd brpop key9184688 0
        $node1_rd flush

        wait_for_condition 50 100 {
            [s 0 blocked_clients] eq {1}
        } else {
            puts "Client not blocked"
            puts "read from blocked client: [$node1_rd read]"
            fail "Client not blocked"
        }

        $node1 lpush key9184688 v2
        assert_equal {key9184688 v2} [$node1_rd read]
    }

    $node1_rd close
    $node3_rd close

    test "Run blocking command again on cluster node1" {
        $node1 del key9184688
        # key9184688 is mapped to slot 10923 which has been moved to node1
        set node1_rd [redis_deferring_client 0]
        $node1_rd brpop key9184688 0
        $node1_rd flush

        wait_for_condition 50 100 {
            [s 0 blocked_clients] eq {1}
        } else {
            fail "Client not blocked"
        }
    }

     test "Kill a cluster node and wait for fail state" {
        # kill node3 in cluster
        exec kill -SIGSTOP $node3_pid

        wait_for_condition 1000 50 {
            [csi 0 cluster_state] eq {fail} &&
            [csi -1 cluster_state] eq {fail}
        } else {
            fail "Cluster doesn't fail"
        }
    }

     test "Verify command got unblocked after cluster failure" {
        assert_error {*CLUSTERDOWN*} {$node1_rd read}

        # verify there are no blocked clients
        assert_equal [s 0 blocked_clients]  {0}
        assert_equal [s -1 blocked_clients]  {0}
    }

    exec kill -SIGCONT $node3_pid
    $node1_rd close

# stop three servers
}
}
}

# Test redis-cli -- cluster create, add-node, call.
# Test that functions are propagated on add-node
start_server [list overrides $base_conf] {
start_server [list overrides $base_conf] {
start_server [list overrides $base_conf] {
start_server [list overrides $base_conf] {
start_server [list overrides $base_conf] {

    set node4_rd [redis_client -3]
    set node5_rd [redis_client -4]

    test {Functions are added to new node on redis-cli cluster add-node} {
        exec src/redis-cli --cluster-yes --cluster create \
                           127.0.0.1:[srv 0 port] \
                           127.0.0.1:[srv -1 port] \
                           127.0.0.1:[srv -2 port]


        wait_for_condition 1000 50 {
            [csi 0 cluster_state] eq {ok} &&
            [csi -1 cluster_state] eq {ok} &&
            [csi -2 cluster_state] eq {ok}
        } else {
            fail "Cluster doesn't stabilize"
        }

        # upload a function to all the cluster
        exec src/redis-cli --cluster-yes --cluster call 127.0.0.1:[srv 0 port] \
                           FUNCTION LOAD LUA TEST {redis.register_function('test', function() return 'hello' end)}

        # adding node to the cluster
        exec src/redis-cli --cluster-yes --cluster add-node \
                       127.0.0.1:[srv -3 port] \
                       127.0.0.1:[srv 0 port]

        wait_for_condition 1000 50 {
            [csi 0 cluster_state] eq {ok} &&
            [csi -1 cluster_state] eq {ok} &&
            [csi -2 cluster_state] eq {ok} &&
            [csi -3 cluster_state] eq {ok}
        } else {
            fail "Cluster doesn't stabilize"
        }

        # make sure 'test' function was added to the new node
        assert_equal {{library_name TEST engine LUA description {} functions {{name test description {} flags {}}}}} [$node4_rd FUNCTION LIST]

        # add function to node 5
        assert_equal {OK} [$node5_rd FUNCTION LOAD LUA TEST {redis.register_function('test', function() return 'hello' end)}]

        # make sure functions was added to node 5
        assert_equal {{library_name TEST engine LUA description {} functions {{name test description {} flags {}}}}} [$node5_rd FUNCTION LIST]

        # adding node 5 to the cluster should failed because it already contains the 'test' function
        catch {
            exec src/redis-cli --cluster-yes --cluster add-node \
                        127.0.0.1:[srv -4 port] \
                        127.0.0.1:[srv 0 port]
        } e
        assert_match {*node already contains functions*} $e
    }
# stop 5 servers
}
}
}
}
}

# Test redis-cli --cluster create, add-node with cluster-port.
# Create five nodes, three with custom cluster_port and two with default values.
start_server [list overrides [list cluster-enabled yes cluster-node-timeout 1 cluster-port [find_available_port $::baseport $::portcount]]] {
start_server [list overrides [list cluster-enabled yes cluster-node-timeout 1]] {
start_server [list overrides [list cluster-enabled yes cluster-node-timeout 1 cluster-port [find_available_port $::baseport $::portcount]]] {
start_server [list overrides [list cluster-enabled yes cluster-node-timeout 1]] {
start_server [list overrides [list cluster-enabled yes cluster-node-timeout 1 cluster-port [find_available_port $::baseport $::portcount]]] {

    # The first three are used to test --cluster create.
    # The last two are used to test --cluster add-node
    set node1_rd [redis_client 0]
    set node2_rd [redis_client -1]
    set node3_rd [redis_client -2]
    set node4_rd [redis_client -3]
    set node5_rd [redis_client -4]

    test {redis-cli --cluster create with cluster-port} {
        exec src/redis-cli --cluster-yes --cluster create \
                           127.0.0.1:[srv 0 port]@[status $node1_rd cluster_port] \
                           127.0.0.1:[srv -1 port] \
                           127.0.0.1:[srv -2 port]@[status $node3_rd cluster_port]

        wait_for_condition 1000 50 {
            [csi 0 cluster_state] eq {ok} &&
            [csi -1 cluster_state] eq {ok} &&
            [csi -2 cluster_state] eq {ok}
        } else {
            fail "Cluster doesn't stabilize"
        }

        # Make sure each node can meet other nodes
        assert_equal 3 [csi 0 cluster_known_nodes]
        assert_equal 3 [csi -1 cluster_known_nodes]
        assert_equal 3 [csi -2 cluster_known_nodes]
    }

    test {redis-cli --cluster add-node with cluster-port} {
        # Adding node to the cluster (without cluster-port)
        exec src/redis-cli --cluster-yes --cluster add-node \
                           127.0.0.1:[srv -3 port] \
                           127.0.0.1:[srv 0 port]

        wait_for_condition 1000 50 {
            [csi 0 cluster_state] eq {ok} &&
            [csi -1 cluster_state] eq {ok} &&
            [csi -2 cluster_state] eq {ok} &&
            [csi -3 cluster_state] eq {ok}
        } else {
            fail "Cluster doesn't stabilize"
        }

        # Adding node to the cluster (with cluster-port)
        exec src/redis-cli --cluster-yes --cluster add-node \
                           127.0.0.1:[srv -4 port]@[status $node5_rd cluster_port] \
                           127.0.0.1:[srv 0 port]

        wait_for_condition 1000 50 {
            [csi 0 cluster_state] eq {ok} &&
            [csi -1 cluster_state] eq {ok} &&
            [csi -2 cluster_state] eq {ok} &&
            [csi -3 cluster_state] eq {ok} &&
            [csi -4 cluster_state] eq {ok}
        } else {
            fail "Cluster doesn't stabilize"
        }

        # Make sure each node can meet other nodes
        assert_equal 5 [csi 0 cluster_known_nodes]
        assert_equal 5 [csi -1 cluster_known_nodes]
        assert_equal 5 [csi -2 cluster_known_nodes]
        assert_equal 5 [csi -3 cluster_known_nodes]
        assert_equal 5 [csi -4 cluster_known_nodes]
    }
# stop 5 servers
}
}
}
}
}

} ;# tags