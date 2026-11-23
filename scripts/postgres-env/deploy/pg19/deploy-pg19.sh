POSTGRES19_IMAGE=pg19-rdf_fdw
RDF_FDW_PATH=~/git/rdf_fdw
PG_CONTAINER=rdf_pg19
NETWORK_NAME=pgnet
IP_ADDRESS="172.19.42.19"

podman build -t $POSTGRES19_IMAGE .

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
  -p 54319:5432 \
  $POSTGRES19_IMAGE -c logging_collector=on &&

podman exec -itw /rdf_fdw/ $PG_CONTAINER make clean &&
podman exec -itw /rdf_fdw/ $PG_CONTAINER make PG_CONFIG=/usr/lib/postgresql/19/bin/pg_config &&
podman exec -itw /rdf_fdw/ $PG_CONTAINER make install

# deploy GeoServer in the same network
# podman run -it --network pgnet -p 8080:8080 docker.osgeo.org/geoserver:3.0.