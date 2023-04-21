This page describes how to run Pulsar-connected services of Transitdata locally

## Requirements

* Docker
  * Optional: Docker Compose

## Dependencies

* Pulsar (used by all services)
  * You can use [this script](https://github.com/HSLdevcom/transitdata/blob/master/bin/pulsar/pulsar-up.sh) to run Pulsar in Docker
* MQTT broker (for services publishing data over MQTT)
  * You can use [this script](https://github.com/HSLdevcom/transitdata/blob/master/bin/mosquitto_broker/mosquitto-broker-up.sh) to run Mosquitto in Docker
* Redis (for services using Redis)
  * You can use [this script](https://github.com/HSLdevcom/transitdata/blob/master/bin/redis/redis-up.sh) to run Redis in Docker

## How to run Transitdata

1. Set up necessary dependencies
2. Check the [architecture diagram](https://raw.githubusercontent.com/HSLdevcom/transitdata/master/transitdata_data_flow_drawio.png) to see which services you want to run
3. Build Docker images for necessary services or use ones from hsldevcom Docker Hub
   * Docker images are named `hsldevcom/<service name>`, e.g. `hsldevcom/transitdata-vehicleposition-processor`
4. Start Docker containers for all services with necessary environment variables
   * All services need at least `PULSAR_HOST` and `PULSAR_PORT` variables, which default to `localhost` and `6650` respectively
   * Also `PULSAR_CONSUMER_TOPIC` and `PULSAR_PRODUCER_TOPIC` might have to be changed from the defaults
    * The idea is to create a pipeline where services read data from a certain topic and write to another
   * Check other environment variables from services README or `src/main/resources/environment.conf`

### Docker Compose

Docker Compose might be helpful when running Transitdata locally as it allows defining all services in a single file. Here's an example of running services that generate GTFS-RT vehicle positions:

```yml
services:
  pulsar:
    image: apachepulsar/pulsar
    ports:
      - 6650
      - 8080
    environment:
      PULSAR_MEM: "-Xms512m -Xmx512m -XX:MaxDirectMemorySize=1g"    
    command: "bin/pulsar standalone"
  mosquitto:
    image: eclipse-mosquitto:1.6.3
    ports:
      - "1050:1883"
      - "9001:9001"
  hfp_mqtt_pulsar_gateway:
    image: hsldevcom/mqtt-pulsar-gateway:develop
    environment:
      - PULSAR_HOST=pulsar
      - PULSAR_PORT=6650
      - "MQTT_TOPIC=/hfp/v2/journey/"
      - MQTT_BROKER_HOST=tcp://mqtt.hsl.fi:1883/
      - "MQTT_CLIENT_ID=transitdata-local"
      - "MQTT_ADD_RANDOM_TO_CLIENT_ID=true"
      - "PULSAR_PRODUCER_TOPIC=hfp-raw"
      - "MAX_MESSAGES_PER_SECOND=1800"
    depends_on:
      - pulsar
  hfp_parser:
    image: hsldevcom/transitdata-hfp-parser:develop
    environment:
      - PULSAR_HOST=pulsar
      - PULSAR_PORT=6650
      - "PULSAR_CONSUMER_TOPIC=hfp-raw"
      - "PULSAR_CONSUMER_SUBSCRIPTION=hfp_parser"
      - "PULSAR_PRODUCER_TOPIC=hfp"
    depends_on:
      - pulsar
  vehicleposition_processor:
    image: hsldevcom/transitdata-vehicleposition-processor:develop
    environment:
      - PULSAR_HOST=pulsar
      - PULSAR_PORT=6650
      - "PULSAR_CONSUMER_MULTIPLE_TOPICS_PATTERN=persistent://public/default/hfp"
      - "PULSAR_CONSUMER_SUBSCRIPTION=vehicleposition_processor"
      - "PULSAR_PRODUCER_TOPIC=gtfsrt-vp"
    depends_on:
      - pulsar
      - hfp_parser
  gtfsrt_mqtt_gateway:
    image: hsldevcom/pulsar-mqtt-gateway:develop
    environment:
      - PULSAR_HOST=pulsar
      - PULSAR_PORT=6650
      - MQTT_BROKER_HOST=tcp://mosquitto:1050
      - "MQTT_TOPIC=gtfsrt/dev/fi/hsl/vp"
      - "PULSAR_CONSUMER_TOPIC=gtfsrt-vp"
      - "MQTT_RETAIN_MESSAGE=false"
      - "MQTT_HAS_AUTHENTICATION=false"
      - "PULSAR_CONSUMER_SUBSCRIPTION=mqtt-gw-vehicleposition"
      - "MQTT_CLIENT_ID=gtfsrt-vp"
    depends_on:
      - pulsar
      - mosquitto
```