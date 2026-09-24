/* New in 2.8: the rdfnode B-tree operator class compares stored terms rather
   than RDF values. The value operators =, <, <=, >= and > stay as they are,
   but they leave the operator class, because RDF value equality is not an
   equivalence relation and RDF value comparison is not a total order.

   Replacing an operator class does not rewrite the indexes built with it, and
   an index whose ordering no longer matches the class returns wrong answers
   without reporting anything, so an upgrade that would leave such an index
   behind is refused. */
DO $$
BEGIN
  IF EXISTS (
    SELECT 1
    FROM pg_catalog.pg_index AS i
    JOIN pg_catalog.pg_opclass AS c ON c.oid = ANY (i.indclass::oid[])
    JOIN pg_catalog.pg_type AS t ON t.oid = c.opcintype
    WHERE c.opcname = 'rdfnode_ops'
      AND t.oid = pg_catalog.pg_typeof(NULL::@extschema@.rdfnode)
      AND c.opcnamespace = t.typnamespace
  ) THEN
    RAISE EXCEPTION 'rdfnode indexes must be rebuilt for the new comparison operator class'
      USING ERRCODE = '55006',
            HINT = 'Save the definitions, drop the dependent indexes or the constraints that own them, upgrade, then recreate them. The new class compares stored terms, not RDF values, so REINDEX alone is not enough.';
  END IF;
END
$$;

/* A stored query that sorts, groups or de-duplicates on an rdfnode keeps the
   ordering operator it was parsed with, and that operator no longer belongs to
   any operator class once the class is replaced. The view still exists and
   still dumps, but every use of it fails with "operator NNN is not a valid
   ordering operator", naming an OID and nothing else. Refuse the upgrade while
   one of those exists, so the failure happens now and says what to do about it.

   Only the ordering operators are looked for, because only a sort, a grouping
   or a DISTINCT holds one. A stored query that compares with = or <> is left
   alone: the operators themselves are not touched and keep comparing RDF
   values exactly as before, and equality by itself is never an ordering. A
   WHERE clause written with <, <=, >= or > is refused even though nothing
   would break it -- there is no way to tell it apart from a sort in the
   catalogue, and refusing an upgrade is recoverable where a view that fails on
   every use is not. */
DO $$
BEGIN
  IF EXISTS (
    SELECT 1
    FROM pg_catalog.pg_opclass AS c
    JOIN pg_catalog.pg_am AS am ON am.oid = c.opcmethod AND am.amname = 'btree'
    JOIN pg_catalog.pg_type AS t ON t.oid = c.opcintype
    JOIN pg_catalog.pg_amop AS a
      ON a.amopfamily = c.opcfamily
     AND a.amoplefttype = c.opcintype
     AND a.amoprighttype = c.opcintype
     AND a.amopstrategy <> 3
    JOIN pg_catalog.pg_depend AS d
      ON d.refclassid = 'pg_catalog.pg_operator'::regclass
     AND d.refobjid = a.amopopr
     AND d.classid IN ('pg_catalog.pg_rewrite'::regclass,
                       'pg_catalog.pg_proc'::regclass)
    WHERE c.opcname = 'rdfnode_ops'
      AND t.oid = pg_catalog.pg_typeof(NULL::@extschema@.rdfnode)
      AND c.opcnamespace = t.typnamespace
  ) THEN
    RAISE EXCEPTION 'rdfnode ordering in stored queries must be reparsed for the new comparison operator class'
      USING ERRCODE = '55006',
            HINT = 'Save the definitions, drop the views, materialized views and SQL-body functions that sort, group or de-duplicate on an rdfnode, upgrade, then recreate them so they bind the new ordering operators.';
  END IF;
END
$$;

CREATE FUNCTION rdfnode_storage_lt(rdfnode, rdfnode)
RETURNS boolean
AS 'MODULE_PATHNAME', 'rdfnode_storage_lt'
LANGUAGE C IMMUTABLE STRICT;

CREATE FUNCTION rdfnode_storage_le(rdfnode, rdfnode)
RETURNS boolean
AS 'MODULE_PATHNAME', 'rdfnode_storage_le'
LANGUAGE C IMMUTABLE STRICT;

CREATE FUNCTION rdfnode_storage_eq(rdfnode, rdfnode)
RETURNS boolean
AS 'MODULE_PATHNAME', 'rdfnode_storage_eq'
LANGUAGE C IMMUTABLE STRICT;

CREATE FUNCTION rdfnode_storage_ge(rdfnode, rdfnode)
RETURNS boolean
AS 'MODULE_PATHNAME', 'rdfnode_storage_ge'
LANGUAGE C IMMUTABLE STRICT;

CREATE FUNCTION rdfnode_storage_gt(rdfnode, rdfnode)
RETURNS boolean
AS 'MODULE_PATHNAME', 'rdfnode_storage_gt'
LANGUAGE C IMMUTABLE STRICT;

CREATE OPERATOR ~<~ (
    LEFTARG = rdfnode,
    RIGHTARG = rdfnode,
    PROCEDURE = rdfnode_storage_lt,
    COMMUTATOR = '~>~',
    NEGATOR = '~>=~',
    RESTRICT = scalarltsel
);

CREATE OPERATOR ~<=~ (
    LEFTARG = rdfnode,
    RIGHTARG = rdfnode,
    PROCEDURE = rdfnode_storage_le,
    COMMUTATOR = '~>=~',
    NEGATOR = '~>~',
    RESTRICT = scalarltsel
);

CREATE OPERATOR ~= (
    LEFTARG = rdfnode,
    RIGHTARG = rdfnode,
    PROCEDURE = rdfnode_storage_eq,
    COMMUTATOR = '~=',
    RESTRICT = eqsel,
    JOIN = eqjoinsel,
    MERGES
);

