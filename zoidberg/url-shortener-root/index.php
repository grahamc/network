<?php

define('URL_ROOT_DIR', '/var/lib/url-shortener');
if (isset($_GET['src'])) { echo highlight_file(__FILE__); exit; }

function get_ids_in_use()
{
    $files = [];
    foreach (glob(URL_ROOT_DIR . '/url-*') as $file) {
        if (is_id_old($file)) {
            unlink($file);
            continue;
        }

        $files[] = (int) str_replace(URL_ROOT_DIR . "/url-", "", $file);
    }

    return $files;
}

function is_id_old($file)
{
    return filemtime($file) < strtotime('-24 hours');
}

function get_lowest_id()
{
    $ids = get_ids_in_use();
    if (empty($ids)) {
        return 1;
    }

    $maxId = max($ids) + 1; // Add one so at least the last ID is possible
    $possibleIds = range(1, $maxId);
    $diffs = array_diff($possibleIds, $ids);

    return min($diffs);
}

function write_url($url)
{
    $existingId = read_id_by_url($url);
    if (is_int($existingId)) {
        return $existingId;
    }

    $id = get_lowest_id();
    $file = URL_ROOT_DIR . '/url-' . (int)$id;

    file_put_contents($file, $url);

    return $id;
}

function read_id_by_url($url)
{
    foreach (get_ids_in_use() as $id) {
        $readUrl = file_get_contents(URL_ROOT_DIR . '/url-' . (int)$id);

        if ($url == $readUrl) {
            return $id;
        }
    }

    return false;
}

function read_by_id($id)
{
    if (in_array($id, get_ids_in_use())) {
        return file_get_contents(URL_ROOT_DIR . '/url-' . (int)$id);
    }

    return false;
}


if (isset($_GET['rl'])) {
    header('HTTP/1.0 201 Created');
    $url = $_GET['rl'];
    echo "https://u.gsc.io/" . write_url($url);
} else if (isset($_GET['n'])) {
    $url = read_by_id($_GET['n']);
    if ($url !== false) {
        header('Location: ' . $url);
        exit(1);
    } else if (is_numeric($_GET['n'])) {
        header("HTTP/1.0 404 Not Found");
    }
} else {
    echo "create a url by GET /?rl=http...\nthe urls expire after 24 hours starting back at zero";
}
