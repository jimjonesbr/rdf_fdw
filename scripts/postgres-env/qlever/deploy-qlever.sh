#!/bin/bash

QLEVER_ENV_PATH=~/git/rdf_fdw/scripts/postgres-env/qlever

set -euo pipefail

export QLEVER_UID=$(id -u)
export QLEVER_GID=$(id -g)

echo -e "\n== Deploying QLever for tests ==\n"

docker compose -f $QLEVER_ENV_PATH/qlever-compose.yml down -v 2>/dev/null || true
docker compose -f $QLEVER_ENV_PATH/qlever-compose.yml up -d qlever-backend

echo "Waiting for QLever SPARQL endpoint..."
for i in $(seq 1 90); do
    if curl -sf \
        -H "Authorization: Bearer secret" \
        --data-urlencode "query=SELECT * WHERE {} LIMIT 1" \
        "http://localhost:7001/sparql" >/dev/null 2>&1; then
        echo "QLever is ready!"
        exit 0
    fi
    echo "  attempt $i/90..."
    sleep 2
done

echo "ERROR: QLever did not become ready in time." >&2
docker compose -f $QLEVER_ENV_PATH/qlever-compose.yml logs >&2
exit 1