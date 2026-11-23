#!/bin/sh 
/usr/local/bin/wal-g.sh backup-push $PGDATA
/usr/local/bin/wal-g.sh delete retain FIND_FULL 15 --confirm
touch /mnt/shared/${INSTANCE_NAME}