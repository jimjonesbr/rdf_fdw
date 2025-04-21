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

/* Custom rdf_fdw Data Types */
CREATE FUNCTION rdf_fdw_iri_in(cstring) RETURNS rdfiri
AS 'MODULE_PATHNAME', 'rdf_fdw_iri_in'
LANGUAGE C IMMUTABLE STRICT;

CREATE FUNCTION rdf_fdw_iri_out(rdfiri) RETURNS cstring
AS 'MODULE_PATHNAME', 'rdf_fdw_iri_out'
LANGUAGE C IMMUTABLE STRICT;

CREATE TYPE rdfiri (
    INPUT = rdf_fdw_iri_in,
    OUTPUT = rdf_fdw_iri_out,
    STORAGE = extended
);

CREATE CAST (text AS rdfiri)
WITH INOUT AS IMPLICIT;

CREATE FUNCTION rdf_fdw_rdfiri_eq(rdfiri, rdfiri) RETURNS boolean
AS 'MODULE_PATHNAME', 'rdf_fdw_rdfiri_eq'
LANGUAGE C IMMUTABLE STRICT;

CREATE FUNCTION rdf_fdw_rdfiri_text_eq(rdfiri, text) RETURNS boolean
AS 'MODULE_PATHNAME', 'rdf_fdw_rdfiri_text_eq'
LANGUAGE C IMMUTABLE STRICT;

CREATE FUNCTION rdf_fdw_rdfiri_text_eq(text, rdfiri) RETURNS boolean
AS 'MODULE_PATHNAME', 'rdf_fdw_rdfiri_text_eq'
LANGUAGE C IMMUTABLE STRICT;

CREATE OPERATOR = (
    PROCEDURE = rdf_fdw_rdfiri_eq,
    LEFTARG = rdfiri,
    RIGHTARG = rdfiri,
    COMMUTATOR = =,
    NEGATOR = <>
);

CREATE OPERATOR = (
    PROCEDURE = rdf_fdw_rdfiri_text_eq,
    LEFTARG = rdfiri,
    RIGHTARG = text,
    COMMUTATOR = =,
    NEGATOR = <>
);

CREATE OPERATOR = (
    PROCEDURE = rdf_fdw_rdfiri_text_eq,
    LEFTARG = text,
    RIGHTARG = rdfiri,
    COMMUTATOR = =,
    NEGATOR = <>
);

CREATE SCHEMA sparql;

CREATE FUNCTION sparql.lex(text)
RETURNS text
AS 'MODULE_PATHNAME', 'rdf_fdw_lex'
LANGUAGE C IMMUTABLE STRICT;
COMMENT ON FUNCTION sparql.lex(text) IS 'Extracts the lexical value of an RDF literal';

CREATE FUNCTION sparql.rdf_fdw_arguments_compatible(text,text) RETURNS boolean
AS 'MODULE_PATHNAME', 'rdf_fdw_arguments_compatible'
LANGUAGE C IMMUTABLE STRICT;
COMMENT ON FUNCTION sparql.rdf_fdw_arguments_compatible(text, text) IS 'Checks if two arguments are compatible for RDF processing.';

CREATE FUNCTION sparql.uri(text) RETURNS text
AS 'MODULE_PATHNAME', 'rdf_fdw_iri'
LANGUAGE C IMMUTABLE STRICT;
COMMENT ON FUNCTION sparql.uri(text) IS 'Converts the input text to a URI (alias for iri).';

/* SPARQL 17.4.2 Functions on RDF Terms */
CREATE FUNCTION sparql.isIRI(text) RETURNS boolean
AS 'MODULE_PATHNAME', 'rdf_fdw_isIRI'
LANGUAGE C IMMUTABLE STRICT;
COMMENT ON FUNCTION sparql.isIRI(text) IS 'Checks if the input text is a valid IRI.';

CREATE FUNCTION sparql.isURI(text) RETURNS boolean
AS 'MODULE_PATHNAME', 'rdf_fdw_isIRI'
LANGUAGE C IMMUTABLE STRICT;
COMMENT ON FUNCTION sparql.isURI(text) IS 'Checks if the input text is a valid URI (alias for isIRI).';

CREATE FUNCTION sparql.isblank(text) RETURNS boolean
AS 'MODULE_PATHNAME', 'rdf_fdw_isBlank'
LANGUAGE C IMMUTABLE STRICT;
COMMENT ON FUNCTION sparql.isblank(text) IS 'Checks if the input text is a blank node.';

