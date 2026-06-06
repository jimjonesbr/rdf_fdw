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