CREATE SCHEMA sparql;

CREATE FUNCTION rdf_fdw_handler()
RETURNS fdw_handler AS 'MODULE_PATHNAME'
LANGUAGE C STRICT;

CREATE FUNCTION rdf_fdw_version()
RETURNS text AS 'MODULE_PATHNAME', 'rdf_fdw_version'
LANGUAGE C IMMUTABLE STRICT;

CREATE FUNCTION rdf_fdw_settings()
RETURNS text AS 'MODULE_PATHNAME', 'rdf_fdw_settings'
LANGUAGE C IMMUTABLE STRICT;

COMMENT ON FUNCTION rdf_fdw_version() IS 'Returns rdf_fdw version and dependency information';
COMMENT ON FUNCTION rdf_fdw_settings() IS 'Returns detailed dependency information including optional components';

CREATE VIEW rdf_fdw_settings AS
    WITH version_string AS (
        SELECT rdf_fdw_settings() AS v
    )
    SELECT component, version
    FROM version_string,
    LATERAL (VALUES
        ('rdf_fdw',    substring(v from 'rdf_fdw\s+([^\s,]+)')),
        ('PostgreSQL', substring(v from 'PostgreSQL\s+([^,]+)')),
        ('libxml',     substring(v from 'libxml\s+([^,]+)')),
        ('librdf',     substring(v from 'librdf\s+([^,]+)')),
        ('libcurl',    substring(v from 'libcurl\s+([^,]+)')),
        ('ssl',        substring(v from ',ssl\s+([^,]+)')),
        ('zlib',       substring(v from ',zlib\s+([^,]+)')),
        ('libSSH',     substring(v from ',libSSH\s+([^,]+)')),
        ('nghttp2',    substring(v from ',nghttp2\s+([^,]+)')),
        ('compiler',   substring(v from 'compiled by\s+([^,]+)')),
        ('built',      substring(v from 'built on\s+([^,]+)'))
    ) AS components(component, version)
    WHERE version IS NOT NULL;

COMMENT ON VIEW rdf_fdw_settings IS 'Parse detailed dependency information into component versions';

CREATE FUNCTION rdf_fdw_validator(text[], oid)
RETURNS void AS 'MODULE_PATHNAME'
LANGUAGE C STRICT;

COMMENT ON FUNCTION rdf_fdw_validator(text[], oid) IS 'RDF Triplestore Foreign-data Wrapper options validator';

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

/* casts, functions, and operators */
CREATE FUNCTION rdfnode_in(cstring) RETURNS rdfnode
AS 'MODULE_PATHNAME', 'rdfnode_in'
LANGUAGE C IMMUTABLE STRICT;

CREATE FUNCTION rdfnode_out(rdfnode) RETURNS cstring
AS 'MODULE_PATHNAME', 'rdfnode_out'
LANGUAGE C IMMUTABLE STRICT;

CREATE TYPE rdfnode (
    INPUT = rdfnode_in,
    OUTPUT = rdfnode_out,
    INTERNALLENGTH = VARIABLE,
    STORAGE = EXTENDED
);

CREATE FUNCTION rdfnode_eq_rdfnode(rdfnode, rdfnode)
RETURNS boolean
AS 'MODULE_PATHNAME', 'rdfnode_eq_rdfnode'
LANGUAGE C IMMUTABLE STRICT;

CREATE OPERATOR = (
  LEFTARG = rdfnode,
  RIGHTARG = rdfnode,
  PROCEDURE = rdfnode_eq_rdfnode,
  COMMUTATOR = '=',
  NEGATOR = '<>',
  RESTRICT = eqsel,
  JOIN = eqjoinsel
);

CREATE FUNCTION rdfnode_neq_rdfnode(rdfnode, rdfnode)
RETURNS boolean
AS 'MODULE_PATHNAME', 'rdfnode_neq_rdfnode'
LANGUAGE C IMMUTABLE STRICT;

CREATE OPERATOR <> (
    LEFTARG = rdfnode,
    RIGHTARG = rdfnode,
    PROCEDURE = rdfnode_neq_rdfnode,
    COMMUTATOR = '<>',
    NEGATOR = '=',
    RESTRICT = neqsel,
    JOIN = neqjoinsel
);

CREATE FUNCTION rdfnode_lt_rdfnode(rdfnode, rdfnode)
RETURNS boolean
AS 'MODULE_PATHNAME', 'rdfnode_lt_rdfnode'
LANGUAGE C IMMUTABLE STRICT;

CREATE OPERATOR < (
    LEFTARG = rdfnode,
    RIGHTARG = rdfnode,
    PROCEDURE = rdfnode_lt_rdfnode,
    COMMUTATOR = '>',
    RESTRICT = scalarltsel
);

CREATE FUNCTION rdfnode_gt_rdfnode(rdfnode, rdfnode)
RETURNS boolean
AS 'MODULE_PATHNAME', 'rdfnode_gt_rdfnode'
LANGUAGE C IMMUTABLE STRICT;

CREATE OPERATOR > (
    LEFTARG = rdfnode,
    RIGHTARG = rdfnode,
    PROCEDURE = rdfnode_gt_rdfnode,
    COMMUTATOR = '<',
    RESTRICT = scalargtsel
);

CREATE FUNCTION rdfnode_le_rdfnode(rdfnode, rdfnode)
RETURNS boolean
AS 'MODULE_PATHNAME', 'rdfnode_le_rdfnode'
LANGUAGE C IMMUTABLE STRICT;

CREATE OPERATOR <= (
    LEFTARG = rdfnode,
    RIGHTARG = rdfnode,
    PROCEDURE = rdfnode_le_rdfnode,
    COMMUTATOR = '>=',
    RESTRICT = scalarltsel
);

CREATE FUNCTION rdfnode_ge_rdfnode(rdfnode, rdfnode)
RETURNS boolean
AS 'MODULE_PATHNAME', 'rdfnode_ge_rdfnode'
LANGUAGE C IMMUTABLE STRICT;

CREATE OPERATOR >= (
    LEFTARG = rdfnode,
    RIGHTARG = rdfnode,
    PROCEDURE = rdfnode_ge_rdfnode,
    COMMUTATOR = '<=',
    RESTRICT = scalargtsel
);

-- Create comparison function for rdfnode
CREATE FUNCTION rdfnode_cmp(rdfnode, rdfnode)
RETURNS integer
AS 'MODULE_PATHNAME', 'rdfnode_cmp'
LANGUAGE C IMMUTABLE STRICT;

-- Create btree operator class for rdfnode
CREATE OPERATOR CLASS rdfnode_ops
DEFAULT FOR TYPE rdfnode USING btree AS
    OPERATOR 1 <  (rdfnode, rdfnode),
    OPERATOR 2 <= (rdfnode, rdfnode),
    OPERATOR 3 =  (rdfnode, rdfnode),
    OPERATOR 4 >= (rdfnode, rdfnode),
    OPERATOR 5 >  (rdfnode, rdfnode),
    FUNCTION 1 rdfnode_cmp(rdfnode, rdfnode);

CREATE FUNCTION rdfnode_to_text(rdfnode)
RETURNS text
AS 'MODULE_PATHNAME', 'rdfnode_to_text'
LANGUAGE C IMMUTABLE STRICT;

CREATE CAST (rdfnode AS text) 
WITH FUNCTION rdfnode_to_text(rdfnode);

/* rdfnode OP numeric */
CREATE FUNCTION rdfnode_eq_numeric(rdfnode, numeric)
RETURNS boolean
AS 'MODULE_PATHNAME', 'rdfnode_eq_numeric'
LANGUAGE C IMMUTABLE STRICT;

CREATE OPERATOR = (
    LEFTARG = rdfnode,
    RIGHTARG = numeric,
    PROCEDURE = rdfnode_eq_numeric,
    COMMUTATOR = '=',
    NEGATOR = '<>',
    RESTRICT = eqsel
);

CREATE FUNCTION rdfnode_neq_numeric(rdfnode, numeric)
RETURNS boolean
AS 'MODULE_PATHNAME', 'rdfnode_neq_numeric'
LANGUAGE C IMMUTABLE STRICT;

CREATE OPERATOR <> (
    LEFTARG = rdfnode,
    RIGHTARG = numeric,
    PROCEDURE = rdfnode_neq_numeric,
    COMMUTATOR = '<>',
    NEGATOR = '=',
    RESTRICT = neqsel
);

CREATE FUNCTION rdfnode_lt_numeric(rdfnode, numeric)
RETURNS boolean
AS 'MODULE_PATHNAME', 'rdfnode_lt_numeric'
LANGUAGE C IMMUTABLE STRICT;

CREATE OPERATOR < (
    LEFTARG = rdfnode,
    RIGHTARG = numeric,
    PROCEDURE = rdfnode_lt_numeric,
    COMMUTATOR = '>',
    RESTRICT = scalarltsel
);

CREATE FUNCTION rdfnode_gt_numeric(rdfnode, numeric)
RETURNS boolean
AS 'MODULE_PATHNAME', 'rdfnode_gt_numeric'
LANGUAGE C IMMUTABLE STRICT;

CREATE OPERATOR > (
    LEFTARG = rdfnode,
    RIGHTARG = numeric,
    PROCEDURE = rdfnode_gt_numeric,
    COMMUTATOR = '<',
    RESTRICT = scalargtsel
);

CREATE FUNCTION rdfnode_le_numeric(rdfnode, numeric)
RETURNS boolean
AS 'MODULE_PATHNAME', 'rdfnode_le_numeric'
LANGUAGE C IMMUTABLE STRICT;

CREATE OPERATOR <= (
    LEFTARG = rdfnode,
    RIGHTARG = numeric,
    PROCEDURE = rdfnode_le_numeric,
    COMMUTATOR = '>=',
    RESTRICT = scalarltsel
);

CREATE FUNCTION rdfnode_ge_numeric(rdfnode, numeric)
RETURNS boolean
AS 'MODULE_PATHNAME', 'rdfnode_ge_numeric'
LANGUAGE C IMMUTABLE STRICT;

CREATE OPERATOR >= (
    LEFTARG = rdfnode,
    RIGHTARG = numeric,
    PROCEDURE = rdfnode_ge_numeric,
    COMMUTATOR = '<=',
    RESTRICT = scalargtsel
);

CREATE FUNCTION rdfnode_to_numeric(rdfnode)
RETURNS numeric
AS 'MODULE_PATHNAME', 'rdfnode_to_numeric'
LANGUAGE C IMMUTABLE STRICT;

CREATE CAST (rdfnode AS numeric) 
WITH FUNCTION rdfnode_to_numeric(rdfnode);

/* numeric OP rdfnode */
CREATE FUNCTION numeric_to_rdfnode(numeric)
RETURNS rdfnode
AS 'MODULE_PATHNAME', 'numeric_to_rdfnode'
LANGUAGE C IMMUTABLE STRICT;

CREATE CAST (numeric AS rdfnode)
WITH FUNCTION numeric_to_rdfnode(numeric);

CREATE FUNCTION numeric_eq_rdfnode(numeric, rdfnode)
RETURNS boolean
AS 'MODULE_PATHNAME', 'numeric_eq_rdfnode'
LANGUAGE C IMMUTABLE STRICT;

CREATE OPERATOR = (
    LEFTARG = numeric,
    RIGHTARG = rdfnode,
    PROCEDURE = numeric_eq_rdfnode,
    COMMUTATOR = '=',
    NEGATOR = '<>',
    RESTRICT = eqsel
);

CREATE FUNCTION numeric_neq_rdfnode(numeric, rdfnode)
RETURNS boolean
AS 'MODULE_PATHNAME', 'numeric_neq_rdfnode'
LANGUAGE C IMMUTABLE STRICT;

CREATE OPERATOR <> (
    LEFTARG = numeric,
    RIGHTARG = rdfnode,
    PROCEDURE = numeric_neq_rdfnode,
    COMMUTATOR = '<>',
    NEGATOR = '=',
    RESTRICT = neqsel
);

CREATE FUNCTION numeric_lt_rdfnode(numeric, rdfnode)
RETURNS boolean
AS 'MODULE_PATHNAME', 'numeric_lt_rdfnode'
LANGUAGE C IMMUTABLE STRICT;

CREATE OPERATOR < (
    LEFTARG = numeric,
    RIGHTARG = rdfnode,
    PROCEDURE = numeric_lt_rdfnode,
    COMMUTATOR = '>',
    RESTRICT = scalarltsel
);

CREATE FUNCTION numeric_gt_rdfnode(numeric, rdfnode)
RETURNS boolean
AS 'MODULE_PATHNAME', 'numeric_gt_rdfnode'
LANGUAGE C IMMUTABLE STRICT;

CREATE OPERATOR > (
    LEFTARG = numeric,
    RIGHTARG = rdfnode,
    PROCEDURE = numeric_gt_rdfnode,
    COMMUTATOR = '<',
    RESTRICT = scalargtsel
);

CREATE FUNCTION numeric_le_rdfnode(numeric, rdfnode)
RETURNS boolean
AS 'MODULE_PATHNAME', 'numeric_le_rdfnode'
LANGUAGE C IMMUTABLE STRICT;

CREATE OPERATOR <= (
    LEFTARG = numeric,
    RIGHTARG = rdfnode,
    PROCEDURE = numeric_le_rdfnode,
    COMMUTATOR = '>=',
    RESTRICT = scalarltsel
);

CREATE FUNCTION numeric_ge_rdfnode(numeric, rdfnode)
RETURNS boolean
AS 'MODULE_PATHNAME', 'numeric_ge_rdfnode'
LANGUAGE C IMMUTABLE STRICT;

CREATE OPERATOR >= (
    LEFTARG = numeric,
    RIGHTARG = rdfnode,
    PROCEDURE = numeric_ge_rdfnode,
    COMMUTATOR = '<=',
    RESTRICT = scalargtsel
);

/* rdfnode OP float8 (double precision) */
CREATE FUNCTION rdfnode_eq_float8(rdfnode, float8)
RETURNS boolean
AS 'MODULE_PATHNAME', 'rdfnode_eq_float8'
LANGUAGE C IMMUTABLE STRICT;

CREATE OPERATOR = (
    LEFTARG = rdfnode,
    RIGHTARG = float8,
    PROCEDURE = rdfnode_eq_float8,
    COMMUTATOR = '=',
    NEGATOR = '<>',
    RESTRICT = eqsel
);

CREATE FUNCTION rdfnode_neq_float8(rdfnode, float8)
RETURNS boolean
AS 'MODULE_PATHNAME', 'rdfnode_neq_float8'
LANGUAGE C IMMUTABLE STRICT;

CREATE OPERATOR <> (
    LEFTARG = rdfnode,
    RIGHTARG = float8,
    PROCEDURE = rdfnode_neq_float8,
    COMMUTATOR = '<>',
    NEGATOR = '=',
    RESTRICT = neqsel
);

CREATE FUNCTION rdfnode_lt_float8(rdfnode, float8)
RETURNS boolean
AS 'MODULE_PATHNAME', 'rdfnode_lt_float8'
LANGUAGE C IMMUTABLE STRICT;

CREATE OPERATOR < (
    LEFTARG = rdfnode,
    RIGHTARG = float8,
    PROCEDURE = rdfnode_lt_float8,
    COMMUTATOR = >,
    NEGATOR = >=,
    RESTRICT = scalarltsel
);

CREATE FUNCTION rdfnode_gt_float8(rdfnode, float8)
RETURNS boolean
AS 'MODULE_PATHNAME', 'rdfnode_gt_float8'
LANGUAGE C IMMUTABLE STRICT;

CREATE OPERATOR > (
    LEFTARG = rdfnode,
    RIGHTARG = float8,
    PROCEDURE = rdfnode_gt_float8,
    COMMUTATOR = <,
    NEGATOR = <=,
    RESTRICT = scalargtsel
);

CREATE FUNCTION rdfnode_le_float8(rdfnode, float8)
RETURNS boolean
AS 'MODULE_PATHNAME', 'rdfnode_le_float8'
LANGUAGE C IMMUTABLE STRICT;

CREATE OPERATOR <= (
    LEFTARG = rdfnode,
    RIGHTARG = float8,
    PROCEDURE = rdfnode_le_float8,
    COMMUTATOR = >=,
    NEGATOR = >,
    RESTRICT = scalarltsel
);

CREATE FUNCTION rdfnode_ge_float8(rdfnode, float8)
RETURNS boolean
AS 'MODULE_PATHNAME', 'rdfnode_ge_float8'
LANGUAGE C IMMUTABLE STRICT;

