# Process for coverting 4store to AG
#
# 1. export bioportal metadata graphs from 4store
4s-metadata-backup.sh
# 2. convert 4s-dump data to .nq format compatible with AG
find data -type f -exec perl convert_4s_to_ag.pl {} \; | gzip > metadata.nq.gz
# 3. load it in AG with 'agtool load'
agtool load --error-strategy save bioportal metadata.nq.gz
# 4. process all ontologies in ncbo_cron
