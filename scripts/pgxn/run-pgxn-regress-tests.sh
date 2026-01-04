#!/bin/bash

CODEPATH="/home/jim/git/rdf_fdw"
PGVERSIONS="9.5,9.6,10,11,12,13,14,15,16,17,18,19"
IMAGENAME="pgxn-image"
NETWORK_NAME="pgnet"
FUSEKI_DATASET="dt"
GRAPHDB_REPOSITORY="test"

# builds a custom pgxn image with extension dependencies (libxml2 and libcurl)
echo -e "\n== Building PGXN Docker Image ==\n"
docker build --tag $IMAGENAME . &&

# create a custom docker network for postgres and fuseki containers to communicate
docker network create --driver=bridge --subnet=172.19.42.0/24 $NETWORK_NAME

# keeps things clean
make -C $CODEPATH clean &&
reset &&

IFS=',' read -ra version <<< "$PGVERSIONS" &&
for pgv in "${version[@]}"; 
do
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

    cat > /tmp/pgxn-repo-config.ttl <<EOF
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
    -F "config=@/tmp/pgxn-repo-config.ttl" \
    http://localhost:7200/rest/repositories
    echo "GraphDB repository 'test' created."

    # SKIP_EXTERNAL_TESTS=1 - skip tests that need external network access
    # SKIP_STRESS_TESTS=1   - skip long running stress tests
    # SKIP_UPDATE_TESTS=1   - skip tests that update data (INSERT/DELETE/UPDATE)
    #
    # ex. export SKIP_STRESS_TESTS=1 &&

    docker run \
        --network $NETWORK_NAME \
        -itw /ext --rm \
        --volume "$CODEPATH:/ext" $IMAGENAME sh -c "export SKIP_STRESS_TESTS=1 SKIP_EXTERNAL_TESTS=1 && pg-start $pgv && pg-build-test && make clean" &&

    
    echo -e "\n\n== Tests finished for PostgreSQL $pgv ==\n\n"    
done

make -C $CODEPATH clean