CREATE OPERATOR >= (
    LEFTARG = rdfnode,
    RIGHTARG = float8,
    PROCEDURE = rdfnode_ge_float8,
    COMMUTATOR = <=,
    NEGATOR = <,
    RESTRICT = scalargtsel
);

CREATE FUNCTION rdfnode_to_float8(rdfnode)
RETURNS float8
AS 'MODULE_PATHNAME', 'rdfnode_to_float8'
LANGUAGE C IMMUTABLE STRICT;

CREATE CAST (rdfnode AS float8) 
WITH FUNCTION rdfnode_to_float8(rdfnode);

/* float8 OP rdfnode  */
CREATE FUNCTION float8_eq_rdfnode(float8, rdfnode)
RETURNS boolean
AS 'MODULE_PATHNAME', 'float8_eq_rdfnode'
LANGUAGE C IMMUTABLE STRICT;

CREATE OPERATOR = (
    LEFTARG = float8,
    RIGHTARG = rdfnode,
    PROCEDURE = float8_eq_rdfnode,
    COMMUTATOR = '=',
    NEGATOR = '<>',
    RESTRICT = eqsel
);

CREATE FUNCTION float8_neq_rdfnode(float8, rdfnode)
RETURNS boolean
AS 'MODULE_PATHNAME', 'float8_neq_rdfnode'
LANGUAGE C IMMUTABLE STRICT;

CREATE OPERATOR <> (
    LEFTARG = float8,
    RIGHTARG = rdfnode,
    PROCEDURE = float8_neq_rdfnode,
    COMMUTATOR = '<>',
    NEGATOR = '=',
    RESTRICT = neqsel
);

CREATE FUNCTION float8_lt_rdfnode(float8, rdfnode)
RETURNS boolean
AS 'MODULE_PATHNAME', 'float8_lt_rdfnode'
LANGUAGE C IMMUTABLE STRICT;

CREATE OPERATOR < (
    LEFTARG = float8,
    RIGHTARG = rdfnode,
    PROCEDURE = float8_lt_rdfnode,
    COMMUTATOR = >,
    NEGATOR = >=,
    RESTRICT = scalarltsel
);

CREATE FUNCTION float8_gt_rdfnode(float8, rdfnode)
RETURNS boolean
AS 'MODULE_PATHNAME', 'float8_gt_rdfnode'
LANGUAGE C IMMUTABLE STRICT;

CREATE OPERATOR > (
    LEFTARG = float8,
    RIGHTARG = rdfnode,
    PROCEDURE = float8_gt_rdfnode,
    COMMUTATOR = <,
    NEGATOR = <=,
    RESTRICT = scalargtsel
);

CREATE FUNCTION float8_le_rdfnode(float8, rdfnode)
RETURNS boolean
AS 'MODULE_PATHNAME', 'float8_le_rdfnode'
LANGUAGE C IMMUTABLE STRICT;

CREATE OPERATOR <= (
    LEFTARG = float8,
    RIGHTARG = rdfnode,
    PROCEDURE = float8_le_rdfnode,
    COMMUTATOR = >=,
    NEGATOR = >,
    RESTRICT = scalarltsel
);

CREATE FUNCTION float8_ge_rdfnode(float8, rdfnode)
RETURNS boolean
AS 'MODULE_PATHNAME', 'float8_ge_rdfnode'
LANGUAGE C IMMUTABLE STRICT;

CREATE OPERATOR >= (
    LEFTARG = float8,
    RIGHTARG = rdfnode,
    PROCEDURE = float8_ge_rdfnode,
    COMMUTATOR = <=,
    NEGATOR = <,
    RESTRICT = scalargtsel
);

CREATE FUNCTION float8_to_rdfnode(float8)
RETURNS rdfnode
AS 'MODULE_PATHNAME', 'float8_to_rdfnode'
LANGUAGE C IMMUTABLE STRICT;

CREATE CAST (float8 AS rdfnode) 
WITH FUNCTION float8_to_rdfnode(float8);

/* rdfnode OP float4 (real) */
CREATE FUNCTION rdfnode_to_float4(rdfnode)
RETURNS float4
AS 'MODULE_PATHNAME', 'rdfnode_to_float4'
LANGUAGE C IMMUTABLE STRICT;

CREATE CAST (rdfnode AS float4) 
WITH FUNCTION rdfnode_to_float4(rdfnode)
AS IMPLICIT;

CREATE FUNCTION rdfnode_eq_float4(rdfnode, float4)
RETURNS boolean
AS 'MODULE_PATHNAME', 'rdfnode_eq_float4'
LANGUAGE C IMMUTABLE STRICT;

CREATE OPERATOR = (
    LEFTARG = rdfnode,
    RIGHTARG = float4,
    PROCEDURE = rdfnode_eq_float4,
    COMMUTATOR = '=',
    NEGATOR = '<>',
    RESTRICT = eqsel
);

CREATE FUNCTION rdfnode_neq_float4(rdfnode, float4)
RETURNS boolean
AS 'MODULE_PATHNAME', 'rdfnode_neq_float4'
LANGUAGE C IMMUTABLE STRICT;

CREATE OPERATOR <> (
    LEFTARG = rdfnode,
    RIGHTARG = float4,
    PROCEDURE = rdfnode_neq_float4,
    COMMUTATOR = '<>',
    NEGATOR = '=',
    RESTRICT = neqsel
);

CREATE FUNCTION rdfnode_lt_float4(rdfnode, float4)
RETURNS boolean
AS 'MODULE_PATHNAME', 'rdfnode_lt_float4'
LANGUAGE C IMMUTABLE STRICT;

CREATE OPERATOR < (
    LEFTARG = rdfnode,
    RIGHTARG = float4,
    PROCEDURE = rdfnode_lt_float4,
    COMMUTATOR = >,
    NEGATOR = >=,
    RESTRICT = scalarltsel
);

CREATE FUNCTION rdfnode_gt_float4(rdfnode, float4)
RETURNS boolean
AS 'MODULE_PATHNAME', 'rdfnode_gt_float4'
LANGUAGE C IMMUTABLE STRICT;

CREATE OPERATOR > (
    LEFTARG = rdfnode,
    RIGHTARG = float4,
    PROCEDURE = rdfnode_gt_float4,
    COMMUTATOR = <,
    NEGATOR = <=,
    RESTRICT = scalargtsel
);

CREATE FUNCTION rdfnode_le_float4(rdfnode, float4)
RETURNS boolean
AS 'MODULE_PATHNAME', 'rdfnode_le_float4'
LANGUAGE C IMMUTABLE STRICT;

CREATE OPERATOR <= (
    LEFTARG = rdfnode,
    RIGHTARG = float4,
    PROCEDURE = rdfnode_le_float4,
    COMMUTATOR = >=,
    NEGATOR = >,
    RESTRICT = scalarltsel
);

CREATE FUNCTION rdfnode_ge_float4(rdfnode, float4)
RETURNS boolean
AS 'MODULE_PATHNAME', 'rdfnode_ge_float4'
LANGUAGE C IMMUTABLE STRICT;

CREATE OPERATOR >= (
    LEFTARG = rdfnode,
    RIGHTARG = float4,
    PROCEDURE = rdfnode_ge_float4,
    COMMUTATOR = <=,
    NEGATOR = <,
    RESTRICT = scalargtsel
);

/* float4 (real) OP rdfnode */
CREATE FUNCTION float4_to_rdfnode(float4)
RETURNS rdfnode
AS 'MODULE_PATHNAME', 'float4_to_rdfnode'
LANGUAGE C IMMUTABLE STRICT;

CREATE CAST (float4 AS rdfnode) 
WITH FUNCTION float4_to_rdfnode(float4);

CREATE FUNCTION float4_eq_rdfnode(float4, rdfnode)
RETURNS boolean
AS 'MODULE_PATHNAME', 'float4_eq_rdfnode'
LANGUAGE C IMMUTABLE STRICT;

CREATE OPERATOR = (
    LEFTARG = float4,
    RIGHTARG = rdfnode,
    PROCEDURE = float4_eq_rdfnode,
    COMMUTATOR = '=',
    NEGATOR = '<>',
    RESTRICT = eqsel
);

CREATE FUNCTION float4_neq_rdfnode(float4, rdfnode)
RETURNS boolean
AS 'MODULE_PATHNAME', 'float4_neq_rdfnode'
LANGUAGE C IMMUTABLE STRICT;

CREATE OPERATOR <> (
    LEFTARG = float4,
    RIGHTARG = rdfnode,
    PROCEDURE = float4_neq_rdfnode,
    COMMUTATOR = '<>',
    NEGATOR = '=',
    RESTRICT = neqsel
);

CREATE FUNCTION float4_lt_rdfnode(float4, rdfnode)
RETURNS boolean
AS 'MODULE_PATHNAME', 'float4_lt_rdfnode'
LANGUAGE C IMMUTABLE STRICT;

CREATE OPERATOR < (
    LEFTARG = float4,
    RIGHTARG = rdfnode,
    PROCEDURE = float4_lt_rdfnode,
    COMMUTATOR = >,
    NEGATOR = >=,
    RESTRICT = scalarltsel
);

CREATE FUNCTION float4_gt_rdfnode(float4, rdfnode)
RETURNS boolean
AS 'MODULE_PATHNAME', 'float4_gt_rdfnode'
LANGUAGE C IMMUTABLE STRICT;

CREATE OPERATOR > (
    LEFTARG = float4,
    RIGHTARG = rdfnode,
    PROCEDURE = float4_gt_rdfnode,
    COMMUTATOR = <,
    NEGATOR = <=,
    RESTRICT = scalargtsel
);

CREATE FUNCTION float4_le_rdfnode(float4, rdfnode)
RETURNS boolean
AS 'MODULE_PATHNAME', 'float4_le_rdfnode'
LANGUAGE C IMMUTABLE STRICT;

CREATE OPERATOR <= (
    LEFTARG = float4,
    RIGHTARG = rdfnode,
    PROCEDURE = float4_le_rdfnode,
    COMMUTATOR = >=,
    NEGATOR = >,
    RESTRICT = scalarltsel
);

CREATE FUNCTION float4_ge_rdfnode(float4, rdfnode)
RETURNS boolean
AS 'MODULE_PATHNAME', 'float4_ge_rdfnode'
LANGUAGE C IMMUTABLE STRICT;

CREATE OPERATOR >= (
    LEFTARG = float4,
    RIGHTARG = rdfnode,
    PROCEDURE = float4_ge_rdfnode,
    COMMUTATOR = <=,
    NEGATOR = <,
    RESTRICT = scalargtsel
);

/* rdfnode OP int8 (bigint) */
CREATE FUNCTION rdfnode_to_int8(rdfnode)
RETURNS bigint
AS 'MODULE_PATHNAME', 'rdfnode_to_int8'
LANGUAGE C IMMUTABLE STRICT;

CREATE CAST (rdfnode AS bigint)
WITH FUNCTION rdfnode_to_int8(rdfnode);

CREATE FUNCTION rdfnode_eq_int8(rdfnode, int8)
RETURNS boolean
AS 'MODULE_PATHNAME', 'rdfnode_eq_int8'
LANGUAGE C IMMUTABLE STRICT;

CREATE OPERATOR = (
    LEFTARG = rdfnode,
    RIGHTARG = int8,
    PROCEDURE = rdfnode_eq_int8,
    COMMUTATOR = '=',
    NEGATOR = '<>',
    RESTRICT = eqsel
);

CREATE FUNCTION rdfnode_neq_int8(rdfnode, int8)
RETURNS boolean
AS 'MODULE_PATHNAME', 'rdfnode_neq_int8'
LANGUAGE C IMMUTABLE STRICT;

CREATE OPERATOR <> (
    LEFTARG = rdfnode,
    RIGHTARG = int8,
    PROCEDURE = rdfnode_neq_int8,
    COMMUTATOR = '<>',
    NEGATOR = '=',
    RESTRICT = neqsel
);

CREATE FUNCTION rdfnode_lt_int8(rdfnode, int8)
RETURNS boolean
AS 'MODULE_PATHNAME', 'rdfnode_lt_int8'
LANGUAGE C IMMUTABLE STRICT;

CREATE OPERATOR < (
    LEFTARG = rdfnode,
    RIGHTARG = int8,
    PROCEDURE = rdfnode_lt_int8,
    COMMUTATOR = >,
    NEGATOR = >=,
    RESTRICT = scalarltsel
);

CREATE FUNCTION rdfnode_gt_int8(rdfnode, int8)
RETURNS boolean
AS 'MODULE_PATHNAME', 'rdfnode_gt_int8'
LANGUAGE C IMMUTABLE STRICT;

CREATE OPERATOR > (
    LEFTARG = rdfnode,
    RIGHTARG = int8,
    PROCEDURE = rdfnode_gt_int8,
    COMMUTATOR = <,
    NEGATOR = <=,
    RESTRICT = scalargtsel
);

CREATE FUNCTION rdfnode_le_int8(rdfnode, int8)
RETURNS boolean
AS 'MODULE_PATHNAME', 'rdfnode_le_int8'
LANGUAGE C IMMUTABLE STRICT;

CREATE OPERATOR <= (
    LEFTARG = rdfnode,
    RIGHTARG = int8,
    PROCEDURE = rdfnode_le_int8,
    COMMUTATOR = >=,
    NEGATOR = >,
    RESTRICT = scalarltsel
);

CREATE FUNCTION rdfnode_ge_int8(rdfnode, int8)
RETURNS boolean
AS 'MODULE_PATHNAME', 'rdfnode_ge_int8'
LANGUAGE C IMMUTABLE STRICT;

CREATE OPERATOR >= (
    LEFTARG = rdfnode,
    RIGHTARG = int8,
    PROCEDURE = rdfnode_ge_int8,
    COMMUTATOR = <=,
    NEGATOR = <,
    RESTRICT = scalargtsel
);


/* int8 OP rdfnode */

CREATE FUNCTION int8_to_rdfnode(bigint)
RETURNS rdfnode
AS 'MODULE_PATHNAME', 'int8_to_rdfnode'
LANGUAGE C IMMUTABLE STRICT;

CREATE CAST (bigint AS rdfnode)
WITH FUNCTION int8_to_rdfnode(bigint);

CREATE FUNCTION int8_eq_rdfnode(int8, rdfnode)
RETURNS boolean
AS 'MODULE_PATHNAME', 'int8_eq_rdfnode'
LANGUAGE C IMMUTABLE STRICT;

CREATE OPERATOR = (
    LEFTARG = int8,
    RIGHTARG = rdfnode,
    PROCEDURE = int8_eq_rdfnode,
    COMMUTATOR = '=',
    NEGATOR = '<>',
    RESTRICT = eqsel
);

CREATE FUNCTION int8_neq_rdfnode(int8, rdfnode)
RETURNS boolean
AS 'MODULE_PATHNAME', 'int8_neq_rdfnode'
LANGUAGE C IMMUTABLE STRICT;

CREATE OPERATOR <> (
    LEFTARG = int8,
    RIGHTARG = rdfnode,
    PROCEDURE = int8_neq_rdfnode,
    COMMUTATOR = '<>',
    NEGATOR = '=',
    RESTRICT = neqsel
);

CREATE FUNCTION int8_lt_rdfnode(int8, rdfnode)
RETURNS boolean
AS 'MODULE_PATHNAME', 'int8_lt_rdfnode'
LANGUAGE C IMMUTABLE STRICT;

CREATE OPERATOR < (
    LEFTARG = int8,
    RIGHTARG = rdfnode,
    PROCEDURE = int8_lt_rdfnode,
    COMMUTATOR = >,
    NEGATOR = >=,
    RESTRICT = scalarltsel
);

CREATE FUNCTION int8_gt_rdfnode(int8, rdfnode)
RETURNS boolean
AS 'MODULE_PATHNAME', 'int8_gt_rdfnode'
LANGUAGE C IMMUTABLE STRICT;

CREATE OPERATOR > (
    LEFTARG = int8,
    RIGHTARG = rdfnode,
    PROCEDURE = int8_gt_rdfnode,
    COMMUTATOR = <,
    NEGATOR = <=,
    RESTRICT = scalargtsel
);

CREATE FUNCTION int8_le_rdfnode(int8, rdfnode)
RETURNS boolean
AS 'MODULE_PATHNAME', 'int8_le_rdfnode'
LANGUAGE C IMMUTABLE STRICT;

