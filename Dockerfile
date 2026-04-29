ARG PG_VERSION=17
FROM postgres:${PG_VERSION}

ARG PG_VERSION=17
ARG RDF_FDW_VERSION=2.6

RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        make \
        gcc \
        git \
        postgresql-server-dev-${PG_VERSION} \
        libxml2-dev \
        libcurl4-gnutls-dev \
        pkg-config && \
    git clone --branch v${RDF_FDW_VERSION} --depth 1 \
        https://github.com/jimjonesbr/rdf_fdw.git /tmp/rdf_fdw && \
    cd /tmp/rdf_fdw && \
    make -j$(nproc) && \
    make install && \
    cd / && rm -rf /tmp/rdf_fdw && \
    apt-get purge -y make gcc git postgresql-server-dev-${PG_VERSION} libxml2-dev libcurl4-gnutls-dev pkg-config && \
    apt-get autoremove -y && \
    apt-get install -y --no-install-recommends libcurl3-gnutls libxml2 && \
    rm -rf /var/lib/apt/lists/*
