## List Docker swarm stacks

Get a list of Docker swarm stacks:

`docker stack ls`

## List running services

Use a stack name from the above Docker swarm stack list to list services running in the stack:

`docker stack ps <stack name> | grep Running`

### Example

`docker stack ps transitdata-prod | grep Running`

## Restart service

Restart a service by first scaling it to 0 replicas and then scaling it back to 1 replica:

`docker service scale <service name>=0 && docker service scale <service name>=1`

### Example

`docker service scale transitdata-prod_transitdata_omm_alert_source=0 && docker service scale transitdata-prod_transitdata_omm_alert_source=1`

### Restart by force updating

Using `docker service scale` command described above is the preferred way to restart a service but it is possible to use `docker service update --force <service name>`. However this may unexpectedly update the Docker image resulting in different version of an application running.
