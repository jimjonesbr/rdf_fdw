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

/* casts, functions, and operators */
CREATE FUNCTION rdf_literal_in(cstring) RETURNS rdf_literal
AS 'MODULE_PATHNAME', 'rdf_literal_in'
LANGUAGE C IMMUTABLE STRICT;

CREATE FUNCTION rdf_literal_out(rdf_literal) RETURNS cstring
AS 'MODULE_PATHNAME', 'rdf_literal_out'
LANGUAGE C IMMUTABLE STRICT;

CREATE TYPE rdf_literal (
  INTERNALLENGTH = VARIABLE,
  INPUT = rdf_literal_in,
  OUTPUT = rdf_literal_out,
  STORAGE = EXTENDED
);

CREATE FUNCTION rdf_literal_eq_rdf_literal(rdf_literal, rdf_literal)
RETURNS boolean
AS 'MODULE_PATHNAME', 'rdf_literal_eq_rdf_literal'
LANGUAGE C IMMUTABLE STRICT;

CREATE OPERATOR = (
  LEFTARG = rdf_literal,
  RIGHTARG = rdf_literal,
  PROCEDURE = rdf_literal_eq_rdf_literal,
  COMMUTATOR = '=',
  NEGATOR = '<>',
  RESTRICT = eqsel,
  JOIN = eqjoinsel
);

CREATE FUNCTION rdf_literal_neq_rdf_literal(rdf_literal, rdf_literal)
RETURNS boolean
AS 'MODULE_PATHNAME', 'rdf_literal_neq_rdf_literal'
LANGUAGE C IMMUTABLE STRICT;

CREATE OPERATOR <> (
    LEFTARG = rdf_literal,
    RIGHTARG = rdf_literal,
    PROCEDURE = rdf_literal_neq_rdf_literal,
    COMMUTATOR = '<>',
    NEGATOR = '=',
    RESTRICT = neqsel,
    JOIN = neqjoinsel
);

CREATE FUNCTION rdf_literal_lt_rdf_literal(rdf_literal, rdf_literal)
RETURNS boolean
AS 'MODULE_PATHNAME', 'rdf_literal_lt_rdf_literal'
LANGUAGE C IMMUTABLE STRICT;

CREATE OPERATOR < (
    LEFTARG = rdf_literal,
    RIGHTARG = rdf_literal,
    PROCEDURE = rdf_literal_lt_rdf_literal,
    COMMUTATOR = '>',
    RESTRICT = scalarltsel
);

CREATE FUNCTION rdf_literal_gt_rdf_literal(rdf_literal, rdf_literal)
RETURNS boolean
AS 'MODULE_PATHNAME', 'rdf_literal_gt_rdf_literal'
LANGUAGE C IMMUTABLE STRICT;

CREATE OPERATOR > (
    LEFTARG = rdf_literal,
    RIGHTARG = rdf_literal,
    PROCEDURE = rdf_literal_gt_rdf_literal,
    COMMUTATOR = '<',
    RESTRICT = scalargtsel
);

CREATE FUNCTION rdf_literal_le_rdf_literal(rdf_literal, rdf_literal)
RETURNS boolean
AS 'MODULE_PATHNAME', 'rdf_literal_le_rdf_literal'
LANGUAGE C IMMUTABLE STRICT;

CREATE OPERATOR <= (
    LEFTARG = rdf_literal,
    RIGHTARG = rdf_literal,
    PROCEDURE = rdf_literal_le_rdf_literal,
    COMMUTATOR = '>=',
    RESTRICT = scalarltsel
);

CREATE FUNCTION rdf_literal_ge_rdf_literal(rdf_literal, rdf_literal)
RETURNS boolean
AS 'MODULE_PATHNAME', 'rdf_literal_ge_rdf_literal'
LANGUAGE C IMMUTABLE STRICT;

CREATE OPERATOR >= (
    LEFTARG = rdf_literal,
    RIGHTARG = rdf_literal,
    PROCEDURE = rdf_literal_ge_rdf_literal,
    COMMUTATOR = '<=',
    RESTRICT = scalargtsel
);

/* rdf_literal OP numeric */
CREATE FUNCTION rdf_literal_eq_numeric(rdf_literal, numeric)
RETURNS boolean
AS 'MODULE_PATHNAME', 'rdf_literal_eq_numeric'
LANGUAGE C IMMUTABLE STRICT;

CREATE OPERATOR = (
    LEFTARG = rdf_literal,
    RIGHTARG = numeric,
    PROCEDURE = rdf_literal_eq_numeric,
    COMMUTATOR = '=',
    NEGATOR = '<>',
    RESTRICT = eqsel
);

CREATE FUNCTION rdf_literal_neq_numeric(rdf_literal, numeric)
RETURNS boolean
AS 'MODULE_PATHNAME', 'rdf_literal_neq_numeric'
LANGUAGE C IMMUTABLE STRICT;

CREATE OPERATOR <> (
    LEFTARG = rdf_literal,
    RIGHTARG = numeric,
    PROCEDURE = rdf_literal_neq_numeric,
    COMMUTATOR = '<>',
    NEGATOR = '=',
    RESTRICT = neqsel
);

CREATE FUNCTION rdf_literal_lt_numeric(rdf_literal, numeric)
RETURNS boolean
AS 'MODULE_PATHNAME', 'rdf_literal_lt_numeric'
LANGUAGE C IMMUTABLE STRICT;

CREATE OPERATOR < (
    LEFTARG = rdf_literal,
    RIGHTARG = numeric,
    PROCEDURE = rdf_literal_lt_numeric,
    COMMUTATOR = '>',
    RESTRICT = scalarltsel
);

CREATE FUNCTION rdf_literal_gt_numeric(rdf_literal, numeric)
RETURNS boolean
AS 'MODULE_PATHNAME', 'rdf_literal_gt_numeric'
LANGUAGE C IMMUTABLE STRICT;

CREATE OPERATOR > (
    LEFTARG = rdf_literal,
    RIGHTARG = numeric,
    PROCEDURE = rdf_literal_gt_numeric,
    COMMUTATOR = '<',
    RESTRICT = scalargtsel
);

CREATE FUNCTION rdf_literal_le_numeric(rdf_literal, numeric)
RETURNS boolean
AS 'MODULE_PATHNAME', 'rdf_literal_le_numeric'
LANGUAGE C IMMUTABLE STRICT;

CREATE OPERATOR <= (
    LEFTARG = rdf_literal,
    RIGHTARG = numeric,
    PROCEDURE = rdf_literal_le_numeric,
    COMMUTATOR = '>=',
    RESTRICT = scalarltsel
);

CREATE FUNCTION rdf_literal_ge_numeric(rdf_literal, numeric)
RETURNS boolean
AS 'MODULE_PATHNAME', 'rdf_literal_ge_numeric'
LANGUAGE C IMMUTABLE STRICT;

CREATE OPERATOR >= (
    LEFTARG = rdf_literal,
    RIGHTARG = numeric,
    PROCEDURE = rdf_literal_ge_numeric,
    COMMUTATOR = '<=',
    RESTRICT = scalargtsel
);

CREATE FUNCTION rdf_literal_to_numeric(rdf_literal)
RETURNS numeric
AS 'MODULE_PATHNAME', 'rdf_literal_to_numeric'
LANGUAGE C IMMUTABLE STRICT;

CREATE CAST (rdf_literal AS numeric) 
WITH FUNCTION rdf_literal_to_numeric(rdf_literal);

/* numeric OP rdf_literal */
CREATE FUNCTION numeric_to_rdf_literal(numeric)
RETURNS rdf_literal
AS 'MODULE_PATHNAME', 'numeric_to_rdf_literal'
LANGUAGE C IMMUTABLE STRICT;

CREATE CAST (numeric AS rdf_literal)
WITH FUNCTION numeric_to_rdf_literal(numeric);

CREATE FUNCTION numeric_eq_rdf_literal(numeric, rdf_literal)
RETURNS boolean
AS 'MODULE_PATHNAME', 'numeric_eq_rdf_literal'
LANGUAGE C IMMUTABLE STRICT;

CREATE OPERATOR = (
    LEFTARG = numeric,
    RIGHTARG = rdf_literal,
    PROCEDURE = numeric_eq_rdf_literal,
    COMMUTATOR = '=',
    NEGATOR = '<>',
    RESTRICT = eqsel
);

CREATE FUNCTION numeric_neq_rdf_literal(numeric, rdf_literal)
RETURNS boolean
AS 'MODULE_PATHNAME', 'numeric_neq_rdf_literal'
LANGUAGE C IMMUTABLE STRICT;

CREATE OPERATOR <> (
    LEFTARG = numeric,
    RIGHTARG = rdf_literal,
    PROCEDURE = numeric_neq_rdf_literal,
    COMMUTATOR = '<>',
    NEGATOR = '=',
    RESTRICT = neqsel
);

CREATE FUNCTION numeric_lt_rdf_literal(numeric, rdf_literal)
RETURNS boolean
AS 'MODULE_PATHNAME', 'numeric_lt_rdf_literal'
LANGUAGE C IMMUTABLE STRICT;

CREATE OPERATOR < (
    LEFTARG = numeric,
    RIGHTARG = rdf_literal,
    PROCEDURE = numeric_lt_rdf_literal,
    COMMUTATOR = '>',
    RESTRICT = scalarltsel
);

CREATE FUNCTION numeric_gt_rdf_literal(numeric, rdf_literal)
RETURNS boolean
AS 'MODULE_PATHNAME', 'numeric_gt_rdf_literal'
LANGUAGE C IMMUTABLE STRICT;

CREATE OPERATOR > (
    LEFTARG = numeric,
    RIGHTARG = rdf_literal,
    PROCEDURE = numeric_gt_rdf_literal,
    COMMUTATOR = '<',
    RESTRICT = scalargtsel
);

CREATE FUNCTION numeric_le_rdf_literal(numeric, rdf_literal)
RETURNS boolean
AS 'MODULE_PATHNAME', 'numeric_le_rdf_literal'
LANGUAGE C IMMUTABLE STRICT;

CREATE OPERATOR <= (
    LEFTARG = numeric,
    RIGHTARG = rdf_literal,
    PROCEDURE = numeric_le_rdf_literal,
    COMMUTATOR = '>=',
    RESTRICT = scalarltsel
);

CREATE FUNCTION numeric_ge_rdf_literal(numeric, rdf_literal)
RETURNS boolean
AS 'MODULE_PATHNAME', 'numeric_ge_rdf_literal'
LANGUAGE C IMMUTABLE STRICT;

CREATE OPERATOR >= (
    LEFTARG = numeric,
    RIGHTARG = rdf_literal,
    PROCEDURE = numeric_ge_rdf_literal,
    COMMUTATOR = '<=',
    RESTRICT = scalargtsel
);

/* rdf_literal OP float8 (double precision) */
CREATE FUNCTION rdf_literal_eq_float8(rdf_literal, float8)
RETURNS boolean
AS 'MODULE_PATHNAME', 'rdf_literal_eq_float8'
LANGUAGE C IMMUTABLE STRICT;

CREATE OPERATOR = (
    LEFTARG = rdf_literal,
    RIGHTARG = float8,
    PROCEDURE = rdf_literal_eq_float8,
    COMMUTATOR = '=',
    NEGATOR = '<>',
    RESTRICT = eqsel
);

CREATE FUNCTION rdf_literal_neq_float8(rdf_literal, float8)
RETURNS boolean
AS 'MODULE_PATHNAME', 'rdf_literal_neq_float8'
LANGUAGE C IMMUTABLE STRICT;

