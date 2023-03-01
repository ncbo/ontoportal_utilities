#!/bin/bash

waitForConnection () {
    SLEEP=/tmp/sleep
    echo Sleeping on ${SLEEP}
    echo with Linux host connect to `hostname` 
    mkdir ${SLEEP}
    while [ -e ${SLEEP} ]
    do
	sleep 2
    done
}

waitForPort() {
    while ! nc -z  $1 $2
    do
	sleep 1
	echo Waiting for $1
    done
}
