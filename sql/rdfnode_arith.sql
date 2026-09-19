\pset null NULL
\set VERBOSITY terse
/*
 * Arithmetic on rdfnode.
 *
 * SPARQL 1.1 §17.3 maps +, -, * and / over two numerics onto op:numeric-add
 * and its siblings. They compute in the wider of the two datatypes, the same
 * XPath promotion the comparison operators use, with one exception the table
 * calls out: dividing two xsd:integers gives an xsd:decimal, because the
 * quotient of two integers need not be one.
 *
 * The type had no arithmetic operators at all before this, so PostgreSQL tried
 * to resolve 1::rdfnode + 1::rdfnode through the type's casts, of which four
 * are implicit, and reported that several candidates tied.
 */
SELECT '"1"^^xsd:integer'::rdfnode + '"2"^^xsd:integer'::rdfnode AS int_add,
       '"7"^^xsd:integer'::rdfnode - '"2"^^xsd:integer'::rdfnode AS int_sub,
       '"3"^^xsd:integer'::rdfnode * '"4"^^xsd:integer'::rdfnode AS int_mul;

/* the result takes the wider of the two datatypes */
SELECT '"1"^^xsd:integer'::rdfnode + '"2.5"^^xsd:decimal'::rdfnode AS integer_and_decimal,
       '"1"^^xsd:integer'::rdfnode + '"2.5"^^xsd:double'::rdfnode  AS integer_and_double,
       '"1"^^xsd:float'::rdfnode   + '"2"^^xsd:float'::rdfnode     AS float_and_float;

/* and the promotion does not depend on which side each term is written */
SELECT ('"1"^^xsd:integer'::rdfnode + '"2.5"^^xsd:decimal'::rdfnode)
     = ('"2.5"^^xsd:decimal'::rdfnode + '"1"^^xsd:integer'::rdfnode) AS symmetric;

/* two integers divide into a decimal, with no trailing zeros to make one
 * number into two terms */
SELECT '"1"^^xsd:integer'::rdfnode / '"2"^^xsd:integer'::rdfnode  AS half,
       '"10"^^xsd:integer'::rdfnode / '"5"^^xsd:integer'::rdfnode AS exact,
       '"1"^^xsd:integer'::rdfnode / '"3"^^xsd:integer'::rdfnode  AS repeating;

/* every numeric datatype, and the subtypes that promote to xsd:integer */
SELECT '"1"^^xsd:int'::rdfnode   + '"2"^^xsd:short'::rdfnode    AS int_subtypes,
       '"1"^^xsd:long'::rdfnode  + '"2"^^xsd:byte'::rdfnode     AS long_and_byte,
       '"1.5"^^xsd:decimal'::rdfnode * '"2"^^xsd:double'::rdfnode AS decimal_and_double;

/* negatives, and an integer wider than any machine integer -- xsd:integer has
 * no bound, and the arithmetic must not acquire one */
SELECT '"-5"^^xsd:integer'::rdfnode * '"3"^^xsd:integer'::rdfnode AS negative,
       '"9223372036854775807"^^xsd:integer'::rdfnode + '"1"^^xsd:integer'::rdfnode AS past_int64;

/* IEEE values travel through xsd:double as IEEE says they should */
SELECT '"NaN"^^xsd:double'::rdfnode + '"1"^^xsd:double'::rdfnode   AS nan_stays_nan,
       '"INF"^^xsd:double'::rdfnode + '"1"^^xsd:double'::rdfnode   AS inf_stays_inf,
       '"INF"^^xsd:double'::rdfnode - '"INF"^^xsd:double'::rdfnode AS inf_minus_inf;

/* a decimal result carries no trailing zeros, which is the canonical XSD form
 * and what Fuseki and Virtuoso answer with; one number must not reach storage
 * as two terms */
SELECT '"1.10"^^xsd:decimal'::rdfnode + '"2.20"^^xsd:decimal'::rdfnode AS trailing_zeros,
       '"2.50"^^xsd:decimal'::rdfnode * '"2"^^xsd:integer'::rdfnode     AS exact_result;

/* an xsd:float keeps the precision its value space has: 16777217 is not one of
 * its values, so adding 1 to 16777216 changes nothing */
SELECT '"16777216"^^xsd:float'::rdfnode + '"1"^^xsd:float'::rdfnode
     = '"16777216"^^xsd:float'::rdfnode AS float_precision_kept;

/* arithmetic is defined over numerics: anything else is a type error */
SELECT '"abc"'::rdfnode + '"1"^^xsd:integer'::rdfnode;
SELECT '<http://example.org/s>'::rdfnode + '"1"^^xsd:integer'::rdfnode;
SELECT '"1"^^xsd:integer'::rdfnode + '"2025-01-01"^^xsd:date'::rdfnode;
SELECT '"1"^^xsd:integer'::rdfnode / '"0"^^xsd:integer'::rdfnode;

/* a plain literal is not a numeric literal, whatever it looks like */
SELECT '"1"'::rdfnode + '"2"'::rdfnode;