CREATE OPERATOR <= (
    LEFTARG = int8,
    RIGHTARG = rdfnode,
    PROCEDURE = int8_le_rdfnode,
    COMMUTATOR = >=,
    NEGATOR = >,
    RESTRICT = scalarltsel
);

CREATE FUNCTION int8_ge_rdfnode(int8, rdfnode)
RETURNS boolean
AS 'MODULE_PATHNAME', 'int8_ge_rdfnode'
LANGUAGE C IMMUTABLE STRICT;

CREATE OPERATOR >= (
    LEFTARG = int8,
    RIGHTARG = rdfnode,
    PROCEDURE = int8_ge_rdfnode,
    COMMUTATOR = <=,
    NEGATOR = <,
    RESTRICT = scalargtsel
);

/* rdfnode OP int4 (int) */
CREATE FUNCTION rdfnode_to_int4(rdfnode)
RETURNS int
AS 'MODULE_PATHNAME', 'rdfnode_to_int4'
LANGUAGE C IMMUTABLE STRICT;

CREATE CAST (rdfnode AS int)
WITH FUNCTION rdfnode_to_int4(rdfnode) 
AS IMPLICIT;

CREATE FUNCTION rdfnode_eq_int4(rdfnode, int4)
RETURNS boolean
AS 'MODULE_PATHNAME', 'rdfnode_eq_int4'
LANGUAGE C IMMUTABLE STRICT;

CREATE OPERATOR = (
    LEFTARG = rdfnode,
    RIGHTARG = int4,
    PROCEDURE = rdfnode_eq_int4,
    COMMUTATOR = '=',
    NEGATOR = '<>',
    RESTRICT = eqsel
);

CREATE FUNCTION rdfnode_neq_int4(rdfnode, int4)
RETURNS boolean
AS 'MODULE_PATHNAME', 'rdfnode_neq_int4'
LANGUAGE C IMMUTABLE STRICT;

CREATE OPERATOR <> (
    LEFTARG = rdfnode,
    RIGHTARG = int4,
    PROCEDURE = rdfnode_neq_int4,
    COMMUTATOR = '<>',
    NEGATOR = '=',
    RESTRICT = neqsel
);

CREATE FUNCTION rdfnode_lt_int4(rdfnode, int4)
RETURNS boolean
AS 'MODULE_PATHNAME', 'rdfnode_lt_int4'
LANGUAGE C IMMUTABLE STRICT;

CREATE OPERATOR < (
    LEFTARG = rdfnode,
    RIGHTARG = int4,
    PROCEDURE = rdfnode_lt_int4,
    COMMUTATOR = >,
    NEGATOR = >=,
    RESTRICT = scalarltsel
);

CREATE FUNCTION rdfnode_gt_int4(rdfnode, int4)
RETURNS boolean
AS 'MODULE_PATHNAME', 'rdfnode_gt_int4'
LANGUAGE C IMMUTABLE STRICT;

CREATE OPERATOR > (
    LEFTARG = rdfnode,
    RIGHTARG = int4,
    PROCEDURE = rdfnode_gt_int4,
    COMMUTATOR = <,
    NEGATOR = <=,
    RESTRICT = scalargtsel
);

CREATE FUNCTION rdfnode_le_int4(rdfnode, int4)
RETURNS boolean
AS 'MODULE_PATHNAME', 'rdfnode_le_int4'
LANGUAGE C IMMUTABLE STRICT;

CREATE OPERATOR <= (
    LEFTARG = rdfnode,
    RIGHTARG = int4,
    PROCEDURE = rdfnode_le_int4,
    COMMUTATOR = >=,
    NEGATOR = >,
    RESTRICT = scalarltsel
);

CREATE FUNCTION rdfnode_ge_int4(rdfnode, int4)
RETURNS boolean
AS 'MODULE_PATHNAME', 'rdfnode_ge_int4'
LANGUAGE C IMMUTABLE STRICT;

CREATE OPERATOR >= (
    LEFTARG = rdfnode,
    RIGHTARG = int4,
    PROCEDURE = rdfnode_ge_int4,
    COMMUTATOR = <=,
    NEGATOR = <,
    RESTRICT = scalargtsel
);


/* int4 (int) OP rdfnode */
CREATE FUNCTION int4_to_rdfnode(int)
RETURNS rdfnode
AS 'MODULE_PATHNAME', 'int4_to_rdfnode'
LANGUAGE C IMMUTABLE STRICT;

CREATE CAST (int AS rdfnode)
WITH FUNCTION int4_to_rdfnode(int);

CREATE FUNCTION int4_eq_rdfnode(int4, rdfnode)
RETURNS boolean
AS 'MODULE_PATHNAME', 'int4_eq_rdfnode'
LANGUAGE C IMMUTABLE STRICT;

CREATE OPERATOR = (
    LEFTARG = int4,
    RIGHTARG = rdfnode,
    PROCEDURE = int4_eq_rdfnode,
    COMMUTATOR = '=',
    NEGATOR = '<>',
    RESTRICT = eqsel
);

CREATE FUNCTION int4_neq_rdfnode(int4, rdfnode)
RETURNS boolean
AS 'MODULE_PATHNAME', 'int4_neq_rdfnode'
LANGUAGE C IMMUTABLE STRICT;

CREATE OPERATOR <> (
    LEFTARG = int4,
    RIGHTARG = rdfnode,
    PROCEDURE = int4_neq_rdfnode,
    COMMUTATOR = '<>',
    NEGATOR = '=',
    RESTRICT = neqsel
);

CREATE FUNCTION int4_lt_rdfnode(int4, rdfnode)
RETURNS boolean
AS 'MODULE_PATHNAME', 'int4_lt_rdfnode'
LANGUAGE C IMMUTABLE STRICT;

CREATE OPERATOR < (
    LEFTARG = int4,
    RIGHTARG = rdfnode,
    PROCEDURE = int4_lt_rdfnode,
    COMMUTATOR = >,
    NEGATOR = >=,
    RESTRICT = scalarltsel
);

CREATE FUNCTION int4_gt_rdfnode(int4, rdfnode)
RETURNS boolean
AS 'MODULE_PATHNAME', 'int4_gt_rdfnode'
LANGUAGE C IMMUTABLE STRICT;

CREATE OPERATOR > (
    LEFTARG = int4,
    RIGHTARG = rdfnode,
    PROCEDURE = int4_gt_rdfnode,
    COMMUTATOR = <,
    NEGATOR = <=,
    RESTRICT = scalargtsel
);

CREATE FUNCTION int4_le_rdfnode(int4, rdfnode)
RETURNS boolean
AS 'MODULE_PATHNAME', 'int4_le_rdfnode'
LANGUAGE C IMMUTABLE STRICT;

CREATE OPERATOR <= (
    LEFTARG = int4,
    RIGHTARG = rdfnode,
    PROCEDURE = int4_le_rdfnode,
    COMMUTATOR = >=,
    NEGATOR = >,
    RESTRICT = scalarltsel
);

CREATE FUNCTION int4_ge_rdfnode(int4, rdfnode)
RETURNS boolean
AS 'MODULE_PATHNAME', 'int4_ge_rdfnode'
LANGUAGE C IMMUTABLE STRICT;

CREATE OPERATOR >= (
    LEFTARG = int4,
    RIGHTARG = rdfnode,
    PROCEDURE = int4_ge_rdfnode,
    COMMUTATOR = <=,
    NEGATOR = <,
    RESTRICT = scalargtsel
);

/* rdfnode OP int2 (smallint) */
CREATE FUNCTION rdfnode_to_int2(rdfnode)
RETURNS smallint
AS 'MODULE_PATHNAME', 'rdfnode_to_int2'
LANGUAGE C IMMUTABLE STRICT;

CREATE CAST (rdfnode AS smallint)
WITH FUNCTION rdfnode_to_int2(rdfnode) 
AS IMPLICIT;

CREATE FUNCTION rdfnode_eq_int2(rdfnode, int2)
RETURNS boolean
AS 'MODULE_PATHNAME', 'rdfnode_eq_int2'
LANGUAGE C IMMUTABLE STRICT;

CREATE OPERATOR = (
    LEFTARG = rdfnode,
    RIGHTARG = int2,
    PROCEDURE = rdfnode_eq_int2,
    COMMUTATOR = '=',
    NEGATOR = '<>',
    RESTRICT = eqsel
);

CREATE FUNCTION rdfnode_neq_int2(rdfnode, int2)
RETURNS boolean
AS 'MODULE_PATHNAME', 'rdfnode_neq_int2'
LANGUAGE C IMMUTABLE STRICT;

CREATE OPERATOR <> (
    LEFTARG = rdfnode,
    RIGHTARG = int2,
    PROCEDURE = rdfnode_neq_int2,
    COMMUTATOR = '<>',
    NEGATOR = '=',
    RESTRICT = neqsel
);

CREATE FUNCTION rdfnode_lt_int2(rdfnode, int2)
RETURNS boolean
AS 'MODULE_PATHNAME', 'rdfnode_lt_int2'
LANGUAGE C IMMUTABLE STRICT;

CREATE OPERATOR < (
    LEFTARG = rdfnode,
    RIGHTARG = int2,
    PROCEDURE = rdfnode_lt_int2,
    COMMUTATOR = >,
    NEGATOR = >=,
    RESTRICT = scalarltsel
);

CREATE FUNCTION rdfnode_gt_int2(rdfnode, int2)
RETURNS boolean
AS 'MODULE_PATHNAME', 'rdfnode_gt_int2'
LANGUAGE C IMMUTABLE STRICT;

CREATE OPERATOR > (
    LEFTARG = rdfnode,
    RIGHTARG = int2,
    PROCEDURE = rdfnode_gt_int2,
    COMMUTATOR = <,
    NEGATOR = <=,
    RESTRICT = scalargtsel
);

CREATE FUNCTION rdfnode_le_int2(rdfnode, int2)
RETURNS boolean
AS 'MODULE_PATHNAME', 'rdfnode_le_int2'
LANGUAGE C IMMUTABLE STRICT;

CREATE OPERATOR <= (
    LEFTARG = rdfnode,
    RIGHTARG = int2,
    PROCEDURE = rdfnode_le_int2,
    COMMUTATOR = >=,
    NEGATOR = >,
    RESTRICT = scalarltsel
);

CREATE FUNCTION rdfnode_ge_int2(rdfnode, int2)
RETURNS boolean
AS 'MODULE_PATHNAME', 'rdfnode_ge_int2'
LANGUAGE C IMMUTABLE STRICT;

CREATE OPERATOR >= (
    LEFTARG = rdfnode,
    RIGHTARG = int2,
    PROCEDURE = rdfnode_ge_int2,
    COMMUTATOR = <=,
    NEGATOR = <,
    RESTRICT = scalargtsel
);


/* int2 (smallint) OP rdfnode */
CREATE FUNCTION int2_to_rdfnode(smallint)
RETURNS rdfnode
AS 'MODULE_PATHNAME', 'int2_to_rdfnode'
LANGUAGE C IMMUTABLE STRICT;

CREATE CAST (smallint AS rdfnode)
WITH FUNCTION int2_to_rdfnode(smallint) 
AS IMPLICIT;

CREATE FUNCTION int2_eq_rdfnode(int2, rdfnode)
RETURNS boolean
AS 'MODULE_PATHNAME', 'int2_eq_rdfnode'
LANGUAGE C IMMUTABLE STRICT;

CREATE OPERATOR = (
    LEFTARG = int2,
    RIGHTARG = rdfnode,
    PROCEDURE = int2_eq_rdfnode,
    COMMUTATOR = '=',
    NEGATOR = '<>',
    RESTRICT = eqsel
);

CREATE FUNCTION int2_neq_rdfnode(int2, rdfnode)
RETURNS boolean
AS 'MODULE_PATHNAME', 'int2_neq_rdfnode'
LANGUAGE C IMMUTABLE STRICT;

CREATE OPERATOR <> (
    LEFTARG = int2,
    RIGHTARG = rdfnode,
    PROCEDURE = int2_neq_rdfnode,
    COMMUTATOR = '<>',
    NEGATOR = '=',
    RESTRICT = neqsel
);

CREATE FUNCTION int2_lt_rdfnode(int2, rdfnode)
RETURNS boolean
AS 'MODULE_PATHNAME', 'int2_lt_rdfnode'
LANGUAGE C IMMUTABLE STRICT;

CREATE OPERATOR < (
    LEFTARG = int2,
    RIGHTARG = rdfnode,
    PROCEDURE = int2_lt_rdfnode,
    COMMUTATOR = >,
    NEGATOR = >=,
    RESTRICT = scalarltsel
);

CREATE FUNCTION int2_gt_rdfnode(int2, rdfnode)
RETURNS boolean
AS 'MODULE_PATHNAME', 'int2_gt_rdfnode'
LANGUAGE C IMMUTABLE STRICT;

CREATE OPERATOR > (
    LEFTARG = int2,
    RIGHTARG = rdfnode,
    PROCEDURE = int2_gt_rdfnode,
    COMMUTATOR = <,
    NEGATOR = <=,
    RESTRICT = scalargtsel
);

CREATE FUNCTION int2_le_rdfnode(int2, rdfnode)
RETURNS boolean
AS 'MODULE_PATHNAME', 'int2_le_rdfnode'
LANGUAGE C IMMUTABLE STRICT;

CREATE OPERATOR <= (
    LEFTARG = int2,
    RIGHTARG = rdfnode,
    PROCEDURE = int2_le_rdfnode,
    COMMUTATOR = >=,
    NEGATOR = >,
    RESTRICT = scalarltsel
);

CREATE FUNCTION int2_ge_rdfnode(int2, rdfnode)
RETURNS boolean
AS 'MODULE_PATHNAME', 'int2_ge_rdfnode'
LANGUAGE C IMMUTABLE STRICT;

CREATE OPERATOR >= (
    LEFTARG = int2,
    RIGHTARG = rdfnode,
    PROCEDURE = int2_ge_rdfnode,
    COMMUTATOR = <=,
    NEGATOR = <,
    RESTRICT = scalargtsel
);

-- rdfnode OP timestamptz (timestamp with time zone)
CREATE FUNCTION rdfnode_to_timestamptz(rdfnode)
RETURNS timestamptz
AS 'MODULE_PATHNAME', 'rdfnode_to_timestamptz'
LANGUAGE C IMMUTABLE STRICT;

CREATE CAST (rdfnode AS timestamptz)
WITH FUNCTION rdfnode_to_timestamptz(rdfnode);

CREATE FUNCTION rdfnode_lt_timestamptz(rdfnode, timestamptz)
RETURNS boolean LANGUAGE SQL IMMUTABLE AS
$$ SELECT rdfnode_to_timestamptz($1) < $2; $$;

CREATE OPERATOR < (
    LEFTARG = rdfnode,
    RIGHTARG = timestamptz,
    PROCEDURE = rdfnode_lt_timestamptz,
    COMMUTATOR = >,
    NEGATOR = >=,
    RESTRICT = scalarltsel
);

CREATE FUNCTION rdfnode_gt_timestamptz(rdfnode, timestamptz)
RETURNS boolean LANGUAGE SQL IMMUTABLE AS
$$ SELECT rdfnode_to_timestamptz($1) > $2; $$;

CREATE OPERATOR > (
    LEFTARG = rdfnode,
    RIGHTARG = timestamptz,
    PROCEDURE = rdfnode_gt_timestamptz,
    COMMUTATOR = <,
    NEGATOR = <=,
    RESTRICT = scalargtsel
);

CREATE FUNCTION rdfnode_le_timestamptz(rdfnode, timestamptz)
RETURNS boolean LANGUAGE SQL IMMUTABLE AS
$$ SELECT rdfnode_to_timestamptz($1) <= $2; $$;

CREATE OPERATOR <= (
    LEFTARG = rdfnode,
    RIGHTARG = timestamptz,
    PROCEDURE = rdfnode_le_timestamptz,
    COMMUTATOR = >=,
    NEGATOR = >,
    RESTRICT = scalarltsel
);

CREATE FUNCTION rdfnode_ge_timestamptz(rdfnode, timestamptz)
RETURNS boolean LANGUAGE SQL IMMUTABLE AS
$$ SELECT rdfnode_to_timestamptz($1) >= $2; $$;

CREATE OPERATOR >= (
    LEFTARG = rdfnode,
    RIGHTARG = timestamptz,
    PROCEDURE = rdfnode_ge_timestamptz,
    COMMUTATOR = <=,
    NEGATOR = <,
    RESTRICT = scalargtsel
);