CREATE FUNCTION sparql.isliteral(text) RETURNS boolean
AS 'MODULE_PATHNAME', 'rdf_fdw_isLiteral'
LANGUAGE C IMMUTABLE STRICT;
COMMENT ON FUNCTION sparql.isliteral(text) IS 'Checks if the input text is a literal.';

CREATE FUNCTION sparql.isnumeric(text) RETURNS boolean
AS 'MODULE_PATHNAME', 'rdf_fdw_isNumeric'
LANGUAGE C IMMUTABLE STRICT;
COMMENT ON FUNCTION sparql.isnumeric(text) IS 'Checks if the input text is numeric.';

CREATE FUNCTION sparql.str(text) RETURNS text
AS 'MODULE_PATHNAME', 'rdf_fdw_str'
LANGUAGE C IMMUTABLE STRICT;
COMMENT ON FUNCTION sparql.str(text) IS 'Converts the input to a simple literal string.';

CREATE FUNCTION sparql.lang(text) RETURNS text
AS 'MODULE_PATHNAME', 'rdf_fdw_lang'
LANGUAGE C IMMUTABLE STRICT;
COMMENT ON FUNCTION sparql.lang(text) IS 'Extracts the language tag from the input literal.';

CREATE FUNCTION sparql.datatype(text)
RETURNS text
AS 'MODULE_PATHNAME', 'rdf_fdw_datatype_text'
LANGUAGE C IMMUTABLE STRICT;

CREATE FUNCTION sparql.datatype(anyelement)
RETURNS text
AS 'MODULE_PATHNAME', 'rdf_fdw_datatype_poly'
LANGUAGE C IMMUTABLE STRICT;
COMMENT ON FUNCTION sparql.datatype(text) IS 'Extracts the datatype URI from the input literal.';
COMMENT ON FUNCTION sparql.datatype(anyelement) IS 'Extracts the datatype URI from the input literal.';

CREATE FUNCTION sparql.iri(text) RETURNS text
AS 'MODULE_PATHNAME', 'rdf_fdw_iri'
LANGUAGE C IMMUTABLE STRICT;
COMMENT ON FUNCTION sparql.iri(text) IS 'Converts the input text to an IRI.';

CREATE FUNCTION sparql.bnode(text) RETURNS text
AS 'MODULE_PATHNAME', 'rdf_fdw_bnode'
LANGUAGE C IMMUTABLE;
COMMENT ON FUNCTION sparql.bnode(text) IS 'Creates a blank node from the input text.';

CREATE FUNCTION sparql.bnode() RETURNS text
AS 'MODULE_PATHNAME', 'rdf_fdw_bnode'
LANGUAGE C IMMUTABLE;
COMMENT ON FUNCTION sparql.bnode() IS 'Generates a new blank node identifier.';

CREATE FUNCTION sparql.strdt(text,text) RETURNS text
AS 'MODULE_PATHNAME', 'rdf_fdw_strdt'
LANGUAGE C IMMUTABLE STRICT;
COMMENT ON FUNCTION sparql.strdt(text, text) IS 'Combines text with a datatype URI.';

CREATE FUNCTION sparql.strlang(text,text) RETURNS text
AS 'MODULE_PATHNAME', 'rdf_fdw_strlang'
LANGUAGE C IMMUTABLE STRICT;
COMMENT ON FUNCTION sparql.strlang(text, text) IS 'Combines text with a language tag.';

CREATE FUNCTION sparql.uuid() RETURNS text
AS 'MODULE_PATHNAME', 'rdf_fdw_uuid'
LANGUAGE C IMMUTABLE;
COMMENT ON FUNCTION sparql.uuid() IS 'Generates a UUID string.';

CREATE FUNCTION sparql.struuid() RETURNS text
AS 'MODULE_PATHNAME', 'rdf_fdw_uuid'
LANGUAGE C IMMUTABLE;
COMMENT ON FUNCTION sparql.struuid() IS 'Generates a UUID string.';

/* SPARQL 17.4.3  Functions on Strings */
CREATE FUNCTION sparql.strlen(text) RETURNS int AS $$
BEGIN
  RETURN length(lex($1));
END;
$$ LANGUAGE plpgsql IMMUTABLE STRICT;
COMMENT ON FUNCTION sparql.strlen(text) IS 'Returns the length of the literal text.';

