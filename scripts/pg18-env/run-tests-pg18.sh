#!/bin/bash

CONTAINER_NAME=pg18
NETWORK_NAME=pgnet
GRAPHDB_REPOSITORY="test"
FUSEKI_DATASET="dt"

# Deploy Fuseki for tests
echo -e "\n== Deploying Fuseki for tests ==\n"

docker stop fuseki
docker rm fuseki
docker run -d --name fuseki \
  --network $NETWORK_NAME \
  -p 3030:3030 \
  -e ADMIN_PASSWORD=secret \
  -e FUSEKI_DATASET_1=$FUSEKI_DATASET \
  stain/jena-fuseki

echo "Waiting for Fuseki to start..."
for i in {1..60}; do
    curl -s http://localhost:3030/$FUSEKI_DATASET >/dev/null 2>&1 && break
    sleep 1
done
echo "Fuseki is ready!"

# Deploy GraphDB for tests
echo -e "\n== Deploying GraphDB for tests ==\n"

docker stop graphdb
docker rm graphdb
docker run -d --name graphdb \
  --network $NETWORK_NAME \
  -p 7200:7200 \
  -e GRAPHDB_HOME=/opt/graphdb/home \
  -e JAVA_OPTS="-Xms2g -Xmx8g" \
  ontotext/graphdb:10.4.2

echo "Waiting for GraphDB to start..."
for i in {1..60}; do
    curl -s http://localhost:7200 >/dev/null 2>&1 && break
    sleep 1
done
echo "GraphDB is ready!"

echo "Creating default GraphDB repository..."

cat > /tmp/repo-config.ttl <<EOF
# GraphDB repository configuration
#
# This is a minimal config for a 'test' repo of type 'free'
#
@prefix rdfs: <http://www.w3.org/2000/01/rdf-schema#>.
@prefix rep: <http://www.openrdf.org/config/repository#>.
@prefix sr: <http://www.openrdf.org/config/repository/sail#>.
@prefix sail: <http://www.openrdf.org/config/sail#>.
@prefix graphdb: <http://www.ontotext.com/config/graphdb#>.

[] a rep:Repository ;
   rep:repositoryID "$GRAPHDB_REPOSITORY" ;
   rdfs:label "Test repository" ;
   rep:repositoryImpl [
      rep:repositoryType "graphdb:SailRepository" ;
      sr:sailImpl [
         sail:sailType "graphdb:Sail"
      ]
   ].
EOF

curl -X POST \
  -H "Content-Type: multipart/form-data" \
  -F "config=@/tmp/repo-config.ttl" \
  http://localhost:7200/rest/repositories
echo "GraphDB repository 'test' created."

# Build and install rdf_fdw
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

docker exec -itw /rdf_fdw/ $CONTAINER_NAME make PGUSER=postgres SKIP_EXTERNAL_TESTS=1 SKIP_STRESS_TESTS=1 installcheck 
echo -e "\n== Tests completed ==\n"