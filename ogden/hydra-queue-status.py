#!/usr/bin/env nix-shell
#!nix-shell -i python3 -p python3Packages.beautifulsoup4 -p python3Packages.requests
from bs4 import BeautifulSoup
import requests

project_q_summary = {}
system_q_summary = {}


data = requests.get("https://hydra.nixos.org/queue_summary")

parsed = BeautifulSoup(data.text, features="html.parser")

tables = parsed.find_all('table')
project_qs = tables[0]
for row in project_qs.tdata.find_all('tr'):
    cols = row.find_all('td')
    project_q_summary[cols[0].text] = int(cols[1].text)

system_qs = tables[1]
for row in system_qs.tdata.find_all('tr'):
    cols = row.find_all('td')
    system_q_summary[cols[0].text] = int(cols[1].text)


print("""
# HELP hydra_project_jobs_total Number of jobs per project.
# TYPE hydra_project_jobs_total gauge
""")
for project, total in project_q_summary.items():
    print("hydra_project_jobs_total{{project=\"{}\"}} {}".format(project, total))

print("""
# HELP hydra_architecture_jobs_total Number of jobs per architecture.
# TYPE hydra_architecture_jobs_total gauge
""")
for arch, total in system_q_summary.items():
    print("hydra_architecture_jobs_total{{architecture=\"{}\"}} {}".format(arch, total))