CREATE FUNCTION sparql.substr(text, int, int)
RETURNS text
AS 'MODULE_PATHNAME', 'rdf_fdw_substr'
LANGUAGE C IMMUTABLE;
COMMENT ON FUNCTION sparql.substr(text, int, int) IS 'Extracts a substring from the input literal with start and length.';

CREATE FUNCTION sparql.substr(text, int)
RETURNS text
AS 'MODULE_PATHNAME', 'rdf_fdw_substr'
LANGUAGE C IMMUTABLE;
COMMENT ON FUNCTION sparql.substr(text, int) IS 'Extracts a substring from the input literal starting at the given position.';

CREATE FUNCTION sparql.ucase(text) RETURNS text
AS 'MODULE_PATHNAME', 'rdf_fdw_ucase'
LANGUAGE C IMMUTABLE STRICT;
COMMENT ON FUNCTION sparql.ucase(text) IS 'Converts the input literal to uppercase.';

CREATE FUNCTION sparql.lcase(text) RETURNS text
AS 'MODULE_PATHNAME', 'rdf_fdw_lcase'
LANGUAGE C IMMUTABLE STRICT;
COMMENT ON FUNCTION sparql.lcase(text) IS 'Converts the input literal to lowercase.';

CREATE FUNCTION sparql.strstarts(text, text) RETURNS boolean
AS 'MODULE_PATHNAME', 'rdf_fdw_strstarts'
LANGUAGE C IMMUTABLE STRICT;
COMMENT ON FUNCTION sparql.strstarts(text, text) IS 'Checks if the first text starts with the second text.';

CREATE FUNCTION sparql.strends(text, text) RETURNS boolean
AS 'MODULE_PATHNAME', 'rdf_fdw_strends'
LANGUAGE C IMMUTABLE STRICT;
COMMENT ON FUNCTION sparql.strends(text, text) IS 'Checks if the first text ends with the second text.';

CREATE FUNCTION sparql.contains(text, text) RETURNS boolean
AS 'MODULE_PATHNAME', 'rdf_fdw_contains'
LANGUAGE C IMMUTABLE STRICT;
COMMENT ON FUNCTION sparql.contains(text, text) IS 'Checks if the first text contains the second text.';

CREATE FUNCTION sparql.strbefore(text, text) RETURNS text
AS 'MODULE_PATHNAME', 'rdf_fdw_strbefore'
LANGUAGE C IMMUTABLE STRICT;
COMMENT ON FUNCTION sparql.strbefore(text, text) IS 'Returns the substring of the first text before the second text.';

CREATE FUNCTION sparql.strafter(text, text) RETURNS text
AS 'MODULE_PATHNAME', 'rdf_fdw_strafter'
LANGUAGE C IMMUTABLE STRICT;
COMMENT ON FUNCTION sparql.strafter(text, text) IS 'Returns the substring of the first text after the second text.';

CREATE FUNCTION sparql.encode_for_uri(text) RETURNS text
AS 'MODULE_PATHNAME', 'rdf_fdw_encode_for_uri'
LANGUAGE C IMMUTABLE STRICT;
COMMENT ON FUNCTION sparql.encode_for_uri(text) IS 'Encodes the input text for use in a URI.';

CREATE FUNCTION sparql.concat(text, text)
RETURNS text
AS 'MODULE_PATHNAME', 'rdf_fdw_concat'
LANGUAGE C IMMUTABLE STRICT;
COMMENT ON FUNCTION sparql.concat(text, text) IS 'Concatenates two literals inputs for RDF processing.';

CREATE FUNCTION sparql.langmatches(text,text) RETURNS boolean
AS 'MODULE_PATHNAME', 'rdf_fdw_langmatches'
LANGUAGE C IMMUTABLE STRICT;
COMMENT ON FUNCTION sparql.langmatches(text, text) IS 'Checks if the language tag matches the given pattern.';

CREATE FUNCTION sparql.regex(text, text)
RETURNS boolean AS $$
BEGIN
  IF sparql.lex($2) = '' THEN
    RETURN FALSE; -- SPARQL: empty pattern matches nothing
  END IF;
  RETURN sparql.lex($1) ~ sparql.lex($2);
END;
$$ LANGUAGE plpgsql IMMUTABLE STRICT;


