#!/bin/bash
. /scripts/util.sh

apt-get update
apt-get install -y default-jre raptor2-utils  netcat

mkdir /FirstRun
