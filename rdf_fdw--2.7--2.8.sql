GRANT USAGE ON SCHEMA sparql TO PUBLIC;

/* These generate a new value on every call, so constant folding must not
   collapse them to a single value for the whole query. */
ALTER FUNCTION sparql.bnode() VOLATILE;
ALTER FUNCTION sparql.uuid() VOLATILE;
ALTER FUNCTION sparql.struuid() VOLATILE;

/* New in 2.8: the SPARQL string functions build their result from lexical
   content, which must not be read back as a serialised term. */
CREATE FUNCTION sparql._quote_literal(text) RETURNS rdfnode
AS 'MODULE_PATHNAME', 'rdf_fdw_quote_literal'
LANGUAGE C IMMUTABLE STRICT;
COMMENT ON FUNCTION sparql._quote_literal(text) IS 'Internal: wraps lexical content in quotes to form a simple literal.';

/* These bodies resolve the rdfnode type at call time, so they are replaced to
   name the schema the extension was installed into rather than relying on the
   caller's search_path. The round(), abs() and replace() bodies additionally
   correct the rounding rule, the loss of exact values and the loss of literal
   metadata; see the 2.8 notes. */

CREATE OR REPLACE FUNCTION sparql.bound(text) RETURNS boolean AS $$
BEGIN
  RETURN sparql.bound($1::@extschema@.rdfnode);
END;
$$ LANGUAGE plpgsql IMMUTABLE;
CREATE OR REPLACE FUNCTION sparql.datatype(text) RETURNS rdfnode
AS $$
BEGIN
  RETURN sparql.datatype($1::@extschema@.rdfnode);
END;
$$ LANGUAGE plpgsql IMMUTABLE STRICT;
CREATE OR REPLACE FUNCTION sparql.strdt(text, text) 
RETURNS rdfnode AS $$
BEGIN
  RETURN sparql.strdt($1::@extschema@.rdfnode, $2::@extschema@.rdfnode);
END;
$$ LANGUAGE plpgsql IMMUTABLE STRICT;
/* REPLACE operates on the lexical form and returns a literal carrying the same
   language tag or datatype as its first argument: replacing part of a
   language-tagged literal yields a literal in that language, not a bare string.
   The result is built with _quote_literal() rather than cast from text, since a
   cast reads its input as a serialised term -- content that happens to look
   like <...> or to contain "@ would be taken for an IRI or an annotated
   literal instead of the string it is. */
CREATE OR REPLACE FUNCTION sparql.replace(text, text, text)
RETURNS rdfnode AS $$
DECLARE
  input_lit @extschema@.rdfnode;
  result_text text;
  result_lit @extschema@.rdfnode;
  lang_text text;
  dt @extschema@.rdfnode;
BEGIN
  /* a bare string carries no metadata to preserve */
  IF pg_catalog.left($1, 1) <> '"' THEN
    RETURN sparql._quote_literal(pg_catalog.regexp_replace(
      $1,
      CASE WHEN pg_catalog.left($2, 1) = '"' THEN sparql.lex($2::@extschema@.rdfnode) ELSE $2 END,
      CASE WHEN pg_catalog.left($3, 1) = '"' THEN sparql.lex($3::@extschema@.rdfnode) ELSE $3 END,
      'g'
    ));
  END IF;

  input_lit := $1::@extschema@.rdfnode;
  RETURN sparql.replace(
    input_lit,
    CASE WHEN pg_catalog.left($2, 1) = '"' THEN $2::@extschema@.rdfnode ELSE sparql._quote_literal($2) END,
    CASE WHEN pg_catalog.left($3, 1) = '"' THEN $3::@extschema@.rdfnode ELSE sparql._quote_literal($3) END);
END;
$$ LANGUAGE plpgsql IMMUTABLE STRICT;
CREATE OR REPLACE FUNCTION sparql.replace(rdfnode, rdfnode, rdfnode)
RETURNS rdfnode AS $$
DECLARE
  result_lit @extschema@.rdfnode;
  lang_text text;
  dt @extschema@.rdfnode;
BEGIN
  result_lit := sparql._quote_literal(pg_catalog.regexp_replace(
    sparql.lex($1),
    sparql.lex($2),
    sparql.lex($3),
    'g'
  ));

  lang_text := sparql.lex(sparql.lang($1));
  IF lang_text <> '' THEN
    RETURN sparql.strlang(result_lit, lang_text::@extschema@.rdfnode);
  END IF;

  dt := sparql.datatype($1);
  IF dt IS NOT NULL AND sparql.lex(dt) <> '' AND
     dt::text <> '<http://www.w3.org/2001/XMLSchema#string>' THEN
    RETURN sparql.strdt(result_lit, dt);
  END IF;

  RETURN result_lit;
