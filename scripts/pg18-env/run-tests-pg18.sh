#!/bin/bash

CONTAINER_NAME=pg18
NETWORK_NAME=pgnet

echo -e "\n== Deploying Fuseki for tests ==\n"

docker stop fuseki
docker rm fuseki
docker run -d --name fuseki \
  --network $NETWORK_NAME \
  -p 3030:3030 \
  -e ADMIN_PASSWORD=secret \
  -e FUSEKI_DATASET_1=dt \
  stain/jena-fuseki

echo "Waiting for Fuseki to start..."
for i in {1..60}; do
    curl -s http://localhost:3030/dt >/dev/null 2>&1 && break
    sleep 1
done
echo "Fuseki is ready!"

echo -e "\n== Building and Installing rdf_fdw on PostgreSQL 18 ==\n"
docker exec -itw /rdf_fdw/ $CONTAINER_NAME make uninstall 2>/dev/null || true
docker exec -itw /rdf_fdw/ $CONTAINER_NAME make clean
docker exec -itw /rdf_fdw/ $CONTAINER_NAME make
docker exec -itw /rdf_fdw/ $CONTAINER_NAME make install
docker restart $CONTAINER_NAME
docker exec -itw /rdf_fdw/ -u postgres $CONTAINER_NAME psql -d postgres \
  -c "DROP EXTENSION IF EXISTS rdf_fdw CASCADE; CREATE EXTENSION rdf_fdw"

# SKIP_STRESS_TESTS=1   - skip long running stress tests
# SKIP_UPDATE_TESTS=1   - skip tests that update data (INSERT/DELETE/UPDATE)
# SKIP_EXTERNAL_TESTS=1 - skip tests that need external network access

docker exec -itw /rdf_fdw/ $CONTAINER_NAME make PGUSER=postgres SKIP_STRESS_TESTS=1 installcheck 
echo -e "\n== Tests completed ==\n"
