#!/bin/bash -x

sudo -v
dd bs=4192 count=1048576 if=/dev/zero of=/home/tredmond/dev.img

sudo losetup -o 0 -f /home/tredmond/dev.img

sudo mkfs.ext4 /dev/loop0
docker volume create --driver local \
       --opt device=/dev/loop0 --opt type=ext4 \
       testvol

