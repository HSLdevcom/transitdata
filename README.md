
## General

This system will poll updates to Pubtrans database (regarding departures and arrivals)
and convert those to [GTFS real-time messages](https://developers.google.com/transit/gtfs-realtime/gtfs-realtime-proto) using a pipeline created with [Apache Pulsar](https://pulsar.incubator.apache.org/). The final step will output the messages via MQTT broker.

General usage pattern is to build Docker images and then run them with docker-compose.
Services are separated to subfolders, each containing the source code and the Dockerfile.

[/bin-folder](/bin) contains scripts to launch Docker images for Pulsar and Redis which are
requirements for some of the services.

## Requirements

Overall system requirements for running the system are:
- Docker
- Redis
- Pulsar
- Connection to a Pubtrans SQL Server database
- Connection to an MQTT broker

## Components

Projects related to this stack:
- [transitdata-common](https://github.com/HSLdevcom/transitdata-common) contains generic components and shared constants.
- [transitdata-cache-bootstrapper](https://github.com/HSLdevcom/transitdata-cache-bootstrapper) fills journey-metadata to Redis cache for the next step
- [transitdata-pubtrans-source](https://github.com/HSLdevcom/transitdata-pubtrans-source) polls changes to Pubtrans database and publishes the events to Pulsar as "raw-data"
- [transitdata-tripupdate-processor](https://github.com/HSLdevcom/transitdata-tripupdate-processor) reads the raw-data and generates GTFS-RT messages and publishes them to Pulsar
- [pulsar-mqtt-gateway](https://github.com/HSLdevcom/pulsar-mqtt-gateway) routes Pulsar messages to MQTT broker. 
- [transitdata-gtfsrt-full-publisher](https://github.com/HSLdevcom/transitdata-gtfsrt-full-publisher) publishes GTFS-RT Full dataset based on the GTFS-RT TripUpdate topic.
- [transitdata-omm-alert-source](https://github.com/HSLdevcom/transitdata-omm-alert-source) reads OMM database and generates GTFS-RT Service alerts
- [transitdata-omm-cancellation-source](https://github.com/HSLdevcom/transitdata-omm-cancellation-source) reads OMM database and generates TripUpdate trip cancellations
- [transitdata-hslalert-source](https://github.com/HSLdevcom/transitdata-hslalert-source) reads trip cancellations from HSL public HTML API and generates TripUpdate cancellations. This is for transition period support and will be removed in the near future.
- [transitdata-pulsar-monitoring](https://github.com/HSLdevcom/transitdata-pulsar-monitoring) creates information about the state of the current pipeline for monitoring purposes


## Versioning

All the components in this project use semver, but the output conforms always to the GTFS Realtime standard. Some vendor-specific extensions might be added, which require incrementing the major version. Otherwise, new features should only increment the minor version, but some exceptions might arise. TripUpdate and ServiceAlert APIs are versioned independently.

## Implementation notes

Pulsar seems to cause approximately 5ms of latency for each message, which is consistent with their promise. The latency is not a problem in itself, and is well within acceptable bounds. However, the latency means that a single-threaded consumer-producer loop can only process 200 messages per second.  
