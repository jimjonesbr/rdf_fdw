CREATE SERVER testserver
FOREIGN DATA WRAPPER rdf_fdw 
OPTIONS (    
  endpoint 'https://dbpedia.org/sparql'
);

CREATE USER u1;

/* empty user name */
CREATE USER MAPPING FOR u1 SERVER testserver OPTIONS (user '', password 'foo');

/* empty password */
CREATE USER MAPPING FOR u1 SERVER testserver OPTIONS (user 'foo', password '');

/* invalid option */
CREATE USER MAPPING FOR u1 SERVER testserver OPTIONS (user 'jim', foo 'bar');

/* empty token */
CREATE USER MAPPING FOR u1 SERVER testserver OPTIONS (token '');

/* token combined with user (mutually exclusive) */
CREATE USER MAPPING FOR u1 SERVER testserver OPTIONS (token 'secret', user 'admin');

/* token combined with user and password (mutually exclusive) */
CREATE USER MAPPING FOR u1 SERVER testserver OPTIONS (token 'secret', user 'admin', password 'pass');

/* valid token-only mapping */
CREATE USER MAPPING FOR u1 SERVER testserver OPTIONS (token 'secret');

/* clean up */
DROP SERVER testserver CASCADE;
DROP USER u1;