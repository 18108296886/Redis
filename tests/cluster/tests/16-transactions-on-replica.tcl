# Check basic transactions on a replica.

source "../tests/includes/init-tests.tcl"

test "Create a primary with a replica" {
    create_cluster 1 1
}

test "Cluster should start ok" {
    assert_cluster_state ok
}

set primary [Rn 0]
set replica [Rn 1]

test "Cant read from replica without READONLY" {
    $primary SET a 1
    catch {$replica GET a} err
    assert {[string range $err 0 4] eq {MOVED}}
}

test "Can read from replica after READONLY" {
    $replica READONLY
    assert {[$replica GET a] eq {1}}
}

test "Can preform HSET primary and HGET from replica" {
    $primary HSET h a 1
    $primary HSET h b 2
    $primary HSET h c 3
    assert {[$replica HGET h a] eq {1}}
    assert {[$replica HGET h b] eq {2}}
    assert {[$replica HGET h c] eq {3}}
}

test "Can MULTI-EXEC transaction of HGET operations from replica" {
    $replica MULTI
    assert {[$replica HGET h a] eq {QUEUED}}
    assert {[$replica HGET h b] eq {QUEUED}}
    assert {[$replica HGET h c] eq {QUEUED}}
    assert {[$replica EXEC] eq {1 2 3}}
}

test "MULTI-EXEC with write operations is MOVED" {
    $replica MULTI
    catch {$replica HSET h b 4} err
    assert {[string range $err 0 4] eq {MOVED}}
}