#!/bin/sh

rm -f ./intake/*.json
mkdir -p ./intake

echo '{' > ./intake/default.nix.next

nixops info --plain | awk '{ print $1; }' \
    | while read -r node; do
    echo "~> $node"
    nixops scp --from "$node" /run/about.json "./intake/$node.json"
    echo "\"${node}\" = builtins.fromJSON (builtins.readFile ./$node.json);" >> ./intake/default.nix.next
done
echo '}' >> ./intake/default.nix.next
mv ./intake/default.nix.next ./intake/default.nix
