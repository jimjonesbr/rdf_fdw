\pset null '(null)'

CREATE SERVER fuseki
FOREIGN DATA WRAPPER rdf_fdw 
OPTIONS (
  endpoint   'http://fuseki:3030/dt/sparql',
  update_url 'http://fuseki:3030/dt/update');

CREATE FOREIGN TABLE ft (
  subject   rdfnode OPTIONS (variable '?s'),
  predicate rdfnode OPTIONS (variable '?p'),
  object    rdfnode OPTIONS (variable '?o') 
)
SERVER fuseki OPTIONS (
  sparql 'SELECT * WHERE {?s ?p ?o}',
  sparql_update_pattern '?s ?p ?o .'
);

CREATE USER MAPPING FOR postgres
SERVER fuseki OPTIONS (user 'admin', password 'secret');

INSERT INTO ft (subject, predicate, object)
VALUES  ('<https://www.uni-muenster.de>', '<http://dbpedia.org/property/name>', '"Westfälische Wilhelms-Universität Münster"@de'),
        ('<https://www.uni-muenster.de>', '<http://dbpedia.org/property/name>', '"University of Münster"@en'),
        ('<https://www.uni-muenster.de>', '<http://dbpedia.org/property/name>', '"Univerrrsity of Münsterrr"@en-US'),
        ('<https://www.uni-muenster.de>', '<http://dbpedia.org/property/name>', '"Univêrsity of Münsta"@en-GB'),
        ('<https://www.uni-muenster.de>', '<http://www.w3.org/2000/01/rdf-schema#time>', '"18:18:42"^^<http://www.w3.org/2001/XMLSchema#time>'),
        ('<https://www.uni-muenster.de>', '<http://dbpedia.org/property/established>', '"1780-04-16"^^<http://www.w3.org/2001/XMLSchema#date>'),
        ('<https://www.uni-muenster.de>', '<http://dbpedia.org/property/modified>', '"2025-12-24T18:30:42"^^<http://www.w3.org/2001/XMLSchema#dateTime>'),
        ('<https://www.uni-muenster.de>', '<http://dbpedia.org/ontology/wikiPageExtracted>', '"2025-12-24T13:00:42Z"^^<http://www.w3.org/2001/XMLSchema#dateTime>'),
        ('<https://www.uni-muenster.de>', '<http://www.w3.org/2003/01/geo/wgs84_pos#lat>', '"51.9636"^^<http://www.w3.org/2001/XMLSchema#float>'),
        ('<https://www.uni-muenster.de>', '<http://www.w3.org/2003/01/geo/wgs84_pos#long>', '"7.6136"^^<http://www.w3.org/2001/XMLSchema#float>'),
        ('<https://www.uni-muenster.de>', '<http://dbpedia.org/property/rector>', '"Johannes Wessels"'),
        ('<https://www.uni-muenster.de>', '<http://dbpedia.org/property/state>', '<http://dbpedia.org/resource/North_Rhine-Westphalia>'),
        ('<https://www.uni-muenster.de>', '<http://dbpedia.org/property/city>', '<http://dbpedia.org/resource/Münster>'),
        ('<https://www.uni-muenster.de>', '<http://www.w3.org/2000/01/rdf-schema#comment>', '"Hello 👋 PostgreSQL 🐘"@en'),
        ('<https://www.uni-muenster.de>', '<http://www.w3.org/2000/01/rdf-schema#comment>', '"unknown literal type"^^<http://www.w3.org/2001/XMLSchema#UNKNOWN>'),
        ('<https://www.uni-muenster.de>', '<http://www.w3.org/2000/01/rdf-schema#comment>', '"explicit string literal"^^<http://www.w3.org/2001/XMLSchema#string>'),
        ('<https://www.uni-muenster.de>', '<http://www.w3.org/2000/01/rdf-schema#comment>', '""'),
        ('<https://www.uni-muenster.de>', '<http://www.w3.org/2000/01/rdf-schema#comment>', '". <= pontos => ."@pt'),
        ('<https://www.uni-muenster.de>', '<http://www.w3.org/2000/01/rdf-schema#comment>', '"\n <= salto de línea => \n"@es'),
        ('<https://www.uni-muenster.de>', '<http://www.w3.org/2000/01/rdf-schema#comment>', '"\" <= double-quotes => \""@en'),
        ('<https://www.uni-muenster.de>', '<http://www.w3.org/2000/01/rdf-schema#comment>', '"\t <= Tabulatorzeichen => \t"@de'),        
        ('<https://www.uni-muenster.de>', '<http://dbpedia.org/property/administrativeStaff>', '"1924"^^<http://www.w3.org/2001/XMLSchema#short>'),
        ('<https://www.uni-muenster.de>', '<http://dbpedia.org/property/students>', '"49098"^^<http://www.w3.org/2001/XMLSchema#int>'),
        ('<https://www.uni-muenster.de>', '<http://dbpedia.org/property/academicStaff>', '"4956"^^<http://www.w3.org/2001/XMLSchema#int>'),
        ('<https://www.uni-muenster.de>', '<http://dbpedia.org/property/budget>', '"803600000"^^<http://www.w3.org/2001/XMLSchema#long>'),
        ('<https://www.uni-muenster.de>', '<http://dbpedia.org/property/tuition>', '"1500.00"^^<http://www.w3.org/2001/XMLSchema#double>'),
        ('<https://www.uni-muenster.de>', '<http://dbpedia.org/property/veryLargeNumber>', '"9999999999999999999"^^<http://www.w3.org/2001/XMLSchema#decimal>'),
        ('<https://www.uni-muenster.de>', '<http://dbpedia.org/property/verySmallNumber>', '"0.000000000000001"^^<http://www.w3.org/2001/XMLSchema#decimal>'),
        ('<https://www.uni-muenster.de>', '<http://dbpedia.org/ontology/restingDate>', '"2024-02-29"^^<http://www.w3.org/2001/XMLSchema#date>'),
        ('<https://www.uni-muenster.de>', '<http://dbpedia.org/ontology/internationally>', '"true"^^<http://www.w3.org/2001/XMLSchema#boolean>');