CREATE OPERATOR <> (
    LEFTARG = rdf_literal,
    RIGHTARG = float8,
    PROCEDURE = rdf_literal_neq_float8,
    COMMUTATOR = '<>',
    NEGATOR = '=',
    RESTRICT = neqsel
);

CREATE FUNCTION rdf_literal_lt_float8(rdf_literal, float8)
RETURNS boolean
AS 'MODULE_PATHNAME', 'rdf_literal_lt_float8'
LANGUAGE C IMMUTABLE STRICT;

CREATE OPERATOR < (
    LEFTARG = rdf_literal,
    RIGHTARG = float8,
    PROCEDURE = rdf_literal_lt_float8,
    COMMUTATOR = >,
    NEGATOR = >=,
    RESTRICT = scalarltsel
);

CREATE FUNCTION rdf_literal_gt_float8(rdf_literal, float8)
RETURNS boolean
AS 'MODULE_PATHNAME', 'rdf_literal_gt_float8'
LANGUAGE C IMMUTABLE STRICT;

CREATE OPERATOR > (
    LEFTARG = rdf_literal,
    RIGHTARG = float8,
    PROCEDURE = rdf_literal_gt_float8,
    COMMUTATOR = <,
    NEGATOR = <=,
    RESTRICT = scalargtsel
);

CREATE FUNCTION rdf_literal_le_float8(rdf_literal, float8)
RETURNS boolean
AS 'MODULE_PATHNAME', 'rdf_literal_le_float8'
LANGUAGE C IMMUTABLE STRICT;

CREATE OPERATOR <= (
    LEFTARG = rdf_literal,
    RIGHTARG = float8,
    PROCEDURE = rdf_literal_le_float8,
    COMMUTATOR = >=,
    NEGATOR = >,
    RESTRICT = scalarltsel
);

CREATE FUNCTION rdf_literal_ge_float8(rdf_literal, float8)
RETURNS boolean
AS 'MODULE_PATHNAME', 'rdf_literal_ge_float8'
LANGUAGE C IMMUTABLE STRICT;

CREATE OPERATOR >= (
    LEFTARG = rdf_literal,
    RIGHTARG = float8,
    PROCEDURE = rdf_literal_ge_float8,
    COMMUTATOR = <=,
    NEGATOR = <,
    RESTRICT = scalargtsel
);

CREATE FUNCTION rdf_literal_to_float8(rdf_literal)
RETURNS float8
AS 'MODULE_PATHNAME', 'rdf_literal_to_float8'
LANGUAGE C IMMUTABLE STRICT;

CREATE CAST (rdf_literal AS float8) 
WITH FUNCTION rdf_literal_to_float8(rdf_literal);

/* float8 OP rdf_literal  */
CREATE FUNCTION float8_eq_rdf_literal(float8, rdf_literal)
RETURNS boolean
AS 'MODULE_PATHNAME', 'float8_eq_rdf_literal'
LANGUAGE C IMMUTABLE STRICT;

CREATE OPERATOR = (
    LEFTARG = float8,
    RIGHTARG = rdf_literal,
    PROCEDURE = float8_eq_rdf_literal,
    COMMUTATOR = '=',
    NEGATOR = '<>',
    RESTRICT = eqsel
);

CREATE FUNCTION float8_neq_rdf_literal(float8, rdf_literal)
RETURNS boolean
AS 'MODULE_PATHNAME', 'float8_neq_rdf_literal'
LANGUAGE C IMMUTABLE STRICT;

CREATE OPERATOR <> (
    LEFTARG = float8,
    RIGHTARG = rdf_literal,
    PROCEDURE = float8_neq_rdf_literal,
    COMMUTATOR = '<>',
    NEGATOR = '=',
    RESTRICT = neqsel
);

CREATE FUNCTION float8_lt_rdf_literal(float8, rdf_literal)
RETURNS boolean
AS 'MODULE_PATHNAME', 'float8_lt_rdf_literal'
LANGUAGE C IMMUTABLE STRICT;

CREATE OPERATOR < (
    LEFTARG = float8,
    RIGHTARG = rdf_literal,
    PROCEDURE = float8_lt_rdf_literal,
    COMMUTATOR = >,
    NEGATOR = >=,
    RESTRICT = scalarltsel
);

CREATE FUNCTION float8_gt_rdf_literal(float8, rdf_literal)
RETURNS boolean
AS 'MODULE_PATHNAME', 'float8_gt_rdf_literal'
LANGUAGE C IMMUTABLE STRICT;

CREATE OPERATOR > (
    LEFTARG = float8,
    RIGHTARG = rdf_literal,
    PROCEDURE = float8_gt_rdf_literal,
    COMMUTATOR = <,
    NEGATOR = <=,
    RESTRICT = scalargtsel
);

CREATE FUNCTION float8_le_rdf_literal(float8, rdf_literal)
RETURNS boolean
AS 'MODULE_PATHNAME', 'float8_le_rdf_literal'
LANGUAGE C IMMUTABLE STRICT;

CREATE OPERATOR <= (
    LEFTARG = float8,
    RIGHTARG = rdf_literal,
    PROCEDURE = float8_le_rdf_literal,
    COMMUTATOR = >=,
    NEGATOR = >,
    RESTRICT = scalarltsel
);

CREATE FUNCTION float8_ge_rdf_literal(float8, rdf_literal)
RETURNS boolean
AS 'MODULE_PATHNAME', 'float8_ge_rdf_literal'
LANGUAGE C IMMUTABLE STRICT;

CREATE OPERATOR >= (
    LEFTARG = float8,
    RIGHTARG = rdf_literal,
    PROCEDURE = float8_ge_rdf_literal,
    COMMUTATOR = <=,
    NEGATOR = <,
    RESTRICT = scalargtsel
);

CREATE FUNCTION float8_to_rdf_literal(float8)
RETURNS rdf_literal
AS 'MODULE_PATHNAME', 'float8_to_rdf_literal'
LANGUAGE C IMMUTABLE STRICT;

CREATE CAST (float8 AS rdf_literal) 
WITH FUNCTION float8_to_rdf_literal(float8);

/* rdf_literal OP float4 (real) */
CREATE FUNCTION rdf_literal_to_float4(rdf_literal)
RETURNS float4
AS 'MODULE_PATHNAME', 'rdf_literal_to_float4'
LANGUAGE C IMMUTABLE STRICT;

CREATE CAST (rdf_literal AS float4) 
WITH FUNCTION rdf_literal_to_float4(rdf_literal)
AS IMPLICIT;

CREATE FUNCTION rdf_literal_eq_float4(rdf_literal, float4)
RETURNS boolean
AS 'MODULE_PATHNAME', 'rdf_literal_eq_float4'
LANGUAGE C IMMUTABLE STRICT;

CREATE OPERATOR = (
    LEFTARG = rdf_literal,
    RIGHTARG = float4,
    PROCEDURE = rdf_literal_eq_float4,
    COMMUTATOR = '=',
    NEGATOR = '<>',
    RESTRICT = eqsel
);

CREATE FUNCTION rdf_literal_neq_float4(rdf_literal, float4)
RETURNS boolean
AS 'MODULE_PATHNAME', 'rdf_literal_neq_float4'
LANGUAGE C IMMUTABLE STRICT;

CREATE OPERATOR <> (
    LEFTARG = rdf_literal,
    RIGHTARG = float4,
    PROCEDURE = rdf_literal_neq_float4,
    COMMUTATOR = '<>',
    NEGATOR = '=',
    RESTRICT = neqsel
);

CREATE FUNCTION rdf_literal_lt_float4(rdf_literal, float4)
RETURNS boolean
AS 'MODULE_PATHNAME', 'rdf_literal_lt_float4'
LANGUAGE C IMMUTABLE STRICT;

CREATE OPERATOR < (
    LEFTARG = rdf_literal,
    RIGHTARG = float4,
    PROCEDURE = rdf_literal_lt_float4,
    COMMUTATOR = >,
    NEGATOR = >=,
    RESTRICT = scalarltsel
);

CREATE FUNCTION rdf_literal_gt_float4(rdf_literal, float4)
RETURNS boolean
AS 'MODULE_PATHNAME', 'rdf_literal_gt_float4'
LANGUAGE C IMMUTABLE STRICT;

CREATE OPERATOR > (
    LEFTARG = rdf_literal,
    RIGHTARG = float4,
    PROCEDURE = rdf_literal_gt_float4,
    COMMUTATOR = <,
    NEGATOR = <=,
    RESTRICT = scalargtsel
);

CREATE FUNCTION rdf_literal_le_float4(rdf_literal, float4)
RETURNS boolean
AS 'MODULE_PATHNAME', 'rdf_literal_le_float4'
LANGUAGE C IMMUTABLE STRICT;

CREATE OPERATOR <= (
    LEFTARG = rdf_literal,
    RIGHTARG = float4,
    PROCEDURE = rdf_literal_le_float4,
    COMMUTATOR = >=,
    NEGATOR = >,
    RESTRICT = scalarltsel
);

CREATE FUNCTION rdf_literal_ge_float4(rdf_literal, float4)
RETURNS boolean
AS 'MODULE_PATHNAME', 'rdf_literal_ge_float4'
LANGUAGE C IMMUTABLE STRICT;

CREATE OPERATOR >= (
    LEFTARG = rdf_literal,
    RIGHTARG = float4,
    PROCEDURE = rdf_literal_ge_float4,
    COMMUTATOR = <=,
    NEGATOR = <,
    RESTRICT = scalargtsel
);

/* float4 (real) OP rdf_literal */
CREATE FUNCTION float4_to_rdf_literal(float4)
RETURNS rdf_literal
AS 'MODULE_PATHNAME', 'float4_to_rdf_literal'
LANGUAGE C IMMUTABLE STRICT;

CREATE CAST (float4 AS rdf_literal) 
WITH FUNCTION float4_to_rdf_literal(float4);

CREATE FUNCTION float4_eq_rdf_literal(float4, rdf_literal)
RETURNS boolean
AS 'MODULE_PATHNAME', 'float4_eq_rdf_literal'
LANGUAGE C IMMUTABLE STRICT;

CREATE OPERATOR = (
    LEFTARG = float4,
    RIGHTARG = rdf_literal,
    PROCEDURE = float4_eq_rdf_literal,
    COMMUTATOR = '=',
    NEGATOR = '<>',
    RESTRICT = eqsel
);

CREATE FUNCTION float4_neq_rdf_literal(float4, rdf_literal)
RETURNS boolean
AS 'MODULE_PATHNAME', 'float4_neq_rdf_literal'
LANGUAGE C IMMUTABLE STRICT;

CREATE OPERATOR <> (
    LEFTARG = float4,
    RIGHTARG = rdf_literal,
    PROCEDURE = float4_neq_rdf_literal,
    COMMUTATOR = '<>',
    NEGATOR = '=',
    RESTRICT = neqsel
);

CREATE FUNCTION float4_lt_rdf_literal(float4, rdf_literal)
RETURNS boolean
AS 'MODULE_PATHNAME', 'float4_lt_rdf_literal'
LANGUAGE C IMMUTABLE STRICT;

CREATE OPERATOR < (
    LEFTARG = float4,
    RIGHTARG = rdf_literal,
    PROCEDURE = float4_lt_rdf_literal,
    COMMUTATOR = >,
    NEGATOR = >=,
    RESTRICT = scalarltsel
);

CREATE FUNCTION float4_gt_rdf_literal(float4, rdf_literal)
RETURNS boolean
AS 'MODULE_PATHNAME', 'float4_gt_rdf_literal'
LANGUAGE C IMMUTABLE STRICT;

