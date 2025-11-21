CREATE SERVER wikidata
FOREIGN DATA WRAPPER rdf_fdw 
OPTIONS (
  endpoint 'https://query.wikidata.org/sparql'
);

CREATE FOREIGN TABLE ft (
  p rdfnode OPTIONS (variable '?p'),
  o rdfnode OPTIONS (variable '?o')
)
SERVER wikidata OPTIONS (
  sparql 'SELECT * {wd:Q192490 ?p ?o}'
);

/* EXPLAIN only */
EXPLAIN
SELECT p, o FROM ft;

EXPLAIN
SELECT p, o FROM ft
WHERE sparql.isnumeric(o) AND o > 100;

EXPLAIN
SELECT p, o FROM ft
WHERE sparql.isnumeric(o) AND o > 100
ORDER BY o DESC;

EXPLAIN
SELECT p, o FROM ft
WHERE sparql.isnumeric(o) AND o > 100
ORDER BY o DESC
LIMIT 3;

EXPLAIN
SELECT p, o FROM ft
WHERE sparql.isnumeric(o) AND o > 100 OR p IS NOT NULL -- non-pushable condition
ORDER BY o DESC
LIMIT 3;

/* EXPLAIN (VERBOSE) */
EXPLAIN (VERBOSE, COSTS OFF)
SELECT p, o FROM ft;

EXPLAIN (VERBOSE, COSTS OFF)
SELECT p, o FROM ft
WHERE sparql.isnumeric(o) AND o > 100;

EXPLAIN (VERBOSE, COSTS OFF)
SELECT p, o FROM ft
WHERE sparql.isnumeric(o) AND o > 100
ORDER BY o DESC;

EXPLAIN (VERBOSE, COSTS OFF)
SELECT p, o FROM ft
WHERE sparql.isnumeric(o) AND o > 100
ORDER BY o DESC
LIMIT 3;

EXPLAIN (VERBOSE, COSTS OFF)
SELECT p, o, sparql.sum(o) FROM ft
WHERE sparql.isnumeric(o) AND o > 100 
GROUP BY p, o
ORDER BY o DESC
LIMIT 3;

EXPLAIN (VERBOSE, COSTS OFF)
SELECT p, o, sparql.sum(o) FROM ft
WHERE sparql.isnumeric(o) AND o > 100 OR p IS NOT NULL -- non-pushable condition
GROUP BY p, o
ORDER BY o DESC
LIMIT 3;

/* EXPLAIN (VERBOSE) with pushdown disabled */
ALTER FOREIGN TABLE ft OPTIONS (enable_pushdown 'false');

EXPLAIN (VERBOSE, COSTS OFF)
SELECT sparql.str(o), sparql.datatype(o) FROM ft
WHERE sparql.isnumeric(o) AND o > 100
ORDER BY o DESC
LIMIT 3;

DROP SERVER wikidata CASCADE;