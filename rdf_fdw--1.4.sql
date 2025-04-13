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
END; $$;

CREATE FUNCTION strstarts(text, text) RETURNS boolean
AS 'MODULE_PATHNAME', 'rdf_fdw_strstarts'
LANGUAGE C IMMUTABLE STRICT;

COMMENT ON FUNCTION strstarts(text,text) IS 'Checks if a given string starts with a certain substring';

CREATE FUNCTION strends(text, text) RETURNS boolean
AS 'MODULE_PATHNAME', 'rdf_fdw_strends'
LANGUAGE C IMMUTABLE STRICT;

COMMENT ON FUNCTION strends(text,text) IS 'Checks if a given string ends with a certain substring';

CREATE FUNCTION strbefore(text, text) RETURNS text
AS 'MODULE_PATHNAME', 'rdf_fdw_strbefore'
LANGUAGE C IMMUTABLE STRICT;

COMMENT ON FUNCTION strbefore(text,text) IS 'Returns a substring containing all characters before the position of a given argument';

CREATE FUNCTION strafter(text, text) RETURNS text
AS 'MODULE_PATHNAME', 'rdf_fdw_strafter'
LANGUAGE C IMMUTABLE STRICT;

COMMENT ON FUNCTION strafter(text,text) IS 'Returns a substring containing all characters after the position of a given argument';

CREATE FUNCTION contains(text, text) RETURNS boolean
AS 'MODULE_PATHNAME', 'rdf_fdw_contains'
LANGUAGE C IMMUTABLE STRICT;

COMMENT ON FUNCTION contains(text,text) IS 'Checks if a string contains a given substring';

CREATE FUNCTION encode_for_uri(text) RETURNS text
AS 'MODULE_PATHNAME', 'rdf_fdw_encode_for_uri'
LANGUAGE C IMMUTABLE STRICT;

COMMENT ON FUNCTION encode_for_uri(text) IS 'Returns a simple literal with the lexical form obtained from the lexical form of its input after translating reserved characters according to the fn:encode-for-uri function';

CREATE FUNCTION strlang(text,text) RETURNS text
AS 'MODULE_PATHNAME', 'rdf_fdw_strlang'
LANGUAGE C IMMUTABLE STRICT;

COMMENT ON FUNCTION strlang(text,text) IS 'Creates an RDF literal with a given language';

CREATE FUNCTION strdt(text,text) RETURNS text
AS 'MODULE_PATHNAME', 'rdf_fdw_strdt'
LANGUAGE C IMMUTABLE STRICT;

COMMENT ON FUNCTION strlang(text,text) IS 'Creates an RDF literal with a given data type';

CREATE FUNCTION str(text) RETURNS text
AS 'MODULE_PATHNAME', 'rdf_fdw_str'
LANGUAGE C IMMUTABLE STRICT;

COMMENT ON FUNCTION strlang(text,text) IS 'Returns the lexical form of a literal or IRI';

CREATE FUNCTION lang(text) RETURNS text
AS 'MODULE_PATHNAME', 'rdf_fdw_lang'
LANGUAGE C IMMUTABLE STRICT;

COMMENT ON FUNCTION lang(text) IS 'Returns the language tag from a literal';

CREATE FUNCTION datatype(text) RETURNS text
AS 'MODULE_PATHNAME', 'rdf_fdw_datatype'
LANGUAGE C IMMUTABLE STRICT;

COMMENT ON FUNCTION lang(text) IS 'Returns the datatype from a literal';

CREATE FUNCTION rdf_fdw_arguments_compatible(text,text) RETURNS boolean
AS 'MODULE_PATHNAME', 'rdf_fdw_arguments_compatible'
LANGUAGE C IMMUTABLE STRICT;

CREATE FUNCTION iri(text) RETURNS text
AS 'MODULE_PATHNAME', 'rdf_fdw_iri'
LANGUAGE C IMMUTABLE STRICT;

CREATE FUNCTION uri(text) RETURNS text
AS 'MODULE_PATHNAME', 'rdf_fdw_iri'
LANGUAGE C IMMUTABLE STRICT;

CREATE FUNCTION isIRI(text) RETURNS boolean
AS 'MODULE_PATHNAME', 'rdf_fdw_isIRI'
LANGUAGE C IMMUTABLE STRICT;

CREATE FUNCTION isURI(text) RETURNS boolean
AS 'MODULE_PATHNAME', 'rdf_fdw_isIRI'
LANGUAGE C IMMUTABLE STRICT;

CREATE FUNCTION langmatches(text,text) RETURNS boolean
AS 'MODULE_PATHNAME', 'rdf_fdw_langmatches'
LANGUAGE C IMMUTABLE STRICT;

CREATE FUNCTION isblank(text) RETURNS boolean
AS 'MODULE_PATHNAME', 'rdf_fdw_isBlank'
LANGUAGE C IMMUTABLE STRICT;

CREATE FUNCTION isnumeric(text) RETURNS boolean
AS 'MODULE_PATHNAME', 'rdf_fdw_isNumeric'
LANGUAGE C IMMUTABLE STRICT;

CREATE FUNCTION isliteral(text) RETURNS boolean
AS 'MODULE_PATHNAME', 'rdf_fdw_isLiteral'
LANGUAGE C IMMUTABLE STRICT;

CREATE FUNCTION bnode(text) RETURNS text
AS 'MODULE_PATHNAME', 'rdf_fdw_bnode'
LANGUAGE C IMMUTABLE;

CREATE FUNCTION bnode() RETURNS text
AS 'MODULE_PATHNAME', 'rdf_fdw_bnode'
LANGUAGE C IMMUTABLE;

CREATE FUNCTION uuid() RETURNS text
AS 'MODULE_PATHNAME', 'rdf_fdw_uuid'
LANGUAGE C IMMUTABLE;

CREATE FUNCTION struuid() RETURNS text
AS 'MODULE_PATHNAME', 'rdf_fdw_uuid'
LANGUAGE C IMMUTABLE;