CREATE OPERATOR > (
    LEFTARG = float4,
    RIGHTARG = rdf_literal,
    PROCEDURE = float4_gt_rdf_literal,
    COMMUTATOR = <,
    NEGATOR = <=,
    RESTRICT = scalargtsel
);

CREATE FUNCTION float4_le_rdf_literal(float4, rdf_literal)
RETURNS boolean
AS 'MODULE_PATHNAME', 'float4_le_rdf_literal'
LANGUAGE C IMMUTABLE STRICT;

CREATE OPERATOR <= (
    LEFTARG = float4,
    RIGHTARG = rdf_literal,
    PROCEDURE = float4_le_rdf_literal,
    COMMUTATOR = >=,
    NEGATOR = >,
    RESTRICT = scalarltsel
);

CREATE FUNCTION float4_ge_rdf_literal(float4, rdf_literal)
RETURNS boolean
AS 'MODULE_PATHNAME', 'float4_ge_rdf_literal'
LANGUAGE C IMMUTABLE STRICT;

CREATE OPERATOR >= (
    LEFTARG = float4,
    RIGHTARG = rdf_literal,
    PROCEDURE = float4_ge_rdf_literal,
    COMMUTATOR = <=,
    NEGATOR = <,
    RESTRICT = scalargtsel
);

/* rdf_literal OP int8 (bigint) */
CREATE FUNCTION rdf_literal_to_int8(rdf_literal)
RETURNS bigint
AS 'MODULE_PATHNAME', 'rdf_literal_to_int8'
LANGUAGE C IMMUTABLE STRICT;

CREATE CAST (rdf_literal AS bigint)
WITH FUNCTION rdf_literal_to_int8(rdf_literal);

CREATE FUNCTION rdf_literal_eq_int8(rdf_literal, int8)
RETURNS boolean
AS 'MODULE_PATHNAME', 'rdf_literal_eq_int8'
LANGUAGE C IMMUTABLE STRICT;

CREATE OPERATOR = (
    LEFTARG = rdf_literal,
    RIGHTARG = int8,
    PROCEDURE = rdf_literal_eq_int8,
    COMMUTATOR = '=',
    NEGATOR = '<>',
    RESTRICT = eqsel
);

CREATE FUNCTION rdf_literal_neq_int8(rdf_literal, int8)
RETURNS boolean
AS 'MODULE_PATHNAME', 'rdf_literal_neq_int8'
LANGUAGE C IMMUTABLE STRICT;

CREATE OPERATOR <> (
    LEFTARG = rdf_literal,
    RIGHTARG = int8,
    PROCEDURE = rdf_literal_neq_int8,
    COMMUTATOR = '<>',
    NEGATOR = '=',
    RESTRICT = neqsel
);

CREATE FUNCTION rdf_literal_lt_int8(rdf_literal, int8)
RETURNS boolean
AS 'MODULE_PATHNAME', 'rdf_literal_lt_int8'
LANGUAGE C IMMUTABLE STRICT;

CREATE OPERATOR < (
    LEFTARG = rdf_literal,
    RIGHTARG = int8,
    PROCEDURE = rdf_literal_lt_int8,
    COMMUTATOR = >,
    NEGATOR = >=,
    RESTRICT = scalarltsel
);

CREATE FUNCTION rdf_literal_gt_int8(rdf_literal, int8)
RETURNS boolean
AS 'MODULE_PATHNAME', 'rdf_literal_gt_int8'
LANGUAGE C IMMUTABLE STRICT;

CREATE OPERATOR > (
    LEFTARG = rdf_literal,
    RIGHTARG = int8,
    PROCEDURE = rdf_literal_gt_int8,
    COMMUTATOR = <,
    NEGATOR = <=,
    RESTRICT = scalargtsel
);

CREATE FUNCTION rdf_literal_le_int8(rdf_literal, int8)
RETURNS boolean
AS 'MODULE_PATHNAME', 'rdf_literal_le_int8'
LANGUAGE C IMMUTABLE STRICT;

CREATE OPERATOR <= (
    LEFTARG = rdf_literal,
    RIGHTARG = int8,
    PROCEDURE = rdf_literal_le_int8,
    COMMUTATOR = >=,
    NEGATOR = >,
    RESTRICT = scalarltsel
);

CREATE FUNCTION rdf_literal_ge_int8(rdf_literal, int8)
RETURNS boolean
AS 'MODULE_PATHNAME', 'rdf_literal_ge_int8'
LANGUAGE C IMMUTABLE STRICT;

CREATE OPERATOR >= (
    LEFTARG = rdf_literal,
    RIGHTARG = int8,
    PROCEDURE = rdf_literal_ge_int8,
    COMMUTATOR = <=,
    NEGATOR = <,
    RESTRICT = scalargtsel
);


/* int8 OP rdf_literal */

CREATE FUNCTION int8_to_rdf_literal(bigint)
RETURNS rdf_literal
AS 'MODULE_PATHNAME', 'int8_to_rdf_literal'
LANGUAGE C IMMUTABLE STRICT;

CREATE CAST (bigint AS rdf_literal)
WITH FUNCTION int8_to_rdf_literal(bigint);

CREATE FUNCTION int8_eq_rdf_literal(int8, rdf_literal)
RETURNS boolean
AS 'MODULE_PATHNAME', 'int8_eq_rdf_literal'
LANGUAGE C IMMUTABLE STRICT;

CREATE OPERATOR = (
    LEFTARG = int8,
    RIGHTARG = rdf_literal,
    PROCEDURE = int8_eq_rdf_literal,
    COMMUTATOR = '=',
    NEGATOR = '<>',
    RESTRICT = eqsel
);

CREATE FUNCTION int8_neq_rdf_literal(int8, rdf_literal)
RETURNS boolean
AS 'MODULE_PATHNAME', 'int8_neq_rdf_literal'
LANGUAGE C IMMUTABLE STRICT;

CREATE OPERATOR <> (
    LEFTARG = int8,
    RIGHTARG = rdf_literal,
    PROCEDURE = int8_neq_rdf_literal,
    COMMUTATOR = '<>',
    NEGATOR = '=',
    RESTRICT = neqsel
);

CREATE FUNCTION int8_lt_rdf_literal(int8, rdf_literal)
RETURNS boolean
AS 'MODULE_PATHNAME', 'int8_lt_rdf_literal'
LANGUAGE C IMMUTABLE STRICT;

CREATE OPERATOR < (
    LEFTARG = int8,
    RIGHTARG = rdf_literal,
    PROCEDURE = int8_lt_rdf_literal,
    COMMUTATOR = >,
    NEGATOR = >=,
    RESTRICT = scalarltsel
);

CREATE FUNCTION int8_gt_rdf_literal(int8, rdf_literal)
RETURNS boolean
AS 'MODULE_PATHNAME', 'int8_gt_rdf_literal'
LANGUAGE C IMMUTABLE STRICT;

CREATE OPERATOR > (
    LEFTARG = int8,
    RIGHTARG = rdf_literal,
    PROCEDURE = int8_gt_rdf_literal,
    COMMUTATOR = <,
    NEGATOR = <=,
    RESTRICT = scalargtsel
);

CREATE FUNCTION int8_le_rdf_literal(int8, rdf_literal)
RETURNS boolean
AS 'MODULE_PATHNAME', 'int8_le_rdf_literal'
LANGUAGE C IMMUTABLE STRICT;

CREATE OPERATOR <= (
    LEFTARG = int8,
    RIGHTARG = rdf_literal,
    PROCEDURE = int8_le_rdf_literal,
    COMMUTATOR = >=,
    NEGATOR = >,
    RESTRICT = scalarltsel
);

CREATE FUNCTION int8_ge_rdf_literal(int8, rdf_literal)
RETURNS boolean
AS 'MODULE_PATHNAME', 'int8_ge_rdf_literal'
LANGUAGE C IMMUTABLE STRICT;

CREATE OPERATOR >= (
    LEFTARG = int8,
    RIGHTARG = rdf_literal,
    PROCEDURE = int8_ge_rdf_literal,
    COMMUTATOR = <=,
    NEGATOR = <,
    RESTRICT = scalargtsel
);

/* rdf_literal OP int4 (int) */
CREATE FUNCTION rdf_literal_to_int4(rdf_literal)
RETURNS int
AS 'MODULE_PATHNAME', 'rdf_literal_to_int4'
LANGUAGE C IMMUTABLE STRICT;

CREATE CAST (rdf_literal AS int)
WITH FUNCTION rdf_literal_to_int4(rdf_literal) 
AS IMPLICIT;

CREATE FUNCTION rdf_literal_eq_int4(rdf_literal, int4)
RETURNS boolean
AS 'MODULE_PATHNAME', 'rdf_literal_eq_int4'
LANGUAGE C IMMUTABLE STRICT;

CREATE OPERATOR = (
    LEFTARG = rdf_literal,
    RIGHTARG = int4,
    PROCEDURE = rdf_literal_eq_int4,
    COMMUTATOR = '=',
    NEGATOR = '<>',
    RESTRICT = eqsel
);

CREATE FUNCTION rdf_literal_neq_int4(rdf_literal, int4)
RETURNS boolean
AS 'MODULE_PATHNAME', 'rdf_literal_neq_int4'
LANGUAGE C IMMUTABLE STRICT;

CREATE OPERATOR <> (
    LEFTARG = rdf_literal,
    RIGHTARG = int4,
    PROCEDURE = rdf_literal_neq_int4,
    COMMUTATOR = '<>',
    NEGATOR = '=',
    RESTRICT = neqsel
);

CREATE FUNCTION rdf_literal_lt_int4(rdf_literal, int4)
RETURNS boolean
AS 'MODULE_PATHNAME', 'rdf_literal_lt_int4'
LANGUAGE C IMMUTABLE STRICT;

CREATE OPERATOR < (
    LEFTARG = rdf_literal,
    RIGHTARG = int4,
    PROCEDURE = rdf_literal_lt_int4,
    COMMUTATOR = >,
    NEGATOR = >=,
    RESTRICT = scalarltsel
);

CREATE FUNCTION rdf_literal_gt_int4(rdf_literal, int4)
RETURNS boolean
AS 'MODULE_PATHNAME', 'rdf_literal_gt_int4'
LANGUAGE C IMMUTABLE STRICT;

CREATE OPERATOR > (
    LEFTARG = rdf_literal,
    RIGHTARG = int4,
    PROCEDURE = rdf_literal_gt_int4,
    COMMUTATOR = <,
    NEGATOR = <=,
    RESTRICT = scalargtsel
);

CREATE FUNCTION rdf_literal_le_int4(rdf_literal, int4)
RETURNS boolean
AS 'MODULE_PATHNAME', 'rdf_literal_le_int4'
LANGUAGE C IMMUTABLE STRICT;

CREATE OPERATOR <= (
    LEFTARG = rdf_literal,
    RIGHTARG = int4,
    PROCEDURE = rdf_literal_le_int4,
    COMMUTATOR = >=,
    NEGATOR = >,
    RESTRICT = scalarltsel
);

CREATE FUNCTION rdf_literal_ge_int4(rdf_literal, int4)
RETURNS boolean
AS 'MODULE_PATHNAME', 'rdf_literal_ge_int4'
LANGUAGE C IMMUTABLE STRICT;

CREATE OPERATOR >= (
    LEFTARG = rdf_literal,
    RIGHTARG = int4,
    PROCEDURE = rdf_literal_ge_int4,
    COMMUTATOR = <=,
    NEGATOR = <,
    RESTRICT = scalargtsel
);


