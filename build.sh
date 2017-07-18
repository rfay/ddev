#!/bin/bash

BUILD=$(date "+%Y%m%d%H%M%S")
export GOPATH=~/tmp/ddevbuild_$BUILD
DRUDSRC=$GOPATH/src/github.com/drud

echo "Building in $DRUDSRC/ddev"

export GOTEST_SHORT=1

echo "Warning: deleting all docker containers"
docker rm -f $(docker ps -aq) 2>/dev/null || true

mkdir -p $DRUDSRC
ln -s $PWD $DRUDSRC/ddev 
cd $DRUDSRC/ddev

#make print-BUILD_OS print-DDEV_BINARY_FULLPATH
make testcmd
