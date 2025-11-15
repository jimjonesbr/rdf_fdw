CREATE FUNCTION rdf_fdw_settings()
RETURNS text AS 'MODULE_PATHNAME', 'rdf_fdw_settings'
LANGUAGE C IMMUTABLE STRICT;

COMMENT ON FUNCTION rdf_fdw_settings() IS 'Returns detailed dependency information including optional components';

CREATE VIEW rdf_fdw_settings AS
    WITH version_string AS (
        SELECT rdf_fdw_settings() AS v
    )
    SELECT component, version
    FROM version_string,
    LATERAL (VALUES
        ('rdf_fdw',    substring(v from 'rdf_fdw\s+([^\s,]+)')),
        ('PostgreSQL', substring(v from 'PostgreSQL\s+([^,]+)')),
        ('libxml',     substring(v from 'libxml\s+([^,]+)')),
        ('librdf',     substring(v from 'librdf\s+([^,]+)')),
        ('libcurl',    substring(v from 'libcurl\s+([^,]+)')),
        ('ssl',        substring(v from ',ssl\s+([^,]+)')),
        ('zlib',       substring(v from ',zlib\s+([^,]+)')),
        ('libSSH',     substring(v from ',libSSH\s+([^,]+)')),
        ('nghttp2',    substring(v from ',nghttp2\s+([^,]+)')),
        ('compiler',   substring(v from 'compiled by\s+([^,]+)')),
        ('built',      substring(v from 'built on\s+([^,]+)'))
    ) AS components(component, version)
    WHERE version IS NOT NULL;

COMMENT ON VIEW rdf_fdw_settings IS 'Parse detailed dependency information into component versions';

-- SUM aggregate for rdfnode
CREATE FUNCTION sparql.sum_rdfnode_sfunc(internal, rdfnode)
RETURNS internal AS 'MODULE_PATHNAME', 'rdf_fdw_sum_sfunc'
LANGUAGE C IMMUTABLE;

CREATE FUNCTION sparql.sum_rdfnode_finalfunc(internal)
RETURNS rdfnode AS 'MODULE_PATHNAME', 'rdf_fdw_sum_finalfunc'
LANGUAGE C IMMUTABLE;

CREATE AGGREGATE sparql.sum(rdfnode) (
    SFUNC = sparql.sum_rdfnode_sfunc,
    STYPE = internal,
    FINALFUNC = sparql.sum_rdfnode_finalfunc
);

COMMENT ON AGGREGATE sparql.sum(rdfnode) IS 'Computes the sum of numeric rdfnode values with XSD type promotion (integer < decimal < float < double)';