/* int4 (int) OP rdf_literal */
CREATE FUNCTION int4_to_rdf_literal(int)
RETURNS rdf_literal
AS 'MODULE_PATHNAME', 'int4_to_rdf_literal'
LANGUAGE C IMMUTABLE STRICT;

CREATE CAST (int AS rdf_literal)
WITH FUNCTION int4_to_rdf_literal(int);

CREATE FUNCTION int4_eq_rdf_literal(int4, rdf_literal)
RETURNS boolean
AS 'MODULE_PATHNAME', 'int4_eq_rdf_literal'
LANGUAGE C IMMUTABLE STRICT;

CREATE OPERATOR = (
    LEFTARG = int4,
    RIGHTARG = rdf_literal,
    PROCEDURE = int4_eq_rdf_literal,
    COMMUTATOR = '=',
    NEGATOR = '<>',
    RESTRICT = eqsel
);

CREATE FUNCTION int4_neq_rdf_literal(int4, rdf_literal)
RETURNS boolean
AS 'MODULE_PATHNAME', 'int4_neq_rdf_literal'
LANGUAGE C IMMUTABLE STRICT;

CREATE OPERATOR <> (
    LEFTARG = int4,
    RIGHTARG = rdf_literal,
    PROCEDURE = int4_neq_rdf_literal,
    COMMUTATOR = '<>',
    NEGATOR = '=',
    RESTRICT = neqsel
);

CREATE FUNCTION int4_lt_rdf_literal(int4, rdf_literal)
RETURNS boolean
AS 'MODULE_PATHNAME', 'int4_lt_rdf_literal'
LANGUAGE C IMMUTABLE STRICT;

CREATE OPERATOR < (
    LEFTARG = int4,
    RIGHTARG = rdf_literal,
    PROCEDURE = int4_lt_rdf_literal,
    COMMUTATOR = >,
    NEGATOR = >=,
    RESTRICT = scalarltsel
);

CREATE FUNCTION int4_gt_rdf_literal(int4, rdf_literal)
RETURNS boolean
AS 'MODULE_PATHNAME', 'int4_gt_rdf_literal'
LANGUAGE C IMMUTABLE STRICT;

CREATE OPERATOR > (
    LEFTARG = int4,
    RIGHTARG = rdf_literal,
    PROCEDURE = int4_gt_rdf_literal,
    COMMUTATOR = <,
    NEGATOR = <=,
    RESTRICT = scalargtsel
);

CREATE FUNCTION int4_le_rdf_literal(int4, rdf_literal)
RETURNS boolean
AS 'MODULE_PATHNAME', 'int4_le_rdf_literal'
LANGUAGE C IMMUTABLE STRICT;

CREATE OPERATOR <= (
    LEFTARG = int4,
    RIGHTARG = rdf_literal,
    PROCEDURE = int4_le_rdf_literal,
    COMMUTATOR = >=,
    NEGATOR = >,
    RESTRICT = scalarltsel
);

CREATE FUNCTION int4_ge_rdf_literal(int4, rdf_literal)
RETURNS boolean
AS 'MODULE_PATHNAME', 'int4_ge_rdf_literal'
LANGUAGE C IMMUTABLE STRICT;

CREATE OPERATOR >= (
    LEFTARG = int4,
    RIGHTARG = rdf_literal,
    PROCEDURE = int4_ge_rdf_literal,
    COMMUTATOR = <=,
    NEGATOR = <,
    RESTRICT = scalargtsel
);

/* rdf_literal OP int2 (smallint) */
CREATE FUNCTION rdf_literal_to_int2(rdf_literal)
RETURNS smallint
AS 'MODULE_PATHNAME', 'rdf_literal_to_int2'
LANGUAGE C IMMUTABLE STRICT;

CREATE CAST (rdf_literal AS smallint)
WITH FUNCTION rdf_literal_to_int2(rdf_literal) 
AS IMPLICIT;

CREATE FUNCTION rdf_literal_eq_int2(rdf_literal, int2)
RETURNS boolean
AS 'MODULE_PATHNAME', 'rdf_literal_eq_int2'
LANGUAGE C IMMUTABLE STRICT;

CREATE OPERATOR = (
    LEFTARG = rdf_literal,
    RIGHTARG = int2,
    PROCEDURE = rdf_literal_eq_int2,
    COMMUTATOR = '=',
    NEGATOR = '<>',
    RESTRICT = eqsel
);

CREATE FUNCTION rdf_literal_neq_int2(rdf_literal, int2)
RETURNS boolean
AS 'MODULE_PATHNAME', 'rdf_literal_neq_int2'
LANGUAGE C IMMUTABLE STRICT;

CREATE OPERATOR <> (
    LEFTARG = rdf_literal,
    RIGHTARG = int2,
    PROCEDURE = rdf_literal_neq_int2,
    COMMUTATOR = '<>',
    NEGATOR = '=',
    RESTRICT = neqsel
);

CREATE FUNCTION rdf_literal_lt_int2(rdf_literal, int2)
RETURNS boolean
AS 'MODULE_PATHNAME', 'rdf_literal_lt_int2'
LANGUAGE C IMMUTABLE STRICT;

CREATE OPERATOR < (
    LEFTARG = rdf_literal,
    RIGHTARG = int2,
    PROCEDURE = rdf_literal_lt_int2,
    COMMUTATOR = >,
    NEGATOR = >=,
    RESTRICT = scalarltsel
);

CREATE FUNCTION rdf_literal_gt_int2(rdf_literal, int2)
RETURNS boolean
AS 'MODULE_PATHNAME', 'rdf_literal_gt_int2'
LANGUAGE C IMMUTABLE STRICT;

CREATE OPERATOR > (
    LEFTARG = rdf_literal,
    RIGHTARG = int2,
    PROCEDURE = rdf_literal_gt_int2,
    COMMUTATOR = <,
    NEGATOR = <=,
    RESTRICT = scalargtsel
);

CREATE FUNCTION rdf_literal_le_int2(rdf_literal, int2)
RETURNS boolean
AS 'MODULE_PATHNAME', 'rdf_literal_le_int2'
LANGUAGE C IMMUTABLE STRICT;

CREATE OPERATOR <= (
    LEFTARG = rdf_literal,
    RIGHTARG = int2,
    PROCEDURE = rdf_literal_le_int2,
    COMMUTATOR = >=,
    NEGATOR = >,
    RESTRICT = scalarltsel
);

CREATE FUNCTION rdf_literal_ge_int2(rdf_literal, int2)
RETURNS boolean
AS 'MODULE_PATHNAME', 'rdf_literal_ge_int2'
LANGUAGE C IMMUTABLE STRICT;

CREATE OPERATOR >= (
    LEFTARG = rdf_literal,
    RIGHTARG = int2,
    PROCEDURE = rdf_literal_ge_int2,
    COMMUTATOR = <=,
    NEGATOR = <,
    RESTRICT = scalargtsel
);


/* int2 (smallint) OP rdf_literal */
CREATE FUNCTION int2_to_rdf_literal(smallint)
RETURNS rdf_literal
AS 'MODULE_PATHNAME', 'int2_to_rdf_literal'
LANGUAGE C IMMUTABLE STRICT;

CREATE CAST (smallint AS rdf_literal)
WITH FUNCTION int2_to_rdf_literal(smallint) 
AS IMPLICIT;

CREATE FUNCTION int2_eq_rdf_literal(int2, rdf_literal)
RETURNS boolean
AS 'MODULE_PATHNAME', 'int2_eq_rdf_literal'
LANGUAGE C IMMUTABLE STRICT;

CREATE OPERATOR = (
    LEFTARG = int2,
    RIGHTARG = rdf_literal,
    PROCEDURE = int2_eq_rdf_literal,
    COMMUTATOR = '=',
    NEGATOR = '<>',
    RESTRICT = eqsel
);

CREATE FUNCTION int2_neq_rdf_literal(int2, rdf_literal)
RETURNS boolean
AS 'MODULE_PATHNAME', 'int2_neq_rdf_literal'
LANGUAGE C IMMUTABLE STRICT;

CREATE OPERATOR <> (
    LEFTARG = int2,
    RIGHTARG = rdf_literal,
    PROCEDURE = int2_neq_rdf_literal,
    COMMUTATOR = '<>',
    NEGATOR = '=',
    RESTRICT = neqsel
);

CREATE FUNCTION int2_lt_rdf_literal(int2, rdf_literal)
RETURNS boolean
AS 'MODULE_PATHNAME', 'int2_lt_rdf_literal'
LANGUAGE C IMMUTABLE STRICT;

CREATE OPERATOR < (
    LEFTARG = int2,
    RIGHTARG = rdf_literal,
    PROCEDURE = int2_lt_rdf_literal,
    COMMUTATOR = >,
    NEGATOR = >=,
    RESTRICT = scalarltsel
);

CREATE FUNCTION int2_gt_rdf_literal(int2, rdf_literal)
RETURNS boolean
AS 'MODULE_PATHNAME', 'int2_gt_rdf_literal'
LANGUAGE C IMMUTABLE STRICT;

CREATE OPERATOR > (
    LEFTARG = int2,
    RIGHTARG = rdf_literal,
    PROCEDURE = int2_gt_rdf_literal,
    COMMUTATOR = <,
    NEGATOR = <=,
    RESTRICT = scalargtsel
);

CREATE FUNCTION int2_le_rdf_literal(int2, rdf_literal)
RETURNS boolean
AS 'MODULE_PATHNAME', 'int2_le_rdf_literal'
LANGUAGE C IMMUTABLE STRICT;

CREATE OPERATOR <= (
    LEFTARG = int2,
    RIGHTARG = rdf_literal,
    PROCEDURE = int2_le_rdf_literal,
    COMMUTATOR = >=,
    NEGATOR = >,
    RESTRICT = scalarltsel
);

CREATE FUNCTION int2_ge_rdf_literal(int2, rdf_literal)
RETURNS boolean
AS 'MODULE_PATHNAME', 'int2_ge_rdf_literal'
LANGUAGE C IMMUTABLE STRICT;

CREATE OPERATOR >= (
    LEFTARG = int2,
    RIGHTARG = rdf_literal,
    PROCEDURE = int2_ge_rdf_literal,
    COMMUTATOR = <=,
    NEGATOR = <,
    RESTRICT = scalargtsel
);

-- rdf_literal OP timestamptz (timestamp with time zone)
CREATE FUNCTION rdf_literal_to_timestamptz(rdf_literal)
RETURNS timestamptz
AS 'MODULE_PATHNAME', 'rdf_literal_to_timestamptz'
LANGUAGE C IMMUTABLE STRICT;

CREATE CAST (rdf_literal AS timestamptz)
WITH FUNCTION rdf_literal_to_timestamptz(rdf_literal);

CREATE FUNCTION rdf_literal_lt_timestamptz(rdf_literal, timestamptz)
RETURNS boolean LANGUAGE SQL IMMUTABLE AS
$$ SELECT rdf_literal_to_timestamptz($1) < $2; $$;

CREATE OPERATOR < (
    LEFTARG = rdf_literal,
    RIGHTARG = timestamptz,
    PROCEDURE = rdf_literal_lt_timestamptz,
    COMMUTATOR = >,
    NEGATOR = >=,
    RESTRICT = scalarltsel
);

CREATE FUNCTION rdf_literal_gt_timestamptz(rdf_literal, timestamptz)
RETURNS boolean LANGUAGE SQL IMMUTABLE AS
$$ SELECT rdf_literal_to_timestamptz($1) > $2; $$;

