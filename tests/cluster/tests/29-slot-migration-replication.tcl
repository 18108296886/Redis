#Tests that validate slot migration states are replicated propoerly

source "../tests/includes/init-tests.tcl"
source "../tests/includes/utils.tcl"

variable master_count 3
variable replica_count 1

proc abort {message} {
    puts $message
    #gets stdin t
    throw 1 $message
}

proc get_node_descr {id} {
    set nodes_descr [split [R $id cluster nodes] "\n"]
    foreach line $nodes_descr {
        set line [string trim $line]
        if {[regexp {myself} $line]} {
            return $line
        }
    }
 }

proc get_a_slot {id} {
    set nd [get_node_descr $id]
    set slots [lindex $nd 8]
    if {[regexp {^[0-9]+} $slots slot]} {
        # puts "found a slot: $slot"
        return $slot
    }
    return {}
}

proc get_migrating_slots {node_id} {
    foreach line [split [R $node_id cluster nodes] "\n"] {
        set line [string trim $line]
        if {$line eq {}} continue
        if {[regexp {myself} $line] == 0} continue
        set args [split $line " "]
        set slave_nodeid [lindex $args 0]
        set slave_mslots {}
        regexp {\[.*} $line slave_mslots
        return $slave_mslots
    }
    error "node $node_id not found"
}

proc validate_slot_migration_states_open {from to slot_to_move} {
    global master_count
    set from_nodeid [R $from cluster myid]
    set to_nodeid [R $to cluster myid]

    assert_equal {OK} [R $from cluster setslot $slot_to_move migrating $to_nodeid]
    assert_equal {OK} [R $to cluster setslot $slot_to_move importing $from_nodeid]
    
    assert_equal [get_migrating_slots $from] "\[$slot_to_move->-$to_nodeid\]"
    assert_equal [get_migrating_slots $to] "\[$slot_to_move-<-$from_nodeid\]"

    # It takes some time to replicate the slot migration states
    set from_replica [expr $from + $master_count]
    wait_for_condition 50 100 {
        [get_migrating_slots $from_replica] eq "\[$slot_to_move->-$to_nodeid\]"
    } else {
        abort "incorrect slot migration state" 
    }
    set to_replica [expr $to + $master_count]
    wait_for_condition 50 100 {
        [get_migrating_slots $to_replica] eq "\[$slot_to_move-<-$from_nodeid\]"
    } else {
        abort "incorrect slot migration state"
    }
}

proc validate_slot_migration_states_close {from to slot_to_move} {
    global master_count
    set from_nodeid [R $from cluster myid]
    set to_nodeid [R $to cluster myid]

    # Close the slot migration states
    assert_equal {OK} [R $to cluster setslot $slot_to_move node $to_nodeid]
    assert_equal {OK} [R $from cluster setslot $slot_to_move node $to_nodeid]

    # No more slot being migrated on primaries
    assert_equal [get_migrating_slots $from] ""
    assert_equal [get_migrating_slots $to] ""

    # It takes some time to replicate the slot migration states
    set from_replica [expr $from + $master_count]
    wait_for_condition 50 100 {
        [get_migrating_slots $from_replica] eq ""
    } else {
        abort "non-empty slot migration state"
    }
    set to_replica [expr $to + $master_count]
    wait_for_condition 50 100 {
        [get_migrating_slots $to_replica] eq ""
    } else {
        abort "non-empty slot migration state"
    }

    wait_for_cluster_propagation
}

proc validate_slot_migration_states {from to} {
    set slot_to_move [get_a_slot $from]
    validate_slot_migration_states_open $from $to $slot_to_move
    validate_slot_migration_states_close $from $to $slot_to_move
}

proc wait_master_replica_stablization {master_id replica_id} {
    global master_count
    global replica_count

    set master_nodeid [R $master_id cluster myid]
    set replica_nodeid [R $replica_id cluster myid]

    wait_for_condition 200 200 {
        {master} eq [lindex [split [R $master_id role] " "] 0]
    } else {
        abort "master check failed: [R $master_id role]"
    }

    wait_for_condition 200 200 {
        {slave} eq [lindex [split [R $replica_id role] " "] 0]
    } else {
        abort "replica check failed: [R $replica_id role]"
    }

    for {set i 0} {$i < [expr $master_count*($replica_count+1)]} {incr i} {
        wait_for_condition 200 200 {
            [regexp "$master_nodeid.+master" [R $i cluster nodes]] == 1
        } else {
            abort "failed to stablize cluster topology for masters: [R $i cluster nodes]"
        }
        wait_for_condition 200 200 {
            [regexp "$replica_nodeid.+slave $master_nodeid" [R $i cluster nodes]] == 1
        } else {
            abort "failed to stablize cluster topology for replicas: [R $i cluster nodes]"
        }
    }
}

proc validate_slot_migration_states_with_failover {from to failover} { 
    global master_count
    set slot_to_move [get_a_slot $from]
    validate_slot_migration_states_open $from $to $slot_to_move

    set from_replica [expr $from + $master_count]
    set to_replica [expr $to + $master_count]

    # Simulate a target primary failure and wait for failover to complete
    set failed [uplevel 1 $failover]

    # It takes some time to replicate the slot migration states
    set from_replica_nodeid [R $from_replica cluster myid]
    set to_replica_nodeid [R $to_replica cluster myid]
    set from_nodeid [R $from cluster myid]
    set to_nodeid [R $to cluster myid]
    if {$failed != $from} {
        wait_for_condition 50 200 {
            [get_migrating_slots $from] eq "\[$slot_to_move->-$to_replica_nodeid\]"
        } else {
            abort "incorrect target slot migration state"
        }
        wait_for_condition 50 200 {
            [get_migrating_slots $from_replica] eq "\[$slot_to_move->-$to_replica_nodeid\]"
        } else {
            abort "incorrect target slot migration state"
        }

        # Node to_replica should still point to node 0 as the migration source
        assert_equal [get_migrating_slots $to_replica] "\[$slot_to_move-<-$from_nodeid\]"
    
        # Node to should come up as a slave but also point to node 0 as the migration source
        assert_equal [get_migrating_slots $to] "\[$slot_to_move-<-$from_nodeid\]"
    } else {
        wait_for_condition 50 200 {
            [get_migrating_slots $to] eq "\[$slot_to_move-<-$from_replica_nodeid\]"
        } else {
            abort "incorrect source slot migration state"
        }
        wait_for_condition 50 200 {
            [get_migrating_slots $to_replica] eq "\[$slot_to_move-<-$from_replica_nodeid\]"
        } else {
            abort "incorrect source slot migration state"
        }

        # Node from_replica should still point to node 0 as the migration target
        assert_equal [get_migrating_slots $from_replica] "\[$slot_to_move->-$to_nodeid\]"
    
        # Node from should come up as a slave but also point to node 0 as the migration target
        assert_equal [get_migrating_slots $from] "\[$slot_to_move->-$to_nodeid\]"
    }

    # Close the slot
    assert_equal {OK} [R $failed cluster failover]
    wait_master_replica_stablization $failed [expr $failed + $master_count]
    validate_slot_migration_states_close $from $to $slot_to_move
}

proc test_slot_migration_with_auto_failover {from to failed} {
    validate_slot_migration_states_with_failover $from $to {
        global master_count
        kill_instance redis $failed

        set failed_replica [expr $failed + $master_count]
        wait_for_condition 500 100 {
            [lindex [split [R $failed_replica role] " "] 0] eq "master"
        } else {
            abort "auto-failover failed"
        }

        restart_instance redis $failed
        
        # Wait for the node to become a replica
        # Now wait for the master to recognize this new replica
        # or future manual failover can be blocked
        wait_master_replica_stablization $failed_replica $failed

        set retval $failed
    }
}

proc test_slot_migration_with_manual_failover {from to failed} {
    validate_slot_migration_states_with_failover $from $to {
        global master_count
        set failed_replica [expr $failed + $master_count]
        assert_equal {OK} [R $failed_replica cluster failover]

        # Now wait for the master to recognize this new replica
        # or future manual failover can be blocked
        wait_master_replica_stablization $failed_replica $failed

        set retval $failed
    }
}

test "Create a cluster with 3 masters and 3 replicas" {
    create_cluster $master_count [expr $master_count * $replica_count]
    config_set_all_nodes cluster-allow-replica-migration no
}

test "Normal shard slot migration states replication" {
    validate_slot_migration_states 0 1
}

test "Normal shard slot migration states replication with target auto-failover" {
    test_slot_migration_with_auto_failover 0 1 1
}


test "Normal shard slot migration states replication with source auto-failover" {
    test_slot_migration_with_auto_failover 0 1 0
}

test "Normal shard slot migration states replication with target manual-failover" {
    test_slot_migration_with_manual_failover 0 1 1
}

test "Normal shard slot migration states replication with source manual-failover" {
    test_slot_migration_with_manual_failover 0 1 0
}

test "New replica inherits migrating slots" {
    set slot_to_move [get_a_slot 0]
    validate_slot_migration_states_open 0 1 $slot_to_move
    assert_equal [get_migrating_slots 17] {}
    assert_equal {OK} [R 17 cluster replicate [R 0 cluster myid]]
    wait_for_condition 50 100 {
        [get_migrating_slots 17] eq [get_migrating_slots 0]
    } else {
        abort "migrating slots not replicated"
    }
    validate_slot_migration_states_close 0 1 $slot_to_move
    assert_equal [get_migrating_slots 17] {}
}

test "New replica inherits importing slots" {
    set slot_to_move [get_a_slot 0]
    validate_slot_migration_states_open 0 1 $slot_to_move
    assert_equal [get_migrating_slots 18] {}
    assert_equal {OK} [R 18 cluster replicate [R 1 cluster myid]]
    wait_for_condition 50 100 {
        [get_migrating_slots 18] eq [get_migrating_slots 1]
    } else {
        abort "importing slots not replicated"
    }
    validate_slot_migration_states_close 0 1 $slot_to_move
    assert_equal [get_migrating_slots 18] {}
}