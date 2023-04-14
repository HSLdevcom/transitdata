## General

This system will read real-time data from various sources (for example, Pubtrans database regarding departures and arrivals)
and convert those to [GTFS real-time messages](https://developers.google.com/transit/gtfs-realtime/gtfs-realtime-proto) using a pipeline created with [Apache Pulsar](https://pulsar.apache.org/). The final step will publish the messages to different locations (such as MQTT brokers and blob storage).

General usage pattern is to build Docker images and then run them with docker-compose.
Services are separated to different GitHub repositories, each containing the source code and the Dockerfile.

[/bin-folder](/bin) contains scripts to launch Docker images for Pulsar, Redis and Mosquitto MQTT broker which are requirements for some of the services.

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
- mqtt.hsl.fi: vehicle positions in [HFP](https://digitransit.fi/en/developers/apis/4-realtime-api/vehicle-positions/) format (all vehicles)
- hsl-mqtt-lab-a.cinfra.fi: estimates for stop time (metros)
- Pubtrans ROI: estimates for stop time (buses, trams, trains)
- Pubtrans DOI: static data (schedule, stops, routes)
- OMM DB: service alerts (cancellations, disruptions)
- sm5.rt.hsl.fi: EKE message from SM5 trains
- apc.rt.hsl.fi: Passenger count data

#### Transitdata output

- MQTT Broker cmqttdev.cinfra.fi: vehicle position in GTFS-RT format (HSL displays at stops)
- Azure Blob storage: used for publishing vehicle position, trip updates and service alerts in GTFS-RT format (for Google Maps and 3rd-party applications) and for archiving messages (HFP and EKE) in CSV files
- MQTT Broker pred.rt.hsl.fi -> Reittiopas.fi: stop estimates in GTFS-RT format
  - **Note:** this MQTT broker is intended to be used by HSL systems only. Its functionality can be changed without a notice and there is no guarantee that it will work for third-party applications.
- Graylog server: logs from all the microservices.

### Transitlog

![Alt text](transitlog_hfp_data_flow_drawio.png?raw=true "Transitlog System Architecture")

Components are stored in their own Github Repositories:

#### Common dependencies

- [transitdata-common](https://github.com/HSLdevcom/transitdata-common) - Contains Protobuf definitions, shared constants and generic components, such as an abstract class for connecting to Pulsar

#### Transitdata components

##### Sources

- [transitdata-cache-bootstrapper](https://github.com/HSLdevcom/transitdata-cache-bootstrapper) - Reads static data such as routes from PubTrans DOI DB and inserts that to Redis
- [transitdata-pubtrans-source](https://github.com/HSLdevcom/transitdata-pubtrans-source) - Polls new stop time predictions from PubTrans ROI DB and publishes them to a Pulsar topic
- [transitdata-omm-cancellation-source](https://github.com/HSLdevcom/transitdata-omm-cancellation-source) - Reads OMM database and generates trip cancellations
- [transitdata-omm-alert-source](https://github.com/HSLdevcom/transitdata-omm-alert-source) - Reads OMM database and generates internal service alert messages
- [transitdata-stop-cancellation-source](https://github.com/HSLdevcom/transitdata-stop-cancellation-source)  - Reads OMM database and generates internal stop cancellation messages
- [mqtt-pulsar-gateway](https://github.com/HSLdevcom/mqtt-pulsar-gateway) - Subscribes to a MQTT topic and publishes raw MQTT messages to a Pulsar topic, can be used with any MQTT-based data source

##### Processors

- [transitdata-hfp-deduplicator](https://github.com/HSLdevcom/transitdata-hfp-deduplicator) - Deduplicates messages. Despite the name, this application can be used for deduplicating other messages than just HFP messages
- [transitdata-hfp-parser](https://github.com/HSLdevcom/transitdata-hfp-parser) - Parses raw HFP / APC messages received from MQTT broker
- [transitdata-metro-ats-parser](https://github.com/HSLdevcom/transitdata-metro-ats-parser) - Parses raw metro ATS messages received from MQTT broker
- [transitdata-metro-ats-cancellation-source](https://github.com/HSLdevcom/transitdata-metro-ats-cancellation-source) - Creates cancellation messages from raw metro ATS messages
- [transitdata-stop-estimates](https://github.com/HSLdevcom/transitdata-stop-estimates) - Creates higher-level data (StopEstimates) from the raw-data where the data source is abstracted (bus, metro, train)
- [transitdata-tripupdate-processor](https://github.com/HSLdevcom/transitdata-tripupdate-processor) - Reads the estimates and cancellations and generates GTFS-RT messages
- [transitdata-alert-processor](https://github.com/HSLdevcom/transitdata-alert-processor) - Reads internal service alert messages and generates GTFS-RT Service alerts
- [transitdata-vehicleposition-processor](https://github.com/HSLdevcom/transitdata-vehicleposition-processor) - Generates GTFS-RT vehicle position messages from HFP messages, adding passenger count data from APC messages if available
- [transitdata-stop-cancellation-processor](https://github.com/HSLdevcom/transitdata-stop-cancellation-processor) - Applies stop cancellations to GTFS-RT trip updates
- [transitdata-partial-apc-expander-combiner](https://github.com/HSLdevcom/transitdata-partial-apc-expander-combiner) - Combines multiple partial APC messages and expands them with metadata from HFP to create full APC messages
- [transitdata-apc-protobuf-json-transformer](https://github.com/HSLdevcom/transitdata-apc-protobuf-json-transformer) - Transforms APC messages in Protobuf format to JSON for sending them back to MQTT broker

##### Publishers

- [pulsar-mqtt-gateway](https://github.com/HSLdevcom/pulsar-mqtt-gateway) - Publishes Pulsar messages to a MQTT broker
- [transitdata-gtfsrt-full-publisher](https://github.com/HSLdevcom/transitdata-gtfsrt-full-publisher) - Publishes GTFS-RT Full datasets to Azure Blob Storage
- [transitdata-eke-sink](https://github.com/HSLdevcom/transitdata-eke-sink) - Collects EKE messages to hourly files and publishes them to Azure Blob Storage

##### Other

These components are not connected to the Pulsar cluster, but they are deployed to the same environment as Transitdata and they produce data that Transitdata uses

- [suomenlinna-ferry-hfp](https://github.com/HSLdevcom/suomenlinna-ferry-hfp) - Creates HFP messages for Suomenlinna ferries from AIS data
- [gtfsrt2hfp](https://github.com/HSLdevcom/gtfsrt2hfp) - Creates HFP messages from GTFS-RT vehicle positions, currently used for U-bus 280

##### Monitoring and testing

- [transitdata-tests](https://github.com/HSLdevcom/transitdata-tests) - Contains code for Transitdata E2E tests
- [transitdata-monitor-data-collector](https://github.com/HSLdevcom/transitdata-monitor-data-collector) - Collects data from Transitdata (Pulsar message rates, MQTT message rates, GTFS-RT feeds) and sends it to Azure Monitoring
- [transitdata-db-monitoring](https://github.com/HSLdevcom/transitdata-db-monitoring) - Tool for periodically checking whether database connections are working, **not in use currently**

#### Transitlog HFP components

- [transitlog-alert-sink](https://github.com/HSLdevcom/transitlog-alert-sink) application for inserting service alerts to PostgreSQL
- [transitlog-hfp-split-sink](https://github.com/HSLdevcom/transitlog-hfp-split-sink) Insert HFP data from Pulsar to Transitlog DB (Citus)
- [transitdata-hfp-parser](https://github.com/HSLdevcom/transitdata-hfp-parser) parses MQTT raw topic & payload into Protobuf with HFP schema
- [transitdata-hfp-deduplicator](https://github.com/HSLdevcom/transitdata-hfp-deduplicator) deduplicate data read from Pulsar topic(s)
- [mqtt-pulsar-gateway](https://github.com/HSLdevcom/mqtt-pulsar-gateway) application for reading data from MQTT topic and feeding it into Pulsar topic. This application doesn't care about the payload, it just transfers the bytes.

## Versioning

All the components in this project use semver, but the output conforms always to the GTFS Realtime standard. Some vendor-specific extensions might be added, which require incrementing the major version. Otherwise, new features should only increment the minor version, but some exceptions might arise. TripUpdate and ServiceAlert APIs are versioned independently.

## Implementation notes

Pulsar seems to cause approximately 5ms of latency for each message, which is consistent with their promise. The latency is not a problem in itself, and is well within acceptable bounds. However, the latency means that a single-threaded consumer-producer loop can only process 200 messages per second.