CREATE OPERATOR > (
    LEFTARG = rdf_literal,
    RIGHTARG = timestamptz,
    PROCEDURE = rdf_literal_gt_timestamptz,
    COMMUTATOR = <,
    NEGATOR = <=,
    RESTRICT = scalargtsel
);

CREATE FUNCTION rdf_literal_le_timestamptz(rdf_literal, timestamptz)
RETURNS boolean LANGUAGE SQL IMMUTABLE AS
$$ SELECT rdf_literal_to_timestamptz($1) <= $2; $$;

CREATE OPERATOR <= (
    LEFTARG = rdf_literal,
    RIGHTARG = timestamptz,
    PROCEDURE = rdf_literal_le_timestamptz,
    COMMUTATOR = >=,
    NEGATOR = >,
    RESTRICT = scalarltsel
);

CREATE FUNCTION rdf_literal_ge_timestamptz(rdf_literal, timestamptz)
RETURNS boolean LANGUAGE SQL IMMUTABLE AS
$$ SELECT rdf_literal_to_timestamptz($1) >= $2; $$;

CREATE OPERATOR >= (
    LEFTARG = rdf_literal,
    RIGHTARG = timestamptz,
    PROCEDURE = rdf_literal_ge_timestamptz,
    COMMUTATOR = <=,
    NEGATOR = <,
    RESTRICT = scalargtsel
);

CREATE FUNCTION rdf_literal_eq_timestamptz(rdf_literal, timestamptz)
RETURNS boolean LANGUAGE SQL IMMUTABLE AS
$$ SELECT rdf_literal_to_timestamptz($1) = $2; $$;

CREATE OPERATOR = (
    LEFTARG = rdf_literal,
    RIGHTARG = timestamptz,
    PROCEDURE = rdf_literal_eq_timestamptz,
    COMMUTATOR = '=',
    NEGATOR = '<>',
    RESTRICT = eqsel
);

CREATE FUNCTION rdf_literal_neq_timestamptz(rdf_literal, timestamptz)
RETURNS boolean LANGUAGE SQL IMMUTABLE AS
$$ SELECT rdf_literal_to_timestamptz($1) <> $2; $$;

CREATE OPERATOR <> (
    LEFTARG = rdf_literal,
    RIGHTARG = timestamptz,
    PROCEDURE = rdf_literal_neq_timestamptz,
    COMMUTATOR = '<>',
    NEGATOR = '=',
    RESTRICT = neqsel
);


-- timestamptz (timestamp with time zone) OP rdf_literal
CREATE FUNCTION timestamptz_to_rdf_literal(timestamptz)
RETURNS rdf_literal
AS 'MODULE_PATHNAME', 'timestamptz_to_rdf_literal'
LANGUAGE C IMMUTABLE STRICT;

CREATE CAST (timestamptz AS rdf_literal)
WITH FUNCTION timestamptz_to_rdf_literal(timestamptz);

CREATE FUNCTION timestamptz_lt_rdf_literal(timestamptz, rdf_literal)
RETURNS boolean LANGUAGE SQL IMMUTABLE AS
$$ SELECT $1 < rdf_literal_to_timestamptz($2); $$;

CREATE OPERATOR < (
    LEFTARG = timestamptz,
    RIGHTARG = rdf_literal,
    PROCEDURE = timestamptz_lt_rdf_literal,
    COMMUTATOR = >,
    NEGATOR = >=,
    RESTRICT = scalarltsel
);

CREATE FUNCTION timestamptz_gt_rdf_literal(timestamptz, rdf_literal)
RETURNS boolean LANGUAGE SQL IMMUTABLE AS
$$ SELECT $1 > rdf_literal_to_timestamptz($2); $$;

CREATE OPERATOR > (
    LEFTARG = timestamptz,
    RIGHTARG = rdf_literal,
    PROCEDURE = timestamptz_gt_rdf_literal,
    COMMUTATOR = <,
    NEGATOR = <=,
    RESTRICT = scalargtsel
);

CREATE FUNCTION timestamptz_le_rdf_literal(timestamptz, rdf_literal)
RETURNS boolean LANGUAGE SQL IMMUTABLE AS
$$ SELECT $1 <= rdf_literal_to_timestamptz($2); $$;

CREATE OPERATOR <= (
    LEFTARG = timestamptz,
    RIGHTARG = rdf_literal,
    PROCEDURE = timestamptz_le_rdf_literal,
    COMMUTATOR = >=,
    NEGATOR = >,
    RESTRICT = scalarltsel
);

CREATE FUNCTION timestamptz_ge_rdf_literal(timestamptz, rdf_literal)
RETURNS boolean LANGUAGE SQL IMMUTABLE AS
$$ SELECT $1 >= rdf_literal_to_timestamptz($2); $$;

CREATE OPERATOR >= (
    LEFTARG = timestamptz,
    RIGHTARG = rdf_literal,
    PROCEDURE = timestamptz_ge_rdf_literal,
    COMMUTATOR = <=,
    NEGATOR = <,
    RESTRICT = scalargtsel
);

CREATE FUNCTION timestamptz_eq_rdf_literal(timestamptz, rdf_literal)
RETURNS boolean LANGUAGE SQL IMMUTABLE AS
$$ SELECT $1 = rdf_literal_to_timestamptz($2); $$;

CREATE OPERATOR = (
    LEFTARG = timestamptz,
    RIGHTARG = rdf_literal,
    PROCEDURE = timestamptz_eq_rdf_literal,
    COMMUTATOR = '=',
    NEGATOR = '<>',
    RESTRICT = eqsel
);

CREATE FUNCTION timestamptz_neq_rdf_literal(timestamptz, rdf_literal)
RETURNS boolean LANGUAGE SQL IMMUTABLE AS
$$ SELECT $1 <> rdf_literal_to_timestamptz($2); $$;

CREATE OPERATOR <> (
    LEFTARG = timestamptz,
    RIGHTARG = rdf_literal,
    PROCEDURE = timestamptz_neq_rdf_literal,
    COMMUTATOR = '<>',
    NEGATOR = '=',
    RESTRICT = neqsel
);

/* rdf_literal OP timestamp (without time zone) */
CREATE FUNCTION rdf_literal_to_timestamp(rdf_literal)
RETURNS timestamp
AS 'MODULE_PATHNAME', 'rdf_literal_to_timestamp'
LANGUAGE C IMMUTABLE STRICT;

CREATE CAST (rdf_literal AS timestamp)
WITH FUNCTION rdf_literal_to_timestamp(rdf_literal) 
AS IMPLICIT;

-- CREATE FUNCTION rdf_literal_eq_timestamp(rdf_literal, timestamp)
-- RETURNS boolean
-- AS 'MODULE_PATHNAME', 'rdf_literal_eq_timestamp'
-- LANGUAGE C IMMUTABLE STRICT;

CREATE FUNCTION rdf_literal_eq_timestamp(rdf_literal, timestamp)
RETURNS boolean LANGUAGE SQL IMMUTABLE AS
$$ SELECT rdf_literal_to_timestamp($1) = $2; $$;

CREATE OPERATOR = (
    LEFTARG = rdf_literal,
    RIGHTARG = timestamp,
    PROCEDURE = rdf_literal_eq_timestamp,
    COMMUTATOR = '=',
    NEGATOR = '<>',
    RESTRICT = eqsel
);

-- CREATE FUNCTION rdf_literal_neq_timestamp(rdf_literal, timestamp)
-- RETURNS boolean
-- AS 'MODULE_PATHNAME', 'rdf_literal_neq_timestamp'
-- LANGUAGE C IMMUTABLE STRICT;

CREATE FUNCTION rdf_literal_neq_timestamp(rdf_literal, timestamp)
RETURNS boolean LANGUAGE SQL IMMUTABLE AS
$$ SELECT rdf_literal_to_timestamp($1) <> $2; $$;

CREATE OPERATOR <> (
    LEFTARG = rdf_literal,
    RIGHTARG = timestamp,
    PROCEDURE = rdf_literal_neq_timestamp,
    COMMUTATOR = '<>',
    NEGATOR = '=',
    RESTRICT = neqsel
);

--CREATE FUNCTION rdf_literal_lt_timestamp(rdf_literal, timestamp)
--RETURNS boolean
--AS 'MODULE_PATHNAME', 'rdf_literal_lt_timestamp'
--LANGUAGE C IMMUTABLE STRICT;

CREATE FUNCTION rdf_literal_lt_timestamp(rdf_literal, timestamp)
RETURNS boolean LANGUAGE SQL IMMUTABLE AS
$$ SELECT rdf_literal_to_timestamp($1) < $2; $$;

CREATE OPERATOR < (
    LEFTARG = rdf_literal,
    RIGHTARG = timestamp,
    PROCEDURE = rdf_literal_lt_timestamp,
    COMMUTATOR = >,
    NEGATOR = >=,
    RESTRICT = scalarltsel
);

-- CREATE FUNCTION rdf_literal_gt_timestamp(rdf_literal, timestamp)
-- RETURNS boolean
-- AS 'MODULE_PATHNAME', 'rdf_literal_gt_timestamp'
-- LANGUAGE C IMMUTABLE STRICT;

CREATE FUNCTION rdf_literal_gt_timestamp(rdf_literal, timestamp)
RETURNS boolean LANGUAGE SQL IMMUTABLE AS
$$ SELECT rdf_literal_to_timestamp($1) > $2; $$;

CREATE OPERATOR > (
    LEFTARG = rdf_literal,
    RIGHTARG = timestamp,
    PROCEDURE = rdf_literal_gt_timestamp,
    COMMUTATOR = <,
    NEGATOR = <=,
    RESTRICT = scalargtsel
);

-- CREATE FUNCTION rdf_literal_le_timestamp(rdf_literal, timestamp)
-- RETURNS boolean
-- AS 'MODULE_PATHNAME', 'rdf_literal_le_timestamp'
-- LANGUAGE C IMMUTABLE STRICT;

CREATE FUNCTION rdf_literal_le_timestamp(rdf_literal, timestamp)
RETURNS boolean LANGUAGE SQL IMMUTABLE AS
$$ SELECT rdf_literal_to_timestamp($1) <= $2; $$;

CREATE OPERATOR <= (
    LEFTARG = rdf_literal,
    RIGHTARG = timestamp,
    PROCEDURE = rdf_literal_le_timestamp,
    COMMUTATOR = >=,
    NEGATOR = >,
    RESTRICT = scalarltsel
);

-- CREATE FUNCTION rdf_literal_ge_timestamp(rdf_literal, timestamp)
-- RETURNS boolean
-- AS 'MODULE_PATHNAME', 'rdf_literal_ge_timestamp'
-- LANGUAGE C IMMUTABLE STRICT;

CREATE FUNCTION rdf_literal_ge_timestamp(rdf_literal, timestamp)
RETURNS boolean LANGUAGE SQL IMMUTABLE AS
$$ SELECT rdf_literal_to_timestamp($1) >= $2; $$;

CREATE OPERATOR >= (
    LEFTARG = rdf_literal,
    RIGHTARG = timestamp,
    PROCEDURE = rdf_literal_ge_timestamp,
    COMMUTATOR = <=,
    NEGATOR = <,
    RESTRICT = scalargtsel
);


/* timestamp (without time zone) OP rdf_literal */
CREATE FUNCTION timestamp_to_rdf_literal(timestamp)
RETURNS rdf_literal
AS 'MODULE_PATHNAME', 'timestamp_to_rdf_literal'
LANGUAGE C IMMUTABLE STRICT;