CREATE FUNCTION rdfnode_eq_timestamptz(rdfnode, timestamptz)
RETURNS boolean LANGUAGE SQL IMMUTABLE AS
$$ SELECT rdfnode_to_timestamptz($1) = $2; $$;

CREATE OPERATOR = (
    LEFTARG = rdfnode,
    RIGHTARG = timestamptz,
    PROCEDURE = rdfnode_eq_timestamptz,
    COMMUTATOR = '=',
    NEGATOR = '<>',
    RESTRICT = eqsel
);

CREATE FUNCTION rdfnode_neq_timestamptz(rdfnode, timestamptz)
RETURNS boolean LANGUAGE SQL IMMUTABLE AS
$$ SELECT rdfnode_to_timestamptz($1) <> $2; $$;

CREATE OPERATOR <> (
    LEFTARG = rdfnode,
    RIGHTARG = timestamptz,
    PROCEDURE = rdfnode_neq_timestamptz,
    COMMUTATOR = '<>',
    NEGATOR = '=',
    RESTRICT = neqsel
);


-- timestamptz (timestamp with time zone) OP rdfnode
CREATE FUNCTION timestamptz_to_rdfnode(timestamptz)
RETURNS rdfnode
AS 'MODULE_PATHNAME', 'timestamptz_to_rdfnode'
LANGUAGE C IMMUTABLE STRICT;

CREATE CAST (timestamptz AS rdfnode)
WITH FUNCTION timestamptz_to_rdfnode(timestamptz);

CREATE FUNCTION timestamptz_lt_rdfnode(timestamptz, rdfnode)
RETURNS boolean LANGUAGE SQL IMMUTABLE AS
$$ SELECT $1 < rdfnode_to_timestamptz($2); $$;

CREATE OPERATOR < (
    LEFTARG = timestamptz,
    RIGHTARG = rdfnode,
    PROCEDURE = timestamptz_lt_rdfnode,
    COMMUTATOR = >,
    NEGATOR = >=,
    RESTRICT = scalarltsel
);

CREATE FUNCTION timestamptz_gt_rdfnode(timestamptz, rdfnode)
RETURNS boolean LANGUAGE SQL IMMUTABLE AS
$$ SELECT $1 > rdfnode_to_timestamptz($2); $$;

CREATE OPERATOR > (
    LEFTARG = timestamptz,
    RIGHTARG = rdfnode,
    PROCEDURE = timestamptz_gt_rdfnode,
    COMMUTATOR = <,
    NEGATOR = <=,
    RESTRICT = scalargtsel
);

CREATE FUNCTION timestamptz_le_rdfnode(timestamptz, rdfnode)
RETURNS boolean LANGUAGE SQL IMMUTABLE AS
$$ SELECT $1 <= rdfnode_to_timestamptz($2); $$;

CREATE OPERATOR <= (
    LEFTARG = timestamptz,
    RIGHTARG = rdfnode,
    PROCEDURE = timestamptz_le_rdfnode,
    COMMUTATOR = >=,
    NEGATOR = >,
    RESTRICT = scalarltsel
);

CREATE FUNCTION timestamptz_ge_rdfnode(timestamptz, rdfnode)
RETURNS boolean LANGUAGE SQL IMMUTABLE AS
$$ SELECT $1 >= rdfnode_to_timestamptz($2); $$;

CREATE OPERATOR >= (
    LEFTARG = timestamptz,
    RIGHTARG = rdfnode,
    PROCEDURE = timestamptz_ge_rdfnode,
    COMMUTATOR = <=,
    NEGATOR = <,
    RESTRICT = scalargtsel
);

CREATE FUNCTION timestamptz_eq_rdfnode(timestamptz, rdfnode)
RETURNS boolean LANGUAGE SQL IMMUTABLE AS
$$ SELECT $1 = rdfnode_to_timestamptz($2); $$;

CREATE OPERATOR = (
    LEFTARG = timestamptz,
    RIGHTARG = rdfnode,
    PROCEDURE = timestamptz_eq_rdfnode,
    COMMUTATOR = '=',
    NEGATOR = '<>',
    RESTRICT = eqsel
);

CREATE FUNCTION timestamptz_neq_rdfnode(timestamptz, rdfnode)
RETURNS boolean LANGUAGE SQL IMMUTABLE AS
$$ SELECT $1 <> rdfnode_to_timestamptz($2); $$;

CREATE OPERATOR <> (
    LEFTARG = timestamptz,
    RIGHTARG = rdfnode,
    PROCEDURE = timestamptz_neq_rdfnode,
    COMMUTATOR = '<>',
    NEGATOR = '=',
    RESTRICT = neqsel
);

/* rdfnode OP timestamp (without time zone) */
CREATE FUNCTION rdfnode_to_timestamp(rdfnode)
RETURNS timestamp
AS 'MODULE_PATHNAME', 'rdfnode_to_timestamp'
LANGUAGE C IMMUTABLE STRICT;

CREATE CAST (rdfnode AS timestamp)
WITH FUNCTION rdfnode_to_timestamp(rdfnode) 
AS IMPLICIT;

-- CREATE FUNCTION rdfnode_eq_timestamp(rdfnode, timestamp)
-- RETURNS boolean
-- AS 'MODULE_PATHNAME', 'rdfnode_eq_timestamp'
-- LANGUAGE C IMMUTABLE STRICT;

CREATE FUNCTION rdfnode_eq_timestamp(rdfnode, timestamp)
RETURNS boolean LANGUAGE SQL IMMUTABLE AS
$$ SELECT rdfnode_to_timestamp($1) = $2; $$;

CREATE OPERATOR = (
    LEFTARG = rdfnode,
    RIGHTARG = timestamp,
    PROCEDURE = rdfnode_eq_timestamp,
    COMMUTATOR = '=',
    NEGATOR = '<>',
    RESTRICT = eqsel
);

-- CREATE FUNCTION rdfnode_neq_timestamp(rdfnode, timestamp)
-- RETURNS boolean
-- AS 'MODULE_PATHNAME', 'rdfnode_neq_timestamp'
-- LANGUAGE C IMMUTABLE STRICT;

CREATE FUNCTION rdfnode_neq_timestamp(rdfnode, timestamp)
RETURNS boolean LANGUAGE SQL IMMUTABLE AS
$$ SELECT rdfnode_to_timestamp($1) <> $2; $$;

CREATE OPERATOR <> (
    LEFTARG = rdfnode,
    RIGHTARG = timestamp,
    PROCEDURE = rdfnode_neq_timestamp,
    COMMUTATOR = '<>',
    NEGATOR = '=',
    RESTRICT = neqsel
);

--CREATE FUNCTION rdfnode_lt_timestamp(rdfnode, timestamp)
--RETURNS boolean
--AS 'MODULE_PATHNAME', 'rdfnode_lt_timestamp'
--LANGUAGE C IMMUTABLE STRICT;

CREATE FUNCTION rdfnode_lt_timestamp(rdfnode, timestamp)
RETURNS boolean LANGUAGE SQL IMMUTABLE AS
$$ SELECT rdfnode_to_timestamp($1) < $2; $$;

CREATE OPERATOR < (
    LEFTARG = rdfnode,
    RIGHTARG = timestamp,
    PROCEDURE = rdfnode_lt_timestamp,
    COMMUTATOR = >,
    NEGATOR = >=,
    RESTRICT = scalarltsel
);

-- CREATE FUNCTION rdfnode_gt_timestamp(rdfnode, timestamp)
-- RETURNS boolean
-- AS 'MODULE_PATHNAME', 'rdfnode_gt_timestamp'
-- LANGUAGE C IMMUTABLE STRICT;

CREATE FUNCTION rdfnode_gt_timestamp(rdfnode, timestamp)
RETURNS boolean LANGUAGE SQL IMMUTABLE AS
$$ SELECT rdfnode_to_timestamp($1) > $2; $$;

CREATE OPERATOR > (
    LEFTARG = rdfnode,
    RIGHTARG = timestamp,
    PROCEDURE = rdfnode_gt_timestamp,
    COMMUTATOR = <,
    NEGATOR = <=,
    RESTRICT = scalargtsel
);

-- CREATE FUNCTION rdfnode_le_timestamp(rdfnode, timestamp)
-- RETURNS boolean
-- AS 'MODULE_PATHNAME', 'rdfnode_le_timestamp'
-- LANGUAGE C IMMUTABLE STRICT;

CREATE FUNCTION rdfnode_le_timestamp(rdfnode, timestamp)
RETURNS boolean LANGUAGE SQL IMMUTABLE AS
$$ SELECT rdfnode_to_timestamp($1) <= $2; $$;

CREATE OPERATOR <= (
    LEFTARG = rdfnode,
    RIGHTARG = timestamp,
    PROCEDURE = rdfnode_le_timestamp,
    COMMUTATOR = >=,
    NEGATOR = >,
    RESTRICT = scalarltsel
);

-- CREATE FUNCTION rdfnode_ge_timestamp(rdfnode, timestamp)
-- RETURNS boolean
-- AS 'MODULE_PATHNAME', 'rdfnode_ge_timestamp'
-- LANGUAGE C IMMUTABLE STRICT;

CREATE FUNCTION rdfnode_ge_timestamp(rdfnode, timestamp)
RETURNS boolean LANGUAGE SQL IMMUTABLE AS
$$ SELECT rdfnode_to_timestamp($1) >= $2; $$;

CREATE OPERATOR >= (
    LEFTARG = rdfnode,
    RIGHTARG = timestamp,
    PROCEDURE = rdfnode_ge_timestamp,
    COMMUTATOR = <=,
    NEGATOR = <,
    RESTRICT = scalargtsel
);


/* timestamp (without time zone) OP rdfnode */
CREATE FUNCTION timestamp_to_rdfnode(timestamp)
RETURNS rdfnode
AS 'MODULE_PATHNAME', 'timestamp_to_rdfnode'
LANGUAGE C IMMUTABLE STRICT;

CREATE CAST (timestamp AS rdfnode)
WITH FUNCTION timestamp_to_rdfnode(timestamp);

-- CREATE FUNCTION timestamp_eq_rdfnode(timestamp, rdfnode)
-- RETURNS boolean
-- AS 'MODULE_PATHNAME', 'timestamp_eq_rdfnode'
-- LANGUAGE C IMMUTABLE STRICT;

CREATE FUNCTION timestamp_eq_rdfnode(timestamp, rdfnode)
RETURNS boolean LANGUAGE SQL IMMUTABLE AS
$$ SELECT $1 = rdfnode_to_timestamp($2); $$;

CREATE OPERATOR = (
    LEFTARG = timestamp,
    RIGHTARG = rdfnode,
    PROCEDURE = timestamp_eq_rdfnode,
    COMMUTATOR = '=',
    NEGATOR = '<>',
    RESTRICT = eqsel
);

-- CREATE FUNCTION timestamp_neq_rdfnode(timestamp, rdfnode)
-- RETURNS boolean
-- AS 'MODULE_PATHNAME', 'timestamp_neq_rdfnode'
-- LANGUAGE C IMMUTABLE STRICT;

CREATE FUNCTION timestamp_neq_rdfnode(timestamp, rdfnode)
RETURNS boolean LANGUAGE SQL IMMUTABLE AS
$$ SELECT $1 <> rdfnode_to_timestamp($2); $$;

CREATE OPERATOR <> (
    LEFTARG = timestamp,
    RIGHTARG = rdfnode,
    PROCEDURE = timestamp_neq_rdfnode,
    COMMUTATOR = '<>',
    NEGATOR = '=',
    RESTRICT = neqsel
);

-- CREATE FUNCTION timestamp_lt_rdfnode(timestamp, rdfnode)
-- RETURNS boolean
-- AS 'MODULE_PATHNAME', 'timestamp_lt_rdfnode'
-- LANGUAGE C IMMUTABLE STRICT;

CREATE FUNCTION timestamp_lt_rdfnode(timestamp, rdfnode)
RETURNS boolean LANGUAGE SQL IMMUTABLE AS
$$ SELECT $1 < rdfnode_to_timestamp($2); $$;

CREATE OPERATOR < (
    LEFTARG = timestamp,
    RIGHTARG = rdfnode,
    PROCEDURE = timestamp_lt_rdfnode,
    COMMUTATOR = >,
    NEGATOR = >=,
    RESTRICT = scalarltsel
);

-- CREATE FUNCTION timestamp_gt_rdfnode(timestamp, rdfnode)
-- RETURNS boolean
-- AS 'MODULE_PATHNAME', 'timestamp_gt_rdfnode'
-- LANGUAGE C IMMUTABLE STRICT;

CREATE FUNCTION timestamp_gt_rdfnode(timestamp, rdfnode)
RETURNS boolean LANGUAGE SQL IMMUTABLE AS
$$ SELECT $1 > rdfnode_to_timestamp($2); $$;

CREATE OPERATOR > (
    LEFTARG = timestamp,
    RIGHTARG = rdfnode,
    PROCEDURE = timestamp_gt_rdfnode,
    COMMUTATOR = <,
    NEGATOR = <=,
    RESTRICT = scalargtsel
);

-- CREATE FUNCTION timestamp_le_rdfnode(timestamp, rdfnode)
-- RETURNS boolean
-- AS 'MODULE_PATHNAME', 'timestamp_le_rdfnode'
-- LANGUAGE C IMMUTABLE STRICT;

CREATE FUNCTION timestamp_le_rdfnode(timestamp, rdfnode)
RETURNS boolean LANGUAGE SQL IMMUTABLE AS
$$ SELECT $1 <= rdfnode_to_timestamp($2); $$;

CREATE OPERATOR <= (
    LEFTARG = timestamp,
    RIGHTARG = rdfnode,
    PROCEDURE = timestamp_le_rdfnode,
    COMMUTATOR = >=,
    NEGATOR = >,
    RESTRICT = scalarltsel
);

-- CREATE FUNCTION timestamp_ge_rdfnode(timestamp, rdfnode)
-- RETURNS boolean
-- AS 'MODULE_PATHNAME', 'timestamp_ge_rdfnode'
-- LANGUAGE C IMMUTABLE STRICT;

CREATE FUNCTION timestamp_ge_rdfnode(timestamp, rdfnode)
RETURNS boolean LANGUAGE SQL IMMUTABLE AS
$$ SELECT $1 >= rdfnode_to_timestamp($2); $$;

CREATE OPERATOR >= (
    LEFTARG = timestamp,
    RIGHTARG = rdfnode,
    PROCEDURE = timestamp_ge_rdfnode,
    COMMUTATOR = <=,
    NEGATOR = <,
    RESTRICT = scalargtsel
);

/* ## rdfnode OP date ## */
CREATE FUNCTION rdfnode_to_date(rdfnode)
RETURNS date
AS 'MODULE_PATHNAME', 'rdfnode_to_date'
LANGUAGE C IMMUTABLE STRICT;

CREATE CAST (rdfnode AS date)
WITH FUNCTION rdfnode_to_date(rdfnode);

CREATE FUNCTION rdfnode_eq_date(rdfnode, date)
RETURNS boolean
AS 'MODULE_PATHNAME', 'rdfnode_eq_date'
LANGUAGE C IMMUTABLE STRICT;

CREATE OPERATOR = (
    LEFTARG = rdfnode,
    RIGHTARG = date,
    PROCEDURE = rdfnode_eq_date,
    COMMUTATOR = '=',
    NEGATOR = '<>',
    RESTRICT = eqsel
);

CREATE FUNCTION rdfnode_neq_date(rdfnode, date)
RETURNS boolean
AS 'MODULE_PATHNAME', 'rdfnode_neq_date'
LANGUAGE C IMMUTABLE STRICT;

CREATE OPERATOR <> (
    LEFTARG = rdfnode,
    RIGHTARG = date,
    PROCEDURE = rdfnode_neq_date,
    COMMUTATOR = '<>',
    NEGATOR = '=',
    RESTRICT = neqsel
);

CREATE FUNCTION rdfnode_lt_date(rdfnode, date)
RETURNS boolean
AS 'MODULE_PATHNAME', 'rdfnode_lt_date'
LANGUAGE C IMMUTABLE STRICT;

CREATE OPERATOR < (
    LEFTARG = rdfnode,
    RIGHTARG = date,
    PROCEDURE = rdfnode_lt_date,
    COMMUTATOR = >,
    NEGATOR = >=,
    RESTRICT = scalarltsel
);

CREATE FUNCTION rdfnode_gt_date(rdfnode, date)
RETURNS boolean
AS 'MODULE_PATHNAME', 'rdfnode_gt_date'
LANGUAGE C IMMUTABLE STRICT;

