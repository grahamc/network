<?php

$queues = json_decode(file_get_contents('http://USER:PASSWORD@127.0.0.1:15672/api/queues'), true);

$stats = array_map(
    function($queue) {
        $total_msgs = $queue['messages'];
        $todo = $queue['messages_ready'];

        return [
            'name' => $queue['name'],
            'consumers' => $queue['consumers'],
            'messages' => [
                'waiting' => $todo,
                'in_progress' => $total_msgs - $todo,
            ],
        ];
    },
    $queues
);

$filtered_stats = array_filter($stats,
                       function($queue) {
                           return (strpos($queue['name'], 'build-inputs-') === 0)
                               || ($queue['name'] === 'mass-rebuild-check-jobs');
                       }
);


$categorized_stats = array_reduce(
    $filtered_stats,
    function($collector, $arch) {
        $name = $arch['name'];
        unset($arch['name']);

        if ($name === 'mass-rebuild-check-jobs') {
            $collector['evaluator'] = $arch;
        } elseif (strpos($name, 'build-inputs-') === 0) {
            if (!isset($collector['build-queues'])) {
                $collector['build-queues'] = [];
            }

            $collector['build-queues'][$name] = $arch;
        }

        return $collector;
    },
    []
);


header('Content-Type: application/json');
echo json_encode($categorized_stats, JSON_PRETTY_PRINT);
