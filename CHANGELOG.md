# Release Notes
## 2.3.0
Release date: **YYYY-MM-DD**

### Enhancements

* INSERT support: added per-row INSERT DATA support via the `sparql_update_pattern` option on foreign tables. Each row inserted into a `FOREIGN TABLE` is converted into a SPARQL `INSERT DATA` statement and sent to the configured SPARQL UPDATE endpoint. Supports multi-row INSERT batching and multiple triple patterns per row.

* DELETE support: added per-row DELETE DATA support for deleting triples from RDF triplestores. DELETE operations on `FOREIGN TABLE`s are translated into SPARQL DELETE DATA requests using concrete triple values retrieved from a prior SELECT operation. Each matching row is converted into a fully-specified DELETE DATA statement and sent to the configured SPARQL UPDATE endpoint. Supports bulk DELETE operations and complex WHERE conditions with multiple predicates.

* UPDATE support: added per-row UPDATE support for modifying triples in RDF triplestores. UPDATE operations on `FOREIGN TABLE`s are translated into a combination of SPARQL DELETE DATA and INSERT DATA statements. The implementation first retrieves the OLD values via a SELECT query, then generates a DELETE DATA statement to remove the old triple(s), followed by an INSERT DATA statement with the NEW values. This approach follows the SPARQL UPDATE protocol since SPARQL has no direct UPDATE syntax. Supports single-column and multi-column updates with complex WHERE conditions.

### Bug Fixes

* Empty RDF literals incorrectly returned as NULL: Fixed a bug where empty RDF literals (e.g., `""`, `""@en`, or `""^^xsd:string`) were being incorrectly returned as SQL NULL values instead of empty strings. The issue occurred in `CreateTuple()` where `xmlNodeGetContent()` returns NULL for empty XML elements. The fix now properly distinguishes between empty RDF terms (valid empty strings) and unbound SPARQL variables (SQL NULL) by checking the XML element type (`<literal>`, `<uri>`, or `<bnode>`).

* Empty literals not being deleted: Fixed a bug where empty literals (e.g., `""@pt`) were not triggering DELETE operations. The issue occurred because `xmlNodeGetContent()` returns NULL for empty content, which caused tuples to be incorrectly marked as NULL, preventing the DELETE callback from executing.

* Literals with escaped quotes corrupted during round-trip: Fixed a critical bug where literals containing escaped quotes (e.g., `"\"WWU\""@en`) were being corrupted when retrieved from SPARQL results. The `CreateTuple()` function was incorrectly reparsing raw XML text content as RDF syntax, causing quote characters to be interpreted as literal delimiters rather than data. This has been fixed by constructing `rdfnode` values directly from raw lexical content and manually appending language tags or datatypes.

* Control characters not properly escaped in SPARQL statements: Control characters (newlines, tabs, carriage returns) in literals are now properly escaped in SPARQL INSERT and DELETE statements, ensuring correct round-trip behavior.


# Release Notes
## 2.2.0
Release date: **2025-12-07**

### Enhancements

* SPARQL aggregate functions:

  Added support for SPARQL-style aggregate functions `sparql.sum`, `sparql.avg`, `sparql.min`, `sparql.max`, `sparql.group_concat`, and `sparql.sample` in SQL queries. These functions are now fully implemented and can be used for local aggregation in PostgreSQL, improving compatibility with SPARQL semantics and enabling more expressive analytics on RDF data. Aggregate pushdown to the SPARQL endpoint is not yet supported; all aggregation is performed locally by PostgreSQL.

* Enhanced version information:

  The `rdf_fdw_version()` function now returns a comprehensive version string that includes PostgreSQL version, compiler information, and all dependency versions (libxml, librdf, libcurl) in a single formatted output. A new `rdf_fdw_settings()` function provides extended dependency information including optional components like SSL, zlib, libSSH, and nghttp2. The `rdf_fdw_settings` view parses this extended information into a table format for convenient programmatic access to individual component versions.

* Improved EXPLAIN diagnostics for Foreign Scan nodes:

  EXPLAIN output now include rdf_fdw-specific details for each Foreign Scan node, showing which SQL clauses are pushed down to the remote SPARQL endpoint. The plan displays lines such as `Pushdown: enabled/disabled`, `Remote Filter`, `Remote Sort Key`, `Remote Limit`, and `Remote Select`, making it easier to understand query translation and pushdown behavior.

### Bug Fixes

* Fix `lex()` to correctly handle doubled-quote escapes in literals.

  RDF literals containing double-quotes were being truncated, leading to invalid results of `sparql.lex()` or any function that depends on it. This has now being fixed.

# Release Notes
## 2.1.0
Release date: **2025-09-25**

### Enhancements

