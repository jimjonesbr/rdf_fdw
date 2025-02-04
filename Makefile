MODULE_big = rdf_fdw
OBJS = rdf_fdw.o
EXTENSION = rdf_fdw
DOCS = README.md
DATA = rdf_fdw--1.3.sql rdf_fdw--1.2--1.3.sql

CURL_CONFIG = curl-config
ifndef MAJORVERSION
MAJORVERSION := $(basename $(VERSION))
endif

REGRESS = virtuoso-dbpedia graphdb-getty blazegraph-wikidata $(if $(findstring $(MAJORVERSION),11 12 13 14 15 16 17 18),exceptions table-clone,)

CFLAGS += $(shell $(CURL_CONFIG) --cflags)
LIBS += $(shell $(CURL_CONFIG) --libs)
SHLIB_LINK := $(LIBS)

PG_CONFIG = pg_config
PGXS := $(shell $(PG_CONFIG) --pgxs)
include $(PGXS)