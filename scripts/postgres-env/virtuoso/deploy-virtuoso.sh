#!/bin/bash

NETWORK_NAME=pgnet
DBA_PASSWORD=secret

echo -e "\n== Deploying Virtuoso for tests ==\n"

docker stop virtuoso 2>/dev/null || true
docker rm virtuoso 2>/dev/null || true
docker run -d --name virtuoso \
  --network $NETWORK_NAME \
  -p 8890:8890 \
  -e DBA_PASSWORD=$DBA_PASSWORD \
  tenforce/virtuoso

echo "Waiting for Virtuoso to start..."
for i in {1..60}; do
    curl -sf "http://localhost:8890/sparql?query=SELECT+%2A+WHERE+%7B%7D+LIMIT+1" \
      -H "Accept: application/sparql-results+json" >/dev/null 2>&1 && break
    sleep 1
done
echo "Virtuoso HTTP endpoint is ready!"

# Switch /sparql-auth from Digest to Basic auth and enable SPARQL UPDATE.
# Changes to DB.DBA.HTTP_PATH require a checkpoint + restart to take effect.
echo "Configuring /sparql-auth for Basic auth..."
docker exec virtuoso isql-v 1111 dba "$DBA_PASSWORD" exec="
GRANT SPARQL_UPDATE TO \"dba\";
UPDATE DB.DBA.HTTP_PATH
  SET HP_SECURITY = 'basic',
      HP_OPTIONS  = serialize(vector('noinherit', 1, 'sparql_update', 1))
  WHERE HP_LPATH = '/sparql-auth' AND HP_HOST = '*ini*';
checkpoint;
"

echo "Restarting Virtuoso to apply HTTP path changes..."
docker restart virtuoso >/dev/null
for i in {1..60}; do
    curl -sf "http://localhost:8890/sparql?query=SELECT+%2A+WHERE+%7B%7D+LIMIT+1" \
      -H "Accept: application/sparql-results+json" >/dev/null 2>&1 && break
    sleep 1
done

echo "Virtuoso is ready!"