END;
$$ LANGUAGE plpgsql IMMUTABLE STRICT;
CREATE OR REPLACE FUNCTION sparql.replace(rdfnode, rdfnode, rdfnode, rdfnode)
RETURNS rdfnode AS $$
DECLARE
  result_lit @extschema@.rdfnode;
  lang_text text;
  dt @extschema@.rdfnode;
BEGIN
  result_lit := sparql._quote_literal(pg_catalog.regexp_replace(
    sparql.lex($1),
    sparql.lex($2),
    sparql.lex($3),
    sparql.lex($4) || 'g'
  ));

  lang_text := sparql.lex(sparql.lang($1));
  IF lang_text <> '' THEN
    RETURN sparql.strlang(result_lit, lang_text::@extschema@.rdfnode);
  END IF;

  dt := sparql.datatype($1);
  IF dt IS NOT NULL AND sparql.lex(dt) <> '' AND
     dt::text <> '<http://www.w3.org/2001/XMLSchema#string>' THEN
    RETURN sparql.strdt(result_lit, dt);
  END IF;

  RETURN result_lit;
END;
$$ LANGUAGE plpgsql IMMUTABLE STRICT;
/* SPARQL 17.4.4 Functions on Numerics */
CREATE OR REPLACE FUNCTION sparql.abs(text) RETURNS rdfnode  AS $$
BEGIN
  --RETURN pg_catalog.abs(sparql.lex($1::@extschema@.rdfnode)::double precision)::@extschema@.rdfnode;
  RETURN sparql.abs($1::@extschema@.rdfnode);
END;
$$ LANGUAGE plpgsql IMMUTABLE STRICT;
CREATE OR REPLACE FUNCTION sparql.abs(rdfnode) RETURNS rdfnode  AS $$
DECLARE dt @extschema@.rdfnode;
BEGIN
  IF NOT sparql.isnumeric($1) THEN
    RAISE EXCEPTION 'invalid value for ABS(): %', $1;
  END IF;

  dt := sparql.datatype($1);

  /* Only the floating datatypes are computed in floating arithmetic. Every
     other numeric datatype is exact, and routing it through double precision
     both rounds the value and prints it in an exponent form that the lexical
     space of xsd:integer and xsd:decimal does not admit. */
  IF dt::text = '<http://www.w3.org/2001/XMLSchema#float>'
     OR dt::text = '<http://www.w3.org/2001/XMLSchema#double>' THEN
    RETURN sparql.strdt(pg_catalog.abs(sparql.lex($1)::double precision)::@extschema@.rdfnode, dt);
  END IF;

  RETURN sparql.strdt(pg_catalog.abs(sparql.lex($1)::numeric)::@extschema@.rdfnode, dt);
END;
$$ LANGUAGE plpgsql IMMUTABLE STRICT;
CREATE OR REPLACE FUNCTION sparql.abs(smallint) RETURNS rdfnode  AS $$
BEGIN
  RETURN pg_catalog.abs($1)::@extschema@.rdfnode;
END;
$$ LANGUAGE plpgsql IMMUTABLE STRICT;
CREATE OR REPLACE FUNCTION sparql.abs(int) RETURNS rdfnode AS $$
BEGIN
  RETURN pg_catalog.abs($1)::@extschema@.rdfnode;
END;
$$ LANGUAGE plpgsql IMMUTABLE STRICT;
CREATE OR REPLACE FUNCTION sparql.abs(bigint) RETURNS rdfnode AS $$
BEGIN
  RETURN pg_catalog.abs($1)::@extschema@.rdfnode;
END;
$$ LANGUAGE plpgsql IMMUTABLE STRICT;
CREATE OR REPLACE FUNCTION sparql.abs(double precision) RETURNS rdfnode  AS $$
BEGIN
  RETURN pg_catalog.abs($1)::@extschema@.rdfnode;
END;
$$ LANGUAGE plpgsql IMMUTABLE STRICT;
CREATE OR REPLACE FUNCTION sparql.abs(numeric) RETURNS rdfnode  AS $$
BEGIN
  RETURN pg_catalog.abs($1)::@extschema@.rdfnode;