CREATE OPERATOR > (
    LEFTARG = rdfnode,
    RIGHTARG = date,
    PROCEDURE = rdfnode_gt_date,
    COMMUTATOR = <,
    NEGATOR = <=,
    RESTRICT = scalargtsel
);

CREATE FUNCTION rdfnode_le_date(rdfnode, date)
RETURNS boolean
AS 'MODULE_PATHNAME', 'rdfnode_le_date'
LANGUAGE C IMMUTABLE STRICT;

CREATE OPERATOR <= (
    LEFTARG = rdfnode,
    RIGHTARG = date,
    PROCEDURE = rdfnode_le_date,
    COMMUTATOR = >=,
    NEGATOR = >,
    RESTRICT = scalarltsel
);

CREATE FUNCTION rdfnode_ge_date(rdfnode, date)
RETURNS boolean
AS 'MODULE_PATHNAME', 'rdfnode_ge_date'
LANGUAGE C IMMUTABLE STRICT;

CREATE OPERATOR >= (
    LEFTARG = rdfnode,
    RIGHTARG = date,
    PROCEDURE = rdfnode_ge_date,
    COMMUTATOR = <=,
    NEGATOR = <,
    RESTRICT = scalargtsel
);

/* date OP rdfnode */
CREATE FUNCTION date_to_rdfnode(date)
RETURNS rdfnode
AS 'MODULE_PATHNAME', 'date_to_rdfnode'
LANGUAGE C IMMUTABLE STRICT;

CREATE CAST (date AS rdfnode)
WITH FUNCTION date_to_rdfnode(date);

CREATE FUNCTION date_eq_rdfnode(date, rdfnode)
RETURNS boolean
AS 'MODULE_PATHNAME', 'date_eq_rdfnode'
LANGUAGE C IMMUTABLE STRICT;

CREATE OPERATOR = (
    LEFTARG = date,
    RIGHTARG = rdfnode,
    PROCEDURE = date_eq_rdfnode,
    COMMUTATOR = '=',
    NEGATOR = '<>',
    RESTRICT = eqsel
);

CREATE FUNCTION date_neq_rdfnode(date, rdfnode)
RETURNS boolean
AS 'MODULE_PATHNAME', 'date_neq_rdfnode'
LANGUAGE C IMMUTABLE STRICT;

CREATE OPERATOR <> (
    LEFTARG = date,
    RIGHTARG = rdfnode,
    PROCEDURE = date_neq_rdfnode,
    COMMUTATOR = '<>',
    NEGATOR = '=',
    RESTRICT = neqsel
);

CREATE FUNCTION date_lt_rdfnode(date, rdfnode)
RETURNS boolean
AS 'MODULE_PATHNAME', 'date_lt_rdfnode'
LANGUAGE C IMMUTABLE STRICT;

CREATE OPERATOR < (
    LEFTARG = date,
    RIGHTARG = rdfnode,
    PROCEDURE = date_lt_rdfnode,
    COMMUTATOR = >,
    NEGATOR = >=,
    RESTRICT = scalarltsel
);

CREATE FUNCTION date_gt_rdfnode(date, rdfnode)
RETURNS boolean
AS 'MODULE_PATHNAME', 'date_gt_rdfnode'
LANGUAGE C IMMUTABLE STRICT;

CREATE OPERATOR > (
    LEFTARG = date,
    RIGHTARG = rdfnode,
    PROCEDURE = date_gt_rdfnode,
    COMMUTATOR = <,
    NEGATOR = <=,
    RESTRICT = scalargtsel
);

CREATE FUNCTION date_le_rdfnode(date, rdfnode)
RETURNS boolean
AS 'MODULE_PATHNAME', 'date_le_rdfnode'
LANGUAGE C IMMUTABLE STRICT;

CREATE OPERATOR <= (
    LEFTARG = date,
    RIGHTARG = rdfnode,
    PROCEDURE = date_le_rdfnode,
    COMMUTATOR = >=,
    NEGATOR = >,
    RESTRICT = scalarltsel
);

CREATE FUNCTION date_ge_rdfnode(date, rdfnode)
RETURNS boolean
AS 'MODULE_PATHNAME', 'date_ge_rdfnode'
LANGUAGE C IMMUTABLE STRICT;

CREATE OPERATOR >= (
    LEFTARG = date,
    RIGHTARG = rdfnode,
    PROCEDURE = date_ge_rdfnode,
    COMMUTATOR = <=,
    NEGATOR = <,
    RESTRICT = scalargtsel
);

/* ## rdfnode OP time ## */
CREATE FUNCTION rdfnode_to_time(rdfnode)
RETURNS time
AS 'MODULE_PATHNAME', 'rdfnode_to_time'
LANGUAGE C IMMUTABLE STRICT;

CREATE CAST (rdfnode AS time)
WITH FUNCTION rdfnode_to_time(rdfnode);

CREATE FUNCTION rdfnode_eq_time(rdfnode, time)
RETURNS boolean
AS 'MODULE_PATHNAME', 'rdfnode_eq_time'
LANGUAGE C IMMUTABLE STRICT;

CREATE OPERATOR = (
    LEFTARG = rdfnode,
    RIGHTARG = time,
    PROCEDURE = rdfnode_eq_time,
    COMMUTATOR = '=',
    NEGATOR = '<>',
    RESTRICT = eqsel
);

CREATE FUNCTION rdfnode_neq_time(rdfnode, time)
RETURNS boolean
AS 'MODULE_PATHNAME', 'rdfnode_neq_time'
LANGUAGE C IMMUTABLE STRICT;

CREATE OPERATOR <> (
    LEFTARG = rdfnode,
    RIGHTARG = time,
    PROCEDURE = rdfnode_neq_time,
    COMMUTATOR = '<>',
    NEGATOR = '=',
    RESTRICT = neqsel
);

CREATE FUNCTION rdfnode_lt_time(rdfnode, time)
RETURNS boolean
AS 'MODULE_PATHNAME', 'rdfnode_lt_time'
LANGUAGE C IMMUTABLE STRICT;

CREATE OPERATOR < (
    LEFTARG = rdfnode,
    RIGHTARG = time,
    PROCEDURE = rdfnode_lt_time,
    COMMUTATOR = >,
    NEGATOR = >=,
    RESTRICT = scalarltsel
);

CREATE FUNCTION rdfnode_gt_time(rdfnode, time)
RETURNS boolean
AS 'MODULE_PATHNAME', 'rdfnode_gt_time'
LANGUAGE C IMMUTABLE STRICT;

CREATE OPERATOR > (
    LEFTARG = rdfnode,
    RIGHTARG = time,
    PROCEDURE = rdfnode_gt_time,
    COMMUTATOR = <,
    NEGATOR = <=,
    RESTRICT = scalargtsel
);

CREATE FUNCTION rdfnode_le_time(rdfnode, time)
RETURNS boolean
AS 'MODULE_PATHNAME', 'rdfnode_le_time'
LANGUAGE C IMMUTABLE STRICT;

CREATE OPERATOR <= (
    LEFTARG = rdfnode,
    RIGHTARG = time,
    PROCEDURE = rdfnode_le_time,
    COMMUTATOR = >=,
    NEGATOR = >,
    RESTRICT = scalarltsel
);

CREATE FUNCTION rdfnode_ge_time(rdfnode, time)
RETURNS boolean
AS 'MODULE_PATHNAME', 'rdfnode_ge_time'
LANGUAGE C IMMUTABLE STRICT;

CREATE OPERATOR >= (
    LEFTARG = rdfnode,
    RIGHTARG = time,
    PROCEDURE = rdfnode_ge_time,
    COMMUTATOR = <=,
    NEGATOR = <,
    RESTRICT = scalargtsel
);

/* ## time OP rdfnode ## */
CREATE FUNCTION time_to_rdfnode(time)
RETURNS rdfnode
AS 'MODULE_PATHNAME', 'time_to_rdfnode'
LANGUAGE C IMMUTABLE STRICT;

CREATE CAST (time AS rdfnode)
WITH FUNCTION time_to_rdfnode(time);

CREATE FUNCTION time_eq_rdfnode(time, rdfnode)
RETURNS boolean
AS 'MODULE_PATHNAME', 'time_eq_rdfnode'
LANGUAGE C IMMUTABLE STRICT;

CREATE OPERATOR = (
    LEFTARG = time,
    RIGHTARG = rdfnode,
    PROCEDURE = time_eq_rdfnode,
    COMMUTATOR = '=',
    NEGATOR = '<>',
    RESTRICT = eqsel
);

CREATE FUNCTION time_neq_rdfnode(time, rdfnode)
RETURNS boolean
AS 'MODULE_PATHNAME', 'time_neq_rdfnode'
LANGUAGE C IMMUTABLE STRICT;

CREATE OPERATOR <> (
    LEFTARG = time,
    RIGHTARG = rdfnode,
    PROCEDURE = time_neq_rdfnode,
    COMMUTATOR = '<>',
    NEGATOR = '=',
    RESTRICT = neqsel
);

CREATE FUNCTION time_lt_rdfnode(time, rdfnode)
RETURNS boolean
AS 'MODULE_PATHNAME', 'time_lt_rdfnode'
LANGUAGE C IMMUTABLE STRICT;

CREATE OPERATOR < (
    LEFTARG = time,
    RIGHTARG = rdfnode,
    PROCEDURE = time_lt_rdfnode,
    COMMUTATOR = >,
    NEGATOR = >=,
    RESTRICT = scalarltsel
);

CREATE FUNCTION time_gt_rdfnode(time, rdfnode)
RETURNS boolean
AS 'MODULE_PATHNAME', 'time_gt_rdfnode'
LANGUAGE C IMMUTABLE STRICT;

CREATE OPERATOR > (
    LEFTARG = time,
    RIGHTARG = rdfnode,
    PROCEDURE = time_gt_rdfnode,
    COMMUTATOR = <,
    NEGATOR = <=,
    RESTRICT = scalargtsel
);

CREATE FUNCTION time_le_rdfnode(time, rdfnode)
RETURNS boolean
AS 'MODULE_PATHNAME', 'time_le_rdfnode'
LANGUAGE C IMMUTABLE STRICT;

CREATE OPERATOR <= (
    LEFTARG = time,
    RIGHTARG = rdfnode,
    PROCEDURE = time_le_rdfnode,
    COMMUTATOR = >=,
    NEGATOR = >,
    RESTRICT = scalarltsel
);

CREATE FUNCTION time_ge_rdfnode(time, rdfnode)
RETURNS boolean
AS 'MODULE_PATHNAME', 'time_ge_rdfnode'
LANGUAGE C IMMUTABLE STRICT;

CREATE OPERATOR >= (
    LEFTARG = time,
    RIGHTARG = rdfnode,
    PROCEDURE = time_ge_rdfnode,
    COMMUTATOR = <=,
    NEGATOR = <,
    RESTRICT = scalargtsel
);






/* ## rdfnode OP timetz ## */
CREATE FUNCTION rdfnode_to_timetz(rdfnode)
RETURNS timetz
AS 'MODULE_PATHNAME', 'rdfnode_to_timetz'
LANGUAGE C IMMUTABLE STRICT;

CREATE CAST (rdfnode AS timetz)
WITH FUNCTION rdfnode_to_timetz(rdfnode);

CREATE FUNCTION rdfnode_eq_timetz(rdfnode, timetz)
RETURNS boolean
AS 'MODULE_PATHNAME', 'rdfnode_eq_timetz'
LANGUAGE C IMMUTABLE STRICT;

CREATE OPERATOR = (
    LEFTARG = rdfnode,
    RIGHTARG = timetz,
    PROCEDURE = rdfnode_eq_timetz,
    COMMUTATOR = '=',
    NEGATOR = '<>',
    RESTRICT = eqsel
);

CREATE FUNCTION rdfnode_neq_timetz(rdfnode, timetz)
RETURNS boolean
AS 'MODULE_PATHNAME', 'rdfnode_neq_timetz'
LANGUAGE C IMMUTABLE STRICT;

CREATE OPERATOR <> (
    LEFTARG = rdfnode,
    RIGHTARG = timetz,
    PROCEDURE = rdfnode_neq_timetz,
    COMMUTATOR = '<>',
    NEGATOR = '=',
    RESTRICT = neqsel
);

CREATE FUNCTION rdfnode_lt_timetz(rdfnode, timetz)
RETURNS boolean
AS 'MODULE_PATHNAME', 'rdfnode_lt_timetz'
LANGUAGE C IMMUTABLE STRICT;

CREATE OPERATOR < (
    LEFTARG = rdfnode,
    RIGHTARG = timetz,
    PROCEDURE = rdfnode_lt_timetz,
    COMMUTATOR = >,
    NEGATOR = >=,
    RESTRICT = scalarltsel
);

CREATE FUNCTION rdfnode_gt_timetz(rdfnode, timetz)
RETURNS boolean
AS 'MODULE_PATHNAME', 'rdfnode_gt_timetz'
LANGUAGE C IMMUTABLE STRICT;

CREATE OPERATOR > (
    LEFTARG = rdfnode,
    RIGHTARG = timetz,
    PROCEDURE = rdfnode_gt_timetz,
    COMMUTATOR = <,
    NEGATOR = <=,
    RESTRICT = scalargtsel
);

CREATE FUNCTION rdfnode_le_timetz(rdfnode, timetz)
RETURNS boolean
AS 'MODULE_PATHNAME', 'rdfnode_le_timetz'
LANGUAGE C IMMUTABLE STRICT;

CREATE OPERATOR <= (
    LEFTARG = rdfnode,
    RIGHTARG = timetz,
    PROCEDURE = rdfnode_le_timetz,
    COMMUTATOR = >=,
    NEGATOR = >,
    RESTRICT = scalarltsel
);

CREATE FUNCTION rdfnode_ge_timetz(rdfnode, timetz)
RETURNS boolean
AS 'MODULE_PATHNAME', 'rdfnode_ge_timetz'
LANGUAGE C IMMUTABLE STRICT;

CREATE OPERATOR >= (
    LEFTARG = rdfnode,
    RIGHTARG = timetz,
    PROCEDURE = rdfnode_ge_timetz,
    COMMUTATOR = <=,
    NEGATOR = <,
    RESTRICT = scalargtsel
);

/* ## time OP rdfnode ## */
CREATE FUNCTION timetz_to_rdfnode(timetz)
RETURNS rdfnode
AS 'MODULE_PATHNAME', 'timetz_to_rdfnode'
LANGUAGE C IMMUTABLE STRICT;

CREATE CAST (timetz AS rdfnode)
WITH FUNCTION timetz_to_rdfnode(timetz);

CREATE FUNCTION timetz_eq_rdfnode(timetz, rdfnode)
RETURNS boolean
AS 'MODULE_PATHNAME', 'timetz_eq_rdfnode'
LANGUAGE C IMMUTABLE STRICT;

CREATE OPERATOR = (
    LEFTARG = timetz,
    RIGHTARG = rdfnode,
    PROCEDURE = timetz_eq_rdfnode,
    COMMUTATOR = '=',
    NEGATOR = '<>',
    RESTRICT = eqsel
);

CREATE FUNCTION timetz_neq_rdfnode(timetz, rdfnode)
RETURNS boolean
AS 'MODULE_PATHNAME', 'timetz_neq_rdfnode'
LANGUAGE C IMMUTABLE STRICT;

CREATE OPERATOR <> (
    LEFTARG = timetz,
    RIGHTARG = rdfnode,
    PROCEDURE = timetz_neq_rdfnode,
    COMMUTATOR = '<>',
    NEGATOR = '=',
    RESTRICT = neqsel
);

CREATE FUNCTION timetz_lt_rdfnode(timetz, rdfnode)
RETURNS boolean
AS 'MODULE_PATHNAME', 'timetz_lt_rdfnode'
LANGUAGE C IMMUTABLE STRICT;

CREATE OPERATOR < (
    LEFTARG = timetz,
    RIGHTARG = rdfnode,
    PROCEDURE = timetz_lt_rdfnode,
    COMMUTATOR = >,
    NEGATOR = >=,
    RESTRICT = scalarltsel
);

CREATE FUNCTION timetz_gt_rdfnode(timetz, rdfnode)
RETURNS boolean
AS 'MODULE_PATHNAME', 'timetz_gt_rdfnode'
LANGUAGE C IMMUTABLE STRICT;

