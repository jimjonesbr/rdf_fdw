GRANT USAGE ON SCHEMA sparql TO PUBLIC;

/* These generate a new value on every call, so constant folding must not
   collapse them to a single value for the whole query. */
ALTER FUNCTION sparql.bnode() VOLATILE;
ALTER FUNCTION sparql.uuid() VOLATILE;
ALTER FUNCTION sparql.struuid() VOLATILE;

/* SPARQL ROUND returns the number with no fractional part nearest the argument,
   and on a tie the one closer to positive infinity. That is floor(x + 0.5) for
   every x, negative values included: ROUND(-2.5) is -2, not -3. */
CREATE OR REPLACE FUNCTION sparql.round(rdfnode) RETURNS rdfnode AS $$
DECLARE dt rdfnode;
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

  RETURN sparql.strdt(pg_catalog.floor(sparql.lex($1)::numeric + 0.5)::rdfnode, dt);
END;
$$ LANGUAGE plpgsql IMMUTABLE STRICT;

CREATE OR REPLACE FUNCTION sparql.round(double precision) RETURNS rdfnode AS $$
DECLARE r double precision;
BEGIN
  /* An argument in [-0.5, 0) rounds to negative zero. */
  IF $1 >= -0.5 AND $1 < 0 THEN
    RETURN (-0.0::double precision)::rdfnode;
  END IF;

  /* The fractional part is compared against one half rather than the half
     being added first: in binary floating point x + 0.5 can carry to the next
     integer on its own, taking a value such as 0.49999999999999994 up to 1. */
  r := pg_catalog.floor($1);
  IF $1 - r >= 0.5 THEN
    r := r + 1;
  END IF;

  RETURN r::rdfnode;
END;
$$ LANGUAGE plpgsql IMMUTABLE STRICT;

CREATE OR REPLACE FUNCTION sparql.round(numeric) RETURNS rdfnode AS $$
BEGIN
  RETURN pg_catalog.floor($1 + 0.5)::rdfnode;
END;
$$ LANGUAGE plpgsql IMMUTABLE STRICT;