CALL
    rdf_fdw_clone_table(
        foreign_table => 'public.ft',
        target_table  => 'public.t1',
        fetch_size => 4,
        verbose => true,
        create_table => true,
        commit_page => false
    );

SELECT * FROM public.t1 ORDER BY object::text COLLATE "C";

/* text data type */
CREATE FOREIGN TABLE ft2 (
  subject   text OPTIONS (variable '?s'),
  predicate text OPTIONS (variable '?p'),
  object    text OPTIONS (variable '?o') 
)
SERVER fuseki OPTIONS (
  sparql 'SELECT * WHERE {?s ?p ?o}'
);

CALL
    rdf_fdw_clone_table(
        foreign_table => 'public.ft2',
        target_table  => 'public.t2',
        fetch_size => 4,
        verbose => true,
        create_table => true,
        commit_page => false
    );

SELECT * FROM public.t2 ORDER BY object::text COLLATE "C";

/* timestamp data type */
CREATE FOREIGN TABLE ft3 (
  subject   text OPTIONS (variable '?s'),
  predicate text OPTIONS (variable '?p'),
  object    timestamp OPTIONS (variable '?o') 
)
SERVER fuseki OPTIONS (
  sparql 'SELECT * WHERE {?s ?p ?o FILTER (?p = <http://dbpedia.org/property/modified> || ?p = <http://dbpedia.org/ontology/wikiPageExtracted>)}'
);

CALL
    rdf_fdw_clone_table(
        foreign_table => 'public.ft3',
        target_table  => 'public.t3',
        fetch_size => 4,
        verbose => true,
        create_table => true,
        commit_page => false
    );

SELECT * FROM public.t3 ORDER BY object::text COLLATE "C";

/* date data type */
CREATE FOREIGN TABLE ft4 (
  subject   text OPTIONS (variable '?s'),
  predicate text OPTIONS (variable '?p'),
  object    date OPTIONS (variable '?o') 
)
SERVER fuseki OPTIONS (
  sparql 'SELECT * WHERE {?s ?p ?o FILTER (?p = <http://dbpedia.org/property/established> || ?p = <http://dbpedia.org/ontology/restingDate>)}'
);

CALL
    rdf_fdw_clone_table(
        foreign_table => 'public.ft4',
        target_table  => 'public.t4',
        fetch_size => 4,
        verbose => true,
        create_table => true,
        commit_page => false
    );

SELECT * FROM public.t4 ORDER BY object::text COLLATE "C";

/* numeric data type */
CREATE FOREIGN TABLE ft5 (
  subject   text OPTIONS (variable '?s'),
  predicate text OPTIONS (variable '?p'),
  object    numeric OPTIONS (variable '?o') 
)
SERVER fuseki OPTIONS (
  sparql 'SELECT * WHERE {?s ?p ?o FILTER (?p = <http://dbpedia.org/property/veryLargeNumber> || ?p = <http://dbpedia.org/property/verySmallNumber>)}'
);

CALL
    rdf_fdw_clone_table(
        foreign_table => 'public.ft5',
        target_table  => 'public.t5',
        fetch_size => 4,
        verbose => true,
        create_table => true,
        commit_page => false
    );

SELECT * FROM public.t5 ORDER BY object::text COLLATE "C";

