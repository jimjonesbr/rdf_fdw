\pset null NULL
\set VERBOSITY terse
/*
 * The B-tree operator class for rdfnode.
 *
 * A B-tree needs a total order, and equality within it has to be an
 * equivalence relation. RDF value comparison is neither. Terms of unlike
 * kinds are incomparable rather than ordered, NaN is not equal to itself,
 * and numeric type promotion makes equality intransitive: an xsd:float
 * literal can be equal to two xsd:integer literals that are not equal to
 * each other, because the float carries fewer significant digits than
 * either of them.
 *
 * The class is therefore built on comparisons of the stored term -- ~<~,
 * ~<=~, ~=, ~>=~ and ~>~ -- which is what rdfnode_cmp has always compared.
 * The value operators =, <>, <, <=, >= and > are unchanged and still mean
 * what they meant; they are simply no longer index search conditions.
 */

/* The value operators and the storage operators answer different questions
 * about the same two terms. */
SELECT '"01"^^xsd:integer'::rdfnode =   '"1"^^xsd:integer'::rdfnode AS same_value,
       '"01"^^xsd:integer'::rdfnode ~=  '"1"^^xsd:integer'::rdfnode AS same_term,
       '"01"^^xsd:integer'::rdfnode ~<~ '"1"^^xsd:integer'::rdfnode AS term_lt;

/* Equality in an operator class must be reflexive. Value equality is not:
 * no numeric comparison involving NaN holds, NaN against itself included. */
SELECT '"NaN"^^xsd:double'::rdfnode =  '"NaN"^^xsd:double'::rdfnode AS same_value,
       '"NaN"^^xsd:double'::rdfnode ~= '"NaN"^^xsd:double'::rdfnode AS same_term;

/* It must also be transitive. Value equality is not: 16777217 is not
 * representable as an xsd:float, so the literal denotes 16777216, which is
 * equal to one xsd:integer and to the other, while those two differ. */
SELECT '"16777217"^^xsd:float'::rdfnode = '"16777216"^^xsd:integer'::rdfnode AS float_eq_16,
       '"16777217"^^xsd:float'::rdfnode = '"16777217"^^xsd:integer'::rdfnode AS float_eq_17,
       '"16777216"^^xsd:integer'::rdfnode = '"16777217"^^xsd:integer'::rdfnode AS ints_eq;

/* Terms of unlike kinds are incomparable as values, so the class orders them
 * the only way it can: by how they are written. That is not the SPARQL term
 * order either -- a quotation mark sorts before an angle bracket, so literals
 * come before IRIs here and after them there. */
SELECT '<http://example.org/a>'::rdfnode ~<~ '"a"'::rdfnode AS iri_lt_literal,
       '"a"@en'::rdfnode ~<~ '"a"^^xsd:string'::rdfnode AS tagged_lt_typed;

/*
 * The defect this class was written for. Sorted grouping compares terms that
 * the sort placed next to each other, so an equality that does not agree with
 * the sort makes the answer depend on which other rows happen to be present:
 * two rows that were one group became two as soon as a third, unrelated row
 * was inserted between them.
 */
CREATE TABLE opclass_pair (term rdfnode);
INSERT INTO opclass_pair VALUES ('"01"^^xsd:integer'), ('"1"^^xsd:integer');
SELECT count(*) AS groups FROM (SELECT DISTINCT term FROM opclass_pair) t;

CREATE TABLE opclass_trio (term rdfnode);
INSERT INTO opclass_trio VALUES ('"01"^^xsd:integer'), ('"1"^^xsd:integer'),
                                ('"02"^^xsd:integer');
SELECT count(*) AS groups FROM (SELECT DISTINCT term FROM opclass_trio) t;

/*
 * The same disagreement let an index exclude rows a sequential scan returned:
 * the scan descended to where the term sorts and stopped there, while the
 * rows it should have found were wherever their own spelling sorts.
 */
CREATE TABLE opclass_scan (term rdfnode);
INSERT INTO opclass_scan VALUES ('"16777216"^^xsd:integer'),
                                ('"16777217"^^xsd:float'),
                                ('"0.5"^^xsd:decimal'),
                                ('"NaN"^^xsd:double');
CREATE INDEX opclass_scan_term ON opclass_scan (term);
ANALYZE opclass_scan;

SET enable_seqscan = off;
SET enable_bitmapscan = off;
SELECT term FROM opclass_scan WHERE term = '"16777217"^^xsd:float' ORDER BY term;
RESET enable_seqscan;
RESET enable_bitmapscan;

SET enable_indexscan = off;
SET enable_indexonlyscan = off;
SELECT term FROM opclass_scan WHERE term = '"16777217"^^xsd:float' ORDER BY term;
RESET enable_indexscan;
RESET enable_indexonlyscan;

/*
 * Which is enforced by the plans: a value comparison is a filter applied to
 * every row the scan returns, and only a storage comparison bounds the scan.
 */
SET enable_seqscan = off;
SET enable_bitmapscan = off;
EXPLAIN (COSTS OFF)
SELECT term FROM opclass_scan WHERE term = '"16777217"^^xsd:float';
EXPLAIN (COSTS OFF)
SELECT term FROM opclass_scan WHERE term ~= '"16777217"^^xsd:float';
RESET enable_seqscan;
RESET enable_bitmapscan;

/* Every stored term is findable by its own spelling, which is what an index
 * has to guarantee. The value operator does not guarantee it: NaN does not
 * find itself. */
SET enable_seqscan = off;
SET enable_bitmapscan = off;
SELECT count(*) AS found_by_term
FROM opclass_scan s
WHERE EXISTS (SELECT 1 FROM opclass_scan i WHERE i.term ~= s.term);
RESET enable_seqscan;
RESET enable_bitmapscan;

SELECT count(*) AS total,
       count(*) FILTER (WHERE term = term) AS found_by_value
FROM opclass_scan;

/* Ordering is by the stored term, which is what it has always been. */
SELECT term FROM opclass_scan ORDER BY term;

/* Two terms with the same value but different spellings are two terms, so a
 * unique index holds both. */
CREATE TABLE opclass_unique (term rdfnode UNIQUE);
INSERT INTO opclass_unique VALUES ('"01"^^xsd:integer'), ('"1"^^xsd:integer');
SELECT count(*) AS rows_kept FROM opclass_unique;
INSERT INTO opclass_unique VALUES ('"1"^^xsd:integer');

DROP TABLE opclass_pair;
DROP TABLE opclass_trio;
DROP TABLE opclass_scan;
DROP TABLE opclass_unique;