* SPARQL Prefix Management:

  `rdf_fdw` now includes built-in support for SPARQL prefix management via a structured catalog and helper functions. This feature introduces:

  `prefix_contexts`: Named groups of reusable SPARQL prefixes.

  `prefixes`: Individual prefix → URI mappings associated with a context.

  A suite of SQL functions to add, update, delete, and override contexts and prefixes. This enhancement simplifies query generation, reduces redundancy, and makes SPARQL integration more maintainable — especially when dealing with multiple endpoints or vocabularies.

* Add `enable_xml_huge` server option to support large XML result sets

  The new `enable_xml_huge` option allows users to enable libxml2's `XML_PARSE_HUGE` flag when parsing SPARQL result sets. This is useful for consuming large XML responses that exceed libxml2's default safety limits. By default, this option is disabled for security reasons.

### Bug Fixes

* NULL RDFNodes:
    
  This fixes a bug that could potentially lead the system to crash if the triple store returns a `NULL` value for an specific node (edge case).

* xmlParseMemory errors

  An issue has been resolved where the system could potentially crash if libxml2 failed to parse a given XML string (for example, due to an out-of-memory error). A check has been added to detect and prevent such crashes.

* xmlDocGetRootElement failing to get the root element

  A safeguard has been introduced to handle cases where xmlDocGetRootElement fails to parse the root node of an XML document. Instead of proceeding with an empty set, an error message is now displayed to inform the user of the issue.

## 2.0.0
Release date: **2025-05-22**

This is a major release of `rdf_fdw` featuring substantial new features, improved standards compliance, and important infrastructure enhancements. Backward compatibility is preserved, but users are encouraged to review the new features and updated behavior.

### Enhancements

* PostgreSQL 9.5 and 18 (in beta1 as of this release) support.
* SPARQL `DESCRIBE` query support via the new `sparql.describe()` support function.
* New `rdfnode` data type, enabling:
  * Representation of RDF literals and IRIs with full lexical fidelity.
  * Precise round-tripping of SPARQL values within SQL.
  * Equality and order comparisons with native PostgreSQL types (e.g., `int`, `float`, `text`, `date`).
