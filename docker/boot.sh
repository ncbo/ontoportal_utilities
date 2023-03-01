#!/bin/bash -x

sudo losetup -o 0 -f /home/tredmond/dev.img
sudo mount /dev/loop0 /home/tredmond/bioportal-docker-home

