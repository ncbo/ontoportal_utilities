#!/bin/bash -x

. /scripts/util.sh

export GOO_HOST="docker_4store-ut_1"
export REDIS_HOST="docker_redis-ut_1"


export SOLR_TERM_SEARCH_URL="http://docker_solr-ut_1:8983/solr/term_search_core1"
export SOLR_PROP_SEARCH_URL="http://docker_solr-ut_1:8983/solr/prop_search_core1"
export MGREP_HOST="docker_mgrep-ut_1"

export REDIS_GOO_CACHE_HOST=docker_redis-ut_1
export REDIS_HTTP_CACHE_HOST=docker_redis-ut_1
export REDIS_PERSISTENT_HOST=docker_redis-ut_1


waitForPort docker_solr-ut_1   8983
waitForPort docker_mgrep-ut_1 55555
waitForPort docker_4store-ut_1 9000
waitForPort docker_redis-ut_1  6379

/scripts/configure-runtime.sh

su ${BIOPORTAL_DOCKER_USER}
cd /home/${BIOPORTAL_DOCKER_USER}/projects/ontologies_api/


bundler exec rake