END;
$$ LANGUAGE plpgsql IMMUTABLE STRICT;
CREATE OR REPLACE FUNCTION sparql.abs(real) RETURNS rdfnode  AS $$
BEGIN
  RETURN pg_catalog.abs($1)::@extschema@.rdfnode;
END;
$$ LANGUAGE plpgsql IMMUTABLE STRICT;
CREATE OR REPLACE FUNCTION sparql.round(text) RETURNS rdfnode AS $$
BEGIN
  RETURN sparql.round($1::@extschema@.rdfnode);
END;
$$ LANGUAGE plpgsql IMMUTABLE STRICT;
/* SPARQL ROUND returns the number with no fractional part nearest the argument,
   and on a tie the one closer to positive infinity. That is floor(x + 0.5) for
   every x, negative values included: ROUND(-2.5) is -2, not -3. */
CREATE OR REPLACE FUNCTION sparql.round(rdfnode) RETURNS rdfnode AS $$
DECLARE dt @extschema@.rdfnode;
BEGIN
  IF NOT sparql.isnumeric($1) THEN
    RAISE EXCEPTION 'invalid value for ROUND(): %', $1;
  END IF;

  dt := sparql.datatype($1);

  /* The floating types are handed to the double overload, which works from the
     fractional part; the exact types can add the half directly. */
  IF dt::text = '<http://www.w3.org/2001/XMLSchema#float>' THEN
    RETURN sparql.strdt(sparql.round(sparql.lex($1)::real::double precision), dt);
  ELSIF dt::text = '<http://www.w3.org/2001/XMLSchema#double>' THEN
    RETURN sparql.strdt(sparql.round(sparql.lex($1)::double precision), dt);
  END IF;

  RETURN sparql.strdt(pg_catalog.floor(sparql.lex($1)::numeric + 0.5)::@extschema@.rdfnode, dt);
END;
$$ LANGUAGE plpgsql IMMUTABLE STRICT;
CREATE OR REPLACE FUNCTION sparql.round(double precision) RETURNS rdfnode AS $$
DECLARE r double precision;
BEGIN
  /* An argument in [-0.5, 0) rounds to negative zero. */
  IF $1 >= -0.5 AND $1 < 0 THEN
    RETURN (-0.0::double precision)::@extschema@.rdfnode;
  END IF;

  /* The fractional part is compared against one half rather than the half
     being added first: in binary floating point x + 0.5 can carry to the next
     integer on its own, taking a value such as 0.49999999999999994 up to 1. */
  r := pg_catalog.floor($1);
  IF $1 - r >= 0.5 THEN
    r := r + 1;
  END IF;

  RETURN r::@extschema@.rdfnode;
END;
$$ LANGUAGE plpgsql IMMUTABLE STRICT;
CREATE OR REPLACE FUNCTION sparql.round(numeric) RETURNS rdfnode AS $$
BEGIN
  RETURN pg_catalog.floor($1 + 0.5)::@extschema@.rdfnode;
END;
$$ LANGUAGE plpgsql IMMUTABLE STRICT;
CREATE OR REPLACE FUNCTION sparql.ceil(text) RETURNS rdfnode AS $$
BEGIN
  RETURN sparql.ceil($1::@extschema@.rdfnode)::@extschema@.rdfnode;
END;
$$ LANGUAGE plpgsql IMMUTABLE STRICT;
CREATE OR REPLACE FUNCTION sparql.ceil(rdfnode) RETURNS rdfnode AS $$
DECLARE dt @extschema@.rdfnode;
BEGIN
  IF NOT sparql.isnumeric($1) THEN
    RAISE EXCEPTION 'invalid value for CEIL(): %', $1;
  END IF;

  dt := sparql.datatype($1);

  RETURN sparql.strdt(pg_catalog.ceil(sparql.lex($1)::numeric)::@extschema@.rdfnode, dt);
END;
$$ LANGUAGE plpgsql IMMUTABLE STRICT;
CREATE OR REPLACE FUNCTION sparql.ceil(numeric) RETURNS rdfnode AS $$
BEGIN
  RETURN pg_catalog.ceil($1)::@extschema@.rdfnode;
END;
$$ LANGUAGE plpgsql IMMUTABLE STRICT;
CREATE OR REPLACE FUNCTION sparql.ceil(double precision) RETURNS rdfnode AS $$
BEGIN
  RETURN pg_catalog.ceil($1)::@extschema@.rdfnode;
