#!/bin/bash
# The database servers a repository's tests run against, started for its
# hooks: each in a container, on a fixed port, waited for until it answers,
# and named in the environment the hooks see (GITHUB_ENV):
#
#   postgres   PostgreSQL 16  127.0.0.1:5432   POSTGRES_URL  POSTGRES_CONTAINER
#   mysql      MySQL 8        127.0.0.1:3306   MYSQL_URL     MYSQL_CONTAINER
#   mariadb    MariaDB 11     127.0.0.1:3307   MARIADB_URL   MARIADB_CONTAINER
#
# Each has the user postgres or root, the password "test", and a database
# named "test" (PostgreSQL's is "postgres" too). Started together, so they
# come up while the rest of the job runs; the job's end removes them.
#
#   DATABASES="postgres mariadb" databases.sh
set -euo pipefail
for db in ${DATABASES:-}; do
  case "$db" in
    postgres) docker run -d --name gnustep-ci-postgres -p 5432:5432 \
                -e POSTGRES_PASSWORD=test -e POSTGRES_DB=test postgres:16 > /dev/null ;;
    mysql)    docker run -d --name gnustep-ci-mysql -p 3306:3306 \
                -e MYSQL_ROOT_PASSWORD=test -e MYSQL_DATABASE=test mysql:8 > /dev/null ;;
    mariadb)  docker run -d --name gnustep-ci-mariadb -p 3307:3306 \
                -e MARIADB_ROOT_PASSWORD=test -e MARIADB_DATABASE=test mariadb:11 > /dev/null ;;
    *) echo "::error::databases: no '$db' (postgres, mysql, mariadb)"; exit 1 ;;
  esac
done
for db in ${DATABASES:-}; do
  # Over TCP: each image's first, temporary server answers on its socket only.
  case "$db" in
    postgres) ready() { docker exec gnustep-ci-postgres pg_isready -h 127.0.0.1 -U postgres; }
              url=postgresql://postgres:test@127.0.0.1:5432/test ;;
    mysql)    ready() { docker exec gnustep-ci-mysql mysql -h 127.0.0.1 -uroot -ptest -e 'SELECT 1' test; }
              url=mysql://root:test@127.0.0.1:3306/test ;;
    mariadb)  ready() { docker exec gnustep-ci-mariadb healthcheck.sh --connect --innodb_initialized; }
              url=mysql://root:test@127.0.0.1:3307/test ;;
  esac
  for i in $(seq 1 90); do ready > /dev/null 2>&1 && break; [ "$i" != 90 ] || { docker logs "gnustep-ci-$db"; echo "::error::$db did not start"; exit 1; }; sleep 2; done
  upper=$(echo "$db" | tr a-z A-Z)
  { echo "${upper}_URL=$url"; echo "${upper}_CONTAINER=gnustep-ci-$db"; } >> "$GITHUB_ENV"
  echo "$db: $url"
done