CREATE OPERATOR > (
    LEFTARG = timetz,
    RIGHTARG = rdfnode,
    PROCEDURE = timetz_gt_rdfnode,
    COMMUTATOR = <,
    NEGATOR = <=,
    RESTRICT = scalargtsel
);

CREATE FUNCTION timetz_le_rdfnode(timetz, rdfnode)
RETURNS boolean
AS 'MODULE_PATHNAME', 'timetz_le_rdfnode'
LANGUAGE C IMMUTABLE STRICT;

CREATE OPERATOR <= (
    LEFTARG = timetz,
    RIGHTARG = rdfnode,
    PROCEDURE = timetz_le_rdfnode,
    COMMUTATOR = >=,
    NEGATOR = >,
    RESTRICT = scalarltsel
);

CREATE FUNCTION timetz_ge_rdfnode(timetz, rdfnode)
RETURNS boolean
AS 'MODULE_PATHNAME', 'timetz_ge_rdfnode'
LANGUAGE C IMMUTABLE STRICT;

CREATE OPERATOR >= (
    LEFTARG = timetz,
    RIGHTARG = rdfnode,
    PROCEDURE = timetz_ge_rdfnode,
    COMMUTATOR = <=,
    NEGATOR = <,
    RESTRICT = scalargtsel
);






-- boolean
CREATE FUNCTION rdfnode_to_boolean(rdfnode)
RETURNS boolean
AS 'MODULE_PATHNAME', 'rdfnode_to_boolean'
LANGUAGE C IMMUTABLE STRICT;

CREATE CAST (rdfnode AS boolean)
WITH FUNCTION rdfnode_to_boolean(rdfnode);

CREATE FUNCTION rdfnode_eq_boolean(rdfnode, boolean)
RETURNS boolean
AS 'MODULE_PATHNAME', 'rdfnode_eq_boolean'
LANGUAGE C IMMUTABLE STRICT;

CREATE OPERATOR = (
    LEFTARG = rdfnode,
    RIGHTARG = boolean,
    PROCEDURE = rdfnode_eq_boolean,
    COMMUTATOR = '=',
    NEGATOR = '<>',
    RESTRICT = eqsel
);

CREATE FUNCTION rdfnode_neq_boolean(rdfnode, boolean)
RETURNS boolean
AS 'MODULE_PATHNAME', 'rdfnode_neq_boolean'
LANGUAGE C IMMUTABLE STRICT;

CREATE OPERATOR <> (
    LEFTARG = rdfnode,
    RIGHTARG = boolean,
    PROCEDURE = rdfnode_neq_boolean,
    COMMUTATOR = '<>',
    NEGATOR = '=',
    RESTRICT = neqsel
);

CREATE FUNCTION boolean_to_rdfnode(boolean)
RETURNS rdfnode
AS 'MODULE_PATHNAME', 'boolean_to_rdfnode'
LANGUAGE C IMMUTABLE STRICT;

CREATE CAST (boolean AS rdfnode)
WITH FUNCTION boolean_to_rdfnode(boolean);

CREATE FUNCTION boolean_eq_rdfnode(boolean, rdfnode)
RETURNS boolean
AS 'MODULE_PATHNAME', 'boolean_eq_rdfnode'
LANGUAGE C IMMUTABLE STRICT;

CREATE OPERATOR = (
    LEFTARG = boolean,
    RIGHTARG = rdfnode,
    PROCEDURE = boolean_eq_rdfnode,
    COMMUTATOR = '=',
    NEGATOR = '<>',
    RESTRICT = eqsel
);

CREATE FUNCTION boolean_neq_rdfnode(boolean, rdfnode)
RETURNS boolean
AS 'MODULE_PATHNAME', 'boolean_neq_rdfnode'
LANGUAGE C IMMUTABLE STRICT;

CREATE OPERATOR <> (
    LEFTARG = boolean,
    RIGHTARG = rdfnode,
    PROCEDURE = boolean_neq_rdfnode,
    COMMUTATOR = '<>',
    NEGATOR = '=',
    RESTRICT = neqsel
);



CREATE FUNCTION rdfnode_to_interval(rdfnode)
RETURNS interval
AS 'MODULE_PATHNAME', 'rdfnode_to_interval'
LANGUAGE C IMMUTABLE STRICT;

CREATE CAST (rdfnode AS interval)
WITH FUNCTION rdfnode_to_interval(rdfnode);

/* interval */
CREATE FUNCTION interval_to_rdfnode(interval)
RETURNS rdfnode
AS 'MODULE_PATHNAME', 'interval_to_rdfnode'
LANGUAGE C IMMUTABLE STRICT;

CREATE CAST (interval AS rdfnode)
WITH FUNCTION interval_to_rdfnode(interval);


CREATE FUNCTION rdfnode_eq_interval(rdfnode, interval)
RETURNS boolean
AS 'MODULE_PATHNAME', 'rdfnode_eq_interval'
LANGUAGE C IMMUTABLE STRICT;

CREATE OPERATOR = (
    LEFTARG = rdfnode,
    RIGHTARG = interval,
    PROCEDURE = rdfnode_eq_interval,
    COMMUTATOR = '=',
    NEGATOR = '<>',
    RESTRICT = eqsel
);

CREATE FUNCTION rdfnode_neq_interval(rdfnode, interval)
RETURNS boolean
AS 'MODULE_PATHNAME', 'rdfnode_neq_interval'
LANGUAGE C IMMUTABLE STRICT;

CREATE OPERATOR <> (
    LEFTARG = rdfnode,
    RIGHTARG = interval,
    PROCEDURE = rdfnode_neq_interval,
    COMMUTATOR = '<>',
    NEGATOR = '=',
    RESTRICT = neqsel
);


CREATE FUNCTION rdfnode_lt_interval(rdfnode, interval)
RETURNS boolean
AS 'MODULE_PATHNAME', 'rdfnode_lt_interval'
LANGUAGE C IMMUTABLE STRICT;

CREATE OPERATOR < (
    LEFTARG = rdfnode,
    RIGHTARG = interval,
    PROCEDURE = rdfnode_lt_interval,
    COMMUTATOR = >,
    NEGATOR = >=,
    RESTRICT = scalarltsel
);

CREATE FUNCTION rdfnode_gt_interval(rdfnode, interval)
RETURNS boolean
AS 'MODULE_PATHNAME', 'rdfnode_gt_interval'
LANGUAGE C IMMUTABLE STRICT;

CREATE OPERATOR > (
    LEFTARG = rdfnode,
    RIGHTARG = interval,
    PROCEDURE = rdfnode_gt_interval,
    COMMUTATOR = <,
    NEGATOR = <=,
    RESTRICT = scalargtsel
);

CREATE FUNCTION rdfnode_le_interval(rdfnode, interval)
RETURNS boolean
AS 'MODULE_PATHNAME', 'rdfnode_le_interval'
LANGUAGE C IMMUTABLE STRICT;

CREATE OPERATOR <= (
    LEFTARG = rdfnode,
    RIGHTARG = interval,
    PROCEDURE = rdfnode_le_interval,
    COMMUTATOR = >=,
    NEGATOR = >,
    RESTRICT = scalarltsel
);

CREATE FUNCTION rdfnode_ge_interval(rdfnode, interval)
RETURNS boolean
AS 'MODULE_PATHNAME', 'rdfnode_ge_interval'
LANGUAGE C IMMUTABLE STRICT;

CREATE OPERATOR >= (
    LEFTARG = rdfnode,
    RIGHTARG = interval,
    PROCEDURE = rdfnode_ge_interval,
    COMMUTATOR = <=,
    NEGATOR = <,
    RESTRICT = scalargtsel
);


/**/

CREATE FUNCTION interval_eq_rdfnode(interval, rdfnode)
RETURNS boolean
AS 'MODULE_PATHNAME', 'interval_eq_rdfnode'
LANGUAGE C IMMUTABLE STRICT;

CREATE OPERATOR = (
    LEFTARG = interval,
    RIGHTARG = rdfnode,
    PROCEDURE = interval_eq_rdfnode,
    COMMUTATOR = '=',
    NEGATOR = '<>',
    RESTRICT = eqsel
);

CREATE FUNCTION interval_neq_rdfnode(interval, rdfnode)
RETURNS boolean
AS 'MODULE_PATHNAME', 'interval_neq_rdfnode'
LANGUAGE C IMMUTABLE STRICT;

CREATE OPERATOR <> (
    LEFTARG = interval,
    RIGHTARG = rdfnode,
    PROCEDURE = interval_neq_rdfnode,
    COMMUTATOR = '<>',
    NEGATOR = '=',
    RESTRICT = neqsel
);

CREATE FUNCTION interval_lt_rdfnode(interval, rdfnode)
RETURNS boolean
AS 'MODULE_PATHNAME', 'interval_lt_rdfnode'
LANGUAGE C IMMUTABLE STRICT;

CREATE OPERATOR < (
    LEFTARG = interval,
    RIGHTARG = rdfnode,
    PROCEDURE = interval_lt_rdfnode,
    COMMUTATOR = >,
    NEGATOR = >=,
    RESTRICT = scalarltsel
);

CREATE FUNCTION interval_gt_rdfnode(interval, rdfnode)
RETURNS boolean
AS 'MODULE_PATHNAME', 'interval_gt_rdfnode'
LANGUAGE C IMMUTABLE STRICT;

CREATE OPERATOR > (
    LEFTARG = interval,
    RIGHTARG = rdfnode,
    PROCEDURE = interval_gt_rdfnode,
    COMMUTATOR = <,
    NEGATOR = <=,
    RESTRICT = scalargtsel
);

CREATE FUNCTION interval_le_rdfnode(interval, rdfnode)
RETURNS boolean
AS 'MODULE_PATHNAME', 'interval_le_rdfnode'
LANGUAGE C IMMUTABLE STRICT;

CREATE OPERATOR <= (
    LEFTARG = interval,
    RIGHTARG = rdfnode,
    PROCEDURE = interval_le_rdfnode,
    COMMUTATOR = >=,
    NEGATOR = >,
    RESTRICT = scalarltsel
);

CREATE FUNCTION interval_ge_rdfnode(interval, rdfnode)
RETURNS boolean
AS 'MODULE_PATHNAME', 'interval_ge_rdfnode'
LANGUAGE C IMMUTABLE STRICT;

CREATE OPERATOR >= (
    LEFTARG = interval,
    RIGHTARG = rdfnode,
    PROCEDURE = interval_ge_rdfnode,
    COMMUTATOR = <=,
    NEGATOR = <,
    RESTRICT = scalargtsel
);


/* SPARQL functions in rdf_fdw */

CREATE FUNCTION sparql.lex(rdfnode)
RETURNS text
AS 'MODULE_PATHNAME', 'rdf_fdw_lex'
LANGUAGE C IMMUTABLE STRICT;
COMMENT ON FUNCTION sparql.lex(rdfnode) IS 'Extracts the lexical value of an RDF literal';

CREATE FUNCTION sparql.rdf_fdw_arguments_compatible(text,text) RETURNS boolean
AS 'MODULE_PATHNAME', 'rdf_fdw_arguments_compatible'
LANGUAGE C IMMUTABLE STRICT;
COMMENT ON FUNCTION sparql.rdf_fdw_arguments_compatible(text, text) IS 'Checks if two arguments are compatible for RDF processing.';

CREATE FUNCTION sparql.uri(rdfnode) RETURNS text
AS 'MODULE_PATHNAME', 'rdf_fdw_iri'
LANGUAGE C IMMUTABLE STRICT;
COMMENT ON FUNCTION sparql.uri(rdfnode) IS 'Converts the input text to a URI (alias for iri).';

/* SPARQL 17.4.1 Functional Forms*/
CREATE FUNCTION sparql.bound(rdfnode) RETURNS boolean
AS 'MODULE_PATHNAME', 'rdf_fdw_bound'
LANGUAGE C IMMUTABLE;
COMMENT ON FUNCTION sparql.bound(rdfnode) IS 'Returns true if the argument is bound (non-NULL). Returns false otherwise. This function is used to test whether a SPARQL variable has a value in the current solution.';

CREATE FUNCTION sparql.bound(text) RETURNS boolean AS $$
BEGIN
  RETURN sparql.bound($1::rdfnode);
END;
$$ LANGUAGE plpgsql IMMUTABLE;

CREATE FUNCTION sparql.sameterm(rdfnode, rdfnode) RETURNS boolean
AS 'MODULE_PATHNAME', 'rdf_fdw_sameterm'
LANGUAGE C IMMUTABLE STRICT;

CREATE FUNCTION sparql.coalesce(VARIADIC rdfnode[]) RETURNS rdfnode
AS 'MODULE_PATHNAME', 'rdf_fdw_coalesce'
LANGUAGE C STABLE;

/* SPARQL 17.4.2 Functions on RDF Terms */
CREATE FUNCTION sparql.isIRI(rdfnode) RETURNS boolean
AS 'MODULE_PATHNAME', 'rdf_fdw_isIRI'
LANGUAGE C IMMUTABLE;
COMMENT ON FUNCTION sparql.isIRI(rdfnode) IS 'Checks if the input text is a valid IRI.';

CREATE FUNCTION sparql.isURI(rdfnode) RETURNS boolean
AS 'MODULE_PATHNAME', 'rdf_fdw_isIRI'
LANGUAGE C IMMUTABLE;
COMMENT ON FUNCTION sparql.isURI(rdfnode) IS 'Checks if the input text is a valid URI (alias for isIRI).';

CREATE FUNCTION sparql.isblank(rdfnode) RETURNS boolean
AS 'MODULE_PATHNAME', 'rdf_fdw_isBlank'
LANGUAGE C IMMUTABLE STRICT;
COMMENT ON FUNCTION sparql.isblank(rdfnode) IS 'Checks if the input text is a blank node.';

CREATE FUNCTION sparql.isliteral(rdfnode) RETURNS boolean
AS 'MODULE_PATHNAME', 'rdf_fdw_isLiteral'
LANGUAGE C IMMUTABLE;
COMMENT ON FUNCTION sparql.isliteral(rdfnode) IS 'Checks if the input text is a literal.';

CREATE FUNCTION sparql.isnumeric(rdfnode) RETURNS boolean
AS 'MODULE_PATHNAME', 'rdf_fdw_isNumeric'
LANGUAGE C IMMUTABLE;
COMMENT ON FUNCTION sparql.isnumeric(rdfnode) IS 'Checks if the input text is numeric.';

CREATE FUNCTION sparql.str(rdfnode) RETURNS rdfnode
AS 'MODULE_PATHNAME', 'rdf_fdw_str'
LANGUAGE C IMMUTABLE STRICT;
COMMENT ON FUNCTION sparql.str(rdfnode) IS 'Converts the input to a simple literal string.';

CREATE FUNCTION sparql.lang(rdfnode) RETURNS rdfnode
AS 'MODULE_PATHNAME', 'rdf_fdw_lang'
LANGUAGE C IMMUTABLE STRICT;
COMMENT ON FUNCTION sparql.lang(rdfnode) IS 'Extracts the language tag from the input literal.';

CREATE FUNCTION sparql.datatype(rdfnode) RETURNS rdfnode
AS 'MODULE_PATHNAME', 'rdf_fdw_datatype'
LANGUAGE C IMMUTABLE STRICT;

CREATE FUNCTION sparql.datatype(date) RETURNS rdfnode
AS 'MODULE_PATHNAME', 'rdf_fdw_datatype'
LANGUAGE C IMMUTABLE STRICT;

CREATE FUNCTION sparql.datatype(timestamp) RETURNS rdfnode
AS 'MODULE_PATHNAME', 'rdf_fdw_datatype'
LANGUAGE C IMMUTABLE STRICT;

CREATE FUNCTION sparql.datatype(timestamptz) RETURNS rdfnode
AS 'MODULE_PATHNAME', 'rdf_fdw_datatype'
LANGUAGE C IMMUTABLE STRICT;

CREATE FUNCTION sparql.datatype(int2) RETURNS rdfnode
AS 'MODULE_PATHNAME', 'rdf_fdw_datatype'
LANGUAGE C IMMUTABLE STRICT;

CREATE FUNCTION sparql.datatype(int4) RETURNS rdfnode
AS 'MODULE_PATHNAME', 'rdf_fdw_datatype'
LANGUAGE C IMMUTABLE STRICT;

CREATE FUNCTION sparql.datatype(int8) RETURNS rdfnode
AS 'MODULE_PATHNAME', 'rdf_fdw_datatype'
LANGUAGE C IMMUTABLE STRICT;