CREATE CAST (timestamp AS rdf_literal)
WITH FUNCTION timestamp_to_rdf_literal(timestamp);

-- CREATE FUNCTION timestamp_eq_rdf_literal(timestamp, rdf_literal)
-- RETURNS boolean
-- AS 'MODULE_PATHNAME', 'timestamp_eq_rdf_literal'
-- LANGUAGE C IMMUTABLE STRICT;

CREATE FUNCTION timestamp_eq_rdf_literal(timestamp, rdf_literal)
RETURNS boolean LANGUAGE SQL IMMUTABLE AS
$$ SELECT $1 = rdf_literal_to_timestamp($2); $$;

CREATE OPERATOR = (
    LEFTARG = timestamp,
    RIGHTARG = rdf_literal,
    PROCEDURE = timestamp_eq_rdf_literal,
    COMMUTATOR = '=',
    NEGATOR = '<>',
    RESTRICT = eqsel
);

-- CREATE FUNCTION timestamp_neq_rdf_literal(timestamp, rdf_literal)
-- RETURNS boolean
-- AS 'MODULE_PATHNAME', 'timestamp_neq_rdf_literal'
-- LANGUAGE C IMMUTABLE STRICT;

CREATE FUNCTION timestamp_neq_rdf_literal(timestamp, rdf_literal)
RETURNS boolean LANGUAGE SQL IMMUTABLE AS
$$ SELECT $1 <> rdf_literal_to_timestamp($2); $$;

CREATE OPERATOR <> (
    LEFTARG = timestamp,
    RIGHTARG = rdf_literal,
    PROCEDURE = timestamp_neq_rdf_literal,
    COMMUTATOR = '<>',
    NEGATOR = '=',
    RESTRICT = neqsel
);

-- CREATE FUNCTION timestamp_lt_rdf_literal(timestamp, rdf_literal)
-- RETURNS boolean
-- AS 'MODULE_PATHNAME', 'timestamp_lt_rdf_literal'
-- LANGUAGE C IMMUTABLE STRICT;

CREATE FUNCTION timestamp_lt_rdf_literal(timestamp, rdf_literal)
RETURNS boolean LANGUAGE SQL IMMUTABLE AS
$$ SELECT $1 < rdf_literal_to_timestamp($2); $$;

CREATE OPERATOR < (
    LEFTARG = timestamp,
    RIGHTARG = rdf_literal,
    PROCEDURE = timestamp_lt_rdf_literal,
    COMMUTATOR = >,
    NEGATOR = >=,
    RESTRICT = scalarltsel
);

-- CREATE FUNCTION timestamp_gt_rdf_literal(timestamp, rdf_literal)
-- RETURNS boolean
-- AS 'MODULE_PATHNAME', 'timestamp_gt_rdf_literal'
-- LANGUAGE C IMMUTABLE STRICT;

CREATE FUNCTION timestamp_gt_rdf_literal(timestamp, rdf_literal)
RETURNS boolean LANGUAGE SQL IMMUTABLE AS
$$ SELECT $1 > rdf_literal_to_timestamp($2); $$;

CREATE OPERATOR > (
    LEFTARG = timestamp,
    RIGHTARG = rdf_literal,
    PROCEDURE = timestamp_gt_rdf_literal,
    COMMUTATOR = <,
    NEGATOR = <=,
    RESTRICT = scalargtsel
);

-- CREATE FUNCTION timestamp_le_rdf_literal(timestamp, rdf_literal)
-- RETURNS boolean
-- AS 'MODULE_PATHNAME', 'timestamp_le_rdf_literal'
-- LANGUAGE C IMMUTABLE STRICT;

CREATE FUNCTION timestamp_le_rdf_literal(timestamp, rdf_literal)
RETURNS boolean LANGUAGE SQL IMMUTABLE AS
$$ SELECT $1 <= rdf_literal_to_timestamp($2); $$;

CREATE OPERATOR <= (
    LEFTARG = timestamp,
    RIGHTARG = rdf_literal,
    PROCEDURE = timestamp_le_rdf_literal,
    COMMUTATOR = >=,
    NEGATOR = >,
    RESTRICT = scalarltsel
);

-- CREATE FUNCTION timestamp_ge_rdf_literal(timestamp, rdf_literal)
-- RETURNS boolean
-- AS 'MODULE_PATHNAME', 'timestamp_ge_rdf_literal'
-- LANGUAGE C IMMUTABLE STRICT;

CREATE FUNCTION timestamp_ge_rdf_literal(timestamp, rdf_literal)
RETURNS boolean LANGUAGE SQL IMMUTABLE AS
$$ SELECT $1 >= rdf_literal_to_timestamp($2); $$;

CREATE OPERATOR >= (
    LEFTARG = timestamp,
    RIGHTARG = rdf_literal,
    PROCEDURE = timestamp_ge_rdf_literal,
    COMMUTATOR = <=,
    NEGATOR = <,
    RESTRICT = scalargtsel
);

/* ## rdf_literal OP date ## */
CREATE FUNCTION rdf_literal_to_date(rdf_literal)
RETURNS date
AS 'MODULE_PATHNAME', 'rdf_literal_to_date'
LANGUAGE C IMMUTABLE STRICT;

CREATE CAST (rdf_literal AS date)
WITH FUNCTION rdf_literal_to_date(rdf_literal);

CREATE FUNCTION rdf_literal_eq_date(rdf_literal, date)
RETURNS boolean
AS 'MODULE_PATHNAME', 'rdf_literal_eq_date'
LANGUAGE C IMMUTABLE STRICT;

CREATE OPERATOR = (
    LEFTARG = rdf_literal,
    RIGHTARG = date,
    PROCEDURE = rdf_literal_eq_date,
    COMMUTATOR = '=',
    NEGATOR = '<>',
    RESTRICT = eqsel
);

CREATE FUNCTION rdf_literal_neq_date(rdf_literal, date)
RETURNS boolean
AS 'MODULE_PATHNAME', 'rdf_literal_neq_date'
LANGUAGE C IMMUTABLE STRICT;

CREATE OPERATOR <> (
    LEFTARG = rdf_literal,
    RIGHTARG = date,
    PROCEDURE = rdf_literal_neq_date,
    COMMUTATOR = '<>',
    NEGATOR = '=',
    RESTRICT = neqsel
);

CREATE FUNCTION rdf_literal_lt_date(rdf_literal, date)
RETURNS boolean
AS 'MODULE_PATHNAME', 'rdf_literal_lt_date'
LANGUAGE C IMMUTABLE STRICT;

CREATE OPERATOR < (
    LEFTARG = rdf_literal,
    RIGHTARG = date,
    PROCEDURE = rdf_literal_lt_date,
    COMMUTATOR = >,
    NEGATOR = >=,
    RESTRICT = scalarltsel
);

CREATE FUNCTION rdf_literal_gt_date(rdf_literal, date)
RETURNS boolean
AS 'MODULE_PATHNAME', 'rdf_literal_gt_date'
LANGUAGE C IMMUTABLE STRICT;

CREATE OPERATOR > (
    LEFTARG = rdf_literal,
    RIGHTARG = date,
    PROCEDURE = rdf_literal_gt_date,
    COMMUTATOR = <,
    NEGATOR = <=,
    RESTRICT = scalargtsel
);

CREATE FUNCTION rdf_literal_le_date(rdf_literal, date)
RETURNS boolean
AS 'MODULE_PATHNAME', 'rdf_literal_le_date'
LANGUAGE C IMMUTABLE STRICT;

CREATE OPERATOR <= (
    LEFTARG = rdf_literal,
    RIGHTARG = date,
    PROCEDURE = rdf_literal_le_date,
    COMMUTATOR = >=,
    NEGATOR = >,
    RESTRICT = scalarltsel
);

CREATE FUNCTION rdf_literal_ge_date(rdf_literal, date)
RETURNS boolean
AS 'MODULE_PATHNAME', 'rdf_literal_ge_date'
LANGUAGE C IMMUTABLE STRICT;

CREATE OPERATOR >= (
    LEFTARG = rdf_literal,
    RIGHTARG = date,
    PROCEDURE = rdf_literal_ge_date,
    COMMUTATOR = <=,
    NEGATOR = <,
    RESTRICT = scalargtsel
);

/* date OP rdf_literal */
CREATE FUNCTION date_to_rdf_literal(date)
RETURNS rdf_literal
AS 'MODULE_PATHNAME', 'date_to_rdf_literal'
LANGUAGE C IMMUTABLE STRICT;

CREATE CAST (date AS rdf_literal)
WITH FUNCTION date_to_rdf_literal(date);

CREATE FUNCTION date_eq_rdf_literal(date, rdf_literal)
RETURNS boolean
AS 'MODULE_PATHNAME', 'date_eq_rdf_literal'
LANGUAGE C IMMUTABLE STRICT;

CREATE OPERATOR = (
    LEFTARG = date,
    RIGHTARG = rdf_literal,
    PROCEDURE = date_eq_rdf_literal,
    COMMUTATOR = '=',
    NEGATOR = '<>',
    RESTRICT = eqsel
);

CREATE FUNCTION date_neq_rdf_literal(date, rdf_literal)
RETURNS boolean
AS 'MODULE_PATHNAME', 'date_neq_rdf_literal'
LANGUAGE C IMMUTABLE STRICT;

CREATE OPERATOR <> (
    LEFTARG = date,
    RIGHTARG = rdf_literal,
    PROCEDURE = date_neq_rdf_literal,
    COMMUTATOR = '<>',
    NEGATOR = '=',
    RESTRICT = neqsel
);

CREATE FUNCTION date_lt_rdf_literal(date, rdf_literal)
RETURNS boolean
AS 'MODULE_PATHNAME', 'date_lt_rdf_literal'
LANGUAGE C IMMUTABLE STRICT;

CREATE OPERATOR < (
    LEFTARG = date,
    RIGHTARG = rdf_literal,
    PROCEDURE = date_lt_rdf_literal,
    COMMUTATOR = >,
    NEGATOR = >=,
    RESTRICT = scalarltsel
);

CREATE FUNCTION date_gt_rdf_literal(date, rdf_literal)
RETURNS boolean
AS 'MODULE_PATHNAME', 'date_gt_rdf_literal'
LANGUAGE C IMMUTABLE STRICT;

CREATE OPERATOR > (
    LEFTARG = date,
    RIGHTARG = rdf_literal,
    PROCEDURE = date_gt_rdf_literal,
    COMMUTATOR = <,
    NEGATOR = <=,
    RESTRICT = scalargtsel
);

CREATE FUNCTION date_le_rdf_literal(date, rdf_literal)
RETURNS boolean
AS 'MODULE_PATHNAME', 'date_le_rdf_literal'
LANGUAGE C IMMUTABLE STRICT;

CREATE OPERATOR <= (
    LEFTARG = date,
    RIGHTARG = rdf_literal,
    PROCEDURE = date_le_rdf_literal,
    COMMUTATOR = >=,
    NEGATOR = >,
    RESTRICT = scalarltsel
);

CREATE FUNCTION date_ge_rdf_literal(date, rdf_literal)
RETURNS boolean
AS 'MODULE_PATHNAME', 'date_ge_rdf_literal'
LANGUAGE C IMMUTABLE STRICT;

CREATE OPERATOR >= (
    LEFTARG = date,
    RIGHTARG = rdf_literal,
    PROCEDURE = date_ge_rdf_literal,
    COMMUTATOR = <=,
    NEGATOR = <,
    RESTRICT = scalargtsel
);

