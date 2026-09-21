MODULE_big = rdf_fdw
OBJS = rdf_fdw.o rdf_utils.o sparql.o rdfnode.o
EXTENSION = rdf_fdw
DOCS = README.md
DATA = rdf_fdw--3.0.sql \
       rdf_fdw--2.7--3.0.sql \
       rdf_fdw--2.6--2.7.sql \
       rdf_fdw--2.5--2.6.sql \
       rdf_fdw--2.4--2.5.sql \
       rdf_fdw--2.3--2.4.sql \
       rdf_fdw--2.2--2.3.sql \
	   rdf_fdw--2.1--2.2.sql \
	   rdf_fdw--2.1.sql

CURL_CONFIG = curl-config
XML2_CONFIG = xml2-config
PG_CONFIG = pg_config

SHLIB_LINK := $(shell $(CURL_CONFIG) --libs)

# Build timestamp reported by rdf_fdw_version() and the rdf_fdw_settings view.
# Package builds set SOURCE_DATE_EPOCH, and honouring it in place of the wall
# clock is what keeps the resulting binary reproducible.
ifdef SOURCE_DATE_EPOCH
  BUILD_DATE := $(shell date -u -d "@$(SOURCE_DATE_EPOCH)" +'%Y-%m-%d %H:%M:%S UTC' 2>/dev/null || \
                        date -u -r "$(SOURCE_DATE_EPOCH)" +'%Y-%m-%d %H:%M:%S UTC' 2>/dev/null || \
                        echo "$(SOURCE_DATE_EPOCH)")
else
  BUILD_DATE := $(shell date -u +'%Y-%m-%d %H:%M:%S UTC')
endif

PG_CPPFLAGS = $(shell $(XML2_CONFIG) --cflags) \
	-DRDF_FDW_CC="\"$(CC)\"" \
	-DRDF_FDW_BUILD_DATE="\"$(BUILD_DATE)\""

PGXS := $(shell $(PG_CONFIG) --pgxs)

MAJORVERSION := $(shell $(PG_CONFIG) --version | awk '{ \
  split($$2,v,"."); \
  if (v[1] < 10) printf("%d%02d", v[1], v[2]); \
  else print v[1] }')

REGRESS +=  create-extension \
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
			rdfnode_opclass \
			rdfnode_arith \
			rdfnode_agg \
			rdfnode_cast \
			explain \
			pushdown \
			pg_datatypes \
			sparql-functions \
			privileges \
			encoding

#
# The tests above need nothing but a PostgreSQL server, and are the ones that
# run by default. Every group below needs a triplestore, so they are opt-in:
#
#   make installcheck INCLUDE_LOCAL_TESTS=1     the triplestores deployed by
#                                               scripts/postgres-env (Virtuoso,
#                                               QLever, Fuseki, GraphDB, proxy)
#   make installcheck INCLUDE_EXTERNAL_TESTS=1  public SPARQL endpoints
#   make installcheck INCLUDE_STRESS_TESTS=1    long running stress tests,
#                                               local deployment as well
#   make installcheck INCLUDE_DEBUG_TESTS=1     debug output, local deployment
#                                               as well
#   make installcheck INCLUDE_ALL_TESTS=1       all of the above
#
ifdef INCLUDE_ALL_TESTS
  INCLUDE_LOCAL_TESTS = 1
  INCLUDE_DEBUG_TESTS = 1
  INCLUDE_STRESS_TESTS = 1
  INCLUDE_EXTERNAL_TESTS = 1
endif

ifdef INCLUDE_LOCAL_TESTS
  REGRESS += virtuoso-delete \
			 virtuoso-update \
  			 virtuoso-insert \
			 virtuoso-select \
			 virtuoso-describe \
			 virtuoso-table-clone \
  			 qlever-delete \
			 qlever-update \
  			 qlever-insert \
			 qlever-select \
			 qlever-describe \
			 qlever-table-clone \
  			 fuseki-delete \
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
			 proxy-auth \
			 stub-endpoint \
			 clone-node-types
endif

ifdef INCLUDE_DEBUG_TESTS
  REGRESS += debug
endif

ifdef INCLUDE_STRESS_TESTS
  REGRESS += fuseki-stress \
  		     graphdb-stress	\
			 virtuoso-stress \
			 qlever-stress
endif

ifdef INCLUDE_EXTERNAL_TESTS
  REGRESS += table-clone \
			 virtuoso-pgtypes-linkedgeodata \
			 virtuoso-rdfnode-linkedgeodata \
			 blazegraph-pgtypes-wikidata \
			 blazegraph-rdfnode-wikidata \
			 graphdb-pgtypes-getty \
			 describe \
			 prefix-management
endif
$(info Running regression tests for MAJORVERSION=$(MAJORVERSION))

$(info Tests to run: $(REGRESS))

include $(PGXS)