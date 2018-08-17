#!/bin/sh

make build && echo SUDOPW | sudo -S etcher -d /dev/disk2 -y -c false -u ./dist/cache/os.img
