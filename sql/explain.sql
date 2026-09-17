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

EXPLAIN
SELECT * FROM ft
WHERE
  sparql.isnumeric(o) AND -- pushable condition
  o::text LIKE '%foo%'    -- non-pushable condition
ORDER BY o DESC
LIMIT 3;

EXPLAIN
SELECT * FROM ft
WHERE
  p::text ILIKE '%foo%' AND -- non-pushable condition
  o::text LIKE '%bar%'      -- non-pushable condition
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

EXPLAIN (VERBOSE, COSTS OFF)
SELECT * FROM ft
WHERE
  sparql.isnumeric(o) AND -- pushable condition
  o::text LIKE '%foo%'    -- non-pushable condition
ORDER BY o DESC
LIMIT 3;

EXPLAIN (VERBOSE, COSTS OFF)
SELECT * FROM ft
WHERE
  p::text ILIKE '%foo%' AND -- non-pushable condition
  o::text LIKE '%bar%'      -- non-pushable condition
ORDER BY o DESC
LIMIT 3;

/*
 * A solution modifier that only looks like one, because it sits inside a
 * string literal, must not be mistaken for a real one - and, more to the
 * point, must not hide the real one that follows it. The query below cannot
 * be rewritten, as it carries a LIMIT of its own: it has to be sent as it
 * stands, with the SQL condition left to the executor. A "Remote Filter"
 * here would mean the query was reconstructed and the user's LIMIT 5
 * silently dropped.
 */
CREATE FOREIGN TABLE ft_quoted_limit (
  s rdfnode OPTIONS (variable '?s'),
  o rdfnode OPTIONS (variable '?o')
)
SERVER wikidata OPTIONS (
  sparql 'SELECT * WHERE { ?s ?p ?o . FILTER(?o != " LIMIT ") } LIMIT 5'
);

EXPLAIN (VERBOSE, COSTS OFF)
SELECT s, o FROM ft_quoted_limit
WHERE o = 100;

/* the same query without the quoted keyword is rewritten as usual */
CREATE FOREIGN TABLE ft_plain (
  s rdfnode OPTIONS (variable '?s'),
  o rdfnode OPTIONS (variable '?o')
)
SERVER wikidata OPTIONS (
  sparql 'SELECT * WHERE { ?s ?p ?o . FILTER(?o != " nothing ") }'
);

EXPLAIN (VERBOSE, COSTS OFF)
SELECT s, o FROM ft_plain
WHERE o = 100;

/* EXPLAIN (VERBOSE) with pushdown disabled */
ALTER FOREIGN TABLE ft OPTIONS (enable_pushdown 'false');

EXPLAIN (VERBOSE, COSTS OFF)
SELECT sparql.str(o), sparql.datatype(o) FROM ft
WHERE sparql.isnumeric(o) AND o > 100
ORDER BY o DESC
LIMIT 3;

/*
 * A server's prefix context is looked up by name when a scan on it is
 * planned, and the lookup has to carry the whole name however long it is. A
 * name that does not survive the lookup intact leaves it malformed rather
 * than merely short, so every query against the server fails and none of its
 * prefixes are reachable. This one is long enough to outrun a lookup assembled
 * in a fixed-size buffer.
 */
SELECT repeat('c', 980) AS long_context \gset

SELECT sparql.add_context(:'long_context', 'name longer than a fixed-size buffer');
INSERT INTO sparql.prefixes (prefix, uri, context)
VALUES ('ex', 'http://example.org/', :'long_context');

CREATE SERVER long_context_server
FOREIGN DATA WRAPPER rdf_fdw
OPTIONS (
  endpoint 'https://example.org/sparql',
  prefix_context :'long_context'
);

CREATE FOREIGN TABLE long_context_ft (
  s rdfnode OPTIONS (variable '?s')
)
SERVER long_context_server OPTIONS (sparql 'SELECT ?s {?s ?p ?o}');

/* planning this reads the context, and must produce a plan rather than fail */
EXPLAIN (VERBOSE, COSTS OFF)
SELECT s FROM long_context_ft;

DROP SERVER long_context_server CASCADE;
DELETE FROM sparql.prefixes WHERE context = :'long_context';
DELETE FROM sparql.prefix_contexts WHERE context = :'long_context';

DROP SERVER wikidata CASCADE;