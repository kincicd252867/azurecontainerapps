#!/bin/bash

CONTAINERNAME="php-fpm"
attempts=0
max_attempts=12
# Pull Nginx image
echo "Pulling Nginx image..."
docker pull kin252867/docker-nginx-leaveapplicationportal:ver1.1

# Pull PHP-FPM image
echo "Pulling PHP-FPM image..."
docker pull kin252867/docker-php-leaveapplicationportal:ver1.1

# Start all services using docker-compose
echo "Starting services..."
docker-compose -f docker-compose-leaveapplicationportalmysql.yml -f docker-compose-leaveapplicationportal.yml up -d

# Wait for PHP-FPM to be ready
echo "Waiting for PHP-FPM to be ready..."
until docker logs $CONTAINERNAME 2>&1 | grep -q "ready to handle connections"; do
  attempts=$((attempts + 1))
  if [ $attempts -ge $max_attempts ]; then
     echo "Timeout: PHP-FPM did not become ready within 60 seconds."
     exit 1
  fi
done

echo "Waiting for MySQL to be ready..."
until docker exec db-leave-application-portal mysqladmin ping -h"localhost" -u"nginx" -p"X!Ncb3b248kQr2" --silent; do
  attempts=$((attempts + 1))
  if [ $attempts -ge $max_attempts ]; then
     echo "Timeout: MySQL did not become ready within 60 seconds."
     exit 1
  fi
done

echo "Health check passed! Deployment completed."