* SPARQL 1.1 Built-in Function Support via [SQL queries](https://github.com/jimjonesbr/rdf_fdw?tab=readme-ov-file#sparql-functions).
  * [Functional Forms](https://www.w3.org/TR/sparql11-query/#func-forms): 
    * `bound`, `COALESCE` and `sameTerm`.
  * [Functions on RDF Terms](https://www.w3.org/TR/sparql11-query/#func-rdfTerms):
    * `isIRI`, `isBlank`, `isLiteral`, `isNumeric`, `str`, `lang`, `datatype`, `IRI`, `BNODE`, `STRDT`, `STRLANG`, `UUID`, and `STRUUID`.
  * [Functions on Strings](https://www.w3.org/TR/sparql11-query/#func-strings): 
    * `STRLEN`, `SUBSTR`, `UCASE`, `LCASE`, `STRSTARTS`, `STRENDS`, `CONTAINS`, `STRBEFORE`, `STRAFTER`, `ENCODE_FOR_URI`, `CONCAT`, `langMatches`, `REGEX`, and `REPLACE`.
  * [Functions on Numerics](https://www.w3.org/TR/sparql11-query/#func-numerics): 
    * `abs`, `round`, `ceil`, `floor`, and `RAND`.
  * [Functions on Dates and Times](https://www.w3.org/TR/sparql11-query/#func-date-time): 
    * `year`, `month`, `day`, `hours`, `minutes`, `seconds`, `timezone`, and `tz`.
  * [Hash Functions](https://www.w3.org/TR/sparql11-query/#func-hash): 
    * `md5`.

  These functions are translated to their SPARQL equivalents when pushed down to the foreign data wrapper. 

### Minor Changes
* The `FOREIGN TABLE` option `log_sparql` is now set to `true`, if omitted. If you don't want to log the SPARQL query, consider using [`ALTER FOREIGN TABLE`](https://github.com/jimjonesbr/rdf_fdw?tab=readme-ov-file#alter-foreign-table-and-alter-server) to disable this option manually, e.g.

  ```sql
  ALTER FOREIGN TABLE myrdftable OPTIONS (ADD log_sparql 'false');
  ```

### Bug Fixes

* Query cancellation support:

  Added `CHECK_FOR_INTERRUPTS()` in key execution points to allow PostgreSQL backends to detect user-initiated query cancellations (e.g., Ctrl+C), improving long-running query handling.

### External Libraries

 * Added a new dependency: Redland RDF Library (`librdf`) — used for parsing and serializing RDF data, and supporting `DESCRIBE` queries.

## 1.3.0
Release date: **2024-09-30**

### Enhancements

* Support for PostgreSQL 9.6, 10, and 17: This adds support for the long EOL'd PostgreSQL versions 9.6 and 10. It is definitely discouraged to use these unsupported versions, but in case you're for whatever reason unable to perform an upgrade you can now use the `rdf_fdw`. 

## 1.2.0
Release date: **2024-05-22**

### Enhancements

* Pushdown support for [Math](https://www.postgresql.org/docs/current/functions-math.html), [String](https://www.postgresql.org/docs/current/functions-string.html) and [Date/Time](https://www.postgresql.org/docs/current/functions-datetime.html) functions:
  * `abs`, `ceil`, `floor`, `round`
  * `length`, `upper`, `lower`, `starts_with`, `substring`, `md5`
  * `extract(year from x)`, `extract(month from x)`, `extract(year from x)`, `extract(hour from x)`, `extract(minute from x)`, `extract(second from x)`
  * `date_part(year, x)`, `date_part('month',x)`, `date_part('year', x)`, `date_part('hour', x)`, `date_part('minute', x)`, `date_part('second', x)`

  When used in the `WHERE` clause these functions will be translated to their correspondent SPARQL `FILTER` expressions.

### Bug Fixes

* Bug fix for WHERE conditions with "inverted" arguments - that is, value in the left side (T_Const) and column in the right side (T_Var): This fixes a bug that led the pushdown of `WHERE` condiditions containing "inverted" arguments to fail, e.g `"foo" = column`, `42 > column`. Now the order of T_Const and T_Var in the arguments is irrelevant.


## 1.1.0
Release date: **2024-04-10**

### Enhancements

* [`USER MAPPING`](https://github.com/jimjonesbr/rdf_fdw?tab=readme-ov-file#create-user-mapping) support: This feature defines a mapping of a PostgreSQL user to an user in the target triplestore - `user` and `password`, so that the user can be authenticated. Requested by [Matt Goldberg](https://github.com/mgberg). 

* Pushdown suuport for [`pattern matching operators`](https://www.postgresql.org/docs/current/functions-matching.html#FUNCTIONS-LIKE) `LIKE` and `ILIKE`: these operators are now translated into SPARQL `FILTER` expressions as `REGEX` and pushed down.

* Enables usage of non-pushable data types in `FOREIGN TABLE` columns: This disables a check that raised an excepetion when data types that cannot be pushed down were used. This includes non-standard data types, such as `geometry` or `geography` from PostGIS.

### Bug Fixes

* Empty SPARQL `SELECT` clause: This fixes a bug that led some SPARQL queries to be created without any variable in the `SELECT` clause. We now use `SELECT *` in case the planner cannot identify which nodes should be retrieved, which can be a bit inefficent if we're dealing with many columns, but it is much better than an error message.

* Missing schema from foreign tables in `rdf_fdw_clone_table` calls: This fixes a bug that led the `rdf_fdw_clone_table` procedure to always look for the given `FOREIGN TABLE` in the `public` schema.

* xmlDoc* memory leak: The xml document containing the resulst sets from the SPARQL queries wasn't beeing freed after the query was complete. This led to a memory leak that could potentially cause a system crash once all available memory was consumed by the orphan documents - which is an issue for rather modest server settings that execute mutliple queries in the same session. Reported by [Filipe Pessoa](https://github.com/lfpessoa).

## 1.0.0
Release date: **2024-03-15**

Initial release. 

Support for PostgreSQL 11, 12, 13, 14, 15 and 16.

### Main Features

* Pushdown: [`LIMIT`](https://github.com/jimjonesbr/rdf_fdw?tab=readme-ov-file#limit), [`ORDER BY`](https://github.com/jimjonesbr/rdf_fdw?tab=readme-ov-file#order-by), [`DISTINCT`](https://github.com/jimjonesbr/rdf_fdw?tab=readme-ov-file#distinct), [`WHERE`](https://github.com/jimjonesbr/rdf_fdw?tab=readme-ov-file#where) with several [data types and operators](https://github.com/jimjonesbr/rdf_fdw?tab=readme-ov-file#where)
* Table copy: This introduces the procedure [`rdf_fdw_clone_table()`](https://github.com/jimjonesbr/rdf_fdw?tab=readme-ov-file#rdf_fdw_clone_table), that is designed to copy data from a `FOREIGN TABLE` into an ordinary `TABLE`. It provides the possibility to retrieve the data set in batches.
* Proxy Support for [`SERVER`](https://github.com/jimjonesbr/rdf_fdw?tab=readme-ov-file#create-server): quite handy feature in case the PostgreSQL and SPARQL endpoint servers are in different networks and can only communicate through a proxy.