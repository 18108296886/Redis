# Check basic transactions on a replica.

source "../tests/includes/init-tests.tcl"

test "Create a primary with a replica" {
    create_cluster 1 1
}

test "Cluster should start ok" {
    assert_cluster_state ok
}

test "Cluster is writable" {
    cluster_write_test 0
}

test "Right to restore backups when fail to diskless load " {
    set master [Rn 0]
    set replica [Rn 1]
    set master_id 0
    set replica_id 1

    $replica READONLY
    $replica config set repl-diskless-load swapdb
    $replica config rewrite
    $master config set repl-backlog-size 1024
    $master config set repl-diskless-sync yes
    $master config set repl-diskless-sync-delay 0
    $master config set rdb-key-save-delay 10000
    $master config set rdbcompression no
    $master config set appendonly no
    $master config set save ""

    # Writ a key that belongs to slot 0 
    set slot0_key "06S"
    $master set $slot0_key 1
    after 100
    assert_equal {1} [$replica get $slot0_key]
    assert_equal $slot0_key [$replica CLUSTER GETKEYSINSLOT 0 1]

    # Kill the replica
    kill_instance redis $replica_id

    # Delete the key from master
    $master del $slot0_key

    # Replia must full sync with master when start because replication
    # backlog size is very small, and dumping rdb will cost several seconds.
    set num 10000
    set value [string repeat A 1024]
    set rd [redis_deferring_client redis $master_id]
    for {set j 0} {$j < $num} {incr j} {
        $rd set $j $value
    }
    for {set j 0} {$j < $num} {incr j} {
        $rd read
    }

    # Start the replica again
    restart_instance redis $replica_id
    $replica READONLY

    # Start full sync
    wait_for_condition 500 10 {
        [string match "*sync*" [$replica role]]
    } else {
        fail "Fail to full sync"
    }
    after 100

    # Kill master, abort full sync
    kill_instance redis $master_id

    # Replica keys and keys to slots map still both are right
    assert_equal {1} [$replica get $slot0_key]
    assert_equal $slot0_key [$replica CLUSTER GETKEYSINSLOT 0 1]
}