END;
$$ LANGUAGE plpgsql IMMUTABLE STRICT;
CREATE OR REPLACE FUNCTION sparql.floor(text) RETURNS rdfnode AS $$
BEGIN
  RETURN sparql.floor($1::@extschema@.rdfnode)::@extschema@.rdfnode;
END;
$$ LANGUAGE plpgsql IMMUTABLE STRICT;
CREATE OR REPLACE FUNCTION sparql.floor(rdfnode) RETURNS rdfnode AS $$
DECLARE dt @extschema@.rdfnode;
BEGIN
  IF NOT sparql.isnumeric($1) THEN
    RAISE EXCEPTION 'invalid value for FLOOR(): %', $1;
  END IF;

  dt := sparql.datatype($1);

  RETURN sparql.strdt(pg_catalog.floor(sparql.lex($1)::numeric)::@extschema@.rdfnode, dt);
END;
$$ LANGUAGE plpgsql IMMUTABLE STRICT;
CREATE OR REPLACE FUNCTION sparql.floor(numeric) RETURNS rdfnode AS $$
BEGIN
  RETURN pg_catalog.floor($1)::@extschema@.rdfnode;
END;
$$ LANGUAGE plpgsql IMMUTABLE STRICT;
CREATE OR REPLACE FUNCTION sparql.floor(double precision) RETURNS rdfnode AS $$
BEGIN
  RETURN pg_catalog.floor($1)::@extschema@.rdfnode;
END;
$$ LANGUAGE plpgsql IMMUTABLE STRICT;
CREATE OR REPLACE FUNCTION sparql.rand() RETURNS rdfnode AS $$
BEGIN
  RETURN sparql.strdt(random()::@extschema@.rdfnode,'xsd:double');
END;
$$ LANGUAGE plpgsql STRICT;
/* SPARQL 17.4.5 Functions on Dates and Times */
CREATE OR REPLACE FUNCTION sparql.now() RETURNS rdfnode AS $$
BEGIN
  RETURN sparql.strdt(pg_catalog.now()::@extschema@.rdfnode, 'xsd:dateTime');
END;
$$ LANGUAGE plpgsql STABLE STRICT;
CREATE OR REPLACE FUNCTION sparql.year(text)
RETURNS int AS $$
BEGIN
  RETURN sparql.year($1::@extschema@.rdfnode);
END;
$$ LANGUAGE plpgsql STABLE STRICT;
CREATE OR REPLACE FUNCTION sparql.month(text)
RETURNS int AS $$
BEGIN
  RETURN sparql.month($1::@extschema@.rdfnode);
END;
$$ LANGUAGE plpgsql STABLE STRICT;
CREATE OR REPLACE FUNCTION sparql.day(text)
RETURNS int AS $$
BEGIN
  RETURN sparql.day($1::@extschema@.rdfnode);
END;
$$ LANGUAGE plpgsql STABLE STRICT;
CREATE OR REPLACE FUNCTION sparql.hours(text)
RETURNS int AS $$
BEGIN
  RETURN sparql.hours($1::@extschema@.rdfnode);
END;
$$ LANGUAGE plpgsql STABLE STRICT;
CREATE OR REPLACE FUNCTION sparql.minutes(text)
RETURNS int AS $$
BEGIN
  RETURN sparql.minutes($1::@extschema@.rdfnode);
END;
$$ LANGUAGE plpgsql STABLE STRICT;
CREATE OR REPLACE FUNCTION sparql.seconds(text)
RETURNS numeric AS $$
BEGIN
  RETURN sparql.seconds($1::@extschema@.rdfnode);
END;
$$ LANGUAGE plpgsql STABLE STRICT;
CREATE OR REPLACE FUNCTION sparql.timezone(text)
RETURNS rdfnode AS $$
BEGIN
  RETURN sparql.timezone($1::@extschema@.rdfnode);
END;
$$ LANGUAGE plpgsql STABLE STRICT;
CREATE OR REPLACE FUNCTION sparql.tz(text)
RETURNS rdfnode AS $$
BEGIN
  RETURN sparql.tz($1::@extschema@.rdfnode);
END;
$$ LANGUAGE plpgsql IMMUTABLE STRICT;
CREATE OR REPLACE FUNCTION sparql.md5(text)
RETURNS rdfnode AS $$
BEGIN
  RETURN sparql.md5($1::@extschema@.rdfnode);
END;
$$ LANGUAGE plpgsql STABLE STRICT;
