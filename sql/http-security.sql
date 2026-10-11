/*
 * What rdf_fdw puts into an HTTP request. These tests need no network: the
 * servers below point at a port nothing listens on, with retries off, so a
 * request that gets as far as being sent fails at once.
 */
SET client_min_messages TO WARNING;

/*
 * Control characters in values that end up in a request. A CR or LF in a
 * header value would add header lines -- or a second request -- of the
 * user's choosing.
 */
CREATE SERVER hs_ctl FOREIGN DATA WRAPPER rdf_fdw
OPTIONS (endpoint 'http://127.0.0.1:1/sparql', connect_retry '0', connect_timeout '1');

ALTER SERVER hs_ctl OPTIONS (ADD format E'application/sparql-results+xml\r\nX-Injected: 1');
ALTER SERVER hs_ctl OPTIONS (ADD custom E'a=1\nb=2');
ALTER SERVER hs_ctl OPTIONS (ADD query_param E'q\tx');
ALTER SERVER hs_ctl OPTIONS (ADD update_url E'http://127.0.0.1:1/update\r\n');
ALTER SERVER hs_ctl OPTIONS (ADD base_uri E'http://example.org/\n');
CREATE SERVER hs_ctl2 FOREIGN DATA WRAPPER rdf_fdw
OPTIONS (endpoint E'http://127.0.0.1:1/sparql\r\nX-Injected: 1');
CREATE USER MAPPING FOR CURRENT_USER SERVER hs_ctl OPTIONS (token E'abc\r\nX-Injected: 1');
CREATE USER MAPPING FOR CURRENT_USER SERVER hs_ctl OPTIONS (user E'admin\n', password 'secret');
CREATE USER MAPPING FOR CURRENT_USER SERVER hs_ctl OPTIONS (user 'admin', password E'sec\x01ret');
CREATE USER MAPPING FOR CURRENT_USER SERVER hs_ctl OPTIONS (proxy_user E'p\r\n', proxy_password 'x');

/* the SPARQL query itself may span lines */
CREATE FOREIGN TABLE hs_ft (s rdfnode OPTIONS (variable '?s'))
SERVER hs_ctl OPTIONS (sparql E'SELECT ?s\nWHERE {\r\n  ?s ?p ?o\n}');

/* a value stored before the validator checked it is refused before sending */
UPDATE pg_foreign_server
SET srvoptions = array_append(srvoptions, E'format=application/sparql-results+xml\r\nX-Injected: 1')
WHERE srvname = 'hs_ctl';
SELECT * FROM hs_ft;

DROP SERVER hs_ctl CASCADE;
