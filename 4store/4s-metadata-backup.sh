#!/usr/bin/env bash
# 4store metadata backup script
# runs 4s-dump and creates gzip file of the data
# https://github.com/ncbo/documentation/blob/master/metadata_dumps.md
#
# This script is used in daily backups

SCRIPTPATH=/srv/ncbo/share/4store/bin/
ENVIRONMENT=production
SERVER='ncboprod-4store1:8080'
BACKUP_DIR=/srv/ncbo/share/env/${ENVIRONMENT}/backup/4store/metadata
UUID=$(cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 32 | head -n 1)
WORKDIR=/tmp/4s-backup-${UUID}

if [ ! -e ${BACKUP_DIR} ] ;then
        echo "${BACKUP_DIR} directory is not present, aborting"
        exit 1
fi

datestamp=`date --iso`

mkdir -p ${WORKDIR}
cd ${WORKDIR}
time ${SCRIPTPATH}/4s-dump http://${SERVER}/sparql/ -f ${SCRIPTPATH}/metadata_graphs
tar -cvzf ${BACKUP_DIR}/4store-$datestamp.tgz data
/bin/rm -Rf ${WORKDIR}
