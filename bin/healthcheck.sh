#!/bin/bash
# Simple healthcheck wrapper for MySQL to satisfy docker-compose configuration
# Ignores arguments passed by docker-compose (like --connect --innodb_initialized)
# and performs a standard ping check.

mysqladmin ping -h localhost -u root -p"${MYSQL_ROOT_PASSWORD}" --silent
