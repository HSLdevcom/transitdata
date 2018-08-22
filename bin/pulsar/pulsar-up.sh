#!/bin/bash

docker run -d -p 127.0.0.1:6650:6650 -p 127.0.0.1:8089:8080 -v $PWD/data:/pulsar/data --rm --name pulsar  apachepulsar/pulsar:2.1.0-incubating bin/pulsar standalone --advertised-address 127.0.0.1

