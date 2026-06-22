#!/bin/bash

NETWORK_NAME=pgnet
GRAPHDB_REPOSITORY="test"

# Deploy GraphDB for tests
echo -e "\n== Deploying GraphDB for tests ==\n"

podman stop graphdb 2>/dev/null || true
podman rm graphdb 2>/dev/null || true
podman run -d --name graphdb \
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
