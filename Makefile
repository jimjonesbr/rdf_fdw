MODULE_big = rdf_fdw
OBJS = rdf_fdw.o
EXTENSION = rdf_fdw
DATA = rdf_fdw--1.1.sql rdf_fdw--1.0--1.1.sql
REGRESS = virtuoso-dbpedia graphdb-getty blazegraph-wikidata exceptions table-clone

CURL_CONFIG = curl-config
PG_CONFIG = pg_config

CFLAGS += $(shell $(CURL_CONFIG) --cflags)
LIBS += $(shell $(CURL_CONFIG) --libs)

SHLIB_LINK := $(LIBS)

PGXS := $(shell $(PG_CONFIG) --pgxs)
include $(PGXS)