CREATE FUNCTION sparql.regex(text, text, text)
RETURNS boolean AS $$
BEGIN
  IF sparql.lex($2) = '' THEN
    RETURN FALSE;
  END IF;
  -- Restrict flags to 'i'
  IF sparql.lex($3) != 'i' THEN
    RAISE EXCEPTION 'Unsupported regex flags: % (only "i" is supported)', sparql.lex($3);
  END IF;
  RETURN sparql.lex($1) ~* sparql.lex($2);
EXCEPTION
  WHEN invalid_regular_expression THEN
    RAISE EXCEPTION 'Invalid regex pattern: %', sparql.lex($2);
END;
$$ LANGUAGE plpgsql IMMUTABLE STRICT;

CREATE FUNCTION sparql.replace(text, text, text)
RETURNS text AS $$
BEGIN
  IF sparql.lex($2) = '' THEN
    RAISE EXCEPTION 'pattern cannot be empty in REPLACE';
  END IF;
  RETURN sparql.str(pg_catalog.replace(sparql.lex($1), sparql.lex($2), sparql.lex($3)));
END;
$$ LANGUAGE plpgsql IMMUTABLE STRICT;

CREATE FUNCTION sparql.replace(text, text, text, text)
RETURNS text
AS $$
BEGIN
  IF sparql.lex($2) = '' THEN
     RAISE EXCEPTION 'pattern cannot be empty in REPLACE';
  END IF;
  RETURN sparql.str(pg_catalog.regexp_replace(sparql.lex($1), sparql.lex($2), sparql.lex($3), sparql.lex($4) || 'g'));
END;
$$ LANGUAGE plpgsql IMMUTABLE STRICT;

/* SPARQL 17.4.4 Functions on Numerics */
CREATE FUNCTION sparql.abs(text) RETURNS double precision  AS $$
BEGIN
  RETURN pg_catalog.abs(sparql.lex($1)::double precision);
END;
$$ LANGUAGE plpgsql IMMUTABLE STRICT;

CREATE FUNCTION sparql.abs(smallint) RETURNS double precision  AS $$
BEGIN
  RETURN pg_catalog.abs($1);
END;
$$ LANGUAGE plpgsql IMMUTABLE STRICT;

CREATE FUNCTION sparql.abs(int) RETURNS double precision  AS $$
BEGIN
  RETURN pg_catalog.abs($1);
END;
$$ LANGUAGE plpgsql IMMUTABLE STRICT;

CREATE FUNCTION sparql.abs(bigint) RETURNS double precision  AS $$
BEGIN
  RETURN pg_catalog.abs($1);
END;
$$ LANGUAGE plpgsql IMMUTABLE STRICT;

CREATE FUNCTION sparql.abs(double precision) RETURNS double precision  AS $$
BEGIN
  RETURN pg_catalog.abs($1);
END;
$$ LANGUAGE plpgsql IMMUTABLE STRICT;

CREATE FUNCTION sparql.abs(numeric) RETURNS double precision  AS $$
BEGIN
  RETURN pg_catalog.abs($1);
END;
$$ LANGUAGE plpgsql IMMUTABLE STRICT;

CREATE FUNCTION sparql.abs(real) RETURNS double precision  AS $$
BEGIN
  RETURN pg_catalog.abs($1);
END;
$$ LANGUAGE plpgsql IMMUTABLE STRICT;

CREATE FUNCTION sparql.round(text) RETURNS numeric AS $$
BEGIN
  IF sparql.lex($1)::numeric > 0 THEN
    RETURN pg_catalog.floor(sparql.lex($1)::numeric + 0.5);
  ELSE
    RETURN pg_catalog.ceil(sparql.lex($1)::numeric + 0.5);
  END IF;
END;
$$ LANGUAGE plpgsql IMMUTABLE STRICT;

CREATE FUNCTION sparql.round(numeric) RETURNS numeric AS $$
BEGIN
  IF $1 > 0 THEN
    RETURN pg_catalog.floor($1 + 0.5);
  ELSE
    RETURN pg_catalog.ceil($1 + 0.5);
  END IF;
END;
$$ LANGUAGE plpgsql IMMUTABLE STRICT;

CREATE FUNCTION sparql.round(double precision) RETURNS double precision AS $$
BEGIN
  IF $1 > 0 THEN
    RETURN pg_catalog.floor($1 + 0.5);
  ELSE
    RETURN pg_catalog.ceil($1 + 0.5);
  END IF;
END;
$$ LANGUAGE plpgsql IMMUTABLE STRICT;

