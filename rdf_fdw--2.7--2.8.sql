GRANT USAGE ON SCHEMA sparql TO PUBLIC;

/* These generate a new value on every call, so constant folding must not
   collapse them to a single value for the whole query. */
ALTER FUNCTION sparql.bnode() VOLATILE;
ALTER FUNCTION sparql.uuid() VOLATILE;
ALTER FUNCTION sparql.struuid() VOLATILE;
