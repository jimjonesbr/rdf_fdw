#!/bin/bash

CODE_PATH=~/git/rdf_fdw
PSQL_PATH=/usr/local/postgres-dev/bin/psql
PG_CONFIG_PATH=/usr/local/postgres-dev/bin/pg_config
TEST_ENV_PATH=~/git/rdf_fdw/scripts/postgres-env
#####################################################

bash $TEST_ENV_PATH/virtuoso/deploy-virtuoso.sh
bash $TEST_ENV_PATH/fuseki/deploy-fuseki.sh
bash $TEST_ENV_PATH/graphdb/deploy-graphdb.sh
bash $TEST_ENV_PATH/qlever/deploy-qlever.sh
bash $TEST_ENV_PATH/squid/deploy-proxy-env.sh

# Build and install rdf_fdw
echo -e "\n== Building and Installing rdf_fdw on PostgreSQL (local) ==\n"

cd $CODE_PATH

make clean && \
 make PG_CONFIG=$PG_CONFIG_PATH CFLAGS="-DUSE_ASSERT_CHECKING -O0 -g" && \
 make install PG_CONFIG=$PG_CONFIG_PATH

$PSQL_PATH postgres -c "DROP EXTENSION IF EXISTS rdf_fdw CASCADE; CREATE EXTENSION rdf_fdw"
$PSQL_PATH postgres -c "SELECT * FROM rdf_fdw_settings;"
$PSQL_PATH postgres -c "CREATE USER postgres SUPERUSER;"
# Tests that need a triplestore are opt-in:
# INCLUDE_LOCAL_TESTS=1    - tests against locally deployed triplestores
# INCLUDE_EXTERNAL_TESTS=1 - tests that need external network access
# INCLUDE_STRESS_TESTS=1   - long running stress tests
# INCLUDE_DEBUG_TESTS=1    - tests that need debug output (debug.out)
# INCLUDE_ALL_TESTS=1      - all of the above
make PG_CONFIG=$PG_CONFIG_PATH PGUSER=postgres INCLUDE_LOCAL_TESTS=1 installcheck 

echo -e "\n== local deployment complete ==\n"