CREATE FUNCTION sparql.ceil(text) 
RETURNS numeric AS $$
BEGIN
  RETURN pg_catalog.ceil(sparql.lex($1)::numeric);
END;
$$ LANGUAGE plpgsql IMMUTABLE STRICT;

CREATE FUNCTION sparql.ceil(numeric) 
RETURNS numeric AS $$
BEGIN
  RETURN pg_catalog.ceil($1);
END;
$$ LANGUAGE plpgsql IMMUTABLE STRICT;

CREATE FUNCTION sparql.ceil(double precision) 
RETURNS double precision AS $$
BEGIN
  RETURN pg_catalog.ceil($1);
END;
$$ LANGUAGE plpgsql IMMUTABLE STRICT;

CREATE FUNCTION sparql.floor(text) 
RETURNS numeric AS $$
BEGIN
  RETURN pg_catalog.floor(sparql.lex($1)::numeric);
END;
$$ LANGUAGE plpgsql IMMUTABLE STRICT;

CREATE FUNCTION sparql.floor(numeric) 
RETURNS numeric AS $$
BEGIN
  RETURN pg_catalog.floor($1);
END;
$$ LANGUAGE plpgsql IMMUTABLE STRICT;

CREATE FUNCTION sparql.floor(double precision) 
RETURNS double precision AS $$
BEGIN
  RETURN pg_catalog.floor($1);
END;
$$ LANGUAGE plpgsql IMMUTABLE STRICT;

CREATE FUNCTION sparql.rand() RETURNS text AS $$
BEGIN
  RETURN sparql.strdt(random()::text,'xsd:double');
END;
$$ LANGUAGE plpgsql PARALLEL RESTRICTED STRICT;

/* SPARQL 17.4.5 Functions on Dates and Times */
CREATE FUNCTION sparql.now() RETURNS text AS $$
BEGIN
  RETURN sparql.strdt(pg_catalog.now()::text, 'xsd:dateTime');
END;
$$ LANGUAGE plpgsql STABLE PARALLEL SAFE STRICT;

CREATE FUNCTION sparql.year(text)
RETURNS int AS $$
BEGIN
  RETURN EXTRACT(year FROM sparql.lex($1)::date);
END;
$$ LANGUAGE plpgsql STABLE PARALLEL SAFE STRICT;

CREATE FUNCTION sparql.year(timestamp)
RETURNS int AS $$
BEGIN
  RETURN EXTRACT(year FROM $1);
END;
$$ LANGUAGE plpgsql STABLE PARALLEL SAFE STRICT;

CREATE FUNCTION sparql.month(text)
RETURNS int AS $$
BEGIN
  RETURN EXTRACT(month FROM sparql.lex($1)::date);
END;
$$ LANGUAGE plpgsql STABLE PARALLEL SAFE STRICT;

CREATE FUNCTION sparql.month(timestamp)
RETURNS int AS $$
BEGIN
  RETURN EXTRACT(month FROM $1);
END;
$$ LANGUAGE plpgsql STABLE PARALLEL SAFE STRICT;

CREATE FUNCTION sparql.day(text)
RETURNS int AS $$
BEGIN
  RETURN EXTRACT(day FROM sparql.lex($1)::date);
END;
$$ LANGUAGE plpgsql STABLE PARALLEL SAFE STRICT;

CREATE FUNCTION sparql.day(timestamp)
RETURNS int AS $$
BEGIN
  RETURN EXTRACT(day FROM $1);
END;
$$ LANGUAGE plpgsql STABLE PARALLEL SAFE STRICT;

CREATE FUNCTION sparql.hours(text)
RETURNS int AS $$
BEGIN
  RETURN EXTRACT(hour FROM sparql.lex($1)::timestamp);
END;
$$ LANGUAGE plpgsql STABLE PARALLEL SAFE STRICT;

CREATE FUNCTION sparql.hours(timestamp)
RETURNS int AS $$
BEGIN
  RETURN EXTRACT(hour FROM $1);
END;
$$ LANGUAGE plpgsql STABLE PARALLEL SAFE STRICT;

CREATE FUNCTION sparql.minutes(text)
RETURNS int AS $$
BEGIN
  RETURN EXTRACT(minute FROM sparql.lex($1)::timestamp);
END;
$$ LANGUAGE plpgsql STABLE PARALLEL SAFE STRICT;

