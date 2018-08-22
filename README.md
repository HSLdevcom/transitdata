
## General

This system will poll updates to Pubtrans database (regarding departures and arrivals)
and convert those to GTFS real-time messages using a pipeline created with [Apache Pulsar](https://pulsar.incubator.apache.org/).

General usage pattern is to build Docker images and then run them with docker-compose.
Services are separated to subfolders, each containing the source code and the Dockerfile.

[/bin-folder](/bin) contains scripts to launch Docker images for Pulsar and Redis which are
requirements for some of the services.

### Requirements

Overall system requirements for running the system are:
- Docker
- Redis
- Pulsar
- Connection to Pubtrans SQL Server database


## Usage

TODO fix. Add individual projects here.

1. Generate Java code for protobuf classes
 - `cd protos && ./generate-protos.sh`

1. Build commons library (see more info below)
 - `./build-commons.sh`

1. Build Docker images (to local repository)
 - `./build-docker-images.sh`

1. Copy /secrets/ folder containing the pubtrans connection string to the project folder, or alternatively copy the two docker-compose files to a folder containing the secrets

1. Fill redis with fresh data
 - `docker-compose -f docker-compose-fill-redis.yml up`

1. Start all the services connecting to Pulsar
 - `docker-compose up`

Optional:

1. You can run individual services with docker-compose
- `docker-compose up pulsar-pubtrans-connect-departure`

1. You can also override individual environment settings with docker-compose override-files.
- `docker-compose -f docker-compose.yml -f docker-compose.local-osx.yml up`


## Commons-library

We've put some generic code into project /common which is a dependency to all other projects.

At the moment we've included this from local maven repository since we don't have a public one yet.
The file is installed to local repository by first copying the file to all projects and using maven-install-plugin to install it during clean-phase.

Note that this is only a temporary solution to enable the build within Docker!
Plan is to publish the common-binary to public m2 repository where it will accessibly to
the Docker-build step and also to all other development frameworks that use maven repositories (f.ex Scala SBT).

TODO once published, remove these steps:
- remove copy-step from build-common.sh
- remove copy-step from all Dockerfile's.
- remove install-external step from pom.xml's

## Pulsar topic names

- `ptroi-arrival`
  - Message key:
    - DatedVehicleJourney Id + JourneyPatternPoint Gid
  - Message properties:
    - `table-name`: `ptroi-arrival` or `ptroi-departure`
    - `dvj-id`: DatedVehicleJourney Id
- `ptroi-departure`
  - Message key:
    - DatedVehicleJourney Id + JourneyPatternPoint Gid
  - Message properties:
    - `table-name`: `ptroi-arrival` or `ptroi-departure`
    - `dvj-id`: DatedVehicleJourney Id
- `stop-event`
  - Message key:
    - DatedVehicleJourney Id + JourneyPatternPoint Gid
  - Message properties:
    - `dvj-id`: `
- `stop-time-update`
- `trip-update`

## Redis keys and fields

Journey information is stored in hash maps behind the dated vehicle journey id. Stop information is stored as key-value pairs.

- `dvj:{dated_vehicle_journey_id}`
  - `operating-day`
  - `start-time`
  - `route-name`
  - `direction`

## Docker images

The following images are built when the script `build-docker-images.sh` is run:

- poc-pulsar-pubtrans-connect
- poc-pubtrans-redis-connect
- poc-stop-event
- poc-stop-time-update
- poc-trip-update

## Things that are hard coded but should be configurable (with environment variables)

- Pulsar service url
- Pulsar consumer topic
- Pulsar producer topic
- Pulsar incoming message queue size
- Pulsar outboung message queue size
- Pulsar message batching (on/off)
- Pulsar message batch size (???)
- Redis service url and port
- MQTT topic for publishing


## Versioning

The project uses semver, but the output conforms always to the GTFS Realtime standard. Some vendor-specific extensions might be added, which require incrementing the major version. Otherwise, new features should only increment the minor version, but some exceptions might arise. TripUpdate and ServiceAlert APIs are versioned independently.

## Implementation notes

Pulsar seems to cause approximately 5ms of latency for each message, which is consistent with their promise. The latency is not a problem in itself, and is well within acceptable bounds. However, the latency means that a single-threaded consumer-producer loop can only process 200 messages per second.  
