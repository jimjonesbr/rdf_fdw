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

CREATE TYPE rdf_fdw_triple AS (
  subject text,
  predicate text,
  object text
);

CREATE FUNCTION rdf_fdw_describe(server text, query text, raw_literal boolean DEFAULT true, base_uri text DEFAULT '')
RETURNS SETOF rdf_fdw_triple AS 'MODULE_PATHNAME', 'rdf_fdw_describe'
LANGUAGE C IMMUTABLE STRICT PARALLEL SAFE;

COMMENT ON FUNCTION rdf_fdw_describe(text,text,boolean,text) IS 'Gateway for DESCRIBE SPARQL queries';

CREATE FOREIGN DATA WRAPPER rdf_fdw
HANDLER rdf_fdw_handler
VALIDATOR rdf_fdw_validator;

COMMENT ON FOREIGN DATA WRAPPER rdf_fdw IS 'RDF Triplestore Foreign Data Wrapper';

DO LANGUAGE plpgsql $$
BEGIN
    CREATE PROCEDURE rdf_fdw_clone_table(
        foreign_table text DEFAULT '',
        target_table text DEFAULT '',
        begin_offset int DEFAULT 0,
        fetch_size int DEFAULT 0,
        max_records int DEFAULT 0,
        orderby_column text DEFAULT '',
        sort_order text DEFAULT 'ASC',
        create_table boolean DEFAULT false,
        verbose boolean DEFAULT false,
        commit_page boolean DEFAULT true)
    AS 'MODULE_PATHNAME', 'rdf_fdw_clone_table'
    LANGUAGE C;

    COMMENT ON PROCEDURE rdf_fdw_clone_table(text,text,int,int,int,text,text,boolean,boolean,boolean)
        IS 'materialize rdf_fdw foreign tables into heap tables';
    EXCEPTION WHEN OTHERS THEN
        RAISE NOTICE 'The PROCEDURE rdf_fdw_clone_table cannot be created.';
END; $$