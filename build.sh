#!/bin/bash

BUILD=$(date "+%Y%m%d%H%M%S")
export GOPATH=~/tmp/ddevbuild_$BUILD

export GOTEST_SHORT=1

echo "Warning: deleting all docker containers"
docker rm -f $(docker ps -aq) 2>/dev/null || true

DRUDSRC=$GOPATH/src/github.com/drud
mkdir -p $DRUDSRC
ln -s $PWD $DRUDSRC/ddev 
cd $DRUDSRC/ddev

make testcmd