/* int data type */
CREATE FOREIGN TABLE ft6 (
  subject   text OPTIONS (variable '?s'),
  predicate text OPTIONS (variable '?p'),
  object    int OPTIONS (variable '?o') 
)
SERVER fuseki OPTIONS (
  sparql 'SELECT * WHERE {?s ?p ?o FILTER (?p = <http://dbpedia.org/property/budget> || ?p = <http://dbpedia.org/property/administrativeStaff>)}'
);

CALL
    rdf_fdw_clone_table(
        foreign_table => 'public.ft6',
        target_table  => 'public.t6',
        fetch_size => 4,
        verbose => true,
        create_table => true,
        commit_page => false
    );

SELECT * FROM public.t6 ORDER BY object::text COLLATE "C";

/*
 * A record need not bind every variable the query selects. A column with no
 * binding in a given record is still a column of that record, and its value
 * is unknown: it has to be inserted as NULL rather than left out of the
 * statement, which hands the row to whatever default the target column
 * carries. When no column of a record is bound there is nothing to leave in
 * either, and the statement built from it is not a statement at all.
 */
CREATE FOREIGN TABLE ft_unbound (
  subject rdfnode OPTIONS (variable '?subject'),
  absent  rdfnode OPTIONS (variable '?absent')
)
SERVER fuseki OPTIONS (sparql $$
  SELECT ?subject ?absent WHERE {
    ?subject <http://dbpedia.org/property/rector> ?o .
    OPTIONAL { ?subject <http://example.org/nonexistent> ?absent }
  }
$$);

CREATE TABLE t_unbound (subject rdfnode, absent rdfnode DEFAULT '"a default"');

CALL
    rdf_fdw_clone_table(
        foreign_table => 'public.ft_unbound',
        target_table  => 'public.t_unbound',
        create_table  => false,
        commit_page   => false
    );

/* the absent binding must be NULL, not the column's default */
SELECT subject, absent IS NULL AS absent_is_null FROM t_unbound;

/* and a record in which nothing at all is bound still makes a row */
CREATE FOREIGN TABLE ft_nothing (
  absent rdfnode OPTIONS (variable '?absent')
)
SERVER fuseki OPTIONS (sparql $$
  SELECT ?absent WHERE {
    ?subject <http://dbpedia.org/property/rector> ?o .
    OPTIONAL { ?subject <http://example.org/nonexistent> ?absent }
  }
$$);

CREATE TABLE t_nothing (absent rdfnode);

CALL
    rdf_fdw_clone_table(
        foreign_table => 'public.ft_nothing',
        target_table  => 'public.t_nothing',
        create_table  => false,
        commit_page   => false
    );

SELECT count(*) AS rows_cloned, count(absent) AS bound_values FROM t_nothing;

DROP TABLE t_unbound;
DROP TABLE t_nothing;
DROP FOREIGN TABLE ft_unbound;
DROP FOREIGN TABLE ft_nothing;

/*
 * fetch_size is read from the foreign table as well as from the server, and
 * the table's value is the one that applies. The clone procedure takes its own
 * fetch_size argument, which overrides both; leaving it at its default of 0 is
 * what makes the option under test the one that decides the page size.
 *
 * The verbose output reports the size it settled on and one line per page, so
 * both the value and the paging it produces are visible.
 */
ALTER SERVER fuseki OPTIONS (ADD fetch_size '10');
CREATE FOREIGN TABLE ft_fetch (
  subject   rdfnode OPTIONS (variable '?s'),
  predicate rdfnode OPTIONS (variable '?p'),
  object    rdfnode OPTIONS (variable '?o')
)
SERVER fuseki OPTIONS (
  sparql 'SELECT * WHERE {?s ?p ?o}',
  fetch_size '25'
);

/* the table's 25 applies, not the server's 10 */
CALL
    rdf_fdw_clone_table(
        foreign_table => 'public.ft_fetch',
        target_table  => 'public.t_fetch',
        verbose => true,
        create_table => true,
        commit_page => false
    );

/* without the table option the server's 10 applies */
ALTER FOREIGN TABLE ft_fetch OPTIONS (DROP fetch_size);
CALL
    rdf_fdw_clone_table(
        foreign_table => 'public.ft_fetch',
        target_table  => 'public.t_fetch2',
        verbose => true,
        create_table => true,
        commit_page => false
    );

/* a page size is rejected when it is not a non-negative integer */
ALTER FOREIGN TABLE ft_fetch OPTIONS (ADD fetch_size 'abc');

DROP TABLE public.t_fetch;
DROP TABLE public.t_fetch2;
DROP FOREIGN TABLE ft_fetch;
ALTER SERVER fuseki OPTIONS (DROP fetch_size);

DELETE FROM ft;
DROP TABLE public.t1;
DROP TABLE public.t2;
DROP TABLE public.t3;
DROP TABLE public.t4;
DROP TABLE public.t5;
DROP TABLE public.t6;
DROP SERVER fuseki CASCADE;