CREATE FUNCTION sparql.datatype(numeric) RETURNS rdfnode
AS 'MODULE_PATHNAME', 'rdf_fdw_datatype'
LANGUAGE C IMMUTABLE STRICT;

CREATE FUNCTION sparql.datatype(float4) RETURNS rdfnode
AS 'MODULE_PATHNAME', 'rdf_fdw_datatype'
LANGUAGE C IMMUTABLE STRICT;

CREATE FUNCTION sparql.datatype(float8) RETURNS rdfnode
AS 'MODULE_PATHNAME', 'rdf_fdw_datatype'
LANGUAGE C IMMUTABLE STRICT;

CREATE FUNCTION sparql.datatype(time) RETURNS rdfnode
AS 'MODULE_PATHNAME', 'rdf_fdw_datatype'
LANGUAGE C IMMUTABLE STRICT;

CREATE FUNCTION sparql.datatype(timetz) RETURNS rdfnode
AS 'MODULE_PATHNAME', 'rdf_fdw_datatype'
LANGUAGE C IMMUTABLE STRICT;

CREATE FUNCTION sparql.datatype(text) RETURNS rdfnode
AS 'MODULE_PATHNAME', 'rdf_fdw_datatype'
LANGUAGE C IMMUTABLE STRICT;

CREATE FUNCTION sparql.datatype(name) RETURNS rdfnode
AS 'MODULE_PATHNAME', 'rdf_fdw_datatype'
LANGUAGE C IMMUTABLE STRICT;

CREATE FUNCTION sparql.datatype(boolean) RETURNS rdfnode
AS 'MODULE_PATHNAME', 'rdf_fdw_datatype'
LANGUAGE C IMMUTABLE STRICT;

CREATE FUNCTION sparql.iri(rdfnode) RETURNS rdfnode
AS 'MODULE_PATHNAME', 'rdf_fdw_iri'
LANGUAGE C IMMUTABLE STRICT;
COMMENT ON FUNCTION sparql.iri(rdfnode) IS 'Converts the input text to an IRI.';

CREATE FUNCTION sparql.bnode(rdfnode) RETURNS rdfnode
AS 'MODULE_PATHNAME', 'rdf_fdw_bnode'
LANGUAGE C IMMUTABLE;
COMMENT ON FUNCTION sparql.bnode(rdfnode) IS 'Creates a blank node from the input text.';

CREATE FUNCTION sparql.bnode() RETURNS rdfnode
AS 'MODULE_PATHNAME', 'rdf_fdw_bnode'
LANGUAGE C IMMUTABLE;
COMMENT ON FUNCTION sparql.bnode() IS 'Generates a new blank node identifier.';

CREATE FUNCTION sparql.strdt(rdfnode, rdfnode) RETURNS rdfnode
AS 'MODULE_PATHNAME', 'rdf_fdw_strdt'
LANGUAGE C IMMUTABLE STRICT;
COMMENT ON FUNCTION sparql.strdt(rdfnode, rdfnode) IS 'Combines text with a datatype URI.';

CREATE FUNCTION sparql.strdt(text, text) 
RETURNS rdfnode AS $$
BEGIN
  RETURN sparql.strdt($1::rdfnode, $2::rdfnode);
END;
$$ LANGUAGE plpgsql IMMUTABLE STRICT;

CREATE FUNCTION sparql.strlang(rdfnode, rdfnode) RETURNS rdfnode
AS 'MODULE_PATHNAME', 'rdf_fdw_strlang'
LANGUAGE C IMMUTABLE STRICT;
COMMENT ON FUNCTION sparql.strlang(rdfnode, rdfnode) IS 'Combines text with a language tag.';

CREATE FUNCTION sparql.uuid() RETURNS rdfnode
AS 'MODULE_PATHNAME', 'rdf_fdw_uuid'
LANGUAGE C IMMUTABLE;
COMMENT ON FUNCTION sparql.uuid() IS 'Generates a UUID string.';

CREATE FUNCTION sparql.struuid() RETURNS rdfnode
AS 'MODULE_PATHNAME', 'rdf_fdw_uuid'
LANGUAGE C IMMUTABLE;
COMMENT ON FUNCTION sparql.struuid() IS 'Generates a UUID string.';

/* SPARQL 17.4.3  Functions on Strings */
CREATE FUNCTION sparql.strlen(rdfnode) RETURNS int AS $$
BEGIN
  RETURN length(sparql.lex($1));
END;
$$ LANGUAGE plpgsql IMMUTABLE STRICT;
COMMENT ON FUNCTION sparql.strlen(rdfnode) IS 'Returns the length of the literal text.';

CREATE FUNCTION sparql.substr(rdfnode, int, int)
RETURNS rdfnode
AS 'MODULE_PATHNAME', 'rdf_fdw_substr'
LANGUAGE C IMMUTABLE;
COMMENT ON FUNCTION sparql.substr(rdfnode, int, int) IS 'Extracts a substring from the input literal with start and length.';

CREATE FUNCTION sparql.substr(rdfnode, int)
RETURNS rdfnode
AS 'MODULE_PATHNAME', 'rdf_fdw_substr'
LANGUAGE C IMMUTABLE;
COMMENT ON FUNCTION sparql.substr(rdfnode, int) IS 'Extracts a substring from the input literal starting at the given position.';

CREATE FUNCTION sparql.ucase(rdfnode) RETURNS rdfnode
AS 'MODULE_PATHNAME', 'rdf_fdw_ucase'
LANGUAGE C IMMUTABLE STRICT;
COMMENT ON FUNCTION sparql.ucase(rdfnode) IS 'Converts the input literal to uppercase.';

CREATE FUNCTION sparql.lcase(rdfnode) RETURNS rdfnode
AS 'MODULE_PATHNAME', 'rdf_fdw_lcase'
LANGUAGE C IMMUTABLE STRICT;
COMMENT ON FUNCTION sparql.lcase(rdfnode) IS 'Converts the input literal to lowercase.';

CREATE FUNCTION sparql.strstarts(rdfnode, rdfnode) RETURNS boolean
AS 'MODULE_PATHNAME', 'rdf_fdw_strstarts'
LANGUAGE C IMMUTABLE STRICT;
COMMENT ON FUNCTION sparql.strstarts(rdfnode, rdfnode) IS 'Checks if the first text starts with the second text.';

CREATE FUNCTION sparql.strends(rdfnode, rdfnode) RETURNS boolean
AS 'MODULE_PATHNAME', 'rdf_fdw_strends'
LANGUAGE C IMMUTABLE STRICT;
COMMENT ON FUNCTION sparql.strends(rdfnode, rdfnode) IS 'Checks if the first text ends with the second text.';

CREATE FUNCTION sparql.contains(rdfnode, rdfnode) RETURNS boolean
AS 'MODULE_PATHNAME', 'rdf_fdw_contains'
LANGUAGE C IMMUTABLE STRICT;
COMMENT ON FUNCTION sparql.contains(rdfnode, rdfnode) IS 'Checks if the first text contains the second text.';

CREATE FUNCTION sparql.strbefore(rdfnode, rdfnode) RETURNS rdfnode
AS 'MODULE_PATHNAME', 'rdf_fdw_strbefore'
LANGUAGE C IMMUTABLE STRICT;
COMMENT ON FUNCTION sparql.strbefore(rdfnode, rdfnode) IS 'Returns the substring of the first text before the second text.';

CREATE FUNCTION sparql.strafter(rdfnode, rdfnode) RETURNS rdfnode
AS 'MODULE_PATHNAME', 'rdf_fdw_strafter'
LANGUAGE C IMMUTABLE STRICT;
COMMENT ON FUNCTION sparql.strafter(rdfnode, rdfnode) IS 'Returns the substring of the first text after the second text.';

CREATE FUNCTION sparql.encode_for_uri(rdfnode) RETURNS rdfnode
AS 'MODULE_PATHNAME', 'rdf_fdw_encode_for_uri'
LANGUAGE C IMMUTABLE STRICT;
COMMENT ON FUNCTION sparql.encode_for_uri(rdfnode) IS 'Encodes the input text for use in a URI.';

-- CREATE FUNCTION sparql.coalesce(VARIADIC rdfnode[]) RETURNS rdfnode
-- AS 'MODULE_PATHNAME', 'rdf_fdw_coalesce'
-- LANGUAGE C STABLE;
CREATE FUNCTION sparql.concat(VARIADIC rdfnode[]) RETURNS rdfnode
AS 'MODULE_PATHNAME', 'rdf_fdw_concat'
LANGUAGE C IMMUTABLE STRICT;
--COMMENT ON FUNCTION sparql.concat(rdfnode, rdfnode) IS 'Concatenates two literals inputs for RDF processing.';

CREATE FUNCTION sparql.langmatches(rdfnode, rdfnode) RETURNS boolean
AS 'MODULE_PATHNAME', 'rdf_fdw_langmatches'
LANGUAGE C IMMUTABLE STRICT;
COMMENT ON FUNCTION sparql.langmatches(rdfnode, rdfnode) IS 'Checks if the language tag matches the given pattern.';

CREATE FUNCTION sparql.replace(text, text, text)
RETURNS rdfnode AS $$
BEGIN
  IF sparql.lex($2::rdfnode) = '' THEN
    RAISE EXCEPTION 'pattern cannot be empty in REPLACE()';
  END IF;
  RETURN pg_catalog.replace(sparql.lex($1::rdfnode), sparql.lex($2::rdfnode), sparql.lex($3::rdfnode))::rdfnode;
END;
$$ LANGUAGE plpgsql IMMUTABLE STRICT;

CREATE FUNCTION sparql.replace(rdfnode, rdfnode, rdfnode)
RETURNS rdfnode AS $$
BEGIN
  IF sparql.lex($2) = '' THEN
    RAISE EXCEPTION 'pattern cannot be empty in REPLACE()';
  END IF;
  RETURN pg_catalog.replace(sparql.lex($1), sparql.lex($2), sparql.lex($3))::rdfnode;
END;
$$ LANGUAGE plpgsql IMMUTABLE STRICT;

CREATE FUNCTION sparql.replace(rdfnode, rdfnode, rdfnode, rdfnode)
RETURNS rdfnode
AS $$
BEGIN
  IF sparql.lex($2) = '' THEN
     RAISE EXCEPTION 'pattern cannot be empty in REPLACE()';
  END IF;
  RETURN sparql.str(pg_catalog.regexp_replace(sparql.lex($1), sparql.lex($2), sparql.lex($3), sparql.lex($4) || 'g')::rdfnode);
END;
$$ LANGUAGE plpgsql IMMUTABLE STRICT;

/* SPARQL 17.4.4 Functions on Numerics */
CREATE FUNCTION sparql.abs(text) RETURNS rdfnode  AS $$
BEGIN
  --RETURN pg_catalog.abs(sparql.lex($1::rdfnode)::double precision)::rdfnode;
  RETURN sparql.abs($1::rdfnode);
END;
$$ LANGUAGE plpgsql IMMUTABLE STRICT;

CREATE FUNCTION sparql.abs(rdfnode) RETURNS rdfnode  AS $$
DECLARE dt rdfnode;
BEGIN
  IF NOT sparql.isnumeric($1) THEN
    RAISE EXCEPTION 'invalid value for ABS(): %', $1;
  END IF;

  dt := sparql.datatype($1);

  RETURN sparql.strdt(pg_catalog.abs(sparql.lex($1)::double precision)::rdfnode, dt);
END;
$$ LANGUAGE plpgsql IMMUTABLE STRICT;

CREATE FUNCTION sparql.abs(smallint) RETURNS rdfnode  AS $$
BEGIN
  RETURN pg_catalog.abs($1)::rdfnode;
END;
$$ LANGUAGE plpgsql IMMUTABLE STRICT;

CREATE FUNCTION sparql.abs(int) RETURNS rdfnode AS $$
BEGIN
  RETURN pg_catalog.abs($1)::rdfnode;
END;
$$ LANGUAGE plpgsql IMMUTABLE STRICT;

CREATE FUNCTION sparql.abs(bigint) RETURNS rdfnode AS $$
BEGIN
  RETURN pg_catalog.abs($1)::rdfnode;
END;
$$ LANGUAGE plpgsql IMMUTABLE STRICT;

CREATE FUNCTION sparql.abs(double precision) RETURNS rdfnode  AS $$
BEGIN
  RETURN pg_catalog.abs($1)::rdfnode;
END;
$$ LANGUAGE plpgsql IMMUTABLE STRICT;

CREATE FUNCTION sparql.abs(numeric) RETURNS rdfnode  AS $$
BEGIN
  RETURN pg_catalog.abs($1)::rdfnode;
END;
$$ LANGUAGE plpgsql IMMUTABLE STRICT;

CREATE FUNCTION sparql.abs(real) RETURNS rdfnode  AS $$
BEGIN
  RETURN pg_catalog.abs($1)::rdfnode;
END;
$$ LANGUAGE plpgsql IMMUTABLE STRICT;

CREATE FUNCTION sparql.round(text) RETURNS rdfnode AS $$
BEGIN
  RETURN sparql.round($1::rdfnode);
END;
$$ LANGUAGE plpgsql IMMUTABLE STRICT;

CREATE FUNCTION sparql.round(rdfnode) RETURNS rdfnode AS $$
DECLARE dt rdfnode;
BEGIN
  IF NOT sparql.isnumeric($1) THEN
    RAISE EXCEPTION 'invalid value for ROUND(): %', $1;
  END IF;

  dt := sparql.datatype($1);

  IF $1::rdfnode > 0.0 THEN    
    RETURN sparql.strdt(pg_catalog.floor(sparql.lex($1)::numeric + 0.5)::rdfnode, dt);
  ELSE
    RETURN sparql.strdt(pg_catalog.ceil(sparql.lex($1)::numeric + 0.5)::rdfnode, dt);
  END IF;
END;
$$ LANGUAGE plpgsql IMMUTABLE STRICT;

CREATE FUNCTION sparql.round(double precision) RETURNS rdfnode AS $$
BEGIN
  IF $1 > 0.0 THEN
    RETURN pg_catalog.floor($1 + 0.5)::rdfnode;
  ELSE
    RETURN pg_catalog.ceil($1 + 0.5)::rdfnode;
  END IF;
END;
$$ LANGUAGE plpgsql IMMUTABLE STRICT;

CREATE FUNCTION sparql.ceil(text) RETURNS rdfnode AS $$
BEGIN
  RETURN sparql.ceil($1::rdfnode)::rdfnode;
END;
$$ LANGUAGE plpgsql IMMUTABLE STRICT;

CREATE FUNCTION sparql.ceil(rdfnode) RETURNS rdfnode AS $$
DECLARE dt rdfnode;
BEGIN
  IF NOT sparql.isnumeric($1) THEN
    RAISE EXCEPTION 'invalid value for CEIL(): %', $1;
  END IF;

  dt := sparql.datatype($1);

  RETURN sparql.strdt(pg_catalog.ceil(sparql.lex($1)::numeric)::rdfnode, dt);
END;
$$ LANGUAGE plpgsql IMMUTABLE STRICT;

CREATE FUNCTION sparql.ceil(numeric) RETURNS rdfnode AS $$
BEGIN
  RETURN pg_catalog.ceil($1)::rdfnode;
END;
$$ LANGUAGE plpgsql IMMUTABLE STRICT;

CREATE FUNCTION sparql.ceil(double precision) RETURNS rdfnode AS $$
BEGIN
  RETURN pg_catalog.ceil($1)::rdfnode;
END;
$$ LANGUAGE plpgsql IMMUTABLE STRICT;

CREATE FUNCTION sparql.floor(text) RETURNS rdfnode AS $$
BEGIN
  RETURN sparql.floor($1::rdfnode)::rdfnode;
END;
$$ LANGUAGE plpgsql IMMUTABLE STRICT;

CREATE FUNCTION sparql.floor(rdfnode) RETURNS rdfnode AS $$
DECLARE dt rdfnode;
BEGIN
  IF NOT sparql.isnumeric($1) THEN
    RAISE EXCEPTION 'invalid value for FLOOR(): %', $1;
  END IF;

  dt := sparql.datatype($1);

  RETURN sparql.strdt(pg_catalog.floor(sparql.lex($1)::numeric)::rdfnode, dt);
END;
$$ LANGUAGE plpgsql IMMUTABLE STRICT;

CREATE FUNCTION sparql.floor(numeric) RETURNS rdfnode AS $$
BEGIN
  RETURN pg_catalog.floor($1)::rdfnode;
