proc get_function_code {args} {
    return [format "library.register_function('%s', function(KEYS, ARGV)\n %s \nend)" [lindex $args 0] [lindex $args 1]]
}

start_server {tags {"scripting"}} {
    test {FUNCTION - Basic usage} {
        r function load LUA test [get_function_code test {return 'hello'}]
        r fcall test 0
    } {hello}

    test {FUNCTION - Create an already exiting library raise error} {
        catch {
            r function load LUA test [get_function_code test {return 'hello1'}]
        } e
        set _ $e
    } {*already exists*}

    test {FUNCTION - Create an already exiting library raise error (case insensitive)} {
        catch {
            r function load LUA TEST [get_function_code test {return 'hello1'}]
        } e
        set _ $e
    } {*already exists*}

    test {FUNCTION - Create a library with wrong name format} {
        catch {
            r function load LUA {bad\0foramat} [get_function_code test {return 'hello1'}]
        } e
        set _ $e
    } {*Library names can only contain letters and numbers*}

    test {FUNCTION - Create library with unexisting engine} {
        catch {
            r function load bad_engine test [get_function_code test {return 'hello1'}]
        } e
        set _ $e
    } {*Engine not found*}

    test {FUNCTION - Test uncompiled script} {
        catch {
            r function load LUA test1 {bad script}
        } e
        set _ $e
    } {*Error compiling function*}

    test {FUNCTION - test replace argument} {
        r function load LUA test REPLACE [get_function_code test {return 'hello1'}]
        r fcall test 0
    } {hello1}

    test {FUNCTION - test function case insensitive} {
        r fcall TEST 0
    } {hello1}

    test {FUNCTION - test replace argument with failure keeps old libraries} {
         catch {r function create LUA test REPLACE {error}}
        r fcall test 0
    } {hello1}

    test {FUNCTION - test function delete} {
        r function delete test
        catch {
            r fcall test 0
        } e
        set _ $e
    } {*Function not found*}

    test {FUNCTION - test description argument} {
        r function load LUA test DESCRIPTION {some description} [get_function_code test {return 'hello'}]
        r function list
    } {{library_name test engine LUA description {some description} functions {{name test description {}}}}}

    test {FUNCTION - test fcall bad arguments} {
        catch {
            r fcall test bad_arg
        } e
        set _ $e
    } {*Bad number of keys provided*}

    test {FUNCTION - test fcall bad number of keys arguments} {
        catch {
            r fcall test 10 key1
        } e
        set _ $e
    } {*Number of keys can't be greater than number of args*}

    test {FUNCTION - test fcall negative number of keys} {
        catch {
            r fcall test -1 key1
        } e
        set _ $e
    } {*Number of keys can't be negative*}

    test {FUNCTION - test delete on not exiting library} {
        catch {
            r function delete test1
        } e
        set _ $e
    } {*Library not found*}

    test {FUNCTION - test function kill when function is not running} {
        catch {
            r function kill
        } e
        set _ $e
    } {*No scripts in execution*}

    test {FUNCTION - test wrong subcommand} {
        catch {
            r function bad_subcommand
        } e
        set _ $e
    } {*Unknown subcommand*}

    test {FUNCTION - test loading from rdb} {
        r debug reload
        r fcall test 0
    } {hello} {needs:debug}

    test {FUNCTION - test debug reload different options} {
        catch {r debug reload noflush} e
        assert_match "*Error trying to load the RDB*" $e
        r debug reload noflush merge
        r function list
    } {{library_name test engine LUA description {some description} functions {{name test description {}}}}} {needs:debug}

    test {FUNCTION - test debug reload with nosave and noflush} {
        r function delete test
        r set x 1
        r function load LUA test1 DESCRIPTION {some description} [get_function_code test1 {return 'hello'}]
        r debug reload
        r function load LUA test2 DESCRIPTION {some description} [get_function_code test2 {return 'hello'}]
        r debug reload nosave noflush merge
        assert_equal [r fcall test1 0] {hello}
        assert_equal [r fcall test2 0] {hello}
    } {} {needs:debug}

    test {FUNCTION - test flushall and flushdb do not clean functions} {
        r function flush
        r function load lua test REPLACE [get_function_code test {return redis.call('set', 'x', '1')}]
        r flushall
        r flushdb
        r function list
    } {{library_name test engine LUA description {} functions {{name test description {}}}}}

    test {FUNCTION - test function dump and restore} {
        r function flush
        r function load lua test description {some description} [get_function_code test {return 'hello'}]
        set e [r function dump]
        r function delete test
        assert_match {} [r function list]
        r function restore $e
        r function list
    } {{library_name test engine LUA description {some description} functions {{name test description {}}}}}

    test {FUNCTION - test function dump and restore with flush argument} {
        set e [r function dump]
        r function flush
        assert_match {} [r function list]
        r function restore $e FLUSH
        r function list
    } {{library_name test engine LUA description {some description} functions {{name test description {}}}}}

    test {FUNCTION - test function dump and restore with append argument} {
        set e [r function dump]
        r function flush
        assert_match {} [r function list]
        r function load lua test [get_function_code test {return 'hello1'}]
        catch {r function restore $e APPEND} err
        assert_match {*already exists*} $err
        r function flush
        r function load lua test1 [get_function_code test1 {return 'hello1'}]
        r function restore $e APPEND
        assert_match {hello} [r fcall test 0]
        assert_match {hello1} [r fcall test1 0]
    }

    test {FUNCTION - test function dump and restore with replace argument} {
        r function flush
        r function load LUA test DESCRIPTION {some description} [get_function_code test {return 'hello'}]
        set e [r function dump]
        r function flush
        assert_match {} [r function list]
        r function load lua test [get_function_code test {return 'hello1'}]
        assert_match {hello1} [r fcall test 0]
        r function restore $e REPLACE
        assert_match {hello} [r fcall test 0]
    }

    test {FUNCTION - test function restore with bad payload do not drop existing functions} {
        r function flush
        r function load LUA test DESCRIPTION {some description} [get_function_code test {return 'hello'}]
        catch {r function restore bad_payload} e
        assert_match {*payload version or checksum are wrong*} $e
        r function list
    } {{library_name test engine LUA description {some description} functions {{name test description {}}}}}

    test {FUNCTION - test function restore with wrong number of arguments} {
        catch {r function restore arg1 args2 arg3} e
        set _ $e
    } {*wrong number of arguments*}

    test {FUNCTION - test fcall_ro with write command} {
        r function load lua test REPLACE [get_function_code test {return redis.call('set', 'x', '1')}]
        catch { r fcall_ro test 0 } e
        set _ $e
    } {*Write commands are not allowed from read-only scripts*}

    test {FUNCTION - test fcall_ro with read only commands} {
        r function load lua test REPLACE [get_function_code test {return redis.call('get', 'x')}]
        r set x 1
        r fcall_ro test 0
    } {1}

    test {FUNCTION - test keys and argv} {
        r function load lua test REPLACE [get_function_code test {return redis.call('set', KEYS[1], ARGV[1])}]
        r fcall test 1 x foo
        r get x
    } {foo}

    test {FUNCTION - test command get keys on fcall} {
        r COMMAND GETKEYS fcall test 1 x foo
    } {x}

    test {FUNCTION - test command get keys on fcall_ro} {
        r COMMAND GETKEYS fcall_ro test 1 x foo
    } {x}

    test {FUNCTION - test function kill} {
        set rd [redis_deferring_client]
        r config set script-time-limit 10
        r function load lua test REPLACE [get_function_code test {local a = 1 while true do a = a + 1 end}]
        $rd fcall test 0
        after 200
        catch {r ping} e
        assert_match {BUSY*} $e
        assert_match {running_script {name test command {fcall test 0} duration_ms *} engines LUA} [r FUNCTION STATS]
        r function kill
        after 200 ; # Give some time to Lua to call the hook again...
        assert_equal [r ping] "PONG"
    }

    test {FUNCTION - test script kill not working on function} {
        set rd [redis_deferring_client]
        r config set script-time-limit 10
        r function load lua test REPLACE [get_function_code test {local a = 1 while true do a = a + 1 end}]
        $rd fcall test 0
        after 200
        catch {r ping} e
        assert_match {BUSY*} $e
        catch {r script kill} e
        assert_match {BUSY*} $e
        r function kill
        after 200 ; # Give some time to Lua to call the hook again...
        assert_equal [r ping] "PONG"
    }

    test {FUNCTION - test function kill not working on eval} {
        set rd [redis_deferring_client]
        r config set script-time-limit 10
        $rd eval {local a = 1 while true do a = a + 1 end} 0
        after 200
        catch {r ping} e
        assert_match {BUSY*} $e
        catch {r function kill} e
        assert_match {BUSY*} $e
        r script kill
        after 200 ; # Give some time to Lua to call the hook again...
        assert_equal [r ping] "PONG"
    }

    test {FUNCTION - test function flush} {
        r function load lua test REPLACE [get_function_code test {local a = 1 while true do a = a + 1 end}]
        assert_match {{library_name test engine LUA description {} functions {{name test description {}}}}} [r function list]
        r function flush
        assert_match {} [r function list]

        r function load lua test REPLACE [get_function_code test {local a = 1 while true do a = a + 1 end}]
        assert_match {{library_name test engine LUA description {} functions {{name test description {}}}}} [r function list]
        r function flush async
        assert_match {} [r function list]

        r function load lua test REPLACE [get_function_code test {local a = 1 while true do a = a + 1 end}]
        assert_match {{library_name test engine LUA description {} functions {{name test description {}}}}} [r function list]
        r function flush sync
        assert_match {} [r function list]
    }

    test {FUNCTION - test function wrong argument} {
        catch {r function flush bad_arg} e
        assert_match {*only supports SYNC|ASYNC*} $e

        catch {r function flush sync extra_arg} e
        assert_match {*wrong number of arguments*} $e
    }
}

start_server {tags {"scripting repl external:skip"}} {
    start_server {} {
        test "Connect a replica to the master instance" {
            r -1 slaveof [srv 0 host] [srv 0 port]
            wait_for_condition 50 100 {
                [s -1 role] eq {slave} &&
                [string match {*master_link_status:up*} [r -1 info replication]]
            } else {
                fail "Can't turn the instance into a replica"
            }
        }

        test {FUNCTION - creation is replicated to replica} {
            r function load LUA test DESCRIPTION {some description} [get_function_code test {return 'hello'}]
            wait_for_condition 50 100 {
                [r -1 function list] eq {{library_name test engine LUA description {some description} functions {{name test description {}}}}}
            } else {
                fail "Failed waiting for function to replicate to replica"
            }
        }

        test {FUNCTION - call on replica} {
            r -1 fcall test 0
        } {hello}

        test {FUNCTION - restore is replicated to replica} {
            set e [r function dump]

            r function delete test
            wait_for_condition 50 100 {
                [r -1 function list] eq {}
            } else {
                fail "Failed waiting for function to replicate to replica"
            }

            assert_equal [r function restore $e] {OK}

            wait_for_condition 50 100 {
                [r -1 function list] eq {{library_name test engine LUA description {some description} functions {{name test description {}}}}}
            } else {
                fail "Failed waiting for function to replicate to replica"
            }
        }

        test {FUNCTION - delete is replicated to replica} {
            r function delete test
            wait_for_condition 50 100 {
                [r -1 function list] eq {}
            } else {
                fail "Failed waiting for function to replicate to replica"
            }
        }

        test {FUNCTION - flush is replicated to replica} {
            r function load LUA test DESCRIPTION {some description} [get_function_code test {return 'hello'}]
            wait_for_condition 50 100 {
                [r -1 function list] eq {{library_name test engine LUA description {some description} functions {{name test description {}}}}}
            } else {
                fail "Failed waiting for function to replicate to replica"
            }
            r function flush
            wait_for_condition 50 100 {
                [r -1 function list] eq {}
            } else {
                fail "Failed waiting for function to replicate to replica"
            }
        }

        test "Disconnecting the replica from master instance" {
            r -1 slaveof no one
            # creating a function after disconnect to make sure function
            # is replicated on rdb phase
            r function load LUA test DESCRIPTION {some description} [get_function_code test {return 'hello'}]

            # reconnect the replica
            r -1 slaveof [srv 0 host] [srv 0 port]
            wait_for_condition 50 100 {
                [s -1 role] eq {slave} &&
                [string match {*master_link_status:up*} [r -1 info replication]]
            } else {
                fail "Can't turn the instance into a replica"
            }
        }

        test "FUNCTION - test replication to replica on rdb phase" {
            r -1 fcall test 0
        } {hello}

        test "FUNCTION - test replication to replica on rdb phase info command" {
            r -1 function list
        } {{library_name test engine LUA description {some description} functions {{name test description {}}}}}

        test "FUNCTION - create on read only replica" {
            catch {
                r -1 function load LUA test DESCRIPTION {some description} [get_function_code test {return 'hello'}]
            } e
            set _ $e
        } {*can't write against a read only replica*}

        test "FUNCTION - delete on read only replica" {
            catch {
                r -1 function delete test
            } e
            set _ $e
        } {*can't write against a read only replica*}

        test "FUNCTION - function effect is replicated to replica" {
            r function load LUA test REPLACE [get_function_code test {return redis.call('set', 'x', '1')}]
            r fcall test 0
            assert {[r get x] eq {1}}
            wait_for_condition 50 100 {
                [r -1 get x] eq {1}
            } else {
                fail "Failed waiting function effect to be replicated to replica"
            }
        }

        test "FUNCTION - modify key space of read only replica" {
            catch {
                r -1 fcall test 0
            } e
            set _ $e
        } {*can't write against a read only replica*}
    }
}

test {FUNCTION can processes create, delete and flush commands in AOF when doing "debug loadaof" in read-only slaves} {
    start_server {} {
        r config set appendonly yes
        waitForBgrewriteaof r
        r FUNCTION LOAD lua test "library.register_function('test', function() return 'hello' end)"
        r config set slave-read-only yes
        r slaveof 127.0.0.1 0
        r debug loadaof
        r slaveof no one
        assert_equal [r function list] {{library_name test engine LUA description {} functions {{name test description {}}}}}

        r FUNCTION DELETE test

        r slaveof 127.0.0.1 0
        r debug loadaof
        r slaveof no one
        assert_equal [r function list] {}

        r FUNCTION LOAD lua test "library.register_function('test', function() return 'hello' end)"
        r FUNCTION FLUSH

        r slaveof 127.0.0.1 0
        r debug loadaof
        r slaveof no one
        assert_equal [r function list] {}
    }
} {} {needs:debug external:skip}

start_server {tags {"scripting"}} {
    test {LIBRARIES - test shared function can access default globals} {
        r function load LUA lib1 {
            local function ping()
                return redis.call('ping')
            end
            library.register_function(
                'f1',
                function(keys, args)
                    return ping()
                end
            )
        }
        r fcall f1 0
    } {PONG}

    test {LIBRARIES - usage and code sharing} {
        r function load LUA lib1 REPLACE {
            local function add1(a)
                return a + 1
            end
            library.register_function(
                'f1',
                function(keys, args)
                    return add1(1)
                end,
                'f1 description'
            )
            library.register_function(
                'f2',
                function(keys, args)
                    return add1(2)
                end,
                'f2 description'
            )
        }
        assert_equal [r fcall f1 0] {2}
        assert_equal [r fcall f2 0] {3}
        r function list
    } {{library_name lib1 engine LUA description {} functions {*}}}

    test {LIBRARIES - test registration failure revert the entire load} {
        catch {
            r function load LUA lib1 replace {
                local function add1(a)
                    return a + 2
                end
                library.register_function(
                    'f1',
                    function(keys, args)
                        return add1(1)
                    end
                )
                library.register_function(
                    'f2',
                    'not a function'
                )
            }
        } e
        assert_match {*second argument to library.register_function must be a function*} $e
        assert_equal [r fcall f1 0] {2}
        assert_equal [r fcall f2 0] {3}
    }

    test {LIBRARIES - test registration function name collision} {
        catch {
            r function load LUA lib2 replace {
                library.register_function(
                    'f1',
                    function(keys, args)
                        return 1
                    end
                )
            }
        } e
        assert_match {*Function f1 already exists*} $e
        assert_equal [r fcall f1 0] {2}
        assert_equal [r fcall f2 0] {3}
    }

    test {LIBRARIES - test registration function name collision on same library} {
        catch {
            r function load LUA lib2 replace {
                library.register_function(
                    'f1',
                    function(keys, args)
                        return 1
                    end
                )
                library.register_function(
                    'f1',
                    function(keys, args)
                        return 1
                    end
                )
            }
        } e
        set _ $e
    } {*Function already exists in the library*}

    test {LIBRARIES - test registration with no argument} {
        catch {
            r function load LUA lib2 replace {
                library.register_function()
            }
        } e
        set _ $e
    } {*wrong number of arguments to library.register_function*}

    test {LIBRARIES - test registration with only name} {
        catch {
            r function load LUA lib2 replace {
                library.register_function('f1')
            }
        } e
        set _ $e
    } {*wrong number of arguments to library.register_function*}

    test {LIBRARIES - test registration with to many arguments} {
        catch {
            r function load LUA lib2 replace {
                library.register_function('f1', function() return 1 end, 'description', 'extra arg')
            }
        } e
        set _ $e
    } {*wrong number of arguments to library.register_function*}

    test {LIBRARIES - test registration with no string name} {
        catch {
            r function load LUA lib2 replace {
                library.register_function(nil, function() return 1 end)
            }
        } e
        set _ $e
    } {*first argument to library.register_function must be a string*}

    test {LIBRARIES - test registration with wrong name format} {
        catch {
            r function load LUA lib2 replace {
                library.register_function('test\0test', function() return 1 end)
            }
        } e
        set _ $e
    } {*Function names can only contain letters and numbers and must be at least one character long*}

    test {LIBRARIES - test registration with empty name} {
        catch {
            r function load LUA lib2 replace {
                library.register_function('', function() return 1 end)
            }
        } e
        set _ $e
    } {*Function names can only contain letters and numbers and must be at least one character long*}

    test {LIBRARIES - math.random from function load} {
        catch {
            r function load LUA lib2 replace {
                return math.random()
            }
        } e
        set _ $e
    } {*attempted to access nonexistent global variable 'math'*}

    test {LIBRARIES - redis.call from function load} {
        catch {
            r function load LUA lib2 replace {
                return redis.call('ping')
            }
        } e
        set _ $e
    } {*attempted to access nonexistent global variable 'redis'*}

    test {LIBRARIES - redis.call from function load} {
        catch {
            r function load LUA lib2 replace {
                return redis.setresp(3)
            }
        } e
        set _ $e
    } {*attempted to access nonexistent global variable 'redis'*}

    test {LIBRARIES - redis.set_repl from function load} {
        catch {
            r function load LUA lib2 replace {
                return redis.set_repl(redis.REPL_NONE)
            }
        } e
        set _ $e
    } {*attempted to access nonexistent global variable 'redis'*}

    test {LIBRARIES - malicious access test} {
        # the 'library' API is not expose inside a
        # function context and the 'redis' API is not
        # expose on the library registration context.
        # But a malicious user might find a way to hack it
        # (like demonstrate in the test). For this we
        # have another level of protection on the C
        # code itself and we want to test it and verify
        # that it works properly.
        r function load LUA lib1 replace {
            local lib = library
            lib.register_function('f1', function ()
                lib.redis = redis
                lib.math = math
                return {ok='OK'}
            end)

            lib.register_function('f2', function ()
                lib.register_function('f1', function ()
                    lib.redis = redis
                    lib.math = math
                    return {ok='OK'}
                end)
            end)
        }
        assert_equal {OK} [r fcall f1 0]

        catch {[r function load LUA lib2 {library.math.random()}]} e
        assert_match {*can only be called inside a script invocation*} $e

        catch {[r function load LUA lib2 {library.math.randomseed()}]} e
        assert_match {*can only be called inside a script invocation*} $e

        catch {[r function load LUA lib2 {library.redis.call('ping')}]} e
        assert_match {*can only be called inside a script invocation*} $e

        catch {[r function load LUA lib2 {library.redis.pcall('ping')}]} e
        assert_match {*can only be called inside a script invocation*} $e

        catch {[r function load LUA lib2 {library.redis.setresp(3)}]} e
        assert_match {*can only be called inside a script invocation*} $e

        catch {[r function load LUA lib2 {library.redis.set_repl(library.redis.REPL_NONE)}]} e
        assert_match {*can only be called inside a script invocation*} $e

        catch {[r fcall f2 0]} e
        assert_match {*can only be called on FUNCTION LOAD command*} $e
    }

    test {LIBRARIES - delete removed all functions on library} {
        r function delete lib1
        r function list
    } {}

    test {LIBRARIES - register function inside a function} {
        r function load LUA lib {
            library.register_function(
                'f1',
                function(keys, args)
                    library.register_function(
                        'f2',
                        function(key, args)
                            return 2
                        end
                    )
                    return 1
                end
            )
        }
        catch {r fcall f1 0} e
        set _ $e
    } {*attempted to access nonexistent global variable 'library'*}

    test {LIBRARIES - register library with no functions} {
        r function flush
        catch {
            r function load LUA lib {
                return 1
            }
        } e
        set _ $e
    } {*No functions registered*}

    test {LIBRARIES - load timeout} {
        catch {
            r function load LUA lib {
                local a = 1
                while 1 do a = a + 1 end
            }
        } e
        set _ $e
    } {*FUNCTION LOAD timeout*}

    test {LIBRARIES - verify global protection on the load run} {
        catch {
            r function load LUA lib {
                a = 1
            }
        } e
        set _ $e
    } {*attempted to create global variable 'a'*}

    test {FUNCTION - test function restore with function name collision} {
        r function flush
        r function load lua lib1 {
            local function add1(a)
                return a + 1
            end
            library.register_function(
                'f1',
                function(keys, args)
                    return add1(1)
                end
            )
            library.register_function(
                'f2',
                function(keys, args)
                    return add1(2)
                end
            )
            library.register_function(
                'f3',
                function(keys, args)
                    return add1(3)
                end
            )
        }
        set e [r function dump]
        r function flush

        # load a library with different name but with the same function name
        r function load lua lib1 {
            library.register_function(
                'f6',
                function(keys, args)
                    return 7
                end
            )
        }
        r function load lua lib2 {
            local function add1(a)
                return a + 1
            end
            library.register_function(
                'f4',
                function(keys, args)
                    return add1(4)
                end
            )
            library.register_function(
                'f5',
                function(keys, args)
                    return add1(5)
                end
            )
            library.register_function(
                'f3',
                function(keys, args)
                    return add1(3)
                end
            )
        }

        catch {r function restore $e} error
        assert_match {*Library lib1 already exists*} $error
        assert_equal [r fcall f3 0] {4}
        assert_equal [r fcall f4 0] {5}
        assert_equal [r fcall f5 0] {6}
        assert_equal [r fcall f6 0] {7}

        catch {r function restore $e replace} error
        assert_match {*Function f3 already exists*} $error
        assert_equal [r fcall f3 0] {4}
        assert_equal [r fcall f4 0] {5}
        assert_equal [r fcall f5 0] {6}
        assert_equal [r fcall f6 0] {7}
    }

    test {FUNCTION - test function list with code} {
        r function flush
        r function load lua library1 {library.register_function('f6', function(keys, args) return 7 end)}
        r function list withcode
    } {{library_name library1 engine LUA description {} functions {{name f6 description {}}} library_code {library.register_function('f6', function(keys, args) return 7 end)}}}

    test {FUNCTION - test function list with pattern} {
        r function load lua lib1 {library.register_function('f7', function(keys, args) return 7 end)}
        r function list libraryname library*
    } {{library_name library1 engine LUA description {} functions {{name f6 description {}}}}}

    test {FUNCTION - test function list wrong argument} {
        catch {r function list bad_argument} e
        set _ $e
    } {*Unknown argument bad_argument*}

    test {FUNCTION - test function list with bad argument to library name} {
        catch {r function list libraryname} e
        set _ $e
    } {*library name argument was not given*}

    test {FUNCTION - test function list withcode multiple times} {
        catch {r function list withcode withcode} e
        set _ $e
    } {*Unknown argument withcode*}

    test {FUNCTION - test function list libraryname multiple times} {
        catch {r function list withcode libraryname foo libraryname foo} e
        set _ $e
    } {*Unknown argument libraryname*}

    test {FUNCTION - verify OOM on function load and function restore} {
        r function flush
        r function load lua test replace {library.register_function('f1', function() return 1 end)}
        set payload [r function dump]
        r config set maxmemory 1

        r function flush
        catch {r function load lua test replace {library.register_function('f1', function() return 1 end)}} e
        assert_match {*command not allowed when used memory*} $e

        r function flush
        catch {r function restore $payload} e
        assert_match {*command not allowed when used memory*} $e

        r config set maxmemory 0
    }
}
