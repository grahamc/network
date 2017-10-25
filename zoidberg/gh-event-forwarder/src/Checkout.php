<?php

namespace GHE;

class Checkout {

    protected $root;

    function __construct($root) {
        $this->root = $root;
    }

    function checkOutRef($repo_name, $clone_url, $id, $ref) {
        $this->prefetchRepoCache($repo_name, $clone_url);

        $pname = $this->pathToRepoCache($repo_name);
        $bname = $this->pathToBuildDir($repo_name, $id);

        if (!is_dir($bname)) {
            echo "Cloning " . $in->issue->html_url . " to $bname\n";
            Exec::exec('git clone --reference-if-able %s %s %s',
                       [
                           $pname,
                           $clone_url,
                           $bname
                       ]);
        }

        if (!chdir($bname)) {
            throw new CoFailedException("Failed to chdir to $bname\n");
        }

        echo "fetching " . $in->repository->full_name . " in $bname\n";
        Exec::exec('git fetch origin');
        Exec::exec('git reset --hard %s', [$ref]);

        return $bname;
    }

    function applyPatches($bname, $patch_url) {
        if (!chdir($bname)) {
            throw new CoFailedException("Failed to chdir to $bname\n");
        }

        Exec::exec('curl -L %s | git am --no-gpg-sign -', [$patch_url]);
    }

    function prefetchRepoCache($name, $clone_url) {
        if (!chdir($this->root)) {
            throw new CoFailedException("Failed to chdir to " . $this->root);
        }

        $pname = $this->pathToRepoCache($name);
        if (!is_dir($pname)) {
            echo "Cloning " . $name . " to $pname\n";
            Exec::exec('git clone --bare %s %s',
                       [
                           $clone_url,
                           $pname
                       ]);
        }

        if (!chdir($pname)) {
            throw new CoFailedException("Failed to chdir to $pname");
        }

        echo "Fetching $name to $pname\n";
        Exec::exec('git fetch origin');
    }

    function pathToRepoCache($name) {
        return $this->root . "/repo-" . md5($name);
    }

    function pathToBuildDir($repo, $id_number) {
        $id = (int) $id_number;
        return $this->root . "/build-" . md5($repo) . "-" . $id;
    }

}

class CoFailedException extends \Exception {}