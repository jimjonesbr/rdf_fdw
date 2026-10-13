/* New in 3.1: sparql.replace() returns NULL for an IRI or a blank node, as
   SPARQL leaves REPLACE unbound for them, instead of raising an error. */
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
    RETURN NULL;
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
     lexical form to rewrite, which is a type error SPARQL leaves unbound. */
  IF sparql.isIRI($1) THEN
    RETURN NULL;
  END IF;
  IF sparql.isblank($1) THEN
    RETURN NULL;
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
     lexical form to rewrite, which is a type error SPARQL leaves unbound. */
  IF sparql.isIRI($1) THEN
    RETURN NULL;
  END IF;
  IF sparql.isblank($1) THEN
    RETURN NULL;
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
