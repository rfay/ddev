#!/bin/bash

export GOPATH=/tmp/go
DRUDSRC=$GOPATH/src/github.com/drud
mkdir -p $DRUDSRC
ln -s $PWD $DRUDSRC/ddev 
cd $DRUDSRC/ddev
make test
