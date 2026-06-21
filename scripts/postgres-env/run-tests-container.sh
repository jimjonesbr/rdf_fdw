#!/bin/bash

TEST_ENV_PATH=~/git/rdf_fdw/scripts/postgres-env
CONTAINER_NAME=rdf_pg18

bash $TEST_ENV_PATH/virtuoso/deploy-virtuoso.sh
bash $TEST_ENV_PATH/fuseki/deploy-fuseki.sh
bash $TEST_ENV_PATH/graphdb/deploy-graphdb.sh
bash $TEST_ENV_PATH/qlever/deploy-qlever.sh
bash $TEST_ENV_PATH/squid/deploy-proxy-env.sh

# Build and install rdf_fdw
echo -e "\n== Building and Installing rdf_fdw on PostgreSQL 18 ==\n"

docker exec -itw /rdf_fdw/ $CONTAINER_NAME make uninstall 2>/dev/null || true
docker exec -itw /rdf_fdw/ $CONTAINER_NAME make clean
docker exec -itw /rdf_fdw/ $CONTAINER_NAME make CFLAGS="-DUSE_ASSERT_CHECKING -O0 -g" 
docker exec -itw /rdf_fdw/ $CONTAINER_NAME make install
docker restart $CONTAINER_NAME
docker exec -itw /rdf_fdw/ -u postgres $CONTAINER_NAME psql -d postgres \
  -c "DROP EXTENSION IF EXISTS rdf_fdw CASCADE; CREATE EXTENSION rdf_fdw"

# SKIP_STRESS_TESTS=1   - skip long running stress tests
# SKIP_UPDATE_TESTS=1   - skip tests that update data (INSERT/DELETE/UPDATE)
# SKIP_EXTERNAL_TESTS=1 - skip tests that need external network access
# SKIP_DEBUG_TESTS=1    - skip tests that need debug output (debug.out)

docker exec -itw /rdf_fdw/ $CONTAINER_NAME make PGUSER=postgres \
    SKIP_EXTERNAL_TESTS=1 SKIP_STRESS_TESTS=1 SKIP_DEBUG_TESTS=1 \
    installcheck 

echo -e "\n== Tests completed ==\n"
