#!/bin/bash

# start couchdb exporter
COUCH_CONFIG=/data/srv/current/auth/couchdb/couchdb_config.ini
# test if file is not zero size
if [ -s "${COUCH_CONFIG}" ]; then
    nohup /data/couchdb-prometheus-exporter -telemetry.address=":9984" \
      --config=$COUCH_CONFIG -databases.views=false 2>&1 1>& \
      /data/couchdb_exporter.log < /dev/null &
else
    echo "ERROR: couchdb_config.ini file is empty and prometheus exporter cannot be started!"
fi

# run filebeat
if [ -f /etc/secrets/filebeat.yaml ] && [ -f /usr/bin/filebeat ]; then
    ldir=/tmp/filebeat
    mkdir -p $ldir/data
    nohup /usr/bin/filebeat \
        -c /etc/secrets/filebeat.yaml \
        --path.data $ldir/data --path.logs $ldir -e 2>&1 1>& $ldir/log < /dev/null &
else
  echo "ERROR: filebeat process is not started as /etc/secrets/filebeat.yaml does not exist"
fi
