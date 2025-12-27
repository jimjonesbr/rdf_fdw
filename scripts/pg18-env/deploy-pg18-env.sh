POSTGRES18_IMAGE=pg18-rdf_fdw
RDF_FDW_PATH=~/git/rdf_fdw
PG_CONTAINER=pg18
NETWORK_NAME=pgnet
IP_ADDRESS="172.19.42.18"

docker build -t $POSTGRES18_IMAGE .

docker stop $PG_CONTAINER
docker rm $PG_CONTAINER
docker network create --driver=bridge --subnet=172.19.42.0/24 $NETWORK_NAME
docker run -d \
  --name   $PG_CONTAINER \
  --network $NETWORK_NAME \
  --env POSTGRES_HOST_AUTH_METHOD=trust \
  --ip $IP_ADDRESS \
  --volume  $RDF_FDW_PATH:/rdf_fdw:Z \
  $POSTGRES18_IMAGE -c logging_collector=on &&

docker exec -itw /rdf_fdw/ $PG_CONTAINER make clean &&
docker exec -itw /rdf_fdw/ $PG_CONTAINER make PG_CONFIG=/usr/lib/postgresql/18/bin/pg_config &&
docker exec -itw /rdf_fdw/ $PG_CONTAINER make install