#!/bin/bash

CODEPATH="/home/jim/git/rdf_fdw"
TEST_ENV_PATH=~/git/rdf_fdw/scripts/postgres-env
PGVERSIONS="9.5,9.6,10,11,12,13,14,15,16,17,18,19"
#PGVERSIONS="9.5"
IMAGENAME="pgxn-image"
NETWORK_NAME="pgnet"

# builds a custom pgxn image with extension dependencies (libxml2 and libcurl)
echo -e "\n== Building PGXN podman Image ==\n"
podman build --tag $IMAGENAME . &&

# create a custom podman network for postgres and fuseki containers to communicate
podman network create --driver=bridge --subnet=172.19.42.0/24 $NETWORK_NAME

# keeps things clean
make -C $CODEPATH clean &&
reset &&

IFS=',' read -ra version <<< "$PGVERSIONS" &&
for pgv in "${version[@]}"; 
do
    
    bash $TEST_ENV_PATH/virtuoso/deploy-virtuoso.sh
    bash $TEST_ENV_PATH/fuseki/deploy-fuseki.sh
    bash $TEST_ENV_PATH/graphdb/deploy-graphdb.sh
    bash $TEST_ENV_PATH/qlever/deploy-qlever.sh
    bash $TEST_ENV_PATH/squid/deploy-proxy-env.sh

    # Tests that need a triplestore are opt-in:
    # INCLUDE_LOCAL_TESTS=1    - tests against locally deployed triplestores
    # INCLUDE_EXTERNAL_TESTS=1 - tests that need external network access
    # INCLUDE_STRESS_TESTS=1   - long running stress tests
    # INCLUDE_DEBUG_TESTS=1    - tests that need debug output (debug.out)
    # INCLUDE_ALL_TESTS=1      - all of the above
    #
    # ex. "export INCLUDE_LOCAL_TESTS=1 && pg-start $pgv && pg-build-test && make clean"

    podman run \
        --network $NETWORK_NAME \
        --no-hosts \
        -itw /ext --rm \
        --volume "$CODEPATH:/ext:z" $IMAGENAME sh -c "export INCLUDE_LOCAL_TESTS=1 && pg-start $pgv && pg-build-test && make clean" &&

    
    echo -e "\n\n== Tests finished for PostgreSQL $pgv ==\n\n"    
done

#make -C $CODEPATH clean
