proc client_field {name f} {
    set clients [split [string trim [r client list]] "\r\n"]
    set c [lsearch -inline $clients *name=$name*]
    if {![regexp $f=(\[a-zA-Z0-9-\]+) $c - res]} {
        throw no-client "no client named $name found with field $f"
    }
    return $res
}

proc clients_sum {f} {
    set sum 0
    set clients [split [string trim [r client list]] "\r\n"]
    foreach c $clients {
        if {![regexp $f=(\[a-zA-Z0-9-\]+) $c - res]} {
            throw no-field "field $f not found in $c"
        }
        incr sum $res
    }
    return $sum
}

start_server {} {
    set maxmemory_clients 3000000
    r config set maxmemory-clients $maxmemory_clients
    
    test "client evicted due to large argv" {
        r flushdb
        set rr [redis_client]
        # Attempt a large multi-bulk command under eviction limit
        $rr mset k v k2 [string repeat v 1000000]
        assert_equal [$rr get k] v
        # Attempt another command, now causing client eviction
        catch { $rr mset k v k2 [string repeat v $maxmemory_clients] } e
        assert_match {*connection reset by peer*} $e
    }

    test "client evicted due to large query buf" {
        r flushdb
        set rr [redis_client]
        # Attempt to fill the query buff without completing the argument above the limit, causing client eviction
        catch { 
            $rr write [join [list "*1\r\n\$$maxmemory_clients\r\n" [string repeat v $maxmemory_clients]] ""]
            $rr flush
            $rr read
        } e
        assert_match {*connection reset by peer*} $e
    }

    test "client evicted due to large multi buf" {
        r flushdb
        set rr [redis_client]
        
        # Attempt a multi-exec where sum of commands is less than maxmemory_clients
        $rr multi
        $rr set k [string repeat v [expr $maxmemory_clients / 4]]
        $rr set k [string repeat v [expr $maxmemory_clients / 4]]
        assert_match [$rr exec] {OK OK}

        # Attempt a multi-exec where sum of commands is more than maxmemory_clients, causing client eviction
        $rr multi
        catch { 
            for {set j 0} {$j < 5} {incr j} {
                $rr set k [string repeat v [expr $maxmemory_clients / 4]]
            }
        } e
        assert_match {*broken pipe*} $e
    }

    test "client evicted due to watched key list" {
        r flushdb
        set rr [redis_client]
        
        # Since watched key list is a small overheatd this test uses a minimal maxmemory-clients config
        r config set maxmemory-clients 300000
        $rr client setname badger
        
        # Append watched keys until list maxes out maxmemroy clients and causes client eviction
        catch { 
            for {set j 0} {$j < $maxmemory_clients} {incr j} {
                $rr watch $j
            }
        } e
        assert_match {I/O error reading reply} $e
        
        # Restore config for next tests
        r config set maxmemory-clients $maxmemory_clients
    }

    test "client evicted due to output buf" {
        r flushdb
        r setrange k 200000 v
        set rr [redis_deferring_client]
        $rr client setname test_client
        $rr flush
        assert {[$rr read] == "OK"}
        # Attempt a large response under eviction limit
        $rr get k
        $rr flush
        assert {[string length [$rr read]] == 200001}
        set mem [client_field test_client tot-mem]
        assert {$mem < $maxmemory_clients}

        # Fill output buff in loop without reading it and make sure 
        # we're eventually disconnected, but before reaching maxmemory_clients
        while true {
            if { [catch {
                set mem [client_field test_client tot-mem]
                assert {$mem < $maxmemory_clients}
                $rr get k
                $rr flush
               } e]} {
                assert_match {no client named test_client found*} $e
                break
            }
        }
    }

    foreach {no_evict} {on off} {
        test "client no-evict $no_evict" {
            r flushdb
            r client setname control
            r client no-evict on ;# Avoid evicting the main connection
            set rr [redis_client]
            $rr client no-evict $no_evict
            $rr client setname test_client
        
            # Overflow maxmemory-clients
            set qbsize [expr {$maxmemory_clients + 1}]
            if {[catch {
                $rr write [join [list "*1\r\n\$$qbsize\r\n" [string repeat v $qbsize]] ""]
                $rr flush
                wait_for_condition 200 10 {
                    [client_field test_client qbuf] == $qbsize
                } else {
                    fail "Failed to fill qbuf for test"
                }
            } e] && $no_evict == off} {
                assert_match {*connection reset by peer*} $e
            } elseif {$no_evict == on} {
                assert {[client_field test_client tot-mem] > $maxmemory_clients}
                $rr close
            }            
        }
    }
}

proc mb {v} {
    return [expr $v * 1024 * 1024]
}

