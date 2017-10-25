# grahamcofborg

1. All github events go in to web/index.php, which sends the event to
   an exchange named for the full name of the repo (ex: nixos/nixpkgs)
   in lower case. The exchange is set to "fanout"
2. build-filter.php creates a queue called build-inputs and binds it
   to the nixos/nixpkgs exchange. It also creates an exchange,
   build-jobs, set to fan out. It listens for messages on the
   build-inputs queue. Issue comments from authorized users on
   PRs get tokenized and turned in to build instructions. These jobs
   are then written to the build-jobs exchange.
3. builder.php creates a queue called `build-inputs-x86_64-linux`, and
   binds it to the build-jobs exchange. It then listens for build
   instructions on the `build-inputs-x86_64-linux` queue. For each
   job, it uses nix-build to run the build instructions. The status
   result (pass/fail) and the last ten lines of output are then placed
   in to the `build-results` queue.
4. poster.php declares the build-results queue, and listens for
   messages on it. It posts the build status and text output on the PR
   the build is from.