END;
$$ LANGUAGE plpgsql IMMUTABLE STRICT;

CREATE FUNCTION sparql.floor(double precision) RETURNS rdfnode AS $$
BEGIN
  RETURN pg_catalog.floor($1)::rdfnode;
END;
$$ LANGUAGE plpgsql IMMUTABLE STRICT;

CREATE FUNCTION sparql.rand() RETURNS rdfnode AS $$
BEGIN
  RETURN sparql.strdt(random()::rdfnode,'xsd:double');
END;
$$ LANGUAGE plpgsql STRICT;

/* SPARQL 17.4.5 Functions on Dates and Times */
CREATE FUNCTION sparql.now() RETURNS rdfnode AS $$
BEGIN
  RETURN sparql.strdt(pg_catalog.now()::rdfnode, 'xsd:dateTime');
END;
$$ LANGUAGE plpgsql STABLE STRICT;

CREATE FUNCTION sparql.year(rdfnode)
RETURNS int AS $$
BEGIN
  RETURN EXTRACT(year FROM sparql.lex($1)::date);
END;
$$ LANGUAGE plpgsql STABLE STRICT;

CREATE FUNCTION sparql.year(text)
RETURNS int AS $$
BEGIN
  RETURN sparql.year($1::rdfnode);
END;
$$ LANGUAGE plpgsql STABLE STRICT;

CREATE FUNCTION sparql.year(timestamp)
RETURNS int AS $$
BEGIN
  RETURN EXTRACT(year FROM $1);
END;
$$ LANGUAGE plpgsql STABLE STRICT;

CREATE FUNCTION sparql.month(rdfnode)
RETURNS int AS $$
BEGIN
  RETURN EXTRACT(month FROM sparql.lex($1)::date);
END;
$$ LANGUAGE plpgsql STABLE STRICT;

CREATE FUNCTION sparql.month(text)
RETURNS int AS $$
BEGIN
  RETURN sparql.month($1::rdfnode);
END;
$$ LANGUAGE plpgsql STABLE STRICT;

CREATE FUNCTION sparql.month(timestamp)
RETURNS int AS $$
BEGIN
  RETURN EXTRACT(month FROM $1);
END;
$$ LANGUAGE plpgsql STABLE STRICT;

CREATE FUNCTION sparql.day(rdfnode)
RETURNS int AS $$
BEGIN
  RETURN EXTRACT(day FROM sparql.lex($1)::date);
END;
$$ LANGUAGE plpgsql STABLE STRICT;

CREATE FUNCTION sparql.day(text)
RETURNS int AS $$
BEGIN
  RETURN sparql.day($1::rdfnode);
END;
$$ LANGUAGE plpgsql STABLE STRICT;

CREATE FUNCTION sparql.day(timestamp)
RETURNS int AS $$
BEGIN
  RETURN EXTRACT(day FROM $1);
END;
$$ LANGUAGE plpgsql STABLE STRICT;

CREATE FUNCTION sparql.hours(rdfnode)
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

CREATE FUNCTION sparql.hours(text)
RETURNS int AS $$
BEGIN
  RETURN sparql.hours($1::rdfnode);
END;
$$ LANGUAGE plpgsql STABLE STRICT;

CREATE FUNCTION sparql.hours(timestamp)
RETURNS int AS $$
BEGIN
  RETURN EXTRACT(hour FROM $1);
END;
$$ LANGUAGE plpgsql STABLE STRICT;

CREATE FUNCTION sparql.hours(time)
RETURNS int AS $$
BEGIN
  RETURN EXTRACT(hour FROM $1);
END;
$$ LANGUAGE plpgsql STABLE STRICT;

CREATE FUNCTION sparql.minutes(rdfnode)
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

CREATE FUNCTION sparql.minutes(text)
RETURNS int AS $$
BEGIN
  RETURN sparql.minutes($1::rdfnode);
END;
$$ LANGUAGE plpgsql STABLE STRICT;

CREATE FUNCTION sparql.minutes(timestamp)
RETURNS int AS $$
BEGIN
  RETURN EXTRACT(minute FROM $1);
END;
$$ LANGUAGE plpgsql STABLE STRICT;

CREATE FUNCTION sparql.minutes(time)
RETURNS int AS $$
BEGIN
  RETURN EXTRACT(minute FROM $1);
END;
$$ LANGUAGE plpgsql STABLE STRICT;

CREATE FUNCTION sparql.seconds(rdfnode)
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

CREATE FUNCTION sparql.seconds(text)
RETURNS int AS $$
BEGIN
  RETURN sparql.seconds($1::rdfnode);
END;
$$ LANGUAGE plpgsql STABLE STRICT;

CREATE FUNCTION sparql.seconds(timestamp)
RETURNS numeric AS $$
BEGIN
  RETURN EXTRACT(second FROM $1);
END;
$$ LANGUAGE plpgsql STABLE STRICT;

CREATE FUNCTION sparql.seconds(time)
RETURNS numeric AS $$
BEGIN
  RETURN EXTRACT(second FROM $1);
END;
$$ LANGUAGE plpgsql STABLE STRICT;

CREATE OR REPLACE FUNCTION sparql.timezone(lit rdfnode)
RETURNS rdfnode AS $$
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

CREATE OR REPLACE FUNCTION sparql.timezone(text)
RETURNS rdfnode AS $$
BEGIN
  RETURN sparql.timezone($1::rdfnode);
END;
$$ LANGUAGE plpgsql STABLE STRICT;

CREATE OR REPLACE FUNCTION sparql.tz(lit rdfnode)
RETURNS rdfnode AS $$
DECLARE
  lexical text := sparql.lex(lit);
  tz_offset text;
BEGIN
  -- Extract the timezone part: ±HH:MM or Z at the end of the string
  tz_offset := substring(lexical from '([-+]\d{2}:\d{2}|Z)$');

  IF tz_offset IS NULL THEN
    -- Return an empty string or raise an error based on your requirements
    RAISE EXCEPTION 'TZ(): datetime has no timezone';
  END IF;

  -- If the timezone is 'Z', return 'Z'
  IF tz_offset = 'Z' THEN
    RETURN 'Z';
  END IF;

  -- Otherwise, return the timezone offset ±HH:MM
  RETURN tz_offset;
END;
$$ LANGUAGE plpgsql IMMUTABLE;

CREATE OR REPLACE FUNCTION sparql.tz(text)
RETURNS rdfnode AS $$
BEGIN
  RETURN sparql.tz($1::rdfnode);
END;
$$ LANGUAGE plpgsql STABLE STRICT;

/* SPARQL 17.4.6 Hash Functions */
CREATE FUNCTION sparql.md5(rdfnode) RETURNS rdfnode
AS 'MODULE_PATHNAME', 'rdf_fdw_md5'
LANGUAGE C IMMUTABLE STRICT;

CREATE FUNCTION sparql.md5(text)
RETURNS rdfnode AS $$
BEGIN
  RETURN sparql.md5($1::rdfnode);
END;
$$ LANGUAGE plpgsql STABLE STRICT;

CREATE TYPE triple AS (
  subject rdfnode,
  predicate rdfnode,
  object rdfnode
);

CREATE FUNCTION sparql.describe(server text, query text, base_uri text DEFAULT '')
RETURNS SETOF triple AS 'MODULE_PATHNAME', 'rdf_fdw_describe'
LANGUAGE C IMMUTABLE STRICT;

COMMENT ON FUNCTION sparql.describe(text,text,text) IS 'Gateway for DESCRIBE SPARQL queries';

-- SUM aggregate for rdfnode
CREATE FUNCTION sparql.sum_rdfnode_sfunc(internal, rdfnode)
RETURNS internal AS 'MODULE_PATHNAME', 'rdf_fdw_sum_sfunc'
LANGUAGE C IMMUTABLE;

CREATE FUNCTION sparql.sum_rdfnode_finalfunc(internal)
RETURNS rdfnode AS 'MODULE_PATHNAME', 'rdf_fdw_sum_finalfunc'
LANGUAGE C IMMUTABLE;

CREATE AGGREGATE sparql.sum(rdfnode) (
    SFUNC = sparql.sum_rdfnode_sfunc,
    STYPE = internal,
    FINALFUNC = sparql.sum_rdfnode_finalfunc
);

COMMENT ON AGGREGATE sparql.sum(rdfnode) IS 'Computes the sum of numeric rdfnode values with XSD type promotion (integer < decimal < float < double)';

-- AVG aggregate for rdfnode
CREATE FUNCTION sparql.avg_rdfnode_sfunc(internal, rdfnode)
RETURNS internal AS 'MODULE_PATHNAME', 'rdf_fdw_avg_sfunc'
LANGUAGE C IMMUTABLE;

CREATE FUNCTION sparql.avg_rdfnode_finalfunc(internal)
RETURNS rdfnode AS 'MODULE_PATHNAME', 'rdf_fdw_avg_finalfunc'
LANGUAGE C IMMUTABLE;

CREATE AGGREGATE sparql.avg(rdfnode) (
    SFUNC = sparql.avg_rdfnode_sfunc,
    STYPE = internal,
    FINALFUNC = sparql.avg_rdfnode_finalfunc
);

COMMENT ON AGGREGATE sparql.avg(rdfnode) IS 'Computes the average of numeric rdfnode values with XSD type promotion (integer < decimal < float < double)';

-- MIN aggregate for rdfnode
CREATE FUNCTION sparql.min_rdfnode_sfunc(internal, rdfnode)
RETURNS internal AS 'MODULE_PATHNAME', 'rdf_fdw_min_sfunc'
LANGUAGE C IMMUTABLE;

CREATE FUNCTION sparql.min_rdfnode_finalfunc(internal)
RETURNS rdfnode AS 'MODULE_PATHNAME', 'rdf_fdw_min_finalfunc'
LANGUAGE C IMMUTABLE;

CREATE AGGREGATE sparql.min(rdfnode) (
    SFUNC = sparql.min_rdfnode_sfunc,
    STYPE = internal,
    FINALFUNC = sparql.min_rdfnode_finalfunc
);

-- MAX aggregate for rdfnode
CREATE FUNCTION sparql.max_rdfnode_sfunc(internal, rdfnode)
RETURNS internal AS 'MODULE_PATHNAME', 'rdf_fdw_max_sfunc'
LANGUAGE C IMMUTABLE;

CREATE FUNCTION sparql.max_rdfnode_finalfunc(internal)
RETURNS rdfnode AS 'MODULE_PATHNAME', 'rdf_fdw_max_finalfunc'
LANGUAGE C IMMUTABLE;

CREATE AGGREGATE sparql.max(rdfnode) (
    SFUNC = sparql.max_rdfnode_sfunc,
    STYPE = internal,
    FINALFUNC = sparql.max_rdfnode_finalfunc
);

COMMENT ON AGGREGATE sparql.min(rdfnode) IS 'Returns the minimum numeric rdfnode value';

-- SAMPLE aggregate for rdfnode
CREATE FUNCTION sparql.sample_rdfnode_sfunc(internal, rdfnode)
RETURNS internal AS 'MODULE_PATHNAME', 'rdf_fdw_sample_sfunc'
LANGUAGE C IMMUTABLE;

CREATE FUNCTION sparql.sample_rdfnode_finalfunc(internal)
RETURNS rdfnode AS 'MODULE_PATHNAME', 'rdf_fdw_sample_finalfunc'
LANGUAGE C IMMUTABLE;

CREATE AGGREGATE sparql.sample(rdfnode) (
    SFUNC = sparql.sample_rdfnode_sfunc,
    STYPE = internal,
    FINALFUNC = sparql.sample_rdfnode_finalfunc
);

COMMENT ON AGGREGATE sparql.sample(rdfnode) IS 'Returns an arbitrary (first non-NULL) value from the aggregate group per SPARQL 1.1 Section 18.5.1.8';

-- SPARQL GROUP_CONCAT aggregate function
CREATE OR REPLACE FUNCTION sparql.group_concat_rdfnode_sfunc(internal, rdfnode, text)
RETURNS internal AS 'MODULE_PATHNAME', 'rdf_fdw_group_concat_sfunc'
LANGUAGE C IMMUTABLE;

CREATE OR REPLACE FUNCTION sparql.group_concat_rdfnode_finalfunc(internal)
RETURNS rdfnode AS 'MODULE_PATHNAME', 'rdf_fdw_group_concat_finalfunc'
LANGUAGE C IMMUTABLE;

-- Base aggregate with separator required
CREATE AGGREGATE sparql.group_concat(rdfnode, text) (
    SFUNC = sparql.group_concat_rdfnode_sfunc,
    STYPE = internal,
    FINALFUNC = sparql.group_concat_rdfnode_finalfunc
);

COMMENT ON AGGREGATE sparql.group_concat(rdfnode, text) IS 
'SPARQL 1.1 GROUP_CONCAT aggregate: concatenates string representations of RDF terms with specified separator';

-- Prefix Management
CREATE TABLE sparql.prefix_contexts (
    context text PRIMARY KEY CHECK (context <> ''),
    description text,
    modified_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE sparql.prefixes (
    prefix text NOT NULL CHECK (prefix <> ''),
    uri text NOT NULL,
    context text NOT NULL REFERENCES sparql.prefix_contexts(context) ON DELETE CASCADE,
    modified_at timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (prefix, context)
);

CREATE OR REPLACE FUNCTION sparql.add_context(
    context_name TEXT,
    context_description TEXT DEFAULT NULL,
    override BOOLEAN DEFAULT FALSE
) RETURNS void AS $$
BEGIN
    IF override THEN
        INSERT INTO sparql.prefix_contexts (context, description)
        VALUES (context_name, context_description)
        ON CONFLICT (context) DO UPDATE
        SET description = EXCLUDED.description,
            modified_at = now();
    ELSE
        INSERT INTO sparql.prefix_contexts (context, description)
        VALUES (context_name, context_description);
    END IF;
EXCEPTION WHEN unique_violation THEN
    RAISE EXCEPTION 'prefix context "%" already exists', context_name;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION sparql.drop_context(
    context_name TEXT,
    cascade BOOLEAN DEFAULT FALSE
) RETURNS void AS $$
BEGIN
    IF cascade THEN
        DELETE FROM sparql.prefixes
        WHERE context = context_name;
    ELSE
        -- Check if context has dependent prefixes
        IF EXISTS (
            SELECT 1 FROM sparql.prefixes
            WHERE context = context_name
        ) THEN
            RAISE EXCEPTION 'prefix context "%" has associated prefixes', context_name;
        END IF;
    END IF;

    -- Now delete the context
    DELETE FROM sparql.prefix_contexts
    WHERE context = context_name;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Prefix context "%" does not exist.', context_name;
    END IF;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION sparql.add_prefix(
    context_name TEXT,
    prefix_name TEXT,
    uri TEXT,
    override BOOLEAN DEFAULT FALSE
) RETURNS void AS $$
BEGIN
    IF override THEN
        INSERT INTO sparql.prefixes (context, prefix, uri)
        VALUES ($1, $2, $3)
        ON CONFLICT (context, prefix) DO UPDATE
        SET uri = EXCLUDED.uri,
            modified_at = now();
    ELSE
        INSERT INTO sparql.prefixes (context, prefix, uri)
        VALUES ($1, $2, $3);
    END IF;
EXCEPTION WHEN unique_violation THEN
    RAISE EXCEPTION 'prefix "%" already exists in context "%"', $1, $2;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION sparql.drop_prefix(
    context_name TEXT,
    prefix_name TEXT
) RETURNS void AS $$
BEGIN
    DELETE FROM sparql.prefixes
    WHERE context = $1 AND prefix = $2;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'prefix "%" not found in context "%".', $1, $2;
    END IF;
END;
$$ LANGUAGE plpgsql;

SELECT sparql.add_context('default', 'Default context for SPARQL prefixes');

SELECT sparql.add_prefix('default', 'rdf', 'http://www.w3.org/1999/02/22-rdf-syntax-ns#');
SELECT sparql.add_prefix('default', 'rdfs', 'http://www.w3.org/2000/01/rdf-schema#');
SELECT sparql.add_prefix('default', 'owl', 'http://www.w3.org/2002/07/owl#');
SELECT sparql.add_prefix('default', 'xsd', 'http://www.w3.org/2001/XMLSchema#');
SELECT sparql.add_prefix('default', 'foaf', 'http://xmlns.com/foaf/0.1/');
SELECT sparql.add_prefix('default', 'dc', 'http://purl.org/dc/elements/1.1/');