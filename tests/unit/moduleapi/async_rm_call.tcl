set testmodule [file normalize tests/modules/blockedclient.so]
set testmodule2 [file normalize tests/modules/postnotifications.so]

start_server {tags {"modules"}} {
    r module load $testmodule

    test {Locked GIL acquisition from async RM_Call} {
        assert_equal {OK} [r do_rm_call_async acquire_gil]
    }

    test "Blpop on async RM_Call fire and forget" {
        assert_equal {Blocked} [r do_rm_call_fire_and_forget blpop l 0]
        r lpush l a
        assert_equal {0} [r llen l]
    }

    foreach cmd {do_rm_call_async do_rm_call_async_script_mode} {

        test "Blpop on async RM_Call using $cmd" {
            set rd [redis_deferring_client]

            $rd $cmd blpop l 0
            wait_for_blocked_client
            r lpush l a
            assert_equal [$rd read] {l a}
        }

        test "Brpop on async RM_Call using $cmd" {
            set rd [redis_deferring_client]

            $rd $cmd brpop l 0
            wait_for_blocked_client
            r lpush l a
            assert_equal [$rd read] {l a}
        }

        test "Brpoplpush on async RM_Call using $cmd" {
            set rd [redis_deferring_client]

            $rd $cmd brpoplpush l1 l2 0
            wait_for_blocked_client
            r lpush l1 a
            assert_equal [$rd read] {a}
            r lpop l2
        } {a}

        test "Blmove on async RM_Call using $cmd" {
            set rd [redis_deferring_client]

            $rd $cmd blmove l1 l2 LEFT LEFT 0
            wait_for_blocked_client
            r lpush l1 a
            assert_equal [$rd read] {a}
            r lpop l2
        } {a}

        test "Bzpopmin on async RM_Call using $cmd" {
            set rd [redis_deferring_client]

            $rd $cmd bzpopmin s 0
            wait_for_blocked_client
            r zadd s 10 foo
            assert_equal [$rd read] {s foo 10}
        }

        test "Bzpopmax on async RM_Call using $cmd" {
            set rd [redis_deferring_client]

            $rd $cmd bzpopmax s 0
            wait_for_blocked_client
            r zadd s 10 foo
            assert_equal [$rd read] {s foo 10}
        }
    }

    test {Nested async RM_Call} {
        set rd [redis_deferring_client]

        $rd do_rm_call_async do_rm_call_async do_rm_call_async do_rm_call_async blpop l 0
        wait_for_blocked_client
        r lpush l a
        assert_equal [$rd read] {l a}
    }

    test {Test multiple async RM_Call waiting on the same event} {
        set rd1 [redis_deferring_client]
        set rd2 [redis_deferring_client]

        $rd1 do_rm_call_async do_rm_call_async do_rm_call_async do_rm_call_async blpop l 0
        $rd2 do_rm_call_async do_rm_call_async do_rm_call_async do_rm_call_async blpop l 0
        wait_for_blocked_client
        r lpush l element element
        assert_equal [$rd1 read] {l element}
        assert_equal [$rd2 read] {l element}
    }

    test {async RM_Call calls RM_Call} {
        assert_equal {PONG} [r do_rm_call_async do_rm_call ping]
    }

    test {async RM_Call calls background RM_Call calls RM_Call} {
        assert_equal {PONG} [r do_rm_call_async do_bg_rm_call do_rm_call ping]
    }

    test {async RM_Call calls background RM_Call calls RM_Call calls async RM_Call} {
        assert_equal {PONG} [r do_rm_call_async do_bg_rm_call do_rm_call do_rm_call_async ping]
    }

    test {async RM_Call inside async RM_Call callback} {
        set rd [redis_deferring_client]
        $rd wait_and_do_rm_call blpop l 0
        wait_for_blocked_client

        start_server {} {
            test "Connect a replica to the master instance" {
                r slaveof [srv -1 host] [srv -1 port]
                wait_for_condition 50 100 {
                    [s role] eq {slave} &&
                    [string match {*master_link_status:up*} [r info replication]]
                } else {
                    fail "Can't turn the instance into a replica"
                }
            }

            assert_equal {1} [r -1 lpush l a]
            assert_equal [$rd read] {l a}
        }
    }

    test {Become replica while having async RM_Call running} {
        set rd [redis_deferring_client]
        $rd wait_and_do_rm_call blpop l 0
        wait_for_blocked_client

        #become a replica of a not existing redis
        r replicaof localhost 30000

        catch {[$rd read]} e
        assert_match {UNBLOCKED force unblock from blocking operation*} $e

        r replicaof no one
    }

    test {Pipeline with blocking RM_Call} {
        set rd [redis_deferring_client]
        set buf ""
        append buf "do_rm_call_async blpop l 0\r\n"
        append buf "ping\r\n"
        $rd write $buf
        $rd flush
        wait_for_blocked_client


        # release the blocked client
        r lpush l 1

        assert_equal [$rd read] {l 1}
        assert_equal [$rd read] {PONG}
    }
}

start_server {tags {"modules"}} {
    r module load $testmodule

    test {Test basic replication stream on unblock handler} {
        r flushall
        set repl [attach_to_replication_stream]

        set rd [redis_deferring_client]

        $rd do_rm_call_async blpop l 0
        wait_for_blocked_client
        r lpush l a
        assert_equal [$rd read] {l a}

        assert_replication_stream $repl {
            {select *}
            {lpush l a}
            {lpop l}
        }
        close_replication_stream $repl
    }

    test {Test unblock handler are executed as a unit} {
        r flushall
        set repl [attach_to_replication_stream]

        set rd [redis_deferring_client]

        $rd blpop_and_set_multiple_keys l x 1 y 2
        wait_for_blocked_client
        r lpush l a
        assert_equal [$rd read] {OK}

        assert_replication_stream $repl {
            {select *}
            {lpush l a}
            {lpop l}
            {multi}
            {set x 1}
            {set y 2}
            {exec}
        }
        close_replication_stream $repl
    }

    test {Test no propagation of blocking command} {
        r flushall
        set repl [attach_to_replication_stream]

        set rd [redis_deferring_client]

        $rd do_rm_call_async_no_replicate blpop l 0
        wait_for_blocked_client
        r lpush l a
        assert_equal [$rd read] {l a}

        # make sure the lpop are not replicated
        r set x 1

        assert_replication_stream $repl {
            {select *}
            {lpush l a}
            {set x 1}
        }
        close_replication_stream $repl
    }
}

start_server {tags {"modules"}} {
    r module load $testmodule
    r module load $testmodule2

    test {Test unblock handler are executed as a unit} {
        r flushall
        set repl [attach_to_replication_stream]

        set rd [redis_deferring_client]

        $rd blpop_and_set_multiple_keys l string_foo 1 string_bar 2
        wait_for_blocked_client
        r lpush l a
        assert_equal [$rd read] {OK}

        assert_replication_stream $repl {
            {select *}
            {lpush l a}
            {lpop l}
            {multi}
            {set string_foo 1}
            {set string_bar 2}
            {incr string_changed{string_foo}}
            {incr string_changed{string_bar}}
            {incr string_total}
            {incr string_total}
            {exec}
        }
        close_replication_stream $repl
    }
}