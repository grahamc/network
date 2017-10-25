<?php

require __DIR__ . '/config.php';
use PhpAmqpLib\Message\AMQPMessage;

# define('AMQP_DEBUG', true);
$connection = rabbitmq_conn();
$channel = $connection->channel();

$channel->exchange_declare('build-jobs', 'fanout', false, true, false);


list($queueName, , ) = $channel->queue_declare('build-inputs',
                                               false, true, false, false);
$channel->queue_bind($queueName, 'nixos/nixpkgs');
$channel->queue_bind($queueName, 'grahamc/elm-stuff');

function runner($msg) {
    $in = json_decode($msg->body);
    if (!isset($in->comment)) {
        echo "event not a comment\n";
        $msg->delivery_info['channel']->basic_ack($msg->delivery_info['delivery_tag']);
        return;
    }

    if (!\GHE\ACL::isUserAuthorized($in->comment->user->login)) {
        echo "commenter not ok (" . $in->comment->user->login . ")\n";
        $msg->delivery_info['channel']->basic_ack($msg->delivery_info['delivery_tag']);
        return;
    }

    if (!\GHE\ACL::isRepoEligible($in->repository->full_name)) {
        echo "repo not ok (" . $in->repository->full_name . ")\n";
        $msg->delivery_info['channel']->basic_ack($msg->delivery_info['delivery_tag']);
        return;
    }

    if (!isset($in->issue->pull_request)) {
        echo "not a PR\n";
        $msg->delivery_info['channel']->basic_ack($msg->delivery_info['delivery_tag']);
        return;
    }

    #if ($in->issue->pull_request->state != "open") {
    #   echo "PR isn't open\n";
    #   $msg->delivery_info['channel']->basic_ack($msg->delivery_info['delivery_tag']);
    #   return;
    #}

    $cmt = explode(' ', strtolower($in->comment->body));
    if (!in_array('@grahamcofborg', $cmt)) {
        echo "not a borgpr\n";
        $msg->delivery_info['channel']->basic_ack($msg->delivery_info['delivery_tag']);
        return;
    }

    $tokens = array_map(function($term) { return trim($term); },
                     array_filter($cmt,
                                  function($term) {
                                      return !in_array($term, [
                                          "@grahamcofborg",
                                          "",
                                      ]);
                                  }
                     )
    );

    if (count($tokens) == 1 && implode("", $tokens) == "default") {
        $forward = [
            'payload' => $in,
            'build_default' => true,
            'attrs' => [],
        ];
    } else {
        $forward = [
            'payload' => $in,
            'build_default' => false,
            'attrs' => $tokens,
        ];
    }

    $message = new AMQPMessage(json_encode($forward),
                               array('content_type' => 'application/json'));
    $msg->delivery_info['channel']->basic_publish($message, 'build-jobs');
    $msg->delivery_info['channel']->basic_ack($msg->delivery_info['delivery_tag']);
}


function outrunner($msg) {
    try {
        return runner($msg);
    } catch (ExecException $e) {
        var_dump($e->getMessage());
        var_dump($e->getCode());
        var_dump($e->getOutput());
    }
}

$consumerTag = 'consumer' . getmypid();
$channel->basic_consume($queueName, $consumerTag, false, false, false, false, 'outrunner');
while(count($channel->callbacks)) {
    $channel->wait();
}
