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

COMMENT ON FUNCTION strstarts(text, text) IS 'Checks if the first text starts with the second text.';

CREATE FUNCTION strends(text, text) RETURNS boolean
AS 'MODULE_PATHNAME', 'rdf_fdw_strends'
LANGUAGE C IMMUTABLE STRICT;

COMMENT ON FUNCTION strends(text, text) IS 'Checks if the first text ends with the second text.';

CREATE FUNCTION strbefore(text, text) RETURNS text
AS 'MODULE_PATHNAME', 'rdf_fdw_strbefore'
LANGUAGE C IMMUTABLE STRICT;

COMMENT ON FUNCTION strbefore(text, text) IS 'Returns the substring of the first text before the second text.';

CREATE FUNCTION strafter(text, text) RETURNS text
AS 'MODULE_PATHNAME', 'rdf_fdw_strafter'
LANGUAGE C IMMUTABLE STRICT;

COMMENT ON FUNCTION strafter(text, text) IS 'Returns the substring of the first text after the second text.';

CREATE FUNCTION contains(text, text) RETURNS boolean
AS 'MODULE_PATHNAME', 'rdf_fdw_contains'
LANGUAGE C IMMUTABLE STRICT;

COMMENT ON FUNCTION contains(text, text) IS 'Checks if the first text contains the second text.';

CREATE FUNCTION encode_for_uri(text) RETURNS text
AS 'MODULE_PATHNAME', 'rdf_fdw_encode_for_uri'
LANGUAGE C IMMUTABLE STRICT;

COMMENT ON FUNCTION encode_for_uri(text) IS 'Encodes the input text for use in a URI.';

CREATE FUNCTION strlang(text,text) RETURNS text
AS 'MODULE_PATHNAME', 'rdf_fdw_strlang'
LANGUAGE C IMMUTABLE STRICT;

COMMENT ON FUNCTION strlang(text, text) IS 'Combines text with a language tag.';

CREATE FUNCTION strdt(text,text) RETURNS text
AS 'MODULE_PATHNAME', 'rdf_fdw_strdt'
LANGUAGE C IMMUTABLE STRICT;

COMMENT ON FUNCTION strdt(text, text) IS 'Combines text with a datatype URI.';

CREATE FUNCTION str(text) RETURNS text
AS 'MODULE_PATHNAME', 'rdf_fdw_str'
LANGUAGE C IMMUTABLE STRICT;

COMMENT ON FUNCTION str(text) IS 'Converts the input to a simple literal string.';

CREATE FUNCTION lang(text) RETURNS text
AS 'MODULE_PATHNAME', 'rdf_fdw_lang'
LANGUAGE C IMMUTABLE STRICT;

COMMENT ON FUNCTION lang(text) IS 'Extracts the language tag from the input literal.';

CREATE FUNCTION datatype(text) RETURNS text
AS 'MODULE_PATHNAME', 'rdf_fdw_datatype'
LANGUAGE C IMMUTABLE STRICT;

COMMENT ON FUNCTION datatype(text) IS 'Extracts the datatype URI from the input literal.';

CREATE FUNCTION rdf_fdw_arguments_compatible(text,text) RETURNS boolean
AS 'MODULE_PATHNAME', 'rdf_fdw_arguments_compatible'
LANGUAGE C IMMUTABLE STRICT;

COMMENT ON FUNCTION rdf_fdw_arguments_compatible(text, text) IS 'Checks if two arguments are compatible for RDF processing.';

CREATE FUNCTION iri(text) RETURNS text
AS 'MODULE_PATHNAME', 'rdf_fdw_iri'
LANGUAGE C IMMUTABLE STRICT;

COMMENT ON FUNCTION iri(text) IS 'Converts the input text to an IRI.';

CREATE FUNCTION uri(text) RETURNS text
AS 'MODULE_PATHNAME', 'rdf_fdw_iri'
LANGUAGE C IMMUTABLE STRICT;

COMMENT ON FUNCTION uri(text) IS 'Converts the input text to a URI (alias for iri).';

CREATE FUNCTION isIRI(text) RETURNS boolean
AS 'MODULE_PATHNAME', 'rdf_fdw_isIRI'
LANGUAGE C IMMUTABLE STRICT;

COMMENT ON FUNCTION isIRI(text) IS 'Checks if the input text is a valid IRI.';

CREATE FUNCTION isURI(text) RETURNS boolean
AS 'MODULE_PATHNAME', 'rdf_fdw_isIRI'
LANGUAGE C IMMUTABLE STRICT;

COMMENT ON FUNCTION isURI(text) IS 'Checks if the input text is a valid URI (alias for isIRI).';

CREATE FUNCTION langmatches(text,text) RETURNS boolean
AS 'MODULE_PATHNAME', 'rdf_fdw_langmatches'
LANGUAGE C IMMUTABLE STRICT;

COMMENT ON FUNCTION langmatches(text, text) IS 'Checks if the language tag matches the given pattern.';

CREATE FUNCTION isblank(text) RETURNS boolean
AS 'MODULE_PATHNAME', 'rdf_fdw_isBlank'
LANGUAGE C IMMUTABLE STRICT;

COMMENT ON FUNCTION isblank(text) IS 'Checks if the input text is a blank node.';

CREATE FUNCTION isnumeric(text) RETURNS boolean
AS 'MODULE_PATHNAME', 'rdf_fdw_isNumeric'
LANGUAGE C IMMUTABLE STRICT;

