#!/usr/bin/env nix-shell
#!nix-shell -i python3 -p python3Packages.beautifulsoup4 -p python3Packages.requests  -p python3Packages.prometheus_client

from bs4 import BeautifulSoup
import requests
from prometheus_client import CollectorRegistry, Histogram, write_to_textfile
import re

def parse_duration(d):
    # https://github.com/NixOS/hydra/blob/0bc548ee2d39debe4fcc7ea1cc1203ba8454a811/src/root/common.tt#L62
    matches = re.match('^\s*((?P<days>\d+)d\s)?((?P<hours>\d+)h\s)?((?P<minutes>\d+)m\s)?(?P<seconds>\d+)s\s*$', d)

    if matches is None:
        return 0

    matched = matches.groupdict(0)
    return ((int(matched['days']) * 24 * 60 * 60) +
           (int(matched['hours']) * 60 * 60) +
           (int(matched['minutes']) * 60) +
           (int(matched['seconds'])))

registry = CollectorRegistry()

data = requests.get("https://hydra.nixos.org/machines")

parsed = BeautifulSoup(data.text, features="html.parser")

h = Histogram('hydra_machine_build_duration',
              'How long builds are taking per server',
                  ['machine'],
                  buckets=[
                      60,
                      600,
                      1800,
                      3600,
                      7200,
                      21600,
                      43200,
                      86400,
                      172800,
                      259200,
                      345600,
                      518400,
                      604800,
                      691200],
                      registry=registry
                  )


for duration in parsed.select('tr > td:nth-of-type(6)'):
    machinename = duration.findPrevious('thead').tt.text
    h.labels(machine=machinename).observe(parse_duration(duration.text))

write_to_textfile('./hydra-machines.prom', registry)
