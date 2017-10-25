<?php

require __DIR__ . '/config.php';

# define('AMQP_DEBUG', true);
$connection = rabbitmq_conn();
$channel = $connection->channel();


list($queueName, , ) = $channel->queue_declare('', false, false, true,
                                               true);
var_dump($queueName);
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

    $bname = $root . "/build-" . md5($in->repository->full_name)
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
    echo shell_exec('curl -L ' . escapeshellarg($in->issue->pull_request->patch_url) . ' | git am --no-gpg-sign -');

    $cmt = array_map(function($term) { return trim($term); },
                     array_filter($cmt,
                                  function($term) { return $term != "@grahamcofborg"; }
                     )
    );

    if (count($cmt) == 1 && implode("", $cmt) == "default") {
        echo "building via nix-build .\n";
        reply_to_issue($in, 'nix-build --keep-going . 2>&1');
    } else {
        echo "building via nix-build . -A\n";
        $attrs = implode(' ', array_map(function($attr) {
            return "-A " . escapeshellarg($attr);
        }, $cmt));
        var_dump($attrs);

        reply_to_issue($in, 'nix-build --keep-going . ' . $attrs . ' 2>&1');
    }

    $msg->delivery_info['channel']->basic_ack($msg->delivery_info['delivery_tag']);

    // shell_exec('git fetch origin && git reset --hard origin/master && ');
}

function reply_to_issue($issue, $to_exec) {
    $client = gh_client();
    $pr = $client->api('pull_request')->show(
        $issue->repository->owner->login,
        $issue->repository->name,
        $issue->issue->number
    );
    $sha = $pr['head']['sha'];

    exec($to_exec, $output, $return);

    // var_dump($issue);

    $lastlines = implode("\n",
                         array_reverse(
                             array_slice(
                                 array_reverse($output),
                                 0, 10
                             )
                         )
    );

    $reviews = $client->api('pull_request')->reviews()->all(
        $issue->repository->owner->login,
        $issue->repository->name,
        $issue->issue->number
    );

    $client->api('pull_request')->reviews()->create(
        $issue->repository->owner->login,
        $issue->repository->name,
        $issue->issue->number,
        array(
            'body' => "```\n$lastlines\n```",
            'event' => $return == 0 ? 'APPROVE' : 'COMMENT',
            'commit_id' => $sha,
        ));

}

$consumerTag = 'consumer' . getmypid();
$channel->basic_consume($queueName, $consumerTag, false, false, false, false, 'runner');
while(count($channel->callbacks)) {
    $channel->wait();
}
