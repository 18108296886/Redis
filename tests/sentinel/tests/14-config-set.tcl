source "../tests/includes/init-tests.tcl"

test "SENTINEL CONFIG SET handles multiple variables" {
    foreach_sentinel_id id {
        assert_equal {OK} [S $id SENTINEL CONFIG SET resolve-hostnames yes announce-port 1234]
    }

    assert_match {*yes*} [S 1 SENTINEL CONFIG GET resolve-hostnames]
    assert_match {*1234*} [S 1 SENTINEL CONFIG GET announce-port]
}

test "SENTINEL CONFIG SET duplicate variables" {
    catch {[S 1 SENTINEL CONFIG SET resolve-hostnames yes announce-port 1234 announce-port 100]} e
    if {![string match "*Duplicate argument*" $e]} {
        fail "Should give wrong arity error"
    }
}

test "SENTINEL CONFIG SET, one option does not exist" {

    foreach_sentinel_id id {
        assert_equal {OK} [S $id SENTINEL CONFIG SET announce-port 111]

        catch {[S $id SENTINEL CONFIG SET does-not-exist yes announce-port 1234]} e
        if {![string match "*Invalid argument*" $e]} {
            fail "Should give Invalid argument error"
        }
    }

    # The announce-port should not be set to 1234 as it was called with a wrong argument
    assert_match {*111*} [S 1 SENTINEL CONFIG GET announce-port]
}

test "SENTINEL CONFIG SET, one option with wrong value" {

    foreach_sentinel_id id {
        assert_equal {OK} [S $id SENTINEL CONFIG SET resolve-hostnames no]

        catch {[S $id SENTINEL CONFIG SET announce-port -1234 resolve-hostnames yes]} e
        if {![string match "*Invalid value*" $e]} {
            fail "Expected to return Invalid value error"
        }
    }

    # The resolve-hostnames should not be set to yes as it was called after an argument with an invalid value
    assert_match {*no*} [S 1 SENTINEL CONFIG GET resolve-hostnames]
}

test "SENTINEL CONFIG SET, wrong number of arguments" {

    catch {[S 1 SENTINEL CONFIG SET resolve-hostnames yes announce-port 1234 announce-ip]} e
    if {![string match "*Missing argument*" $e]} {
        fail "Expected to return Missing argument error"
    }
}
