#!/bin/sh

set -euxo pipefail

modprobe -r dvb_usb_rtl28xxu || true

function finish {
    set +eu
    kill "$COPROC_PID"  >&2
    sleep 5
    while pgrep rtl_tcp  >&2; do
        echo "rtl_tcp still running?"  >&2
        pkill -9 rtl_tcp  >&2
        sleep 1
    done
}
trap finish EXIT

coproc rtl_tcp >&2

i=0
while ! nc -z 127.0.0.1 1234 >&2; do
    sleep 1
    i=$((i+1))
    if [ $i -gt 30 ]; then
        exit 1
    fi
done



echo "# HELP consumption_meter meter consumption"
echo "# TYPE consumption_meter counter"
rtlamr -format=csv -duration=30s \
    | awk -F, '{ $1=""; print "consumption_meter{id=\""$4"\", type=\""$5"\"} "$8"" }' \
    | sort | rev | uniq -f2 | rev # one report per meter
