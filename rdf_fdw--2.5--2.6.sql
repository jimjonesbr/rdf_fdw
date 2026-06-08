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