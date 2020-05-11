start_server {tags {"auth"}} {
    test {AUTH fails if there is no password configured server side} {
        catch {r auth foo} err
        set _ $err
    } {ERR*any password*}
}

start_server {tags {"auth"} overrides {requirepass foobar}} {
    test {AUTH fails when a wrong password is given} {
        catch {r auth wrong!} err
        set _ $err
    } {WRONGPASS*}

    test {Arbitrary command gives an error when AUTH is required} {
        catch {r set foo bar} err
        set _ $err
    } {NOAUTH*}

    test {AUTH succeeds when the right password is given} {
        r auth foobar
    } {OK}

    test {Once AUTH succeeded we can actually send commands to the server} {
        r set foo 100
        r incr foo
    } {101}
}

start_server {tags {"auth_binary_password"}} {
    test {AUTH fails when binary password is wrong} {
        r config set requirepass "abc\x00def"
        catch {r auth abc} err
        set _ $err
    } {WRONGPASS*}

    test {AUTH succeeds when binary password is correct} {
        r config set requirepass "abc\x00def"
        r auth "abc\x00def"
    } {OK}

    start_server {tags {"masterauth"}} {
        set master [srv -1 client]
        set master_host [srv -1 host]
        set master_port [srv -1 port]
        set slave [srv 0 client]

        test {MASTERAUTH test with binary password} {
            $master config set requirepass "abc\x00def"

            # Configure the replica with masterauth
            $slave slaveof $master_host $master_port
            $slave config set masterauth "abc"

            # sleep for 3 seconds and verify replica is not in sync with master
            $slave debug sleep 3
            assert_equal {down} [s 0 master_link_status]
            
            # Test replica with the correct masterauth
            $slave config set masterauth "abc\x00def"
            wait_for_condition 50 100 {
                [s 0 master_link_status] eq {up}
            } else {
                fail "Can't turn the instance into a replica"
            }
        }
    }
}
