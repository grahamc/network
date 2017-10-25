<?php

require __DIR__ . '/config.php';

# define('AMQP_DEBUG', true);
$connection = rabbitmq_conn();
$channel = $connection->channel();


list($queueName, , ) = $channel->queue_declare('build-inputs',
                                               false, true, false, false);
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

    $co = new GHE\Checkout("/home/grahamc/.nix-test", "builder");
    $pname = $co->checkOutRef($in->repository->full_name,
                              $in->repository->clone_url,
                              $in->issue->number,
                              "origin/master"
    );

    $co->applyPatches($pname, $in->issue->pull_request->patch_url);

    $cmt = array_map(function($term) { return trim($term); },
                     array_filter($cmt,
                                  function($term) { return $term != "@grahamcofborg"; }
                     )
    );

    if (count($cmt) == 1 && implode("", $cmt) == "default") {
        echo "building via nix-build .\n";
        reply_to_issue($in, 'nix-build --keep-going .', []);
    } else {
        echo "building via nix-build . -A\n";
        $attrs = array_intersperse($cmt, '-A');

        $fillers = implode(" ", array_fill(0, count($attrs), '%s'));

        reply_to_issue($in, 'nix-build --keep-going . ' . $fillers, $attrs);
    }

    $msg->delivery_info['channel']->basic_ack($msg->delivery_info['delivery_tag']);

    // shell_exec('git fetch origin && git reset --hard origin/master && ');
}

function array_intersperse($array, $val) {
    array_reduce($l,
                      function($c, $elem) {
                          $c[] = $val;
                          $c[] = $elem;
                          return $c;
                      },
                      array());
}


function reply_to_issue($issue, $to_exec, $args) {
    $client = gh_client();
    $pr = $client->api('pull_request')->show(
        $issue->repository->owner->login,
        $issue->repository->name,
        $issue->issue->number
    );
    $sha = $pr['head']['sha'];

    try {
        $output = GHE\Exec::exec($to_exec, $args);
        $pass = true;
    } catch (GHE\ExecException $e) {
        $output = $e->getOutput();
        $pass = false;
    }

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
            'event' => $pass ? 'APPROVE' : 'COMMENT',
            'commit_id' => $sha,
        ));

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
