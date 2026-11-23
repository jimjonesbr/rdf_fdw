POSTGRES18_IMAGE=pg18-rdf_fdw
RDF_FDW_PATH=~/git/rdf_fdw
PG_CONTAINER=rdf_pg18
NETWORK_NAME=pgnet
IP_ADDRESS="172.19.42.18"

podman build -t $POSTGRES18_IMAGE .

podman stop $PG_CONTAINER
podman rm $PG_CONTAINER
podman network create --driver=bridge --subnet=172.19.42.0/24 $NETWORK_NAME
podman run -d \
  --name   $PG_CONTAINER \
  --network $NETWORK_NAME \
  --env POSTGRES_HOST_AUTH_METHOD=trust \
  --ip $IP_ADDRESS \
  --volume  $RDF_FDW_PATH:/rdf_fdw:Z \
  --no-hosts \
  -p 54318:5432 \
  $POSTGRES18_IMAGE -c logging_collector=on &&

podman exec -itw /rdf_fdw/ $PG_CONTAINER make clean &&
podman exec -itw /rdf_fdw/ $PG_CONTAINER make PG_CONFIG=/usr/lib/postgresql/18/bin/pg_config &&
podman exec -itw /rdf_fdw/ $PG_CONTAINER make install

# deploy GeoServer in the same network
# podman run -it --network pgnet -p 8080:8080 docker.osgeo.org/geoserver:3.0.