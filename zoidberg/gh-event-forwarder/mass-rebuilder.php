<?php

require __DIR__ . '/config.php';

use PhpAmqpLib\Message\AMQPMessage;

# define('AMQP_DEBUG', true);
$connection = rabbitmq_conn();
$channel = $connection->channel();


list($queueName, , ) = $channel->queue_declare('mass-rebuild-checks',
                                               false, true, false, false);
$channel->queue_bind($queueName, 'nixos/nixpkgs');

function outrunner($msg) {
    try {
        $ret = runner($msg);
        var_dump($ret);
        if ($ret === true) {
            echo "acking\n";
            $r = $msg->delivery_info['channel']->basic_ack($msg->delivery_info['delivery_tag']);
            var_dump($r);
        } else {
            echo "Not acking?\n";
        }
    } catch (\GHE\ExecException $e) {
        var_dump($msg);
        var_dump($e->getMessage());
        var_dump($e->getCode());
        var_dump($e->getOutput());
    }
}

function runner($msg) {
    $in = json_decode($msg->body);

    try {
        $etype = \GHE\EventClassifier::classifyEvent($in);

        if ($etype != "pull_request") {
            echo "Skipping event type: $etype\n";
            return true;
        }
    } catch (\GHE\EventClassifierUnknownException $e) {
        echo "Skipping unknown event type\n";
        print_r($in);
        return true;
    }

    if (!\GHE\ACL::isRepoEligible($in->repository->full_name)) {
        echo "Repo not authorized (" . $in->repository->full_name . ")\n";
        return true;
    }

    if ($in->pull_request->state != "open") {
        echo "PR isn't open\n";
        return true;
    }

    $ok_events = [
        'created',
        'edited',
        'synchronize',
    ];

    if (!in_array($in->action, $ok_events)) {
        echo "Uninteresting event " . $in->action . "\n";
        return true;
    }

        $against = "origin/" . $in->pull_request->base->ref;
        echo "Building against $against\n";
        $co = new GHE\Checkout("/home/grahamc/.nix-test", "mr-est");
    $pname = $co->checkOutRef($in->repository->full_name,
            $in->repository->clone_url,
            $in->number,
            $against
            );

    try {
        $co->applyPatches($pname, $in->pull_request->patch_url);
    } catch (GHE\ExecException $e) {
        echo "Received ExecException applying patches, likely due to conflicts:\n";
        var_dump($e->getCode());
        var_dump($e->getMessage());
        var_dump($e->getArgs());
        var_dump($e->getOutput());
        return true;
    }

    reply_to_issue($in, $against);
    return true;
}

function reply_to_issue($issue, $prev) {
    $client = gh_client();

    $output = GHE\Exec::exec('$(nix-instantiate --eval -E %s) %s',
                             [
                                 '<nixpkgs/maintainers/scripts/rebuild-amount.sh>',
                                 $prev
                             ]
    );

    $labels = [];
    foreach ($output as $line) {
        if (preg_match('/^\s*(\d+) (.*)$/', $line, $matches)) {
            var_dump($matches);
            if ($matches[1] > 2500) {
                if ($matches[2] == "x86_64-darwin") {
                    $labels[] = "1.severity: mass-darwin-rebuild";
                } else {
                    $labels[] = "1.severity: mass-rebuild";
                }
            }
        }
    }

    foreach ($labels as $label) {
        echo "will label +$label\n";

        $client->api('issue')->labels()->add(
            $issue->repository->owner->login,
            $issue->repository->name,
            $issue->number,
            $label);
    }
}

$consumerTag = 'consumer' . getmypid();
$channel->basic_consume($queueName, $consumerTag, false, false, false, false, 'outrunner');
while(count($channel->callbacks)) {
    $channel->wait();
}
