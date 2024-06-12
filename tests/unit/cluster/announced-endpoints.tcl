start_cluster 2 2 {tags {external:skip cluster}} {

    test "Test change cluster-announce-port and cluster-announce-tls-port at runtime" {
        if {$::tls} {
            set baseport [lindex [R 0 config get tls-port] 1]
        } else {
            set baseport [lindex [R 0 config get port] 1]
        }
        set count [expr [llength $::servers] + 1]
        set used_port [find_available_port $baseport $count]

        R 0 config set cluster-announce-tls-port $used_port
        R 0 config set cluster-announce-port $used_port

        assert_match "*:$used_port@*" [R 0 CLUSTER NODES]
        wait_for_condition 50 100 {
            [string match "*:$used_port@*" [R 1 CLUSTER NODES]]
        } else {
            fail "Cluster announced port was not propagated via gossip"
        }

        R 0 config set cluster-announce-tls-port 0
        R 0 config set cluster-announce-port 0
        assert_match "*:$baseport@*" [R 0 CLUSTER NODES]
    }

    test "Test change cluster-announce-bus-port at runtime" {
        if {$::tls} {
            set baseport [lindex [R 0 config get tls-port] 1]
        } else {
            set baseport [lindex [R 0 config get port] 1]
        }
        set count [expr [llength $::servers] + 1]
        set used_port [find_available_port $baseport $count]

        # Verify config set cluster-announce-bus-port
        R 0 config set cluster-announce-bus-port $used_port
        assert_match "*@$used_port *" [R 0 CLUSTER NODES]
        wait_for_condition 50 100 {
            [string match "*@$used_port *" [R 1 CLUSTER NODES]]
        } else {
            fail "Cluster announced port was not propagated via gossip"
        }

        # Verify restore default cluster-announce-port
        set base_bus_port [expr $baseport + 10000]
        R 0 config set cluster-announce-bus-port 0
        assert_match "*@$base_bus_port *" [R 0 CLUSTER NODES]
    }

    test "Test change cluster-announce-ip at runtime" {
        assert_error "ERR CONFIG SET failed*" {
            R 0 config set cluster-announce-ip 127.0.0.1:1234
        }
        assert_error "ERR CONFIG SET failed*" {
            R 0 config set cluster-announce-ip redis.example.com:1234
        }
        # Check that we accept an IP or a hostname (for backward compatibility)
        assert_equal OK [R 0 config set cluster-announce-ip 127.0.0.1]
        assert_equal {cluster-announce-ip 127.0.0.1} [R 0 config get cluster-announce-ip]
        assert_equal OK [R 0 config set cluster-announce-ip redis.example.com]
        assert_equal {cluster-announce-ip redis.example.com} [R 0 config get cluster-announce-ip]
        assert_equal OK [R 0 config set cluster-announce-ip ""]
        assert_equal {cluster-announce-ip {}} [R 0 config get cluster-announce-ip]
    }
}
