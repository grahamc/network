#!/bin/sh

set -eu

dbg() {
    :
    echo "$@" >&2
}

filter_recent_timestamps() {
    since=$(date -d "15 days ago" "+%s")
    while read commit timestamp; do
        if [ "$timestamp" -ge "$since" ]; then
            echo "$commit $timestamp";
        fi;
    done
}

datapoints() {
    cat | filter_recent_timestamps \
        | awk '{ print "    [\""$1"\", "$2"000, '$i'],"; }'
}

make_graph() {
    cat <<EOF
  <div id="container"></div>
  <script src='https://code.highcharts.com/highcharts.js'></script>

    <script>
    Highcharts.chart('container', {
  xAxis: {
    type: 'datetime'
  },
  yAxis: {
    title: {
      text: "",
    },
    labels: {
      enabled: false,
    },
  },
  series: [
EOF

    find . -name history | (
        i=1
        while read file; do
            datapoints=$(datapoints < "$file");
            dbg "Processing $file"
            name=$(echo "$file" | cut -d/ -f2)

            if [ $(echo -n "$datapoints" | wc -c) -ge 1 ]; then
                echo "{name: '$name', type: 'scatter', keys: ['commit', 'x', 'y'],";
                echo 'point: {events: { click: function() { window.open("https://github.com/NixOS/nixpkgs/commit/" + this.commit); }}},'
                echo "data: [";
                echo "$datapoints"
                echo "]},";
            else
                dbg "Skipping $file for no datapoints" >&2
            fi

            i=$((i + 1));
        done
    )
    cat <<EOF
  ]
});
  </script>

EOF
}

readonly CHAN="#nixos"
readonly URL="https://channels.nix.gsc.io"
readonly remote="origin"
readonly gitrepo="$1"
readonly dest="$2"

(
    cd "$gitrepo" >&2
    git fetch "$remote"  >&2
    git for-each-ref --format '%(refname:strip=3)' \
        "refs/remotes/$remote"
) | grep -v HEAD |
    (
        cd "$dest"
        touch summary
        echo -n "" > summary
        summary="$(pwd)/summary"
        while read -r branch; do
            name=$(echo "$branch" | sed -e "s#/#_#g" -e "s#\.\.#_#g")
            mkdir -p "$name"
            (
                cd "$name"
                touch latest
                (
                    cd "$gitrepo" >&2
                    git show -s --format="%H %at" "$remote/$branch"
                ) > latest.next
                if [ "$(md5sum < latest.next)" != "$(md5sum < latest)" ]; then
                    dbg "Change in ${branch}"
                    (
                        cd "$gitrepo" >&2
                        echo -n "Channel $branch advanced to "
                        git show -s --format="https://github.com/NixOS/nixpkgs/commit/%h (from %cr, history: $URL/$name)" "$remote/$branch"
                    ) >> "$summary"
                    mv latest.next latest
                    chmod a+r latest
                    touch history
                    (
                        cat history
                        cat latest
                    ) | tail -n10000 > history.next
                    mv history.next history
                    chmod a+r history
                else
                    dbg "No change in ${branch}"
                    rm latest.next
                fi

                cat <<EOF > README.txt
                    This service is provided for free.

                    If you use this service automatically please be
                    polite and follow some rules:

                      - please don't poll any more often than every 15
                        minutes, to reduce the traffic to my server.

                      - please don't poll exactly on a 5 minute
                        increment, to avoid the "thundering herd"
                        problem.

                      - please add a delay on your scheduled polling
                        script for a random delay between 1 and 59
                        seconds, to further spread out  the load.

                      - please consider using my webhooks instead:
                        email me at graham at grahamc dot com or
                        message gchristensen on #nixos on Freenode.

                    Thank you, good luck, have fun
                    Graham
EOF
            )
        done

        if [ $(wc -l "$summary" | cut -d' ' -f1) -gt 0 ]; then
            (
                sleep 5
                echo 'NICK nix-gsc-io`bot'
                sleep 2
                echo 'USER nix-gsc-io`bot 0 * :Nix Channel Bot by gchristensen'
                sleep 2
                echo "JOIN :$CHAN"
                sleep 10
                cat "$summary" | sed -e "s/^/NOTICE $CHAN :/"
                sleep 3
                echo "QUIT :Info at $URL"
                sleep 5
            ) | telnet irc.freenode.net 6667 || true
        fi

        rm -f summary

        make_graph > graph.html
    )
# gnuplot <<< "set term svg; set output 'channel.svg'; set title 'Channel updates'; set timefmt '%s'; set format x '%m-%d'; set xdata time; plot 0, 'channel' using 1:(\$2-\$1)/3600 with linespoints title 'nixos-whatever';"
