#!/bin/bash

CODEPATH="/home/jim/git/rdf_fdw"
PGVERSIONS="9.5,9.6,10,11,12,13,14,15,16,17,18,19"
IMAGENAME="pgxn-image"
NETWORK_NAME="pgnet"

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
    echo -e "\n== Deploying Fuseki for $pgv tests ==\n"
    docker stop fuseki 
    docker rm fuseki
    docker run -d --name fuseki \
        --network $NETWORK_NAME \
        -p 3030:3030 \
        -e ADMIN_PASSWORD=secret \
        -e FUSEKI_DATASET_1=dt \
        stain/jena-fuseki

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