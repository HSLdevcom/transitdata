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

TODO