COMMENT ON FUNCTION isnumeric(text) IS 'Checks if the input text is numeric.';

CREATE FUNCTION isliteral(text) RETURNS boolean
AS 'MODULE_PATHNAME', 'rdf_fdw_isLiteral'
LANGUAGE C IMMUTABLE STRICT;

COMMENT ON FUNCTION isliteral(text) IS 'Checks if the input text is a literal.';

CREATE FUNCTION bnode(text) RETURNS text
AS 'MODULE_PATHNAME', 'rdf_fdw_bnode'
LANGUAGE C IMMUTABLE;

COMMENT ON FUNCTION bnode(text) IS 'Creates a blank node from the input text.';

CREATE FUNCTION bnode() RETURNS text
AS 'MODULE_PATHNAME', 'rdf_fdw_bnode'
LANGUAGE C IMMUTABLE;

COMMENT ON FUNCTION bnode() IS 'Generates a new blank node identifier.';

CREATE FUNCTION uuid() RETURNS text
AS 'MODULE_PATHNAME', 'rdf_fdw_uuid'
LANGUAGE C IMMUTABLE;

COMMENT ON FUNCTION uuid() IS 'Generates a UUID string.';

CREATE FUNCTION struuid() RETURNS text
AS 'MODULE_PATHNAME', 'rdf_fdw_uuid'
LANGUAGE C IMMUTABLE;

COMMENT ON FUNCTION struuid() IS 'Generates a UUID string.';

CREATE FUNCTION lcase(text) RETURNS text
AS 'MODULE_PATHNAME', 'rdf_fdw_lcase'
LANGUAGE C IMMUTABLE STRICT;

COMMENT ON FUNCTION lcase(text) IS 'Converts the input literal to lowercase.';

CREATE FUNCTION ucase(text) RETURNS text
AS 'MODULE_PATHNAME', 'rdf_fdw_ucase'
LANGUAGE C IMMUTABLE STRICT;
COMMENT ON FUNCTION ucase(text) IS 'Converts the input literal to uppercase.';

CREATE FUNCTION strlen(text)
RETURNS int AS $$
BEGIN
  RETURN length(lex($1));
END;
$$ LANGUAGE plpgsql IMMUTABLE STRICT;
COMMENT ON FUNCTION strlen(text) IS 'Returns the length of the literal text.';

CREATE FUNCTION substr_rdf(text, int, int)
RETURNS text
AS 'MODULE_PATHNAME', 'rdf_fdw_substr'
LANGUAGE C IMMUTABLE;

COMMENT ON FUNCTION substr_rdf(text, int, int) IS 'Extracts a substring from the input literal with start and length.';

CREATE FUNCTION substr_rdf(text, int)
RETURNS text
AS 'MODULE_PATHNAME', 'rdf_fdw_substr'
LANGUAGE C IMMUTABLE;

COMMENT ON FUNCTION substr_rdf(text, int) IS 'Extracts a substring from the input literal starting at the given position.';

CREATE FUNCTION concat_rdf(text, text)
RETURNS text
AS 'MODULE_PATHNAME', 'rdf_fdw_concat'
LANGUAGE C IMMUTABLE STRICT;

COMMENT ON FUNCTION concat_rdf(text, text) IS 'Concatenates two literals inputs for RDF processing.';

CREATE FUNCTION lex(text)
RETURNS text
AS 'MODULE_PATHNAME', 'rdf_fdw_lex'
LANGUAGE C IMMUTABLE STRICT;

COMMENT ON FUNCTION lex(text) IS 'Extracts the lexical value of an RDF literal';

CREATE FUNCTION replace_rdf(text, text, text)
RETURNS text AS $$
BEGIN
  IF lex($2) = '' THEN
    RAISE EXCEPTION 'pattern cannot be empty in REPLACE';
  END IF;
  RETURN str(replace(lex($1), lex($2), lex($3)));
END;
$$ LANGUAGE plpgsql IMMUTABLE STRICT;

CREATE FUNCTION replace_rdf(text, text, text, text)
RETURNS text
AS $$
BEGIN
  IF lex($2) = '' THEN
     RAISE EXCEPTION 'pattern cannot be empty in REPLACE';
  END IF;
  RETURN str(regexp_replace(lex($1), lex($2), lex($3), lex($4) || 'g'));
END;
$$ LANGUAGE plpgsql IMMUTABLE STRICT;

CREATE FUNCTION regex(text, text)
RETURNS boolean AS $$
BEGIN
  IF lex($2) = '' THEN
    RETURN FALSE; -- SPARQL: empty pattern matches nothing
  END IF;
  RETURN lex($1) ~ lex($2);
END;
$$ LANGUAGE plpgsql IMMUTABLE STRICT;


CREATE FUNCTION regex(text, text, text)
RETURNS boolean AS $$
BEGIN
  IF lex($2) = '' THEN
    RETURN FALSE;
  END IF;
  -- Restrict flags to 'i'
  IF lex($3) != 'i' THEN
    RAISE EXCEPTION 'Unsupported regex flags: % (only "i" is supported)', lex($3);
  END IF;
  RETURN lex($1) ~* lex($2);
EXCEPTION
  WHEN invalid_regular_expression THEN
    RAISE EXCEPTION 'Invalid regex pattern: %', lex($2);
END;
$$ LANGUAGE plpgsql IMMUTABLE STRICT;

