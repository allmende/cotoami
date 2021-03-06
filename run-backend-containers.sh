#!/bin/bash

#
# Run backend services as docker containers
#

if [ -n "$DOCKER_HOST" ]; then
  DOCKER_HOST_IP=$(echo $DOCKER_HOST | sed 's/^.*\/\/\(.*\):[0-9][0-9]*$/\1/g')
else
  DOCKER_HOST_IP="127.0.0.1"
fi

# Redis
echo
echo "# Running redis..."
docker run -d -p 6379:6379 redis:alpine
export COTOAMI_REDIS_HOST=$DOCKER_HOST_IP

# PostgreSQL
echo
echo "# Running postgres..."
docker run -d -p 5432:5432 -e POSTGRES_PASSWORD=postgres -e POSTGRES_DB=cotoami_dev postgres:9.5-alpine
export COTOAMI_DEV_REPO_HOST=$DOCKER_HOST_IP

# Neo4j
echo
echo "# Running neo4j..."
docker run -d -p 7687:7687 -p 7474:7474 -e NEO4J_AUTH=none neo4j:3.2.2
export COTOAMI_NEO4J_HOST=$DOCKER_HOST_IP

# Mail server
echo
echo "# Running maildev..."
docker run -d -p 25:25 -p 8080:80 djfarrelly/maildev:latest
export COTOAMI_SMTP_SERVER=$DOCKER_HOST_IP
export COTOAMI_SMTP_PORT=25
echo
echo "You can check sign-up/in mails at http://$DOCKER_HOST_IP:8080"

# Mail sender
export COTOAMI_EMAIL_FROM="no-reply@cotoa.me"
