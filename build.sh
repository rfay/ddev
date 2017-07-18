#!/bin/bash

export GOPATH=$(mktemp -d)

echo "Warning: deleting all docker containers"
docker rm -f $(docker ps -aq)

DRUDSRC=$GOPATH/src/github.com/drud
mkdir -p $DRUDSRC
ln -s $PWD $DRUDSRC/ddev 
cd $DRUDSRC/ddev
make test
