CREATE FUNCTION rdf_fdw_handler()
RETURNS fdw_handler AS 'MODULE_PATHNAME'
LANGUAGE C STRICT;

CREATE FUNCTION rdf_fdw_version()
RETURNS text AS 'MODULE_PATHNAME', 'rdf_fdw_version'
LANGUAGE C IMMUTABLE STRICT PARALLEL SAFE;

CREATE FUNCTION rdf_fdw_validator(text[], oid)
RETURNS void AS 'MODULE_PATHNAME'
LANGUAGE C STRICT;

COMMENT ON FUNCTION rdf_fdw_validator(text[], oid) IS 'RDF Triplestore Foreign-data Wrapper options validator';
  
CREATE FOREIGN DATA WRAPPER rdf_fdw
HANDLER rdf_fdw_handler
VALIDATOR rdf_fdw_validator;

COMMENT ON FOREIGN DATA WRAPPER rdf_fdw IS 'RDF Triplestore Foreign Data Wrapper';