MODULE_big = rdf_fdw
OBJS = rdf_fdw.o
EXTENSION = rdf_fdw
DOCS = README.md
DATA = rdf_fdw--1.4.sql rdf_fdw--1.3--1.4.sql

RDF_CONFIG = pkg-config
CURL_CONFIG = curl-config
PG_CONFIG = pg_config

ifndef MAJORVERSION
MAJORVERSION := $(basename $(VERSION))
endif

REGRESS = describe virtuoso-dbpedia graphdb-getty blazegraph-wikidata $(if $(findstring $(MAJORVERSION),11 12 13 14 15 16 17 18),exceptions table-clone,)

SHLIB_LINK := $(shell $(CURL_CONFIG) --libs) \
	$(shell $(RDF_CONFIG) --libs raptor2) \
	$(shell $(RDF_CONFIG) --libs redland)

PG_CPPFLAGS = $(shell xml2-config --cflags) \
	$(shell $(RDF_CONFIG) --cflags raptor2) \
	$(shell $(RDF_CONFIG) --cflags redland)

PGXS := $(shell $(PG_CONFIG) --pgxs)
include $(PGXS)