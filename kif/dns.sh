#!/usr/bin/env bash

set -eux

# More advanced options below
# The Time-To-Live of this recordset


dns() {
    RECORD=$1
    TYPE=$2
    IP=$3
    TTL=300
    # Fill a temp file with valid JSON
    TMPFILE=$(mktemp /tmp/temporary-file.XXXXXXXX)
    cat > ${TMPFILE} << EOF
   {
      "Changes":[
        {
          "Action":"UPSERT",
          "ResourceRecordSet":{
            "ResourceRecords":[
              {
                "Value":"$IP"
              }
            ],
            "Name":"$RECORD",
            "Type":"$TYPE",
            "TTL":$TTL
          }
        }
      ]
    }
EOF

    # Update the Hosted Zone record
    aws route53 change-resource-record-sets \
        --hosted-zone-id $ZONEID \
        --change-batch file://"$TMPFILE"
    echo ""

    # Clean up
    rm $TMPFILE
}

dns "$(hostname).wg.gsc.io" "A" "$(ip --json addr show dev wg0 \
    | jq -r '.[] | .addr_info[] | select(.family == "inet") | .local')"
dns "$(hostname).gsc.io" "A" "$(curl https://ipv4.icanhazip.com)"
dns "$(hostname).gsc.io" "AAAA" "$(curl https://ipv6.icanhazip.com)"
