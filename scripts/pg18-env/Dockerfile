FROM postgres:18

RUN apt-get update && \
    apt-get install -y make gcc postgresql-server-dev-18 libxml2-dev libcurl4-gnutls-dev librdf0-dev pkg-config

RUN mkdir /rdf_fdw