start_server {} {
    set server_pid [s process_id]
    set maxmemory_clients [mb 10]
    set obuf_limit [mb 3]
    r config set maxmemory-clients $maxmemory_clients
    r config set client-output-buffer-limit "normal $obuf_limit 0 0"

    test "avoid client eviction when client is freed by output buffer limit" {
        r flushdb
        set obuf_size [expr {$obuf_limit + [mb 1]}]
        r setrange k $obuf_size v
        set rr1 [redis_client]
        $rr1 client setname "qbuf-client"
        set rr2 [redis_deferring_client]
        $rr2 client setname "obuf-client1"
        assert_match [$rr2 read] OK
        set rr3 [redis_deferring_client]
        $rr3 client setname "obuf-client2"
        assert_match [$rr3 read] OK

        # Occupy client's query buff with less than output buffer limit left to exceed maxmemory-clients
        set qbsize [expr {$maxmemory_clients - $obuf_size}]
        $rr1 write [join [list "*1\r\n\$$qbsize\r\n" [string repeat v $qbsize]] ""]
        $rr1 flush
        # Wait for qbuff to be as expected
        wait_for_condition 200 10 {
            [client_field qbuf-client qbuf] == $qbsize
        } else {
            fail "Failed to fill qbuf for test"
        }
        
        # Make the other two obuf-clients pass obuf limit and also pass maxmemory-clients
        # We use two obuf-clients to make sure that even if client eviction is attempted
        # btween two command processing (with no sleep) we don't perform any client eviction
        # because the obuf limit is enforced with precendence.
        exec kill -SIGSTOP $server_pid
        $rr2 get k
        $rr2 flush
        $rr3 get k
        $rr3 flush
        exec kill -SIGCONT $server_pid
        
        # Validate obuf-clients were disconnected (because of obuf limit)
        catch {client_field obuf-client1 name} e
        assert_match {no client named obuf-client1 found*} $e
        catch {client_field obuf-client2 name} e
        assert_match {no client named obuf-client2 found*} $e
        
        # Validate qbuf-client is still connected and wasn't evicted
        assert_match [client_field qbuf-client name] {qbuf-client}
    }
}

start_server {} {
    test "decrease maxmemory-clients causes client eviction" {
        set maxmemory_clients [mb 4]
        set client_count 10
        set qbsize [expr ($maxmemory_clients - [mb 1]) / $client_count]
        r config set maxmemory-clients $maxmemory_clients


        # Make multiple clients consume together roughly 1mb less than maxmemory_clients
        for {set j 0} {$j < $client_count} {incr j} {
            set rr [redis_client]
            $rr client setname client$j
            $rr write [join [list "*2\r\n\$$qbsize\r\n" [string repeat v $qbsize]] ""]
            $rr flush
            wait_for_condition 200 10 {
                [client_field client$j qbuf] >= $qbsize
            } else {
                fail "Failed to fill qbuf for test"
            }
        }
        
        # Make sure all clients are still connected
        set connected_clients [llength [lsearch -all [split [string trim [r client list]] "\r\n"] *name=client*]]
        assert {$connected_clients == $client_count}
        
        # Decrease maxmemory_clients and expect client eviction
        r config set maxmemory-clients [expr $maxmemory_clients / 2]
        set connected_clients [llength [lsearch -all [split [string trim [r client list]] "\r\n"] *name=client*]]
        assert {$connected_clients > 0 && $connected_clients < $client_count}
    }
}

start_server {} {
    test "evict clients only until below limit" {
        set client_count 10
        set client_mem [mb 1]
        r config set maxmemory-clients 0
        r client setname control
        r client no-evict on
        
        # Make multiple clients consume together roughly 1mb less than maxmemory_clients
        for {set j 0} {$j < $client_count} {incr j} {
            set rr [redis_client]
            $rr client setname client$j
            $rr write [join [list "*2\r\n\$$client_mem\r\n" [string repeat v $client_mem]] ""]
            $rr flush
            wait_for_condition 200 10 {
                [client_field client$j tot-mem] >= $client_mem
            } else {
                fail "Failed to fill qbuf for test"
            }
        }

        set total_client_mem [clients_sum tot-mem]
        set client_actual_mem [expr $total_client_mem / $client_count]
        
        # Make sure client_acutal_mem is more or equal to what we indended
        assert {$client_actual_mem >= $client_mem}

        # Make sure all clients are still connected
        set connected_clients [llength [lsearch -all [split [string trim [r client list]] "\r\n"] *name=client*]]
        assert {$connected_clients == $client_count}

        # Set maxmemory-clients to accomodate have our clients (taking into account the control client)
        set maxmemory_clients [expr ($client_actual_mem * $client_count) / 2 + [client_field control tot-mem]]
        r config set maxmemory-clients $maxmemory_clients
        
        # Make sure total used memory is below maxmemory_clients
        set total_client_mem [clients_sum tot-mem]
        assert {$total_client_mem <= $maxmemory_clients}

        # Make sure we have only half of our clients now
        set connected_clients [llength [lsearch -all [split [string trim [r client list]] "\r\n"] *name=client*]]
        assert {$connected_clients == [expr $client_count / 2]}
    }
}


