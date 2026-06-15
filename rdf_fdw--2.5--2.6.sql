/* fix returning type of sparql.seconds() from int to numeric */
DROP FUNCTION IF EXISTS sparql.seconds(text);
CREATE OR REPLACE FUNCTION sparql.seconds(text)
RETURNS numeric AS $$
BEGIN
  RETURN sparql.seconds($1::rdfnode);
END;
$$ LANGUAGE plpgsql STABLE STRICT;

/* 
 * fix casting to non xsd:time datatypes to timestamptz 
 * instead of timestamp to preserve timezone info, if any
 */
CREATE OR REPLACE FUNCTION sparql.seconds(rdfnode)
RETURNS numeric AS $$
DECLARE
    dt text := sparql.datatype($1)::text;
BEGIN
    IF dt = '<http://www.w3.org/2001/XMLSchema#time>' THEN
        RETURN EXTRACT(second FROM sparql.lex($1)::time);
    ELSE
        RETURN EXTRACT(second FROM sparql.lex($1)::timestamptz);
    END IF;
END;
$$ LANGUAGE plpgsql STABLE STRICT;

/* Add check for valid timezone offsets */
CREATE OR REPLACE FUNCTION sparql.tz(lit rdfnode)
RETURNS rdfnode AS $$
DECLARE
  lexical    text := sparql.lex(lit);
  tz_offset  text;
  hh         int;
  mm         int;
BEGIN
  tz_offset := substring(lexical from '([-+]\d{2}:\d{2}|Z)$');

  IF tz_offset IS NULL THEN
    RAISE EXCEPTION 'TZ(): datetime has no timezone';
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
$$ LANGUAGE plpgsql IMMUTABLE;

/* Fix the TZ() text overload to IMMUTABLE */
CREATE OR REPLACE FUNCTION sparql.tz(text)
RETURNS rdfnode AS $$
BEGIN
  RETURN sparql.tz($1::rdfnode);
END;
$$ LANGUAGE plpgsql IMMUTABLE STRICT;

CREATE OR REPLACE FUNCTION sparql.isblank(rdfnode) RETURNS boolean
AS 'MODULE_PATHNAME', 'rdf_fdw_isBlank'
LANGUAGE C IMMUTABLE;
COMMENT ON FUNCTION sparql.isblank(rdfnode) IS 'Checks if the input text is a blank node.';

/* add overload function for numeric arguments in ROUND()*/
CREATE OR REPLACE FUNCTION sparql.round(numeric) RETURNS rdfnode AS $$
BEGIN
  IF $1 > 0.0 THEN
    RETURN pg_catalog.floor($1 + 0.5)::rdfnode;
  ELSE
    RETURN pg_catalog.ceil($1 + 0.5)::rdfnode;
  END IF;
END;
$$ LANGUAGE plpgsql IMMUTABLE STRICT;

/* now return an exception on invalid xsd data type */
CREATE OR REPLACE FUNCTION sparql.timezone(lit rdfnode)
RETURNS rdfnode AS $$
DECLARE
  lexical text := sparql.lex(lit);
  tz_offset text;
  hours int;
  minutes int;
  sign text;
  dt text := sparql.datatype($1);
BEGIN
  -- Validate input
  IF dt <> '<http://www.w3.org/2001/XMLSchema#dateTime>' THEN
    RAISE EXCEPTION 'TIMEZONE(): argument must be xsd:dateTime, got %', dt ; -- new error!
  END IF;

  IF lexical IS NULL OR lexical = '' THEN
    RAISE EXCEPTION 'TIMEZONE(): invalid xsd:dateTime literal';
  END IF;

  -- Basic xsd:dateTime format validation
  IF NOT lexical ~ '^[0-9]{4}-(0[1-9]|1[0-2])-(0[1-9]|[12][0-9]|3[01])T([01][0-9]|2[0-3]):[0-5][0-9]:[0-5][0-9](\.\d+)?([+-]\d{2}:\d{2}|Z)?$' THEN
    RAISE EXCEPTION 'TIMEZONE(): invalid xsd:dateTime format: %', lexical;
  END IF;

  -- Extract timezone
  tz_offset := substring(lexical from '([-+]\d{2}:\d{2}|Z)$');

  IF tz_offset IS NULL THEN
    RAISE EXCEPTION 'TIMEZONE(): datetime has no time zone: %', lexical;
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
    RAISE EXCEPTION 'TIMEZONE(): invalid timezone offset: %', tz_offset;
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

/* validate the argument with :: before calling the C function */
CREATE OR REPLACE FUNCTION sparql.datatype(text)
RETURNS rdfnode AS $$
BEGIN
  RETURN sparql.datatype($1::rdfnode);
END;
$$ LANGUAGE plpgsql IMMUTABLE STRICT;