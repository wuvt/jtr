#!/bin/bash

docker stop jtr-postgres
docker rm jtr-postgres
docker run --name jtr-postgres -e POSTGRES_PASSWORD=mysecretpassword -p 5432:5432 -d postgres

sleep 15

export PGPASSWORD=mysecretpassword
psql -h 127.0.0.1 -p 5432 -U postgres -c "CREATE DATABASE jtr;" 
psql -h 127.0.0.1 -p 5432 -U postgres -c "CREATE USER jtr WITH ENCRYptED PASSWORD 'mysecretpassword'; GRANT ALL PRIVILEGES ON DATABASE jtr TO jtr;"