CREATE FUNCTION sparql.minutes(timestamp)
RETURNS int AS $$
BEGIN
  RETURN EXTRACT(minute FROM $1);
END;
$$ LANGUAGE plpgsql STABLE PARALLEL SAFE STRICT;

CREATE FUNCTION sparql.seconds(text)
RETURNS numeric AS $$
BEGIN
  RETURN EXTRACT(second FROM sparql.lex($1)::timestamp);
END;
$$ LANGUAGE plpgsql STABLE PARALLEL SAFE STRICT;

CREATE FUNCTION sparql.seconds(timestamp)
RETURNS numeric AS $$
BEGIN
  RETURN EXTRACT(second FROM $1);
END;
$$ LANGUAGE plpgsql STABLE PARALLEL SAFE STRICT;

CREATE OR REPLACE FUNCTION sparql.timezone(lit text)
RETURNS text AS $$
DECLARE
  lexical text := sparql.lex(lit);
  tz_offset text;
  hours int;
  minutes int;
  sign text;
BEGIN
  -- Validate input
  IF sparql.datatype($1) <> '<http://www.w3.org/2001/XMLSchema#dateTime>' THEN
    RETURN NULL;
  END IF;

  IF lexical IS NULL OR lexical = '' THEN
    RAISE EXCEPTION 'SPARQL TIMEZONE(): invalid xsd:dateTime literal';
  END IF;

  -- Basic xsd:dateTime format validation
  IF NOT lexical ~ '^[0-9]{4}-(0[1-9]|1[0-2])-(0[1-9]|[12][0-9]|3[01])T([01][0-9]|2[0-3]):[0-5][0-9]:[0-5][0-9](\.\d+)?([+-]\d{2}:\d{2}|Z)?$' THEN
    RAISE EXCEPTION 'SPARQL TIMEZONE(): invalid xsd:dateTime format: %', lexical;
  END IF;

  -- Extract timezone
  tz_offset := substring(lexical from '([-+]\d{2}:\d{2}|Z)$');

  IF tz_offset IS NULL THEN
    RAISE EXCEPTION 'SPARQL TIMEZONE(): datetime has no timezone: %', lexical;
  END IF;

  IF tz_offset = 'Z' THEN
    RETURN sparql.strdt('PT0S', 'xsd:dayTimeDuration');
  END IF;

  -- Parse timezone
  sign := CASE WHEN tz_offset LIKE '-%' THEN '-' ELSE '' END;
  hours := abs(split_part(tz_offset, ':', 1)::int);
  minutes := split_part(tz_offset, ':', 2)::int;

  -- Validate timezone offset
  IF hours > 14 OR (hours = 14 AND minutes > 0) OR minutes >= 60 THEN
    RAISE EXCEPTION 'SPARQL TIMEZONE(): invalid timezone offset: %', tz_offset;
  END IF;

  -- Format xsd:dayTimeDuration
  IF hours = 0 AND minutes = 0 THEN
    RETURN sparql.strdt('PT0S', 'xsd:dayTimeDuration');
  ELSE
    RETURN sparql.strdt(
      sign || 'PT' || hours || 'H' || (CASE WHEN minutes > 0 THEN minutes || 'M' ELSE '' END),
      'xsd:dayTimeDuration'
    );
  END IF;
END;
$$ LANGUAGE plpgsql STRICT IMMUTABLE;

CREATE OR REPLACE FUNCTION sparql.tz(lit text)
RETURNS text AS $$
DECLARE
  lexical text := sparql.lex(lit);
  tz_offset text;
BEGIN
  -- Extract the timezone part: ±HH:MM or Z at the end of the string
  tz_offset := substring(lexical from '([-+]\d{2}:\d{2}|Z)$');

  IF tz_offset IS NULL THEN
    -- Return an empty string or raise an error based on your requirements
    RAISE EXCEPTION 'SPARQL TZ(): datetime has no timezone';
  END IF;

  -- If the timezone is 'Z', return 'Z'
  IF tz_offset = 'Z' THEN
    RETURN 'Z';
  END IF;

  -- Otherwise, return the timezone offset ±HH:MM
  RETURN tz_offset;
END;
$$ LANGUAGE plpgsql IMMUTABLE;

/* SPARQL 17.4.6 Hash Functions */
CREATE FUNCTION sparql.md5(text) RETURNS text
AS 'MODULE_PATHNAME', 'rdf_fdw_md5'
LANGUAGE C IMMUTABLE STRICT;
