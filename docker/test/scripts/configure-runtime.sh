#!/bin/bash -x

. /scripts/util.sh

export FIRST_RUN=/FirstRun
if [ -e ${FIRST_RUN} ]
then
    rmdir ${FIRST_RUN}

    if ! grep -q ":${BIOPORTAL_DOCKER_GID}:" /etc/group
    then
	groupadd --gid ${BIOPORTAL_DOCKER_GID} ${BIOPORTAL_DOCKER_USER}
    fi
    
    useradd --uid ${BIOPORTAL_DOCKER_UID} --gid ${BIOPORTAL_DOCKER_GID} ${BIOPORTAL_DOCKER_USER}
    chown ${BIOPORTAL_DOCKER_USER}:${BIOPORTAL_DOCKER_USER} /home/${BIOPORTAL_DOCKER_USER}

    su ${BIOPORTAL_DOCKER_USER}
    cd /home/${BIOPORTAL_DOCKER_USER}/projects/ontologies_api/

    gem install bundler:${BUNDLER_VERSION}
    bundle install
    gem install ruby-debug-ide
fi
