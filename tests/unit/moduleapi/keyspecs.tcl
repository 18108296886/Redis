set testmodule [file normalize tests/modules/keyspecs.so]

start_server {tags {"modules"}} {
    r module load $testmodule

    test "Module key specs: No spec, only legacy triple" {
        set reply [lindex [r command info kspec.none] 0]
        # Verify (first, last, step) and not movablekeys
        assert_equal [lindex $reply 2] {module}
        assert_equal [lindex $reply 3] 1
        assert_equal [lindex $reply 4] 2
        assert_equal [lindex $reply 5] 1
        # Verify key-spec auto-generated from the legacy triple
        set keyspecs [lindex $reply 8]
        assert_equal [llength $keyspecs] 1
        assert_equal [lindex $keyspecs 0] {flags {RW access update} begin_search {type index spec {index 1}} find_keys {type range spec {lastkey 1 keystep 1 limit 0}}}
    }

    test "Module key specs: Two ranges" {
        set reply [lindex [r command info kspec.tworanges] 0]
        # Verify (first, last, step) and not movablekeys
        assert_equal [lindex $reply 2] {module}
        assert_equal [lindex $reply 3] 1
        assert_equal [lindex $reply 4] 2
        assert_equal [lindex $reply 5] 1
        # Verify key-specs
        set keyspecs [lindex $reply 8]
        assert_equal [lindex $keyspecs 0] {flags {RO access} begin_search {type index spec {index 1}} find_keys {type range spec {lastkey 0 keystep 1 limit 0}}}
        assert_equal [lindex $keyspecs 1] {flags {RW update} begin_search {type index spec {index 2}} find_keys {type range spec {lastkey 0 keystep 1 limit 0}}}
    }

    test "Module key specs: Keyword-only spec clears the legacy triple" {
        set reply [lindex [r command info kspec.keyword] 0]
        # Verify (first, last, step) and movablekeys
        assert_equal [lindex $reply 2] {module movablekeys}
        assert_equal [lindex $reply 3] 0
        assert_equal [lindex $reply 4] 0
        assert_equal [lindex $reply 5] 0
        # Verify key-specs
        set keyspecs [lindex $reply 8]
        assert_equal [lindex $keyspecs 0] {flags {RO access} begin_search {type keyword spec {keyword KEYS startfrom 1}} find_keys {type range spec {lastkey -1 keystep 1 limit 0}}}
    }

    test "Module key specs: Complex specs, case 1" {
        set reply [lindex [r command info kspec.complex1] 0]
        # Verify (first, last, step) and movablekeys
        assert_equal [lindex $reply 2] {module movablekeys}
        assert_equal [lindex $reply 3] 1
        assert_equal [lindex $reply 4] 1
        assert_equal [lindex $reply 5] 1
        # Verify key-specs
        set keyspecs [lindex $reply 8]
        assert_equal [lindex $keyspecs 0] {flags RO begin_search {type index spec {index 1}} find_keys {type range spec {lastkey 0 keystep 1 limit 0}}}
        assert_equal [lindex $keyspecs 1] {flags {RW update} begin_search {type keyword spec {keyword STORE startfrom 2}} find_keys {type range spec {lastkey 0 keystep 1 limit 0}}}
        assert_equal [lindex $keyspecs 2] {flags {RO access} begin_search {type keyword spec {keyword KEYS startfrom 2}} find_keys {type keynum spec {keynumidx 0 firstkey 1 keystep 1}}}
    }

    test "Module key specs: Complex specs, case 2" {
        set reply [lindex [r command info kspec.complex2] 0]
        # Verify (first, last, step) and movablekeys
        assert_equal [lindex $reply 2] {module movablekeys}
        assert_equal [lindex $reply 3] 1
        assert_equal [lindex $reply 4] 2
        assert_equal [lindex $reply 5] 1
        # Verify key-specs
        set keyspecs [lindex $reply 8]
        assert_equal [lindex $keyspecs 0] {flags {RW update} begin_search {type keyword spec {keyword STORE startfrom 5}} find_keys {type range spec {lastkey 0 keystep 1 limit 0}}}
        assert_equal [lindex $keyspecs 1] {flags {RO access} begin_search {type index spec {index 1}} find_keys {type range spec {lastkey 0 keystep 1 limit 0}}}
        assert_equal [lindex $keyspecs 2] {flags {RO access} begin_search {type index spec {index 2}} find_keys {type range spec {lastkey 0 keystep 1 limit 0}}}
        assert_equal [lindex $keyspecs 3] {flags {RW update} begin_search {type index spec {index 3}} find_keys {type keynum spec {keynumidx 0 firstkey 1 keystep 1}}}
        assert_equal [lindex $keyspecs 4] {flags {RW update} begin_search {type keyword spec {keyword MOREKEYS startfrom 5}} find_keys {type range spec {lastkey -1 keystep 1 limit 0}}}
    }

    test "Module command list filtering" {
        ;# Note: we piggyback this tcl file to test the general functionality of command list filtering
        set reply [r command list filterby module keyspecs]
        assert_equal [lsort $reply] {kspec.complex1 kspec.complex2 kspec.keyword kspec.none kspec.tworanges}
    }

    test {COMMAND GETKEYSANDFLAGS correctly reports module key-spec without flags} {
        r command getkeysandflags kspec.none key1 key2
    } {{key1 {RW access update}} {key2 {RW access update}}}

    test {COMMAND GETKEYSANDFLAGS correctly reports module key-spec flags} {
        r command getkeysandflags kspec.keyword keys key1 key2 key3
    } {{key1 {RO access}} {key2 {RO access}} {key3 {RO access}}}

    # user that can only read from "read" keys, write to "write" keys, and read+write to "RW" keys
    r ACL setuser testuser +@all %R~read* %W~write* %RW~rw*

    test "Module key specs: No spec, only legacy triple - ACL" {
        # legacy triple didn't provide flags, so they require both read and write
        assert_equal "OK" [r ACL DRYRUN testuser kspec.none rw]
        assert_equal "This user has no permissions to access the 'read' key" [r ACL DRYRUN testuser kspec.none read read]
        assert_equal "This user has no permissions to access the 'write' key" [r ACL DRYRUN testuser kspec.none write write]
    }

    test "Module key specs: tworanges - ACL" {
        assert_equal "OK" [r ACL DRYRUN testuser kspec.tworanges read write]
        assert_equal "OK" [r ACL DRYRUN testuser kspec.tworanges rw rw]
        assert_equal "This user has no permissions to access the 'read' key" [r ACL DRYRUN testuser kspec.tworanges rw read]
        assert_equal "This user has no permissions to access the 'write' key" [r ACL DRYRUN testuser kspec.tworanges write rw]
    }

    test "Unload the module - keyspecs" {
        assert_equal {OK} [r module unload keyspecs]
    }
}
