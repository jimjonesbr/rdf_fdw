MODULE_big = rdf_fdw
OBJS = rdf_fdw.o rdf_utils.o sparql.o rdfnode.o
EXTENSION = rdf_fdw
DOCS = README.md
DATA = rdf_fdw--2.3.sql rdf_fdw--2.2.sql rdf_fdw--2.1.sql rdf_fdw--2.1--2.2.sql rdf_fdw--2.2--2.3.sql

RDF_CONFIG = pkg-config
CURL_CONFIG = curl-config
PG_CONFIG = pg_config

SHLIB_LINK := $(shell $(CURL_CONFIG) --libs)

PG_CPPFLAGS = $(shell xml2-config --cflags) \
	-DRDF_FDW_CC="\"$(CC)\"" \
	-DRDF_FDW_BUILD_DATE="\"$(shell date -u +'%Y-%m-%d %H:%M:%S UTC')\""

PGXS := $(shell $(PG_CONFIG) --pgxs)

MAJORVERSION := $(shell $(PG_CONFIG) --version | awk '{ \
  split($$2,v,"."); \
  if (v[1] < 10) printf("%d%02d", v[1], v[2]); \
  else print v[1] }')

REGRESS += create_extension \
			upgrade \
			create-server \
			create-foreign-table \
			create-user-mapping \
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
			prefix-management

ifndef SKIP_UPDATE_TESTS
  REGRESS += fuseki-delete \
  			 fuseki-update \
			 fuseki-insert \
			 fuseki-select \
			 fuseki-table-clone \
			 fuseki-describe \
			 graphdb-delete \
			 graphdb-insert \
			 graphdb-update \
			 graphdb-select \
			 graphdb-table-clone \
			 graphdb-describe \
			 proxy \
			 proxy-auth
endif

ifndef SKIP_STRESS_TESTS
  REGRESS += fuseki-stress \
  		     graphdb-stress	
endif

ifndef SKIP_EXTERNAL_TESTS
  REGRESS += table-clone \
			 virtuoso-pgtypes-linkedgeodata \
			 virtuoso-rdfnode-linkedgeodata \
			 blazegraph-pgtypes-wikidata \
			 blazegraph-rdfnode-wikidata \
			 graphdb-pgtypes-getty \
			 describe
endif
$(info Running regression tests for MAJORVERSION=$(MAJORVERSION))

$(info Tests to run: $(REGRESS))

include $(PGXS)