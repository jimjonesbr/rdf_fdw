FROM docker.io/library/postgres:19

RUN apt-get update && \
    apt-get install -y make gcc postgresql-server-dev-19 libxml2-dev libcurl4-gnutls-dev pkg-config postgresql-19-postgis-3

RUN mkdir /rdf_fdw
