<?php

require __DIR__ . '/config.php';

use PhpAmqpLib\Message\AMQPMessage;

# define('AMQP_DEBUG', true);
$connection = rabbitmq_conn();
$channel = $connection->channel();


list($queueName, , ) = $channel->queue_declare('', false, false, true,
                                               true);
$channel->queue_bind($queueName, 'nixos/nixpkgs');

function runner($msg) {
    $in = json_decode($msg->body);

    $ok_names = [
        'nixos/nixpkgs',
    ];

    if (!in_array(strtolower($in->repository->full_name), $ok_names)) {
        echo "repo not ok (" . $in->repository->full_name . ")\n";
        $msg->delivery_info['channel']->basic_ack($msg->delivery_info['delivery_tag']);
        return;
    }

    if (!isset($in->issue) || !isset($in->issue->number)) {
        echo "not an issue\n";
        $msg->delivery_info['channel']->basic_ack($msg->delivery_info['delivery_tag']);
        return;
    }

    #if (!isset($in->issue->pull_request)) {
    #   echo "not a PR\n";
    #   $msg->delivery_info['channel']->basic_ack($msg->delivery_info['delivery_tag']);
    #   return;
    #}

    #if ($in->issue->pull_request->state != "open") {
    #   echo "PR isn't open\n";
    #   $msg->delivery_info['channel']->basic_ack($msg->delivery_info['delivery_tag']);
    #   return;
    #}

    $ok_events = [
        'created',
        'edited',
        'synchronized',
    ];
    if (!in_array($in->action, $ok_events)) {
        echo "Uninteresting event " . $in->action . "\n";
        #$msg->delivery_info['channel']->basic_ack($msg->delivery_info['delivery_tag']);
        #return;
    }


    $root = "/home/grahamc/.nix-test";
    if (!is_dir($root)) {
        exit("$root doesn't exist!");
    }
    if (!chdir($root)) {
        exit("Failed to chdir $root");
    }
    $pname = $root . "/repo-" . md5($in->repository->full_name);
    if (!is_dir($pname) || !chdir($pname)) {
        echo "Cloning " . $in->repository->full_name . " to $pname\n";
        shell_exec('git clone --bare ' .
                   escapeshellarg($in->repository->clone_url)
                   . ' ' . escapeshellarg($pname));
    } else {
        echo "fetching " . $in->repository->full_name . " in $pname\n";
        if (!chdir($pname)) {
            echo "failed to chdir to $pname\n";
            exit();
        }
        shell_exec('git fetch origin');
    }

    $bname = $root . "/estimate-" . md5($in->repository->full_name)
           . "-" . $in->issue->number;
    if (!is_dir($bname) || !chdir($bname)) {
        echo "Cloning " . $in->issue->html_url . " to $bname\n";
        shell_exec('git clone --reference-if-able ' .
                   escapeshellarg($pname) . ' ' .
                   escapeshellarg($in->repository->clone_url)
                   . ' ' . escapeshellarg($bname));
    } else {
        if (!chdir($bname)) {
            echo "failed to chdir to $bname\n";
            exit();
        }

        echo "fetching " . $in->repository->full_name . " in $bname\n";
        shell_exec('git fetch origin');
        shell_exec('git reset --hard origin/master');
    }

    if (!chdir($bname)) {
        echo "failed to chdir to $bname\n";
        exit();
    }

    $prev = shell_exec('git rev-parse HEAD');
    echo shell_exec('curl -L ' . escapeshellarg($in->issue->pull_request->patch_url) . ' | git am --no-gpg-sign -');

    reply_to_issue($in, trim($prev));

    $msg->delivery_info['channel']->basic_ack($msg->delivery_info['delivery_tag']);
}

function reply_to_issue($issue, $prev) {
    $client = gh_client();

    $pr = $client->api('pull_request')->show(
        $issue->repository->owner->login,
        $issue->repository->name,
        $issue->issue->number
    );
    $head = $pr['head']['sha'];
    $base = $pr['base']['sha'];

    $cmd = "$(nix-instantiate --eval -E '<nixpkgs/maintainers/scripts/rebuild-amount.sh>') "
         . escapeshellarg($prev)
         . " | tail -n+2";
    echo "$cmd\n";

    $c = shell_exec($cmd);

    $labels = [];
    foreach (explode("\n", $c) as $line) {
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
        echo "would label +$label\n";

        $client->api('issue')->labels()->add(
            $issue->repository->owner->login,
            $issue->repository->name,
            $issue->issue->number,
            $label);
    }



}

$consumerTag = 'consumer' . getmypid();
$channel->basic_consume($queueName, $consumerTag, false, false, false, false, 'runner');
while(count($channel->callbacks)) {
    $channel->wait();
}
