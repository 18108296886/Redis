# Test PUBSUB shard propagation in a cluster slot.

source "../tests/includes/init-tests.tcl"

test "Create a 3 nodes cluster" {
    cluster_create_with_continuous_slots 3 3
}

set cluster [redis_cluster 127.0.0.1:[get_instance_attrib redis 0 port]]
test "Pub/Sub shard basics" {

    set slot [$cluster cluster keyslot "channel.0"]
    array set publishnode [$cluster masternode_for_slot $slot]
    array set notshardnode [$cluster masternode_notfor_slot $slot]

    set publishclient [redis_client_by_addr $publishnode(host) $publishnode(port)]
    set subscribeclient [redis_deferring_client_by_addr $publishnode(host) $publishnode(port)]
    set subscribeclient2 [redis_deferring_client_by_addr $publishnode(host) $publishnode(port)]
    set anotherclient [redis_deferring_client_by_addr $notshardnode(host) $notshardnode(port)]

    $subscribeclient ssubscribe channel.0
    $subscribeclient read

    $subscribeclient2 ssubscribe channel.0
    $subscribeclient2 read

    $anotherclient ssubscribe channel.0
    catch {$anotherclient read} err
    assert_match {MOVED *} $err

    set data [randomValue]
    $publishclient spublish channel.0 $data

    set msg [$subscribeclient read]
    assert_equal $data [lindex $msg 2]

    set msg [$subscribeclient2 read]
    assert_equal $data [lindex $msg 2]

    $publishclient close
    $subscribeclient close
    $subscribeclient2 close
    $anotherclient close
}

test "PUBSUB SHARDNUMSUB blocks CROSSSLOT" {
    catch {$cluster pubsub shardnumsub channel.0 channel.1} err
    assert_match {CROSSSLOT Keys*} $err
}

test "client can't subscribe to multiple shard channels across different slots in same call" {
    catch {$cluster ssubscribe channel.0 channel.1} err
    assert_match {CROSSSLOT Keys*} $err
}

test "client can subscribe to multiple shard channels across different slots in separate call" {
    $cluster ssubscribe ch3
    $cluster ssubscribe ch7

    $cluster sunsubscribe ch3
    $cluster sunsubscribe ch7
}


test "Verify Pub/Sub and Pub/Sub shard no overlap" {
    set slot [$cluster cluster keyslot "channel.0"]
    array set publishnode [$cluster masternode_for_slot $slot]
    array set notshardnode [$cluster masternode_notfor_slot $slot]

    set publishshardclient [redis_client_by_addr $publishnode(host) $publishnode(port)]
    set publishclient [redis_deferring_client_by_addr $publishnode(host) $publishnode(port)]
    set subscribeshardclient [redis_deferring_client_by_addr $publishnode(host) $publishnode(port)]
    set subscribeclient [redis_deferring_client_by_addr $publishnode(host) $publishnode(port)]

    $subscribeshardclient deferred 1
    $subscribeshardclient ssubscribe channel.0
    $subscribeshardclient read

    $subscribeclient deferred 1
    $subscribeclient subscribe channel.0
    $subscribeclient read

    set sharddata "testingpubsubdata"
    $publishshardclient spublish channel.0 $sharddata

    set data "somemoredata"
    $publishclient publish channel.0 $data

    set msg [$subscribeshardclient read]
    assert_equal $sharddata [lindex $msg 2]

    set msg [$subscribeclient read]
    assert_equal $data [lindex $msg 2]

    $cluster close
    $publishclient close
    $subscribeclient close
    $subscribeshardclient close
}