MODULE_big = rdf_fdw
OBJS = rdf_fdw.o rdf_utils.o sparql.o rdfnode.o
EXTENSION = rdf_fdw
DOCS = README.md
DATA = rdf_fdw--2.2.sql rdf_fdw--2.1--2.2.sql rdf_fdw--2.1.sql

RDF_CONFIG = pkg-config
CURL_CONFIG = curl-config
PG_CONFIG = pg_config

SHLIB_LINK := $(shell $(CURL_CONFIG) --libs) \
	$(shell $(RDF_CONFIG) --libs raptor2) \
	$(shell $(RDF_CONFIG) --libs redland)

PG_CPPFLAGS = $(shell xml2-config --cflags) \
	$(shell $(RDF_CONFIG) --cflags raptor2) \
	$(shell $(RDF_CONFIG) --cflags redland) \
	-DRDF_FDW_CC="\"$(CC)\"" \
	-DRDF_FDW_BUILD_DATE="\"$(shell date -u +'%Y-%m-%d %H:%M:%S UTC')\""

PGXS := $(shell $(PG_CONFIG) --pgxs)

MAJORVERSION := $(shell $(PG_CONFIG) --version | awk '{ \
  split($$2,v,"."); \
  if (v[1] < 10) printf("%d%02d", v[1], v[2]); \
  else print v[1] }')

REGRESS += create_extension \
			upgrade \
			version \
			rdfnode_in \
			rdfnode_eq \
			rdfnode_neq \
			rdfnode_lt \
			rdfnode_gt \
			rdfnode_le \
			rdfnode_ge \
			rdfnode_agg \
			rdfnode_cast \
			explain \
			pg_datatypes \
			sparql-functions \
			prefix-management \
			table-clone \
			virtuoso-pgtypes-linkedgeodata \
			virtuoso-rdfnode-linkedgeodata \
			blazegraph-pgtypes-wikidata \
			blazegraph-rdfnode-wikidata \
			graphdb-pgtypes-getty \
			graphdb-rdfnode-agrovoc \
			describe

$(info Running regression tests for MAJORVERSION=$(MAJORVERSION))

ifeq ($(shell [ "$(MAJORVERSION)" != "906" ] && [ "$(MAJORVERSION)" != "10" ] && echo yes),yes)
  REGRESS += exceptions
endif

$(info Tests to run: $(REGRESS))

include $(PGXS)