/* ## rdf_literal OP time ## */
CREATE FUNCTION rdf_literal_to_time(rdf_literal)
RETURNS time
AS 'MODULE_PATHNAME', 'rdf_literal_to_time'
LANGUAGE C IMMUTABLE STRICT;

CREATE CAST (rdf_literal AS time)
WITH FUNCTION rdf_literal_to_time(rdf_literal);

CREATE FUNCTION rdf_literal_eq_time(rdf_literal, time)
RETURNS boolean
AS 'MODULE_PATHNAME', 'rdf_literal_eq_time'
LANGUAGE C IMMUTABLE STRICT;

CREATE OPERATOR = (
    LEFTARG = rdf_literal,
    RIGHTARG = time,
    PROCEDURE = rdf_literal_eq_time,
    COMMUTATOR = '=',
    NEGATOR = '<>',
    RESTRICT = eqsel
);

CREATE FUNCTION rdf_literal_neq_time(rdf_literal, time)
RETURNS boolean
AS 'MODULE_PATHNAME', 'rdf_literal_neq_time'
LANGUAGE C IMMUTABLE STRICT;

CREATE OPERATOR <> (
    LEFTARG = rdf_literal,
    RIGHTARG = time,
    PROCEDURE = rdf_literal_neq_time,
    COMMUTATOR = '<>',
    NEGATOR = '=',
    RESTRICT = neqsel
);

CREATE FUNCTION rdf_literal_lt_time(rdf_literal, time)
RETURNS boolean
AS 'MODULE_PATHNAME', 'rdf_literal_lt_time'
LANGUAGE C IMMUTABLE STRICT;

CREATE OPERATOR < (
    LEFTARG = rdf_literal,
    RIGHTARG = time,
    PROCEDURE = rdf_literal_lt_time,
    COMMUTATOR = >,
    NEGATOR = >=,
    RESTRICT = scalarltsel
);

CREATE FUNCTION rdf_literal_gt_time(rdf_literal, time)
RETURNS boolean
AS 'MODULE_PATHNAME', 'rdf_literal_gt_time'
LANGUAGE C IMMUTABLE STRICT;

CREATE OPERATOR > (
    LEFTARG = rdf_literal,
    RIGHTARG = time,
    PROCEDURE = rdf_literal_gt_time,
    COMMUTATOR = <,
    NEGATOR = <=,
    RESTRICT = scalargtsel
);

CREATE FUNCTION rdf_literal_le_time(rdf_literal, time)
RETURNS boolean
AS 'MODULE_PATHNAME', 'rdf_literal_le_time'
LANGUAGE C IMMUTABLE STRICT;

CREATE OPERATOR <= (
    LEFTARG = rdf_literal,
    RIGHTARG = time,
    PROCEDURE = rdf_literal_le_time,
    COMMUTATOR = >=,
    NEGATOR = >,
    RESTRICT = scalarltsel
);

CREATE FUNCTION rdf_literal_ge_time(rdf_literal, time)
RETURNS boolean
AS 'MODULE_PATHNAME', 'rdf_literal_ge_time'
LANGUAGE C IMMUTABLE STRICT;

CREATE OPERATOR >= (
    LEFTARG = rdf_literal,
    RIGHTARG = time,
    PROCEDURE = rdf_literal_ge_time,
    COMMUTATOR = <=,
    NEGATOR = <,
    RESTRICT = scalargtsel
);

/* ## time OP rdf_literal ## */
CREATE FUNCTION time_to_rdf_literal(time)
RETURNS rdf_literal
AS 'MODULE_PATHNAME', 'time_to_rdf_literal'
LANGUAGE C IMMUTABLE STRICT;

CREATE CAST (time AS rdf_literal)
WITH FUNCTION time_to_rdf_literal(time);

CREATE FUNCTION time_eq_rdf_literal(time, rdf_literal)
RETURNS boolean
AS 'MODULE_PATHNAME', 'time_eq_rdf_literal'
LANGUAGE C IMMUTABLE STRICT;

CREATE OPERATOR = (
    LEFTARG = time,
    RIGHTARG = rdf_literal,
    PROCEDURE = time_eq_rdf_literal,
    COMMUTATOR = '=',
    NEGATOR = '<>',
    RESTRICT = eqsel
);

CREATE FUNCTION time_neq_rdf_literal(time, rdf_literal)
RETURNS boolean
AS 'MODULE_PATHNAME', 'time_neq_rdf_literal'
LANGUAGE C IMMUTABLE STRICT;

CREATE OPERATOR <> (
    LEFTARG = time,
    RIGHTARG = rdf_literal,
    PROCEDURE = time_neq_rdf_literal,
    COMMUTATOR = '<>',
    NEGATOR = '=',
    RESTRICT = neqsel
);

CREATE FUNCTION time_lt_rdf_literal(time, rdf_literal)
RETURNS boolean
AS 'MODULE_PATHNAME', 'time_lt_rdf_literal'
LANGUAGE C IMMUTABLE STRICT;

CREATE OPERATOR < (
    LEFTARG = time,
    RIGHTARG = rdf_literal,
    PROCEDURE = time_lt_rdf_literal,
    COMMUTATOR = >,
    NEGATOR = >=,
    RESTRICT = scalarltsel
);

CREATE FUNCTION time_gt_rdf_literal(time, rdf_literal)
RETURNS boolean
AS 'MODULE_PATHNAME', 'time_gt_rdf_literal'
LANGUAGE C IMMUTABLE STRICT;

CREATE OPERATOR > (
    LEFTARG = time,
    RIGHTARG = rdf_literal,
    PROCEDURE = time_gt_rdf_literal,
    COMMUTATOR = <,
    NEGATOR = <=,
    RESTRICT = scalargtsel
);

CREATE FUNCTION time_le_rdf_literal(time, rdf_literal)
RETURNS boolean
AS 'MODULE_PATHNAME', 'time_le_rdf_literal'
LANGUAGE C IMMUTABLE STRICT;

CREATE OPERATOR <= (
    LEFTARG = time,
    RIGHTARG = rdf_literal,
    PROCEDURE = time_le_rdf_literal,
    COMMUTATOR = >=,
    NEGATOR = >,
    RESTRICT = scalarltsel
);

CREATE FUNCTION time_ge_rdf_literal(time, rdf_literal)
RETURNS boolean
AS 'MODULE_PATHNAME', 'time_ge_rdf_literal'
LANGUAGE C IMMUTABLE STRICT;

CREATE OPERATOR >= (
    LEFTARG = time,
    RIGHTARG = rdf_literal,
    PROCEDURE = time_ge_rdf_literal,
    COMMUTATOR = <=,
    NEGATOR = <,
    RESTRICT = scalargtsel
);






/* ## rdf_literal OP timetz ## */
CREATE FUNCTION rdf_literal_to_timetz(rdf_literal)
RETURNS timetz
AS 'MODULE_PATHNAME', 'rdf_literal_to_timetz'
LANGUAGE C IMMUTABLE STRICT;

CREATE CAST (rdf_literal AS timetz)
WITH FUNCTION rdf_literal_to_timetz(rdf_literal);

CREATE FUNCTION rdf_literal_eq_timetz(rdf_literal, timetz)
RETURNS boolean
AS 'MODULE_PATHNAME', 'rdf_literal_eq_timetz'
LANGUAGE C IMMUTABLE STRICT;

CREATE OPERATOR = (
    LEFTARG = rdf_literal,
    RIGHTARG = timetz,
    PROCEDURE = rdf_literal_eq_timetz,
    COMMUTATOR = '=',
    NEGATOR = '<>',
    RESTRICT = eqsel
);

CREATE FUNCTION rdf_literal_neq_timetz(rdf_literal, timetz)
RETURNS boolean
AS 'MODULE_PATHNAME', 'rdf_literal_neq_timetz'
LANGUAGE C IMMUTABLE STRICT;

CREATE OPERATOR <> (
    LEFTARG = rdf_literal,
    RIGHTARG = timetz,
    PROCEDURE = rdf_literal_neq_timetz,
    COMMUTATOR = '<>',
    NEGATOR = '=',
    RESTRICT = neqsel
);

CREATE FUNCTION rdf_literal_lt_timetz(rdf_literal, timetz)
RETURNS boolean
AS 'MODULE_PATHNAME', 'rdf_literal_lt_timetz'
LANGUAGE C IMMUTABLE STRICT;

CREATE OPERATOR < (
    LEFTARG = rdf_literal,
    RIGHTARG = timetz,
    PROCEDURE = rdf_literal_lt_timetz,
    COMMUTATOR = >,
    NEGATOR = >=,
    RESTRICT = scalarltsel
);

CREATE FUNCTION rdf_literal_gt_timetz(rdf_literal, timetz)
RETURNS boolean
AS 'MODULE_PATHNAME', 'rdf_literal_gt_timetz'
LANGUAGE C IMMUTABLE STRICT;

CREATE OPERATOR > (
    LEFTARG = rdf_literal,
    RIGHTARG = timetz,
    PROCEDURE = rdf_literal_gt_timetz,
    COMMUTATOR = <,
    NEGATOR = <=,
    RESTRICT = scalargtsel
);

CREATE FUNCTION rdf_literal_le_timetz(rdf_literal, timetz)
RETURNS boolean
AS 'MODULE_PATHNAME', 'rdf_literal_le_timetz'
LANGUAGE C IMMUTABLE STRICT;

CREATE OPERATOR <= (
    LEFTARG = rdf_literal,
    RIGHTARG = timetz,
    PROCEDURE = rdf_literal_le_timetz,
    COMMUTATOR = >=,
    NEGATOR = >,
    RESTRICT = scalarltsel
);

CREATE FUNCTION rdf_literal_ge_timetz(rdf_literal, timetz)
RETURNS boolean
AS 'MODULE_PATHNAME', 'rdf_literal_ge_timetz'
LANGUAGE C IMMUTABLE STRICT;

CREATE OPERATOR >= (
    LEFTARG = rdf_literal,
    RIGHTARG = timetz,
    PROCEDURE = rdf_literal_ge_timetz,
    COMMUTATOR = <=,
    NEGATOR = <,
    RESTRICT = scalargtsel
);

/* ## time OP rdf_literal ## */
CREATE FUNCTION timetz_to_rdf_literal(timetz)
RETURNS rdf_literal
AS 'MODULE_PATHNAME', 'timetz_to_rdf_literal'
LANGUAGE C IMMUTABLE STRICT;

CREATE CAST (timetz AS rdf_literal)
WITH FUNCTION timetz_to_rdf_literal(timetz);

CREATE FUNCTION timetz_eq_rdf_literal(timetz, rdf_literal)
RETURNS boolean
AS 'MODULE_PATHNAME', 'timetz_eq_rdf_literal'
LANGUAGE C IMMUTABLE STRICT;

CREATE OPERATOR = (
    LEFTARG = timetz,
    RIGHTARG = rdf_literal,
    PROCEDURE = timetz_eq_rdf_literal,
    COMMUTATOR = '=',
    NEGATOR = '<>',
    RESTRICT = eqsel
);

CREATE FUNCTION timetz_neq_rdf_literal(timetz, rdf_literal)
RETURNS boolean
AS 'MODULE_PATHNAME', 'timetz_neq_rdf_literal'
LANGUAGE C IMMUTABLE STRICT;

CREATE OPERATOR <> (
    LEFTARG = timetz,
    RIGHTARG = rdf_literal,
    PROCEDURE = timetz_neq_rdf_literal,
    COMMUTATOR = '<>',
    NEGATOR = '=',
    RESTRICT = neqsel
);

