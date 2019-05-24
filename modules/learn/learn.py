#!python3

import os
import sys
import json
import subprocess


def eprint(*args, **kwargs):
    print(*args, file=sys.stderr, **kwargs)


dataset = {}

# Host key
if os.path.isfile("/etc/ssh/ssh_host_ed25519_key.pub"):
    with open("/etc/ssh/ssh_host_ed25519_key.pub") as fp:
        dataset["ssh_host_key"] = fp.read().strip()

# Root SSH Public Key
if os.path.isfile("/root/.ssh/id_ed25519.pub"):
    with open("/root/.ssh/id_ed25519.pub") as fp:
        dataset["ssh_root_key"] = fp.read().strip()

# Wireguard public keys
dataset["wireguard_public_keys"] = {}
try:
    output = subprocess.run(["wg", "show", "all", "public-key"],
                            capture_output=True)
    if output.stderr != b'':
        eprint("wg show all public-key produced output on stderr:")
        eprint(output.stderr)

    if output.returncode == 0:
        for line in output.stdout.decode('utf8').strip().split("\n"):
            parts = line.split("\t")
            if len(parts) == 2:
                interface = parts[0]
                publickey = parts[1]
                dataset['wireguard_public_keys'][interface] = publickey
            else:
                eprint("wg output '{}' doesn't split to two tab-separated"
                       "components!".format(line))
    else:
        eprint("wg show all public-key exited non-zero: {}"
               .format(output.returncode))
except FileNotFoundError as e:
    eprint("wg failed to start: {}".format(e))
print(json.dumps(dataset, indent=4))
