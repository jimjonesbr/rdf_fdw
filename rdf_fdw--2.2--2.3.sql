
CREATE OR REPLACE FUNCTION sparql.hours(time)
RETURNS int AS $$
BEGIN
  RETURN EXTRACT(hour FROM $1);
END;
$$ LANGUAGE plpgsql STABLE STRICT;

CREATE OR REPLACE FUNCTION sparql.seconds(rdfnode)
RETURNS numeric AS $$
BEGIN
    DECLARE
        dt text := sparql.datatype($1)::text;
    BEGIN
        IF dt = '<http://www.w3.org/2001/XMLSchema#time>' THEN
            RETURN EXTRACT(second FROM sparql.lex($1)::time);
        ELSE
            RETURN EXTRACT(second FROM sparql.lex($1)::timestamp);
        END IF;
    END;
END;
$$ LANGUAGE plpgsql STABLE STRICT;

CREATE OR REPLACE FUNCTION sparql.minutes(rdfnode)
RETURNS int AS $$
BEGIN
    DECLARE
        dt text := sparql.datatype($1)::text;
    BEGIN
        IF dt = '<http://www.w3.org/2001/XMLSchema#time>' THEN
            RETURN EXTRACT(minute FROM sparql.lex($1)::time);
        ELSE
            RETURN EXTRACT(minute FROM sparql.lex($1)::timestamp);
        END IF;
    END;
END;
$$ LANGUAGE plpgsql STABLE STRICT;

CREATE OR REPLACE FUNCTION sparql.hours(rdfnode)
RETURNS int AS $$
DECLARE
    dt text := sparql.datatype($1)::text;
BEGIN
    IF dt = '<http://www.w3.org/2001/XMLSchema#time>' THEN
        RETURN EXTRACT(hour FROM sparql.lex($1)::time);
    ELSE
        RETURN EXTRACT(hour FROM sparql.lex($1)::timestamp);
    END IF;
END;
$$ LANGUAGE plpgsql STABLE STRICT;

CREATE OR REPLACE FUNCTION sparql.minutes(time)
RETURNS int AS $$
BEGIN
  RETURN EXTRACT(minute FROM $1);
END;
$$ LANGUAGE plpgsql STABLE STRICT;

CREATE OR REPLACE FUNCTION sparql.seconds(time)
RETURNS numeric AS $$
BEGIN
  RETURN EXTRACT(second FROM $1);
END;
$$ LANGUAGE plpgsql STABLE STRICT;

DROP FUNCTION sparql.describe(text, text, boolean, text);
CREATE FUNCTION sparql.describe(server text, query text, base_uri text DEFAULT '')
RETURNS SETOF triple AS 'MODULE_PATHNAME', 'rdf_fdw_describe'
LANGUAGE C IMMUTABLE STRICT;
COMMENT ON FUNCTION sparql.describe(text,text,text) IS 'Gateway for DESCRIBE SPARQL queries';

/* Drop deprecated functions */
DROP FUNCTION IF EXISTS sparql.regex(rdfnode, rdfnode);
DROP FUNCTION IF EXISTS sparql.regex(rdfnode, rdfnode, rdfnode);