#!/bin/bash

CODE_PATH=~/git/rdf_fdw
PSQL_PATH=/usr/local/postgres-dev/bin/psql
PG_CONFIG_PATH=/usr/local/postgres-dev/bin/pg_config

#####################################################

# Build and install rdf_fdw
echo -e "\n== Building and Installing rdf_fdw on PostgreSQL (local) ==\n"

cd $CODE_PATH

make clean && \
 make PG_CONFIG=$PG_CONFIG_PATH CFLAGS="-DUSE_ASSERT_CHECKING -O0 -g" && \
 make install PG_CONFIG=$PG_CONFIG_PATH

$PSQL_PATH postgres -c "DROP EXTENSION IF EXISTS rdf_fdw CASCADE; CREATE EXTENSION rdf_fdw"
$PSQL_PATH postgres -c "SELECT * FROM rdf_fdw_settings;"

# SKIP_STRESS_TESTS=1   - skip long running stress tests
# SKIP_UPDATE_TESTS=1   - skip tests that update data (INSERT/DELETE/UPDATE)
# SKIP_EXTERNAL_TESTS=1 - skip tests that need external network access
# SKIP_DEBUG_TESTS=1    - skip tests that need debug output (debug.out)
# make PG_CONFIG=$PG_CONFIG_PATH PGUSER=jim \
#     SKIP_EXTERNAL_TESTS=1 SKIP_STRESS_TESTS=1 SKIP_DEBUG_TESTS=1 SKIP_UPDATE_TESTS=1 \
#     installcheck 

echo -e "\n== local deployment complete ==\n"
