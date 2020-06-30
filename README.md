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

## System Architecture & Components

### Transitdata

![Alt text](transitdata_data_flow_drawio.png?raw=true "Transitdata System Architecture")

#### Transitdata input
- mqtt.hsl.fi vehicle position in hfp format (all)
- hsl-mqtt-lab-a.confra.fi estimate for stop time (metros)
- Pubtrans ROI: estimates for stop time (bus and trams)
- Pubtrans DOI: static data (schedule, stops, routes)
- api.digitransit.fi/realtime/service-alerts/v1: not used
- OMM DB: service alerts (cancellations, disruptions)
- raildigitraffic2gtfsrt: train stop estimates (to be replaced by a service connected to ratadigitraffic)

#### Transitdata output

- MQTT Broker cmqttdv.cinfra.fi: vehicle position in gtfs format (HSL displays at stops)
- Azure storage -> Google maps: vehicle position, trips in gtfs format
- MQTT Broker mqtt.cinfra.fi -> Reittiopas.fi: stop estimates in gtfs
- Graylog server: logs from all the microservices	

### Transitlog

![Alt text](transitlog_hfp_data_flow_drawio.png?raw=true "Transitlog System Architecture")

Components are stored in their own Github Repositories:

#### Common dependencies

- [transitdata-common](https://github.com/HSLdevcom/transitdata-common) contains generic components and shared constants.

#### Transitdata components

- [transitdata-cache-bootstrapper](https://github.com/HSLdevcom/transitdata-cache-bootstrapper) fills journey-metadata to Redis cache for the next step
- [transitdata-pubtrans-source](https://github.com/HSLdevcom/transitdata-pubtrans-source) polls changes to Pubtrans database and publishes the events to Pulsar as "raw-data"
- [transitdata-stop-estimates](https://github.com/HSLdevcom/transitdata-stop-estimates) creates higher-level data (StopEstimates) from the raw-data where the data source is abstracted (bus, metro, train).
- [transitdata-omm-cancellation-source](https://github.com/HSLdevcom/transitdata-omm-cancellation-source) reads OMM database and generates TripUpdate trip cancellations
- [transitdata-hslalert-source](https://github.com/HSLdevcom/transitdata-hslalert-source) reads trip cancellations from HSL public HTML API and generates TripUpdate cancellations. This is for transition period support and will be removed in the near future.
- [transitdata-tripupdate-processor](https://github.com/HSLdevcom/transitdata-tripupdate-processor) reads the estimates and cancellations and generates GTFS-RT messages and publishes them to Pulsar
- [transitdata-omm-alert-source](https://github.com/HSLdevcom/transitdata-omm-alert-source) reads OMM database and generates internal service alert messages.
- [transitdata-alert-processor](https://github.com/HSLdevcom/transitdata-alert-processor) reads internal service alert messages and generates GTFS-RT Service alerts
- [pulsar-mqtt-gateway](https://github.com/HSLdevcom/pulsar-mqtt-gateway) routes Pulsar messages to MQTT broker.
- [transitdata-gtfsrt-full-publisher](https://github.com/HSLdevcom/transitdata-gtfsrt-full-publisher) publishes GTFS-RT Full dataset based on the GTFS-RT TripUpdate topic.
- [transitdata-pulsar-monitoring](https://github.com/HSLdevcom/transitdata-pulsar-monitoring) creates information about the state of the current pipeline for monitoring purposes

#### Transitlog HFP components

- [transitlog-alert-sink](https://github.com/HSLdevcom/transitlog-alert-sink) application for inserting service alerts to PostgreSQL
- [transitlog-hfp-sink](https://github.com/HSLdevcom/transitlog-hfp-sink)
  Insert HFP data from Pulsar to TimescaleDB
- [transitdata-hfp-parser](https://github.com/HSLdevcom/transitdata-hfp-parser) parses MQTT raw topic & payload into Protobuf with HFP schema
- [transitdata-hfp-deduplicator](https://github.com/HSLdevcom/transitdata-hfp-deduplicator) deduplicate data read from Pulsar topic(s)
- [mqtt-pulsar-gateway](https://github.com/HSLdevcom/mqtt-pulsar-gateway) application for reading data from MQTT topic and feeding it into Pulsar topic. This application doesn't care about the payload, it just transfers the bytes.

## Versioning

All the components in this project use semver, but the output conforms always to the GTFS Realtime standard. Some vendor-specific extensions might be added, which require incrementing the major version. Otherwise, new features should only increment the minor version, but some exceptions might arise. TripUpdate and ServiceAlert APIs are versioned independently.

## Implementation notes

Pulsar seems to cause approximately 5ms of latency for each message, which is consistent with their promise. The latency is not a problem in itself, and is well within acceptable bounds. However, the latency means that a single-threaded consumer-producer loop can only process 200 messages per second.
