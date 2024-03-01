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

CREATE FUNCTION rdf_fdw_clone_table(
    foreign_table oid,
    target_table text,
    begin_offset int DEFAULT 0,
    page_size int DEFAULT 0,
    max_records int DEFAULT 0, 
    ordering_column text DEFAULT '',
    create_table boolean DEFAULT false,
    verbose boolean DEFAULT false)
RETURNS void AS 'MODULE_PATHNAME', 'rdf_fdw_clone_table'
LANGUAGE C IMMUTABLE STRICT PARALLEL UNSAFE;

COMMENT ON FUNCTION rdf_fdw_clone_table(oid,text,int,int,int,text,boolean,boolean) IS 'materialize rdf_fdw foreign tables into heap tables';

CREATE FOREIGN DATA WRAPPER rdf_fdw
HANDLER rdf_fdw_handler
VALIDATOR rdf_fdw_validator;

COMMENT ON FOREIGN DATA WRAPPER rdf_fdw IS 'RDF Triplestore Foreign Data Wrapper';