CREATE FUNCTION timetz_lt_rdf_literal(timetz, rdf_literal)
RETURNS boolean
AS 'MODULE_PATHNAME', 'timetz_lt_rdf_literal'
LANGUAGE C IMMUTABLE STRICT;

CREATE OPERATOR < (
    LEFTARG = timetz,
    RIGHTARG = rdf_literal,
    PROCEDURE = timetz_lt_rdf_literal,
    COMMUTATOR = >,
    NEGATOR = >=,
    RESTRICT = scalarltsel
);

CREATE FUNCTION timetz_gt_rdf_literal(timetz, rdf_literal)
RETURNS boolean
AS 'MODULE_PATHNAME', 'timetz_gt_rdf_literal'
LANGUAGE C IMMUTABLE STRICT;

CREATE OPERATOR > (
    LEFTARG = timetz,
    RIGHTARG = rdf_literal,
    PROCEDURE = timetz_gt_rdf_literal,
    COMMUTATOR = <,
    NEGATOR = <=,
    RESTRICT = scalargtsel
);

CREATE FUNCTION timetz_le_rdf_literal(timetz, rdf_literal)
RETURNS boolean
AS 'MODULE_PATHNAME', 'timetz_le_rdf_literal'
LANGUAGE C IMMUTABLE STRICT;

CREATE OPERATOR <= (
    LEFTARG = timetz,
    RIGHTARG = rdf_literal,
    PROCEDURE = timetz_le_rdf_literal,
    COMMUTATOR = >=,
    NEGATOR = >,
    RESTRICT = scalarltsel
);

CREATE FUNCTION timetz_ge_rdf_literal(timetz, rdf_literal)
RETURNS boolean
AS 'MODULE_PATHNAME', 'timetz_ge_rdf_literal'
LANGUAGE C IMMUTABLE STRICT;

CREATE OPERATOR >= (
    LEFTARG = timetz,
    RIGHTARG = rdf_literal,
    PROCEDURE = timetz_ge_rdf_literal,
    COMMUTATOR = <=,
    NEGATOR = <,
    RESTRICT = scalargtsel
);






-- boolean
CREATE FUNCTION rdf_literal_to_boolean(rdf_literal)
RETURNS boolean
AS 'MODULE_PATHNAME', 'rdf_literal_to_boolean'
LANGUAGE C IMMUTABLE STRICT;

CREATE CAST (rdf_literal AS boolean)
WITH FUNCTION rdf_literal_to_boolean(rdf_literal);

CREATE FUNCTION boolean_to_rdf_literal(boolean)
RETURNS rdf_literal
AS 'MODULE_PATHNAME', 'boolean_to_rdf_literal'
LANGUAGE C IMMUTABLE STRICT;

CREATE CAST (boolean AS rdf_literal)
WITH FUNCTION boolean_to_rdf_literal(boolean);

-- boolean
CREATE FUNCTION rdf_literal_to_interval(rdf_literal)
RETURNS interval
AS 'MODULE_PATHNAME', 'rdf_literal_to_interval'
LANGUAGE C IMMUTABLE STRICT;

CREATE CAST (rdf_literal AS interval)
WITH FUNCTION rdf_literal_to_interval(rdf_literal);

/* interval */
CREATE FUNCTION interval_to_rdf_literal(interval)
RETURNS rdf_literal
AS 'MODULE_PATHNAME', 'interval_to_rdf_literal'
LANGUAGE C IMMUTABLE STRICT;

CREATE CAST (interval AS rdf_literal)
WITH FUNCTION interval_to_rdf_literal(interval);


CREATE FUNCTION rdf_literal_eq_interval(rdf_literal, interval)
RETURNS boolean
AS 'MODULE_PATHNAME', 'rdf_literal_eq_interval'
LANGUAGE C IMMUTABLE STRICT;

CREATE OPERATOR = (
    LEFTARG = rdf_literal,
    RIGHTARG = interval,
    PROCEDURE = rdf_literal_eq_interval,
    COMMUTATOR = '=',
    NEGATOR = '<>',
    RESTRICT = eqsel
);

CREATE FUNCTION rdf_literal_neq_interval(rdf_literal, interval)
RETURNS boolean
AS 'MODULE_PATHNAME', 'rdf_literal_neq_interval'
LANGUAGE C IMMUTABLE STRICT;

CREATE OPERATOR <> (
    LEFTARG = rdf_literal,
    RIGHTARG = interval,
    PROCEDURE = rdf_literal_neq_interval,
    COMMUTATOR = '<>',
    NEGATOR = '=',
    RESTRICT = neqsel
);


CREATE FUNCTION rdf_literal_lt_interval(rdf_literal, interval)
RETURNS boolean
AS 'MODULE_PATHNAME', 'rdf_literal_lt_interval'
LANGUAGE C IMMUTABLE STRICT;

CREATE OPERATOR < (
    LEFTARG = rdf_literal,
    RIGHTARG = interval,
    PROCEDURE = rdf_literal_lt_interval,
    COMMUTATOR = >,
    NEGATOR = >=,
    RESTRICT = scalarltsel
);

CREATE FUNCTION rdf_literal_gt_interval(rdf_literal, interval)
RETURNS boolean
AS 'MODULE_PATHNAME', 'rdf_literal_gt_interval'
LANGUAGE C IMMUTABLE STRICT;

CREATE OPERATOR > (
    LEFTARG = rdf_literal,
    RIGHTARG = interval,
    PROCEDURE = rdf_literal_gt_interval,
    COMMUTATOR = <,
    NEGATOR = <=,
    RESTRICT = scalargtsel
);

CREATE FUNCTION rdf_literal_le_interval(rdf_literal, interval)
RETURNS boolean
AS 'MODULE_PATHNAME', 'rdf_literal_le_interval'
LANGUAGE C IMMUTABLE STRICT;

CREATE OPERATOR <= (
    LEFTARG = rdf_literal,
    RIGHTARG = interval,
    PROCEDURE = rdf_literal_le_interval,
    COMMUTATOR = >=,
    NEGATOR = >,
    RESTRICT = scalarltsel
);

CREATE FUNCTION rdf_literal_ge_interval(rdf_literal, interval)
RETURNS boolean
AS 'MODULE_PATHNAME', 'rdf_literal_ge_interval'
LANGUAGE C IMMUTABLE STRICT;

CREATE OPERATOR >= (
    LEFTARG = rdf_literal,
    RIGHTARG = interval,
    PROCEDURE = rdf_literal_ge_interval,
    COMMUTATOR = <=,
    NEGATOR = <,
    RESTRICT = scalargtsel
);


/**/

CREATE FUNCTION interval_eq_rdf_literal(interval, rdf_literal)
RETURNS boolean
AS 'MODULE_PATHNAME', 'interval_eq_rdf_literal'
LANGUAGE C IMMUTABLE STRICT;

CREATE OPERATOR = (
    LEFTARG = interval,
    RIGHTARG = rdf_literal,
    PROCEDURE = interval_eq_rdf_literal,
    COMMUTATOR = '=',
    NEGATOR = '<>',
    RESTRICT = eqsel
);

CREATE FUNCTION interval_neq_rdf_literal(interval, rdf_literal)
RETURNS boolean
AS 'MODULE_PATHNAME', 'interval_neq_rdf_literal'
LANGUAGE C IMMUTABLE STRICT;

CREATE OPERATOR <> (
    LEFTARG = interval,
    RIGHTARG = rdf_literal,
    PROCEDURE = interval_neq_rdf_literal,
    COMMUTATOR = '<>',
    NEGATOR = '=',
    RESTRICT = neqsel
);

CREATE FUNCTION interval_lt_rdf_literal(interval, rdf_literal)
RETURNS boolean
AS 'MODULE_PATHNAME', 'interval_lt_rdf_literal'
LANGUAGE C IMMUTABLE STRICT;

CREATE OPERATOR < (
    LEFTARG = interval,
    RIGHTARG = rdf_literal,
    PROCEDURE = interval_lt_rdf_literal,
    COMMUTATOR = >,
    NEGATOR = >=,
    RESTRICT = scalarltsel
);

CREATE FUNCTION interval_gt_rdf_literal(interval, rdf_literal)
RETURNS boolean
AS 'MODULE_PATHNAME', 'interval_gt_rdf_literal'
LANGUAGE C IMMUTABLE STRICT;

CREATE OPERATOR > (
    LEFTARG = interval,
    RIGHTARG = rdf_literal,
    PROCEDURE = interval_gt_rdf_literal,
    COMMUTATOR = <,
    NEGATOR = <=,
    RESTRICT = scalargtsel
);

CREATE FUNCTION interval_le_rdf_literal(interval, rdf_literal)
RETURNS boolean
AS 'MODULE_PATHNAME', 'interval_le_rdf_literal'
LANGUAGE C IMMUTABLE STRICT;

CREATE OPERATOR <= (
    LEFTARG = interval,
    RIGHTARG = rdf_literal,
    PROCEDURE = interval_le_rdf_literal,
    COMMUTATOR = >=,
    NEGATOR = >,
    RESTRICT = scalarltsel
);

CREATE FUNCTION interval_ge_rdf_literal(interval, rdf_literal)
RETURNS boolean
AS 'MODULE_PATHNAME', 'interval_ge_rdf_literal'
LANGUAGE C IMMUTABLE STRICT;

CREATE OPERATOR >= (
    LEFTARG = interval,
    RIGHTARG = rdf_literal,
    PROCEDURE = interval_ge_rdf_literal,
    COMMUTATOR = <=,
    NEGATOR = <,
    RESTRICT = scalargtsel
);


/* SPARQL functions in rdf_fdw */
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

/* SPARQL 17.4.1 Functional Forms*/
CREATE FUNCTION sparql.bound(text) RETURNS boolean
AS 'MODULE_PATHNAME', 'rdf_fdw_bound'
LANGUAGE C IMMUTABLE;
COMMENT ON FUNCTION sparql.bound(text) IS 'Returns true if the argument is bound (non-NULL). Returns false otherwise. This function is used to test whether a SPARQL variable has a value in the current solution.';

CREATE FUNCTION sparql.sameterm(text, text) RETURNS boolean
AS 'MODULE_PATHNAME', 'rdf_fdw_sameterm'
LANGUAGE C IMMUTABLE STRICT;

CREATE FUNCTION sparql.coalesce(VARIADIC text[]) RETURNS text
AS 'MODULE_PATHNAME', 'rdf_fdw_coalesce'
LANGUAGE C STABLE;

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
  RETURN length(sparql.lex($1));
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
  --IF sparql.lex($1)::numeric > 0 THEN
  IF $1::rdf_literal > 0.0 THEN
    RETURN pg_catalog.floor(sparql.lex($1)::numeric + 0.5);
  ELSE
    RETURN pg_catalog.ceil(sparql.lex($1)::numeric + 0.5);
  END IF;
END;
$$ LANGUAGE plpgsql IMMUTABLE STRICT;

-- CREATE FUNCTION sparql.round(numeric) RETURNS numeric AS $$
-- BEGIN
--   IF $1 > 0.0 THEN
--     RETURN pg_catalog.floor($1 + 0.5);
--   ELSE
--     RETURN pg_catalog.ceil($1 + 0.5);
--   END IF;
-- END;
-- $$ LANGUAGE plpgsql IMMUTABLE STRICT;

CREATE FUNCTION sparql.round(double precision) RETURNS double precision AS $$
BEGIN
  IF $1 > 0.0 THEN
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
