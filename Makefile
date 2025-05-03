MODULE_big = rdf_fdw
OBJS = rdf_fdw.o
EXTENSION = rdf_fdw
DOCS = README.md
DATA = rdf_fdw--1.4.sql rdf_fdw--1.3--1.4.sql

RDF_CONFIG = pkg-config
CURL_CONFIG = curl-config
PG_CONFIG = pg_config

SHLIB_LINK := $(shell $(CURL_CONFIG) --libs) \
	$(shell $(RDF_CONFIG) --libs raptor2) \
	$(shell $(RDF_CONFIG) --libs redland)

PG_CPPFLAGS = $(shell xml2-config --cflags) \
	$(shell $(RDF_CONFIG) --cflags raptor2) \
	$(shell $(RDF_CONFIG) --cflags redland)

PGXS := $(shell $(PG_CONFIG) --pgxs)

MAJORVERSION := $(shell $(PG_CONFIG) --version | awk '{ \
  split($$2,v,"."); \
  if (v[1] < 10) printf("%d%02d", v[1], v[2]); \
  else print v[1] }')

REGRESS = create_extension \
			rdfiri_in \
			rdfiri_eq \
			rdfiri_neq \
			rdfliteral_in \
			rdfliteral_eq \
			rdfliteral_neq \
			rdfliteral_lt \
			rdfliteral_gt \
			rdfliteral_le \
			rdfliteral_ge \
			pg_datatypes \
			functions \
			describe \
			graphdb-getty \
			blazegraph-wikidata

$(info Running regression tests for MAJORVERSION=$(MAJORVERSION))

ifeq ($(shell [ "$(MAJORVERSION)" != "906" ] && [ "$(MAJORVERSION)" != "10" ] && echo yes),yes)
  REGRESS += exceptions
endif

$(info Tests to run: $(REGRESS))

include $(PGXS)