CREATE OPERATOR ~>=~ (
    LEFTARG = rdfnode,
    RIGHTARG = rdfnode,
    PROCEDURE = rdfnode_storage_ge,
    COMMUTATOR = '~<=~',
    NEGATOR = '~<~',
    RESTRICT = scalargtsel
);

CREATE OPERATOR ~>~ (
    LEFTARG = rdfnode,
    RIGHTARG = rdfnode,
    PROCEDURE = rdfnode_storage_gt,
    COMMUTATOR = '~<~',
    NEGATOR = '~<=~',
    RESTRICT = scalargtsel
);

DROP OPERATOR CLASS rdfnode_ops USING btree;

CREATE OPERATOR CLASS rdfnode_ops
DEFAULT FOR TYPE rdfnode USING btree AS
    OPERATOR 1 ~<~  (rdfnode, rdfnode),
    OPERATOR 2 ~<=~ (rdfnode, rdfnode),
    OPERATOR 3 ~=   (rdfnode, rdfnode),
    OPERATOR 4 ~>=~ (rdfnode, rdfnode),
    OPERATOR 5 ~>~  (rdfnode, rdfnode),
    FUNCTION 1 rdfnode_cmp(rdfnode, rdfnode);

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
CREATE OR REPLACE FUNCTION sparql._xpath_replacement(text) RETURNS text
AS 'MODULE_PATHNAME', 'rdf_fdw_xpath_replacement'
LANGUAGE C IMMUTABLE STRICT;
COMMENT ON FUNCTION sparql._xpath_replacement(text) IS 'Internal: rewrites an XPath fn:replace replacement string ($1, \$) as a regexp_replace() one (\1, $).';

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
  /* an angle-bracketed argument is an IRI whatever type it arrives as */
  IF sparql.isIRI($1::@extschema@.rdfnode) THEN
    RAISE EXCEPTION 'REPLACE does not allow IRIs: %', $1 USING ERRCODE = '22023';
  END IF;

  /* a bare string carries no metadata to preserve */
  IF pg_catalog.left($1, 1) <> '"' THEN
    RETURN sparql._quote_literal(pg_catalog.regexp_replace(
      $1,
      CASE WHEN pg_catalog.left($2, 1) = '"' THEN sparql.lex($2::@extschema@.rdfnode) ELSE $2 END,
      sparql._xpath_replacement(
        CASE WHEN pg_catalog.left($3, 1) = '"' THEN sparql.lex($3::@extschema@.rdfnode) ELSE $3 END),
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
  /* REPLACE is defined over string literals: an IRI or a blank node has no
     lexical form to rewrite, and rewriting its written shape would invent a
     term nothing describes. */
  IF sparql.isIRI($1) THEN
    RAISE EXCEPTION 'REPLACE does not allow IRIs: %', $1 USING ERRCODE = '22023';
  END IF;
  IF sparql.isblank($1) THEN
    RAISE EXCEPTION 'REPLACE does not allow blank nodes: %', $1 USING ERRCODE = '22023';
  END IF;

  result_lit := sparql._quote_literal(pg_catalog.regexp_replace(
    sparql.lex($1),
    sparql.lex($2),
    sparql._xpath_replacement(sparql.lex($3)),
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
  /* REPLACE is defined over string literals: an IRI or a blank node has no
     lexical form to rewrite, and rewriting its written shape would invent a
     term nothing describes. */
  IF sparql.isIRI($1) THEN
    RAISE EXCEPTION 'REPLACE does not allow IRIs: %', $1 USING ERRCODE = '22023';
  END IF;
  IF sparql.isblank($1) THEN
    RAISE EXCEPTION 'REPLACE does not allow blank nodes: %', $1 USING ERRCODE = '22023';
  END IF;

  result_lit := sparql._quote_literal(pg_catalog.regexp_replace(
    sparql.lex($1),
    sparql.lex($2),
    sparql._xpath_replacement(sparql.lex($3)),
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
CREATE OR REPLACE FUNCTION sparql.tz(lit rdfnode)
RETURNS rdfnode AS $$
DECLARE
  lexical    text := sparql.lex(lit);
  tz_offset  text;
  hh         int;
  mm         int;
  dt         text := sparql.datatype($1);
BEGIN

  -- Validate input
  IF dt <> '<http://www.w3.org/2001/XMLSchema#dateTime>' THEN
    RAISE EXCEPTION 'TZ(): argument must be xsd:dateTime, got %', dt;
  END IF;

  -- Basic xsd:dateTime format validation
  IF NOT lexical ~ '^[0-9]{4}-(0[1-9]|1[0-2])-(0[1-9]|[12][0-9]|3[01])T([01][0-9]|2[0-3]):[0-5][0-9]:[0-5][0-9](\.\d+)?([+-]\d{2}:\d{2}|Z)?$' THEN
    RAISE EXCEPTION 'TZ(): invalid xsd:dateTime format: %', lexical;
  END IF;

  tz_offset := substring(lexical from '([-+]\d{2}:\d{2}|Z)$');

  -- SPARQL 1.1 17.4.5.8: "Returns the timezone part of arg as a simple
  -- literal. Returns the empty string if there is no timezone." TZ is the
  -- total function of the pair; TIMEZONE, in 17.4.5.7, is the one that raises.
  IF tz_offset IS NULL THEN
    RETURN '""';
  END IF;

  IF tz_offset = 'Z' THEN
    RETURN '"Z"';
  END IF;

  hh := abs(substring(tz_offset from 2 for 2)::int);
  mm := substring(tz_offset from 5 for 2)::int;

  IF hh > 14 OR mm > 59 OR (hh = 14 AND mm > 0) THEN
    RAISE EXCEPTION 'TZ(): invalid timezone offset: %', tz_offset;
  END IF;

  RETURN '"' || tz_offset || '"';
END;
$$ LANGUAGE plpgsql IMMUTABLE STRICT;

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

/* Comparisons between an rdfnode and timestamp or timestamptz were SQL
   wrappers around the cast to that type. The cast rejects any term that is
   neither xsd:dateTime nor xsd:date, so a filter over a predicate carrying
   mixed datatypes failed instead of returning its matching rows, and the
   planner inlined the wrapper into a cast expression that could not be
   deparsed. The C implementations report such a term as non-matching and
   leave the operator intact. The ones involving timestamptz are STABLE, see
   below. */
CREATE OR REPLACE FUNCTION rdfnode_eq_timestamp(rdfnode, timestamp)
RETURNS boolean
AS 'MODULE_PATHNAME', 'rdfnode_eq_timestamp'
LANGUAGE C IMMUTABLE STRICT;
CREATE OR REPLACE FUNCTION rdfnode_neq_timestamp(rdfnode, timestamp)
RETURNS boolean
AS 'MODULE_PATHNAME', 'rdfnode_neq_timestamp'
LANGUAGE C IMMUTABLE STRICT;
CREATE OR REPLACE FUNCTION rdfnode_lt_timestamp(rdfnode, timestamp)
RETURNS boolean
AS 'MODULE_PATHNAME', 'rdfnode_lt_timestamp'
LANGUAGE C IMMUTABLE STRICT;
CREATE OR REPLACE FUNCTION rdfnode_gt_timestamp(rdfnode, timestamp)
RETURNS boolean
AS 'MODULE_PATHNAME', 'rdfnode_gt_timestamp'
LANGUAGE C IMMUTABLE STRICT;
CREATE OR REPLACE FUNCTION rdfnode_le_timestamp(rdfnode, timestamp)
RETURNS boolean
AS 'MODULE_PATHNAME', 'rdfnode_le_timestamp'
LANGUAGE C IMMUTABLE STRICT;
CREATE OR REPLACE FUNCTION rdfnode_ge_timestamp(rdfnode, timestamp)
RETURNS boolean
AS 'MODULE_PATHNAME', 'rdfnode_ge_timestamp'
LANGUAGE C IMMUTABLE STRICT;
CREATE OR REPLACE FUNCTION rdfnode_eq_timestamptz(rdfnode, timestamptz)
RETURNS boolean
AS 'MODULE_PATHNAME', 'rdfnode_eq_timestamptz'
LANGUAGE C STABLE STRICT;
CREATE OR REPLACE FUNCTION rdfnode_neq_timestamptz(rdfnode, timestamptz)
RETURNS boolean
AS 'MODULE_PATHNAME', 'rdfnode_neq_timestamptz'
LANGUAGE C STABLE STRICT;
CREATE OR REPLACE FUNCTION rdfnode_lt_timestamptz(rdfnode, timestamptz)
RETURNS boolean
AS 'MODULE_PATHNAME', 'rdfnode_lt_timestamptz'
LANGUAGE C STABLE STRICT;
CREATE OR REPLACE FUNCTION rdfnode_gt_timestamptz(rdfnode, timestamptz)
RETURNS boolean
AS 'MODULE_PATHNAME', 'rdfnode_gt_timestamptz'
LANGUAGE C STABLE STRICT;
CREATE OR REPLACE FUNCTION rdfnode_le_timestamptz(rdfnode, timestamptz)
RETURNS boolean
AS 'MODULE_PATHNAME', 'rdfnode_le_timestamptz'
LANGUAGE C STABLE STRICT;
CREATE OR REPLACE FUNCTION rdfnode_ge_timestamptz(rdfnode, timestamptz)
RETURNS boolean
AS 'MODULE_PATHNAME', 'rdfnode_ge_timestamptz'
LANGUAGE C STABLE STRICT;
CREATE OR REPLACE FUNCTION timestamp_eq_rdfnode(timestamp, rdfnode)
RETURNS boolean
AS 'MODULE_PATHNAME', 'timestamp_eq_rdfnode'
LANGUAGE C IMMUTABLE STRICT;
CREATE OR REPLACE FUNCTION timestamp_neq_rdfnode(timestamp, rdfnode)
RETURNS boolean
AS 'MODULE_PATHNAME', 'timestamp_neq_rdfnode'
LANGUAGE C IMMUTABLE STRICT;
CREATE OR REPLACE FUNCTION timestamp_lt_rdfnode(timestamp, rdfnode)
RETURNS boolean
AS 'MODULE_PATHNAME', 'timestamp_lt_rdfnode'
LANGUAGE C IMMUTABLE STRICT;
CREATE OR REPLACE FUNCTION timestamp_gt_rdfnode(timestamp, rdfnode)
RETURNS boolean
AS 'MODULE_PATHNAME', 'timestamp_gt_rdfnode'
LANGUAGE C IMMUTABLE STRICT;
CREATE OR REPLACE FUNCTION timestamp_le_rdfnode(timestamp, rdfnode)
RETURNS boolean
AS 'MODULE_PATHNAME', 'timestamp_le_rdfnode'
LANGUAGE C IMMUTABLE STRICT;
CREATE OR REPLACE FUNCTION timestamp_ge_rdfnode(timestamp, rdfnode)
RETURNS boolean
AS 'MODULE_PATHNAME', 'timestamp_ge_rdfnode'
LANGUAGE C IMMUTABLE STRICT;
CREATE OR REPLACE FUNCTION timestamptz_eq_rdfnode(timestamptz, rdfnode)
RETURNS boolean
AS 'MODULE_PATHNAME', 'timestamptz_eq_rdfnode'
LANGUAGE C STABLE STRICT;
CREATE OR REPLACE FUNCTION timestamptz_neq_rdfnode(timestamptz, rdfnode)
RETURNS boolean
AS 'MODULE_PATHNAME', 'timestamptz_neq_rdfnode'
LANGUAGE C STABLE STRICT;
CREATE OR REPLACE FUNCTION timestamptz_lt_rdfnode(timestamptz, rdfnode)
RETURNS boolean
AS 'MODULE_PATHNAME', 'timestamptz_lt_rdfnode'
LANGUAGE C STABLE STRICT;
CREATE OR REPLACE FUNCTION timestamptz_gt_rdfnode(timestamptz, rdfnode)
RETURNS boolean
AS 'MODULE_PATHNAME', 'timestamptz_gt_rdfnode'
LANGUAGE C STABLE STRICT;
CREATE OR REPLACE FUNCTION timestamptz_le_rdfnode(timestamptz, rdfnode)
RETURNS boolean
AS 'MODULE_PATHNAME', 'timestamptz_le_rdfnode'
LANGUAGE C STABLE STRICT;
CREATE OR REPLACE FUNCTION timestamptz_ge_rdfnode(timestamptz, rdfnode)
RETURNS boolean
AS 'MODULE_PATHNAME', 'timestamptz_ge_rdfnode'
LANGUAGE C STABLE STRICT;

/* A value without a time zone offset is read in the session's TimeZone when
   it is converted to timestamptz or timetz, so the conversions and the
   comparisons built on them give different answers under different settings,
   as PostgreSQL's own timestamp -> timestamptz cast does. They were IMMUTABLE,
   which let them into generated columns and index expressions, where the
   stored result then depended on the TimeZone of whoever wrote the row.
   sparql.describe() returns whatever the endpoint holds at the time, so it is
   VOLATILE. */
ALTER FUNCTION rdfnode_to_timestamptz(rdfnode) STABLE;
ALTER FUNCTION rdfnode_to_timetz(rdfnode) STABLE;
ALTER FUNCTION rdfnode_eq_timetz(rdfnode, timetz) STABLE;
ALTER FUNCTION rdfnode_neq_timetz(rdfnode, timetz) STABLE;
ALTER FUNCTION rdfnode_lt_timetz(rdfnode, timetz) STABLE;
ALTER FUNCTION rdfnode_gt_timetz(rdfnode, timetz) STABLE;
ALTER FUNCTION rdfnode_le_timetz(rdfnode, timetz) STABLE;
ALTER FUNCTION rdfnode_ge_timetz(rdfnode, timetz) STABLE;
ALTER FUNCTION timetz_eq_rdfnode(timetz, rdfnode) STABLE;
ALTER FUNCTION timetz_neq_rdfnode(timetz, rdfnode) STABLE;
ALTER FUNCTION timetz_lt_rdfnode(timetz, rdfnode) STABLE;
ALTER FUNCTION timetz_gt_rdfnode(timetz, rdfnode) STABLE;
ALTER FUNCTION timetz_le_rdfnode(timetz, rdfnode) STABLE;
ALTER FUNCTION timetz_ge_rdfnode(timetz, rdfnode) STABLE;
ALTER FUNCTION sparql.describe(text, text, text) VOLATILE;

/* New in 2.8: sparql.uri() returns rdfnode, as sparql.iri() always did.
   SPARQL 1.1 17.4.2.8 makes URI() a synonym of IRI() and gives both the return
   type iri, and the two have always called the same C function -- only the
   declared return type differed, which left uri()'s result unusable as an
   argument to any other sparql function without a cast. A return type cannot
   be changed in place, so the function is dropped and recreated. */
DROP FUNCTION sparql.uri(rdfnode);

CREATE FUNCTION sparql.uri(rdfnode) RETURNS rdfnode
AS 'MODULE_PATHNAME', 'rdf_fdw_iri'
LANGUAGE C IMMUTABLE STRICT;
COMMENT ON FUNCTION sparql.uri(rdfnode) IS 'Constructs an IRI. SPARQL 1.1 17.4.2.8 makes URI() a synonym of IRI().';

/* New in 2.8: STRLEN, LANG and REPLACE refuse an IRI and a blank node, as
   UCASE, LCASE, SUBSTR and CONCAT already did. LANG is guarded in C, so it
   needs nothing here. STRLEN was length(lex(...)), which counted an IRI's
   angle brackets and accepted a literal of any datatype; it now calls the
   implementation that was written for it and never wired up. */
CREATE OR REPLACE FUNCTION sparql.strlen(rdfnode) RETURNS int
AS 'MODULE_PATHNAME', 'rdf_fdw_strlen'
LANGUAGE C IMMUTABLE STRICT;

/* SPARQL 1.1 §17.3 maps +, -, * and / over two numerics onto op:numeric-add
   and its siblings. The result takes the wider of the two datatypes, except
   that dividing two xsd:integers gives an xsd:decimal. Without these the type
   had no arithmetic at all, and PostgreSQL resolved 1::rdfnode + 1::rdfnode
   through its casts instead, where several candidates tie. */
CREATE FUNCTION rdfnode_add_rdfnode(rdfnode, rdfnode)
RETURNS rdfnode AS 'MODULE_PATHNAME', 'rdfnode_add_rdfnode'
LANGUAGE C IMMUTABLE STRICT;

CREATE FUNCTION rdfnode_sub_rdfnode(rdfnode, rdfnode)
RETURNS rdfnode AS 'MODULE_PATHNAME', 'rdfnode_sub_rdfnode'
LANGUAGE C IMMUTABLE STRICT;

CREATE FUNCTION rdfnode_mul_rdfnode(rdfnode, rdfnode)
RETURNS rdfnode AS 'MODULE_PATHNAME', 'rdfnode_mul_rdfnode'
LANGUAGE C IMMUTABLE STRICT;

CREATE FUNCTION rdfnode_div_rdfnode(rdfnode, rdfnode)
RETURNS rdfnode AS 'MODULE_PATHNAME', 'rdfnode_div_rdfnode'
LANGUAGE C IMMUTABLE STRICT;

CREATE OPERATOR + (
    LEFTARG = rdfnode, RIGHTARG = rdfnode,
    PROCEDURE = rdfnode_add_rdfnode, COMMUTATOR = '+'
);

CREATE OPERATOR - (
    LEFTARG = rdfnode, RIGHTARG = rdfnode,
    PROCEDURE = rdfnode_sub_rdfnode
);

CREATE OPERATOR * (
    LEFTARG = rdfnode, RIGHTARG = rdfnode,
    PROCEDURE = rdfnode_mul_rdfnode, COMMUTATOR = '*'
);

CREATE OPERATOR / (
    LEFTARG = rdfnode, RIGHTARG = rdfnode,
    PROCEDURE = rdfnode_div_rdfnode
);

/*
 * Arithmetic between an rdfnode and a PostgreSQL number.
 *
 * Without these, PostgreSQL resolves such an expression through the type's
 * implicit casts: it either finds several candidates and reports that the
 * operator is not unique, or it settles on one and leaves RDF altogether,
 * so that "0.1"^^xsd:decimal * 3.0 answers 0.30000000447034836 as a float
 * rather than "0.3"^^xsd:decimal as a term. The operators below give each
 * combination an exact match, which resolution prefers over any cast, and
 * the answer is then the one SPARQL 1.1 17.3 defines.
 *
 * The PostgreSQL operand stands for the term its cast to rdfnode produces,
 * so an int is an xsd:int, a numeric an xsd:decimal, and a double precision
 * an xsd:double; the result's datatype follows from the promotion of the
 * pair, exactly as it does between two rdfnodes.
 */

/* rdfnode OP numeric */
CREATE FUNCTION rdfnode_add_numeric(rdfnode, numeric)
RETURNS rdfnode
AS 'MODULE_PATHNAME', 'rdfnode_add_numeric'
LANGUAGE C IMMUTABLE STRICT;

CREATE OPERATOR + (
    LEFTARG = rdfnode,
    RIGHTARG = numeric,
    PROCEDURE = rdfnode_add_numeric,
    COMMUTATOR = '+'
);

CREATE FUNCTION rdfnode_sub_numeric(rdfnode, numeric)
RETURNS rdfnode
AS 'MODULE_PATHNAME', 'rdfnode_sub_numeric'
LANGUAGE C IMMUTABLE STRICT;

CREATE OPERATOR - (
    LEFTARG = rdfnode,
    RIGHTARG = numeric,
    PROCEDURE = rdfnode_sub_numeric
);

CREATE FUNCTION rdfnode_mul_numeric(rdfnode, numeric)
RETURNS rdfnode
AS 'MODULE_PATHNAME', 'rdfnode_mul_numeric'
LANGUAGE C IMMUTABLE STRICT;

CREATE OPERATOR * (
    LEFTARG = rdfnode,
    RIGHTARG = numeric,
    PROCEDURE = rdfnode_mul_numeric,
    COMMUTATOR = '*'
);

CREATE FUNCTION rdfnode_div_numeric(rdfnode, numeric)
RETURNS rdfnode
AS 'MODULE_PATHNAME', 'rdfnode_div_numeric'
LANGUAGE C IMMUTABLE STRICT;

CREATE OPERATOR / (
    LEFTARG = rdfnode,
    RIGHTARG = numeric,
    PROCEDURE = rdfnode_div_numeric
);

/* numeric OP rdfnode */
CREATE FUNCTION numeric_add_rdfnode(numeric, rdfnode)
RETURNS rdfnode
AS 'MODULE_PATHNAME', 'numeric_add_rdfnode'
LANGUAGE C IMMUTABLE STRICT;

CREATE OPERATOR + (
    LEFTARG = numeric,
    RIGHTARG = rdfnode,
    PROCEDURE = numeric_add_rdfnode,
    COMMUTATOR = '+'
);

CREATE FUNCTION numeric_sub_rdfnode(numeric, rdfnode)
RETURNS rdfnode
AS 'MODULE_PATHNAME', 'numeric_sub_rdfnode'
LANGUAGE C IMMUTABLE STRICT;

CREATE OPERATOR - (
    LEFTARG = numeric,
    RIGHTARG = rdfnode,
    PROCEDURE = numeric_sub_rdfnode
);

CREATE FUNCTION numeric_mul_rdfnode(numeric, rdfnode)
RETURNS rdfnode
AS 'MODULE_PATHNAME', 'numeric_mul_rdfnode'
LANGUAGE C IMMUTABLE STRICT;

CREATE OPERATOR * (
    LEFTARG = numeric,
    RIGHTARG = rdfnode,
    PROCEDURE = numeric_mul_rdfnode,
    COMMUTATOR = '*'
);

CREATE FUNCTION numeric_div_rdfnode(numeric, rdfnode)
RETURNS rdfnode
AS 'MODULE_PATHNAME', 'numeric_div_rdfnode'
LANGUAGE C IMMUTABLE STRICT;

CREATE OPERATOR / (
    LEFTARG = numeric,
    RIGHTARG = rdfnode,
    PROCEDURE = numeric_div_rdfnode
);


/* rdfnode OP float8 */
CREATE FUNCTION rdfnode_add_float8(rdfnode, float8)
RETURNS rdfnode
AS 'MODULE_PATHNAME', 'rdfnode_add_float8'
LANGUAGE C IMMUTABLE STRICT;

CREATE OPERATOR + (
    LEFTARG = rdfnode,
    RIGHTARG = float8,
    PROCEDURE = rdfnode_add_float8,
    COMMUTATOR = '+'
);

CREATE FUNCTION rdfnode_sub_float8(rdfnode, float8)
RETURNS rdfnode
AS 'MODULE_PATHNAME', 'rdfnode_sub_float8'
LANGUAGE C IMMUTABLE STRICT;

CREATE OPERATOR - (
    LEFTARG = rdfnode,
    RIGHTARG = float8,
    PROCEDURE = rdfnode_sub_float8
);

CREATE FUNCTION rdfnode_mul_float8(rdfnode, float8)
RETURNS rdfnode
AS 'MODULE_PATHNAME', 'rdfnode_mul_float8'
LANGUAGE C IMMUTABLE STRICT;

CREATE OPERATOR * (
    LEFTARG = rdfnode,
    RIGHTARG = float8,
    PROCEDURE = rdfnode_mul_float8,
    COMMUTATOR = '*'
);

CREATE FUNCTION rdfnode_div_float8(rdfnode, float8)
RETURNS rdfnode
AS 'MODULE_PATHNAME', 'rdfnode_div_float8'
LANGUAGE C IMMUTABLE STRICT;

CREATE OPERATOR / (
    LEFTARG = rdfnode,
    RIGHTARG = float8,
    PROCEDURE = rdfnode_div_float8
);

/* float8 OP rdfnode */
CREATE FUNCTION float8_add_rdfnode(float8, rdfnode)
RETURNS rdfnode
AS 'MODULE_PATHNAME', 'float8_add_rdfnode'
LANGUAGE C IMMUTABLE STRICT;

CREATE OPERATOR + (
    LEFTARG = float8,
    RIGHTARG = rdfnode,
    PROCEDURE = float8_add_rdfnode,
    COMMUTATOR = '+'
);

CREATE FUNCTION float8_sub_rdfnode(float8, rdfnode)
RETURNS rdfnode
AS 'MODULE_PATHNAME', 'float8_sub_rdfnode'
LANGUAGE C IMMUTABLE STRICT;

CREATE OPERATOR - (
    LEFTARG = float8,
    RIGHTARG = rdfnode,
    PROCEDURE = float8_sub_rdfnode
);

CREATE FUNCTION float8_mul_rdfnode(float8, rdfnode)
RETURNS rdfnode
AS 'MODULE_PATHNAME', 'float8_mul_rdfnode'
LANGUAGE C IMMUTABLE STRICT;

CREATE OPERATOR * (
    LEFTARG = float8,
    RIGHTARG = rdfnode,
    PROCEDURE = float8_mul_rdfnode,
    COMMUTATOR = '*'
);

CREATE FUNCTION float8_div_rdfnode(float8, rdfnode)
RETURNS rdfnode
AS 'MODULE_PATHNAME', 'float8_div_rdfnode'
LANGUAGE C IMMUTABLE STRICT;

CREATE OPERATOR / (
    LEFTARG = float8,
    RIGHTARG = rdfnode,
    PROCEDURE = float8_div_rdfnode
);


/* rdfnode OP float4 */
CREATE FUNCTION rdfnode_add_float4(rdfnode, float4)
RETURNS rdfnode
AS 'MODULE_PATHNAME', 'rdfnode_add_float4'
LANGUAGE C IMMUTABLE STRICT;

CREATE OPERATOR + (
    LEFTARG = rdfnode,
    RIGHTARG = float4,
    PROCEDURE = rdfnode_add_float4,
    COMMUTATOR = '+'
);

CREATE FUNCTION rdfnode_sub_float4(rdfnode, float4)
RETURNS rdfnode
AS 'MODULE_PATHNAME', 'rdfnode_sub_float4'
LANGUAGE C IMMUTABLE STRICT;

CREATE OPERATOR - (
    LEFTARG = rdfnode,
    RIGHTARG = float4,
    PROCEDURE = rdfnode_sub_float4
);

CREATE FUNCTION rdfnode_mul_float4(rdfnode, float4)
RETURNS rdfnode
AS 'MODULE_PATHNAME', 'rdfnode_mul_float4'
LANGUAGE C IMMUTABLE STRICT;

CREATE OPERATOR * (
    LEFTARG = rdfnode,
    RIGHTARG = float4,
    PROCEDURE = rdfnode_mul_float4,
    COMMUTATOR = '*'
);

CREATE FUNCTION rdfnode_div_float4(rdfnode, float4)
RETURNS rdfnode
AS 'MODULE_PATHNAME', 'rdfnode_div_float4'
LANGUAGE C IMMUTABLE STRICT;

CREATE OPERATOR / (
    LEFTARG = rdfnode,
    RIGHTARG = float4,
    PROCEDURE = rdfnode_div_float4
);

/* float4 OP rdfnode */
CREATE FUNCTION float4_add_rdfnode(float4, rdfnode)
RETURNS rdfnode
AS 'MODULE_PATHNAME', 'float4_add_rdfnode'
LANGUAGE C IMMUTABLE STRICT;

CREATE OPERATOR + (
    LEFTARG = float4,
    RIGHTARG = rdfnode,
    PROCEDURE = float4_add_rdfnode,
    COMMUTATOR = '+'
);

CREATE FUNCTION float4_sub_rdfnode(float4, rdfnode)
RETURNS rdfnode
AS 'MODULE_PATHNAME', 'float4_sub_rdfnode'
LANGUAGE C IMMUTABLE STRICT;

CREATE OPERATOR - (
    LEFTARG = float4,
    RIGHTARG = rdfnode,
    PROCEDURE = float4_sub_rdfnode
);

CREATE FUNCTION float4_mul_rdfnode(float4, rdfnode)
RETURNS rdfnode
AS 'MODULE_PATHNAME', 'float4_mul_rdfnode'
LANGUAGE C IMMUTABLE STRICT;

CREATE OPERATOR * (
    LEFTARG = float4,
    RIGHTARG = rdfnode,
    PROCEDURE = float4_mul_rdfnode,
    COMMUTATOR = '*'
);

CREATE FUNCTION float4_div_rdfnode(float4, rdfnode)
RETURNS rdfnode
AS 'MODULE_PATHNAME', 'float4_div_rdfnode'
LANGUAGE C IMMUTABLE STRICT;

CREATE OPERATOR / (
    LEFTARG = float4,
    RIGHTARG = rdfnode,
    PROCEDURE = float4_div_rdfnode
);


/* rdfnode OP int8 */
CREATE FUNCTION rdfnode_add_int8(rdfnode, int8)
RETURNS rdfnode
AS 'MODULE_PATHNAME', 'rdfnode_add_int8'
LANGUAGE C IMMUTABLE STRICT;

CREATE OPERATOR + (
    LEFTARG = rdfnode,
    RIGHTARG = int8,
    PROCEDURE = rdfnode_add_int8,
    COMMUTATOR = '+'
);

CREATE FUNCTION rdfnode_sub_int8(rdfnode, int8)
RETURNS rdfnode
AS 'MODULE_PATHNAME', 'rdfnode_sub_int8'
LANGUAGE C IMMUTABLE STRICT;

CREATE OPERATOR - (
    LEFTARG = rdfnode,
    RIGHTARG = int8,
    PROCEDURE = rdfnode_sub_int8
);

CREATE FUNCTION rdfnode_mul_int8(rdfnode, int8)
RETURNS rdfnode
AS 'MODULE_PATHNAME', 'rdfnode_mul_int8'
LANGUAGE C IMMUTABLE STRICT;

CREATE OPERATOR * (
    LEFTARG = rdfnode,
    RIGHTARG = int8,
    PROCEDURE = rdfnode_mul_int8,
    COMMUTATOR = '*'
);

CREATE FUNCTION rdfnode_div_int8(rdfnode, int8)
RETURNS rdfnode
AS 'MODULE_PATHNAME', 'rdfnode_div_int8'
LANGUAGE C IMMUTABLE STRICT;

CREATE OPERATOR / (
    LEFTARG = rdfnode,
    RIGHTARG = int8,
    PROCEDURE = rdfnode_div_int8
);

/* int8 OP rdfnode */
CREATE FUNCTION int8_add_rdfnode(int8, rdfnode)
RETURNS rdfnode
AS 'MODULE_PATHNAME', 'int8_add_rdfnode'
LANGUAGE C IMMUTABLE STRICT;

CREATE OPERATOR + (
    LEFTARG = int8,
    RIGHTARG = rdfnode,
    PROCEDURE = int8_add_rdfnode,
    COMMUTATOR = '+'
);

CREATE FUNCTION int8_sub_rdfnode(int8, rdfnode)
RETURNS rdfnode
AS 'MODULE_PATHNAME', 'int8_sub_rdfnode'
LANGUAGE C IMMUTABLE STRICT;

CREATE OPERATOR - (
    LEFTARG = int8,
    RIGHTARG = rdfnode,
    PROCEDURE = int8_sub_rdfnode
);

CREATE FUNCTION int8_mul_rdfnode(int8, rdfnode)
RETURNS rdfnode
AS 'MODULE_PATHNAME', 'int8_mul_rdfnode'
LANGUAGE C IMMUTABLE STRICT;

CREATE OPERATOR * (
    LEFTARG = int8,
    RIGHTARG = rdfnode,
    PROCEDURE = int8_mul_rdfnode,
    COMMUTATOR = '*'
);

CREATE FUNCTION int8_div_rdfnode(int8, rdfnode)
RETURNS rdfnode
AS 'MODULE_PATHNAME', 'int8_div_rdfnode'
LANGUAGE C IMMUTABLE STRICT;

CREATE OPERATOR / (
    LEFTARG = int8,
    RIGHTARG = rdfnode,
    PROCEDURE = int8_div_rdfnode
);


/* rdfnode OP int4 */
CREATE FUNCTION rdfnode_add_int4(rdfnode, int4)
RETURNS rdfnode
AS 'MODULE_PATHNAME', 'rdfnode_add_int4'
LANGUAGE C IMMUTABLE STRICT;

CREATE OPERATOR + (
    LEFTARG = rdfnode,
    RIGHTARG = int4,
    PROCEDURE = rdfnode_add_int4,
    COMMUTATOR = '+'
);

CREATE FUNCTION rdfnode_sub_int4(rdfnode, int4)
RETURNS rdfnode
AS 'MODULE_PATHNAME', 'rdfnode_sub_int4'
LANGUAGE C IMMUTABLE STRICT;

CREATE OPERATOR - (
    LEFTARG = rdfnode,
    RIGHTARG = int4,
    PROCEDURE = rdfnode_sub_int4
);

CREATE FUNCTION rdfnode_mul_int4(rdfnode, int4)
RETURNS rdfnode
AS 'MODULE_PATHNAME', 'rdfnode_mul_int4'
LANGUAGE C IMMUTABLE STRICT;

CREATE OPERATOR * (
    LEFTARG = rdfnode,
    RIGHTARG = int4,
    PROCEDURE = rdfnode_mul_int4,
    COMMUTATOR = '*'
);

CREATE FUNCTION rdfnode_div_int4(rdfnode, int4)
RETURNS rdfnode
AS 'MODULE_PATHNAME', 'rdfnode_div_int4'
LANGUAGE C IMMUTABLE STRICT;

CREATE OPERATOR / (
    LEFTARG = rdfnode,
    RIGHTARG = int4,
    PROCEDURE = rdfnode_div_int4
);

/* int4 OP rdfnode */
CREATE FUNCTION int4_add_rdfnode(int4, rdfnode)
RETURNS rdfnode
AS 'MODULE_PATHNAME', 'int4_add_rdfnode'
LANGUAGE C IMMUTABLE STRICT;

CREATE OPERATOR + (
    LEFTARG = int4,
    RIGHTARG = rdfnode,
    PROCEDURE = int4_add_rdfnode,
    COMMUTATOR = '+'
);

CREATE FUNCTION int4_sub_rdfnode(int4, rdfnode)
RETURNS rdfnode
AS 'MODULE_PATHNAME', 'int4_sub_rdfnode'
LANGUAGE C IMMUTABLE STRICT;

CREATE OPERATOR - (
    LEFTARG = int4,
    RIGHTARG = rdfnode,
    PROCEDURE = int4_sub_rdfnode
);

CREATE FUNCTION int4_mul_rdfnode(int4, rdfnode)
RETURNS rdfnode
AS 'MODULE_PATHNAME', 'int4_mul_rdfnode'
LANGUAGE C IMMUTABLE STRICT;

CREATE OPERATOR * (
    LEFTARG = int4,
    RIGHTARG = rdfnode,
    PROCEDURE = int4_mul_rdfnode,
    COMMUTATOR = '*'
);

CREATE FUNCTION int4_div_rdfnode(int4, rdfnode)
RETURNS rdfnode
AS 'MODULE_PATHNAME', 'int4_div_rdfnode'
LANGUAGE C IMMUTABLE STRICT;

CREATE OPERATOR / (
    LEFTARG = int4,
    RIGHTARG = rdfnode,
    PROCEDURE = int4_div_rdfnode
);


/* rdfnode OP int2 */
CREATE FUNCTION rdfnode_add_int2(rdfnode, int2)
RETURNS rdfnode
AS 'MODULE_PATHNAME', 'rdfnode_add_int2'
LANGUAGE C IMMUTABLE STRICT;

CREATE OPERATOR + (
    LEFTARG = rdfnode,
    RIGHTARG = int2,
    PROCEDURE = rdfnode_add_int2,
    COMMUTATOR = '+'
);

CREATE FUNCTION rdfnode_sub_int2(rdfnode, int2)
RETURNS rdfnode
AS 'MODULE_PATHNAME', 'rdfnode_sub_int2'
LANGUAGE C IMMUTABLE STRICT;

CREATE OPERATOR - (
    LEFTARG = rdfnode,
    RIGHTARG = int2,
    PROCEDURE = rdfnode_sub_int2
);

CREATE FUNCTION rdfnode_mul_int2(rdfnode, int2)
RETURNS rdfnode
AS 'MODULE_PATHNAME', 'rdfnode_mul_int2'
LANGUAGE C IMMUTABLE STRICT;

CREATE OPERATOR * (
    LEFTARG = rdfnode,
    RIGHTARG = int2,
    PROCEDURE = rdfnode_mul_int2,
    COMMUTATOR = '*'
);

CREATE FUNCTION rdfnode_div_int2(rdfnode, int2)
RETURNS rdfnode
AS 'MODULE_PATHNAME', 'rdfnode_div_int2'
LANGUAGE C IMMUTABLE STRICT;

CREATE OPERATOR / (
    LEFTARG = rdfnode,
    RIGHTARG = int2,
    PROCEDURE = rdfnode_div_int2
);

/* int2 OP rdfnode */
CREATE FUNCTION int2_add_rdfnode(int2, rdfnode)
RETURNS rdfnode
AS 'MODULE_PATHNAME', 'int2_add_rdfnode'
LANGUAGE C IMMUTABLE STRICT;

CREATE OPERATOR + (
    LEFTARG = int2,
    RIGHTARG = rdfnode,
    PROCEDURE = int2_add_rdfnode,
    COMMUTATOR = '+'
);

CREATE FUNCTION int2_sub_rdfnode(int2, rdfnode)
RETURNS rdfnode
AS 'MODULE_PATHNAME', 'int2_sub_rdfnode'
LANGUAGE C IMMUTABLE STRICT;

CREATE OPERATOR - (
    LEFTARG = int2,
    RIGHTARG = rdfnode,
    PROCEDURE = int2_sub_rdfnode
);

CREATE FUNCTION int2_mul_rdfnode(int2, rdfnode)
RETURNS rdfnode
AS 'MODULE_PATHNAME', 'int2_mul_rdfnode'
LANGUAGE C IMMUTABLE STRICT;

CREATE OPERATOR * (
    LEFTARG = int2,
    RIGHTARG = rdfnode,
    PROCEDURE = int2_mul_rdfnode,
    COMMUTATOR = '*'
);

CREATE FUNCTION int2_div_rdfnode(int2, rdfnode)
RETURNS rdfnode
AS 'MODULE_PATHNAME', 'int2_div_rdfnode'
LANGUAGE C IMMUTABLE STRICT;

CREATE OPERATOR / (
    LEFTARG = int2,
    RIGHTARG = rdfnode,
    PROCEDURE = int2_div_rdfnode
);
