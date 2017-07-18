#!/usr/bin/env bash

export GOPATH=/tmp/go
DRUDSRC=$GOPATH/src/github.com/drud
mkdir -p $DRUDSRC
ln -s $DRUDSRC/ddev $PWD
cd $DRUDSRC/ddev
make test
