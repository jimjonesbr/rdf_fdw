#!/bin/bash

NETWORK_NAME=pgnet

echo -e "\n== Deploying Blazegraph for tests ==\n"

podman stop blazegraph 2>/dev/null || true
podman rm blazegraph 2>/dev/null || true
podman run -d --name blazegraph \
  --network $NETWORK_NAME \
  -p 9999:9999 \
  -e JAVA_TOOL_OPTIONS="-Dfile.encoding=UTF-8" \
  nawer/blazegraph:2.1.5

echo "Waiting for Blazegraph to start..."
for i in {1..60}; do
    curl -sf "http://localhost:9999/blazegraph/sparql?query=SELECT+%2A+WHERE+%7B%7D+LIMIT+1" \
      -H "Accept: application/sparql-results+json" >/dev/null 2>&1 && break
    sleep 1
done
echo "Blazegraph is ready!"
