#!/bin/bash

NETWORK_NAME=pgnet
FUSEKI_DATASET="dt"

echo -e "\n== Deploying Fuseki for tests ==\n"

podman stop fuseki 2>/dev/null || true
podman rm fuseki 2>/dev/null || true
podman run -d --name fuseki \
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