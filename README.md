## General

This system will read real-time data from various sources (for example, Pubtrans database regarding departures and arrivals)
and convert those to [GTFS real-time messages](https://developers.google.com/transit/gtfs-realtime/gtfs-realtime-proto) using a pipeline created with [Apache Pulsar](https://pulsar.incubator.apache.org/). The final step will publish the messages to different locations (such as MQTT brokers and blob storage).

General usage pattern is to build Docker images and then run them with docker-compose.
Services are separated to different GitHub repositories, each containing the source code and the Dockerfile.

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
- mqtt.hsl.fi vehicle positions in [HFP](https://digitransit.fi/en/developers/apis/4-realtime-api/vehicle-positions/) format (all vehicles)
- hsl-mqtt-lab-a.confra.fi estimates for stop time (metros)
- Pubtrans ROI: estimates for stop time (bus and trams)
- Pubtrans DOI: static data (schedule, stops, routes)
- api.digitransit.fi/realtime/service-alerts/v1: not used
- OMM DB: service alerts (cancellations, disruptions)
- raildigitraffic2gtfsrt: train stop estimates (to be replaced by a service connected to ratadigitraffic)

#### Transitdata output

- MQTT Broker cmqttdv.cinfra.fi: vehicle position in gtfs format (HSL displays at stops)
- Azure storage -> Google maps: vehicle position, trips in gtfs format
- MQTT Broker mqtt.cinfra.fi -> Reittiopas.fi: stop estimates in GTFS-RT format
- Graylog server: logs from all the microservices	

### Transitlog

![Alt text](transitlog_hfp_data_flow_drawio.png?raw=true "Transitlog System Architecture")

Components are stored in their own Github Repositories:

#### Common dependencies

- [transitdata-common](https://github.com/HSLdevcom/transitdata-common) contains generic components and shared constants.

#### Transitdata components

##### Sources

- [transitdata-cache-bootstrapper](https://github.com/HSLdevcom/transitdata-cache-bootstrapper) fills journey-metadata to Redis cache for the next step
- [transitdata-pubtrans-source](https://github.com/HSLdevcom/transitdata-pubtrans-source) polls changes to Pubtrans database and publishes the events to Pulsar as "raw-data"
- [transitdata-omm-cancellation-source](https://github.com/HSLdevcom/transitdata-omm-cancellation-source) reads OMM database and generates TripUpdate trip cancellations
- [transitdata-omm-alert-source](https://github.com/HSLdevcom/transitdata-omm-alert-source) reads OMM database and generates internal service alert messages
- [transitdata-stop-cancellation-source](https://github.com/HSLdevcom/transitdata-stop-cancellation-source) reads OMM database and generates internal service stop cancellation messages
- [transitdata-rail-tripupdate-source](https://github.com/HSLdevcom/transitdata-rail-tripupdate-source) reads GTFS-RT trip updates from Digitransit rail trip update API
- [pulsar-mqtt-gateway](https://github.com/HSLdevcom/pulsar-mqtt-gateway) subscribes to a MQTT topic and publishes raw MQTT messages to a Pulsar topic, can be used with any MQTT-based data source

##### Processors

- [transitdata-hfp-deduplicator](https://github.com/HSLdevcom/transitdata-hfp-deduplicator) deduplicates messages. Despite the name, this application can be used for deduplicating other messages than just HFP messages
- [transitdata-hfp-parser](https://github.com/HSLdevcom/transitdata-hfp-parser) parses raw HFP messages received from MQTT broker
- [transitdata-metro-ats-parser](https://github.com/HSLdevcom/transitdata-metro-ats-parser) parses raw metro ATS messages received from MQTT broker
- [transitdata-metro-ats-cancellation-source](https://github.com/HSLdevcom/transitdata-metro-ats-cancellation-source) creates cancellation messages from metro ATS messages
- [transitdata-stop-estimates](https://github.com/HSLdevcom/transitdata-stop-estimates) creates higher-level data (StopEstimates) from the raw-data where the data source is abstracted (bus, metro, train)
- [transitdata-tripupdate-processor](https://github.com/HSLdevcom/transitdata-tripupdate-processor) reads the estimates and cancellations and generates GTFS-RT messages and publishes them to Pulsar
- [transitdata-alert-processor](https://github.com/HSLdevcom/transitdata-alert-processor) reads internal service alert messages and generates GTFS-RT Service alerts
- [transitdata-vehicleposition-processor](https://github.com/HSLdevcom/transitdata-alert-processor) generates GTFS-RT vehicle position messages from HFP messages
- [transitdata-stop-cancellation-processor](https://github.com/HSLdevcom/transitdata-stop-cancellation-processor) applies stop cancellations to GTFS-RT trip updates

##### Publishers

- [pulsar-mqtt-gateway](https://github.com/HSLdevcom/pulsar-mqtt-gateway) routes Pulsar messages to MQTT broker
- [transitdata-gtfsrt-full-publisher](https://github.com/HSLdevcom/transitdata-gtfsrt-full-publisher) publishes GTFS-RT Full dataset
- [transitdata-pulsar-monitoring](https://github.com/HSLdevcom/transitdata-pulsar-monitoring) creates information about the state of the current pipeline for monitoring purposes

##### Unused components

- [transitdata-hslalert-source](https://github.com/HSLdevcom/transitdata-hslalert-source) reads trip cancellations from HSL public HTML API and generates TripUpdate cancellations. Not in use anymore.

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
