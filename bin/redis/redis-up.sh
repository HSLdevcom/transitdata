#!/bin/bash

docker run -d --name test-redis --rm -p 127.0.0.1:6379:6379 -v $PWD/data:/data redis

