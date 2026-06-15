# 2.6
Release date: **YYYY-MM-DD**

## Enhancements

* **Add `token` option to USER MAPPING**: A new `token` option allows Bearer token authentication (RFC 6750) for SPARQL endpoints that use token-based access control instead of HTTP Basic Authentication. When set, `rdf_fdw` sends an `Authorization: Bearer <token>` HTTP header with every request.

  ```sql
  CREATE USER MAPPING FOR postgres
  SERVER myserver OPTIONS (token 'mysecrettoken');
  ```

* **Add `max_response_size` option to FOREIGN SERVERS**: A new `max_response_size` server option caps the HTTP response body size in bytes. If the endpoint sends more data than the configured limit, the query is aborted with an error before PostgreSQL allocates further memory. The default is `0` (unlimited). This is particularly useful when connecting to public or untrusted SPARQL endpoints to prevent runaway memory consumption from unexpectedly large result sets.

  ```sql
  -- Reject responses larger than 100 MB
  CREATE SERVER dbpedia
  FOREIGN DATA WRAPPER rdf_fdw
  OPTIONS (endpoint 'https://dbpedia.org/sparql', max_response_size '104857600');
  ```

## Deprecations

* **Native PostgreSQL column types in `FOREIGN TABLE` definitions**: Declaring foreign table columns with standard PostgreSQL types (e.g. `text`, `int`, `date`, `timestamp`) is deprecated. The `rdfnode` type must be used instead, as it correctly represents the full RDF term — including IRIs, language tags, and XSD datatypes — and is required by all SPARQL functions. Existing tables continue to work but will emit a `WARNING` on every query listing the affected columns. The column options `expression`, `language`, `literal_type`, and `nodetype` are also deprecated, as they are only meaningful for native-typed columns. Support for native column types will be removed in a future release.

## Bug Fixes

* **Fixed `CURLE_WRITE_ERROR(23)` on SPARQL UPDATE and unrecognised `Content-Type` responses**: `HeaderCallbackFunction` was returning `0` for any `Content-Type` not recognised as an RDF or SPARQL XML type. Returning `0` from a libcurl write callback signals an abort and triggers `CURLE_WRITE_ERROR(23)`, causing endpoints that respond with `application/json` — such as QLever on successful UPDATEs or Fuseki on HTTP 400 errors — to produce a spurious "unable to connect" error instead of the real outcome. Fixed by returning `realsize` for unrecognised `Content-Type` headers.

* **SPARQL UPDATE response body is now discarded**: For `INSERT`, `DELETE`, and `UPDATE` operations only the HTTP status code matters; the response body is irrelevant. Previously the full body was accumulated in memory, which wasted resources for endpoints that return large JSON documents on success or failure. It now sets `chunk.max_size = 0` to bypass the `max_response_size` limit.

* **HTTP error response bodies are now truncated in log and error messages**: Error bodies included in `errdetail()` and server-log `elog()` calls were previously unbounded. A misconfigured proxy returning a large HTML error page would be written verbatim into the PostgreSQL server log. Error bodies are now truncated to 512 bytes (`RDF_FDW_MAX_ERROR_BODY`) before being included in any message.

* **Encoded credentials are no longer written to server logs via libcurl verbose output**: When `client_min_messages` is set to `DEBUG3`, libcurl's verbose output is now routed through PostgreSQL's `elog(DEBUG3)` via a custom `CURLOPT_DEBUGFUNCTION` callback (`CurlDebugCallback`) instead of being written directly to `stderr`. Crucially, any outgoing or incoming HTTP header whose name matches `Authorization:` or `Proxy-Authorization:` has its value replaced with `[REDACTED]` before being logged, so Bearer tokens, Basic auth credentials (base64-encoded), and proxy passwords never appear in plaintext in the PostgreSQL server log.

* **rdfnodes with invalid trailing content now raise an error**: rdfnodes with trailing content, which can contain malicious SPARQL instructions, were being silently truncated. While this avoided any attempt of SPARQL injection, it could lead to confusion, since the user was never aware of this truncation. The function `rdfnode_in` now raises an error if such content is detected.

* **Blank nodes in FILTER expressions**: Blank nodes in FILTER expressions are now passed as blank nodes; previously, they were cast as literals. This allows triplestores that deviate from the SPARQL specification to handle blank nodes according to their own implementation.

* **Invalid `rdfnode` input now raises an error**: Inputs to `rdfnode_in` that are not a valid RDF literal, IRI, or blank node now raise `ERRCODE_INVALID_TEXT_REPRESENTATION` instead of being silently coerced. IRIs and blank nodes are returned as-is without unnecessary literal parsing.

* **Accept ill-typed literals**: Ill-typed literals are no longer rejected by `rdfnode_in` -- a literal is ill-typed if its lexical form falls outside the lexical space of its datatype (e.g., `"foo"^^xsd:int`). While semantically inconsistent under RDF 1.1, these literals are syntactically valid RDF. Validation is now deferred to the underlying triplestore rather than being enforced at the database level.

* **Fixed wrong ordering of string and language-tagged literals in `sparql.min()` / `sparql.max()`**: The aggregate comparator (`rdfnode_cmp_for_aggregate`) was using `varstr_cmp` with `DEFAULT_COLLATION_OID` for lexical comparisons of plain literals, `xsd:string` literals, and language-tagged literals. On databases whose locale is not `C`, this produces locale-dependent ordering (e.g., accented characters may be folded or reordered), which violates [SPARQL 1.1 §17.3](https://www.w3.org/TR/sparql11-query/#OperatorMapping) — string ordering must follow Unicode codepoint order. Both calls have been replaced with `strcmp`.

* **Fixed negative `xsd:duration` round-trip**: Casting a negative PostgreSQL `interval` to `rdfnode` produces a valid XSD duration with a leading `-` (e.g., `-P1Y2M`), but casting that value back to `interval` failed with `invalid input syntax for type interval: "-P1Y2M"` because PostgreSQL's `interval_in` does not accept the XSD negative-duration notation. A helper `xsd_duration_to_pg_interval` now strips the leading `-`, parses the positive form, and negates the result.

* **Fixed trailing zeros in fractional seconds of `xsd:duration` output**: `interval_to_rdfnode` was always formatting sub-second values with six decimal places (e.g., `PT1M0.500000S`). It now strips trailing zeros, producing the canonical lexical form (e.g., `PT1M0.5S`).

* **Fixed `LANGMATCHES` to correctly return `false` when the language tag is empty**: Previously, `LANGMATCHES("", "*")` returned `true`, violating SPARQL 1.1 and RFC 4647 basic filtering semantics, which require `"*"` to match only non-empty language tags. This affected queries filtering untagged literals via `FILTER LANGMATCHES(LANG(?x), "*")`, which would incorrectly include
  untagged literals in results.

* **Fixed `SECONDS()` return type and value**: the `text` overload was incorrectly declared as returning `int` instead of `numeric`, causing fractional seconds to be truncated. Additionally, timezone-aware `xsd:dateTime` values were returning the wrong seconds value due to implicit session timezone adjustment during timestamp casting; the lexical form is now cast to `timestamptz` to preserve the correct component.

* **Fixed `TZ()` to reject invalid timezone offsets**: when given an `xsd:dateTime` literal with an out-of-range timezone offset (e.g., `"2020-12-01T08:00:00+25:00"^^xsd:dateTime`), the function would previously extract and return the offset as-is without validation. It now raises an error for offsets outside the valid XSD range of `±14:00`.

* **Fixed session-timezone-dependent `xsd:dateTime` comparisons**: All `rdfnode` comparison operators (`=`, `<>`, `<`, `<=`, `>`, `>=`) and the aggregate comparator were calling PostgreSQL's `timestamptz_in()` for every `xsd:dateTime` literal, including timezone-naive ones. This caused two bugs: (1) comparing a timezone-naive literal with a timezone-aware one could return `true` instead of the correct SPARQL result of incomparable (`false`), depending on the session timezone; (2) the old timezone-detection heuristic used `strpbrk(lex, "+-")`, which matched the `-` separators in the date portion (e.g., `2025-04-25`) and incorrectly classified every well-formed dateTime as timezone-aware. The fix introduces a `datetime_has_tz()` helper that restricts the search for `Z`, `+`, and `-` to the time portion of the lexical form (after the `T` or space separator). Timezone-aware pairs are compared via `timestamptz_in()` / `timestamptz_cmp_internal()`; timezone-naive pairs via `timestamp_in()` without any session-timezone influence; and mixed pairs return `false` (incomparable) per XSD §3.2.7.4 and SPARQL 1.1 §17.3 (Operator Mapping).

* **Fixed incomplete `xsd:time` support in `rdfnode` comparison operators**: `rdfnode_eq` (`=`, `<>`) was missing `xsd:time` value-space comparison entirely, falling back to lexical comparison. The ordering operators (`<`, `<=`, `>`, `>=`) had `xsd:time` support but lacked timezone handling, unconditionally using `time_in()` for all literals. The fix adds `xsd:time` equality to `rdfnode_eq` and introduces a `time_has_tz()` helper that detects timezone designators (`Z`, `+`, `-`) in the time lexical form; timezone-aware pairs are now compared via `timetz_in()` / `timetz_eq()` (with UTC normalisation); timezone-naive pairs via `time_in()` without session-timezone influence; and mixed pairs return `false` (incomparable).

* **Fixed NaN‑NaN comparison bug**: Previously the expression `?a = ?b` returned true when both operands were the literal `"NaN"^^xsd:double` (or "NaN"^^xsd:float). According to SPARQL 1.1 (which follows the XSD 1.1 definition of xsd:double and the IEEE‑754 rules), a `NaN` value is never equal to any value, including another `NaN`; all numeric comparison operators must therefore evaluate to `false` for `NaN` operands. See [XPath and XQuery Functions and Operators 3.1](https://www.w3.org/TR/xpath-functions/) at [4.3.1 op:numeric-equal](https://www.w3.org/TR/xpath-functions/#func-numeric-equal), [4.3.2 op:numeric-less-than](https://www.w3.org/TR/xpath-functions/#func-numeric-less-than), and [4.3.3 op:numeric-greater-than](https://www.w3.org/TR/xpath-functions/#func-numeric-greater-than).

* **Add missing boolean-boolean comparison**: This adds `xsd:boolean` support to `rdfnode` comparison operators (`=`, `<>`, `<`, `<=`, `>`, `>=`), using PostgreSQL's `boolin` / `booleq` / `boollt` / `boolle` / `boolgt` / `boolge` functions.

* **Fixed invalid XSD lexical forms for infinity in `rdfnode` cast functions**: `float4_to_rdfnode`, `float8_to_rdfnode`, `numeric_to_rdfnode`, and `numeric_to_rdfnode` were producing `"Infinity"` and `"-Infinity"` as lexical forms, which are not valid XSD representations. XSD 1.1 Part 2 §3.3.4/§3.3.5 defines `INF` and `-INF` as the only valid lexical forms for positive and negative infinity in `xsd:float` and `xsd:double`. The cast functions now produce `"INF"^^xsd:float`, `"-INF"^^xsd:float`, `"INF"^^xsd:double`, and `"-INF"^^xsd:double` respectively. Numeric infinity (`xsd:decimal`) is mapped to `xsd:double` following the same convention.

* **Reject blank nodes in `IRI`, `STRDT`, and `STRLANG`**: These functions require a simple literal as their first argument. Previously, passing a blank node (e.g. `_:b1` or the result of `sparql.bnode()`) silently produced an invalid RDF term such as `_:b1@en` or a blank node with an attached datatype. Now these functions raise an error with a descriptive message when given a blank node.

* Fixed `cstring_to_rdfliteral()` incorrectly treating literal content that resembles a blank node label (`_:...`) or IRI (`<...>`) as an actual blank node/IRI term, causing `rdfnode_in()` to strip quotes from literals such as `"_:b1"` and `"<http://example.org>"`, making `sparql.isblank()` and  `sparql.isiri()` return incorrect results for these literals.

* **Fixed SPARQL pushdown for IRI-valued constants**: rdfnodes containing IRIs, when placed in the **left side** in an operation, were being incorrectly rendered as quoted literals, e.g. `WHERE '<http://example.org/property>'::rdfnode = sparql.iri(p)` was being pushed down as `Remote Filter: (("http://example.org/property" = IRI(?p)))` instead of `Remote Filter: ((<http://example.org/property> = IRI(?p)))`. The `T_OpExpr` path in `DeparseExpr` now skips the rdfnode normalisation when dealing with IRIs and blank nodes.

* **Fixes isBlank result for NULL inputs**: the SQL declaration of isBlank was defined as `STRICT` which led function calls with `NULL` inputs to directly return `NULL`, but isBlank should return `false` instead, ans its companions `isIRI`, `isLiteral`, and `isNumeric` do.

* **Fixed `CONCAT` result for incompatible arguments**: `CONTAINS()` now correctly returns `NULL` instead of `false` when argument types are incompatible, e.g. a plain literal paired with a language-tagged literal such as `@en`). It now also now correctly returns `NULL` instead of true when either argument carries a non-string datatype (i.e. anything other than `xsd:string` or `rdf:langString`). The function was previously operating on the raw lexical form regardless of the datatype, which produced incorrect results for custom-typed literals such as `"123"^^<http://example.com/int>`.

* **Fixed incorrect XSD data type for numeric arguments in `ROUND()`**: The funcion `ROUND()` was incorrectly returning `xsd:double` for PG `numeric` arguments, and it now returns `xsd:decimal` as also defined in other numeric functions, such as `CEIL()`, `FLOOR()`, or `ABS()`.

# 2.5
Release date: **2026-04-20**

## Enhancements

* **Add 'request_timeout' to FOREIGN SERVERS**: This option sets the maximum time in seconds allowed for a complete HTTP request (connect + transfer). `0` disables the limit (default). Unlike `connect_timeout`, this applies to the entire duration of the request, including data transfer.

* **Add 'readonly' option to FOREIGN SERVERS and FOREIGN TABLES**: A new boolean `readonly` option can be set on both `SERVER` and `FOREIGN TABLE` to prevent `INSERT`, `UPDATE`, and `DELETE` operations before they reach the SPARQL endpoint. When set at the server level it applies to all foreign tables backed by that server; when set at the table level it overrides the server setting, allowing a read-only server to have individual writable tables (or a read-write server to have individual protected tables). PostgreSQL will report the correct updatability via `IsForeignRelUpdatable`, so client tools that inspect `pg_catalog` can also discover whether a table allows DML.

  ```sql
  -- Mark the entire server as read-only
  ALTER SERVER fuseki OPTIONS (ADD readonly 'true');

  -- Override at the table level: this table is still writable despite the server setting
  ALTER FOREIGN TABLE ft OPTIONS (ADD readonly 'false');
  ```
## Minor Changes

Fixed `rdfReScanForeignScan` to reset the row index, making it correct for any future plan shape where PostgreSQL omits the Materialize node above a foreign scan.

# 2.4
Release date: **2026-02-14**

## Breaking Changes

* **Proxy authentication credentials moved to USER MAPPING**: For improved security, proxy authentication credentials (`proxy_user` and `proxy_password`) must now be specified in `USER MAPPING` instead of `SERVER` options. This change prevents proxy passwords from being visible to all users with `USAGE` privilege on the foreign server, as PostgreSQL automatically hides `USER MAPPING` passwords from non-owners.

  **Before (v2.3):**
  ```sql
  CREATE SERVER myserver
  FOREIGN DATA WRAPPER rdf_fdw 
  OPTIONS (
    endpoint 'http://fuseki:3030/sparql',
    http_proxy 'http://proxy:3128',
    proxy_user 'proxyuser',
    proxy_user_password 'proxypass'
  );
  ```

  **After (v2.4):**
  ```sql
  CREATE SERVER myserver
  FOREIGN DATA WRAPPER rdf_fdw 
  OPTIONS (
    endpoint 'http://fuseki:3030/sparql',
    http_proxy 'http://proxy:3128'  -- Proxy URL stays in SERVER
  );

  CREATE USER MAPPING FOR myuser
  SERVER myserver 
  OPTIONS (
    user 'admin',
    password 'secret',
    proxy_user 'proxyuser',    -- Moved from SERVER
    proxy_password 'proxypass' -- Moved from SERVER (previously 'proxy_user_password' )
  );
  ```

  **Migration**: Existing servers using `proxy_user` or `proxy_user_password` in SERVER options will need to be updated. Remove these options from the server and add them to user mappings instead. The validator will reject the old options with a clear error message.

# 2.3
Release date: **2026-01-28**

## Enhancements

* **Removed librdf dependency**: The extension no longer depends on the Redland RDF Library (`librdf`). RDF/XML parsing for `DESCRIBE` queries is now performed using only `libxml2`, reducing external dependencies and improving maintainability.

* **Support to data modification queries**: Introduced per-row SPARQL `INSERT DATA`, `DELETE DATA`, and `UPDATE` operations via the `sparql_update_pattern` option on foreign tables. The addition of the `batch_size` parameter enables efficient batching of these operations, significantly improving performance for bulk modifications.

* **Enhanced error handling in `ExecuteSPARQL`**: Improved the handling of HTTP errors by capturing and displaying detailed error messages from the SPARQL endpoint. This includes disabling `CURLOPT_FAILONERROR` to capture response bodies for HTTP errors, adding specific error messages for common HTTP status codes (e.g., 400, 401, 404, 500).

## Breaking Changes

* The `sparql.describe()` function no longer accepts the `raw_literal` parameter. Users who need to extract plain text from literals can use the `sparql.lex()` function instead. This simplifies the function signature and encourages a more consistent approach to handling RDF literals.

* The `sparql.regex` function is no longer available for local evaluation in PostgreSQL, as it turned out that its semantics cannot be reliably reproduced locally. Queries relying on local evaluation of `sparql.regex` will now fail with an error.

## Minor Changes

* The `log_sparql` option for foreign tables now defaults to `false`. Since `INSERT`, `UPDATE`, and `DELETE` operations can generate large SPARQL queries, enabling this option by default could result in unnecessarily large log entries.

## Bug Fixes

* Fixed URIs and blank nodes being incorrectly handled as plain literals in `InsertRetrievedData()` (used by `rdf_fdw_clone_table()`). When cloning foreign tables with `rdfnode` columns, URIs were being treated as plain text instead of being wrapped in angle brackets (e.g., `<http://example.com>`), and blank nodes were missing the `_:` prefix. The fix now checks the target column type: for `rdfnode` columns, it properly formats URIs with `<>` and blank nodes with `_:`, while for standard PostgreSQL types it extracts only the raw content. This ensures correct round-trip behavior when materializing RDF data into ordinary tables.

* Fixed failure when extracting content from empty RDF literals in `InsertRetrievedData()`. The code was incorrectly using `xmlNodeDump()` to serialize RDF term nodes, which included XML tags in the output (e.g., `<literal datatype="...">value</literal>`). This caused `rdf_fdw_clone_table()` calls on columns containing empty literals (e.g., `""`, `""@en`, or `""^^xsd:string`) to fail. Now uses `xmlNodeGetContent()` to extract only the text content without XML tags, properly handling empty and non-empty RDF term nodes alike.

* Fixed critical bug in all date comparison operators (>, >=, <, <=, =, !=) between `rdfnode` and PostgreSQL `date` types. Previously, the code used the wrong macro (`PG_GETARG_INT16`) to retrieve date arguments, causing all local date comparisons to fail or behave unpredictably. Now uses the correct `PG_GETARG_DATEADT` macro and adds robust error handling for non-date values. This ensures correct filtering and pushdown of date conditions, especially for queries like `WHERE col > '1900-01-30'::date`.

* Fixed a bug in `sparql.hours(rdfnode)`, `sparql.minutes(rdfnode)`, and `sparql.seconds(rdfnode)` where RDF nodes containing only `xsd:time` were not handled correctly. These functions now properly extract the hour, minute, and second from both `xsd:dateTime` and `xsd:time` typed RDF nodes, instead of assuming all values are `xsd:dateTime`.

* Updated `sparql.concat()` function to comply with SPARQL 1.1: now returns a simple literal (no language tag or datatype) when concatenating literals with conflicting language tags or incompatible datatypes, instead of throwing an error.

* Empty RDF literals incorrectly returned as `NULL`: Fixed a bug where empty RDF literals (e.g., `""`, `""@en`, or `""^^xsd:string`) were being incorrectly returned as SQL NULL values instead of empty strings. The issue occurred in `CreateTuple()` where `xmlNodeGetContent()` returns NULL for empty XML elements. The fix now properly distinguishes between empty RDF terms (valid empty strings) and unbound SPARQL variables (SQL NULL) by checking the XML element type (`<literal>`, `<uri>`, or `<bnode>`).

* Literals with escaped quotes corrupted during round-trip: Fixed a critical bug where literals containing escaped quotes (e.g., `"\"WWU\""@en`) were being corrupted when retrieved from SPARQL results. The `CreateTuple()` function was incorrectly reparsing raw XML text content as RDF syntax, causing quote characters to be interpreted as literal delimiters rather than data. This has been fixed by constructing `rdfnode` values directly from raw lexical content and manually appending language tags or datatypes.

* Control characters not properly escaped in SPARQL statements: Control characters (newlines, tabs, carriage returns) in literals are now properly escaped in SPARQL INSERT and DELETE statements, ensuring correct round-trip behavior.

* `DESCRIBE` queries with large result sets caused severe performance degradation: Fixed a critical performance issue where `sparql.describe()` queries returning large result sets took too long to complete. The root cause was in `DescribeIRI()`, which used `librdf_parser_parse_string_into_model()` to build a complete in-memory RDF graph model before extracting triples. This has been replaced with `librdf_parser_parse_string_as_stream()`, which processes RDF/XML on-the-fly without constructing an intermediate graph database. This dramatically reduces memory footprint and brings `DESCRIBE` query performance in line with SELECT queries handling similar-sized result sets.

* UCASE and LCASE functions failed to convert multibyte UTF-8 characters: Fixed a bug where `sparql.ucase()` and `sparql.lcase()` were only converting ASCII characters (a-z, A-Z) and leaving multibyte UTF-8 characters unchanged. For example, `sparql.ucase('"Westfälische Wilhelms-Universität Münster"@de')` would incorrectly return `"WESTFäLISCHE WILHELMS-UNIVERSITäT MüNSTER"@de` instead of properly uppercasing ä, ö, ü to Ä, Ö, Ü. The functions now use PostgreSQL's built-in `upper()` and `lower()` functions with proper collation support, correctly handling all Unicode characters according to the database's locale settings.

* SUBSTR function failed for multibyte UTF-8 characters and empty inputs: Fixed a bug in `sparql.substr()` where it incorrectly counted bytes instead of characters for multibyte UTF-8 strings, leading to truncated results. Additionally, the function now correctly returns an empty string when the start position is beyond the string length, instead of throwing an error.

* Malformed SPARQL with `FILTER(NULL)` in older PostgreSQL versions: Fixed a bug in PostgreSQL 9.5 where NULL constants in expressions were being deparsed as the literal string "NULL" instead of returning a `NULL` pointer. This caused malformed SPARQL queries like `FILTER(NULL)` to be generated. The fix ensures that NULL constants are properly handled by preventing pushdown of such expressions.

* Fixed unexpected behavior in `sparql.bnode()` where passing an already-formatted blank node (e.g., `_:bnode1`) would return SQL `NULL` instead of handling it gracefully. The function now implements idempotent behavior: if the input is already a blank node, it returns it as-is.

* Fixed a bug where local filters (`WHERE` clauses) that were pushed down were also being evaluated locally, which was just redundant. Now, only conditions that cannot be pushed down are evaluated locally by PostgreSQL, ensuring correct results for non-pushable foreign tables.

# 2.2.0
Release date: **2025-12-07**

## Enhancements

* SPARQL aggregate functions:

  Added support for SPARQL-style aggregate functions `sparql.sum`, `sparql.avg`, `sparql.min`, `sparql.max`, `sparql.group_concat`, and `sparql.sample` in SQL queries. These functions are now fully implemented and can be used for local aggregation in PostgreSQL, improving compatibility with SPARQL semantics and enabling more expressive analytics on RDF data. Aggregate pushdown to the SPARQL endpoint is not yet supported; all aggregation is performed locally by PostgreSQL.

* Enhanced version information:

  The `rdf_fdw_version()` function now returns a comprehensive version string that includes PostgreSQL version, compiler information, and all dependency versions (libxml, librdf, libcurl) in a single formatted output. A new `rdf_fdw_settings()` function provides extended dependency information including optional components like SSL, zlib, libSSH, and nghttp2. The `rdf_fdw_settings` view parses this extended information into a table format for convenient programmatic access to individual component versions.

* Improved EXPLAIN diagnostics for Foreign Scan nodes:

  EXPLAIN output now include rdf_fdw-specific details for each Foreign Scan node, showing which SQL clauses are pushed down to the remote SPARQL endpoint. The plan displays lines such as `Pushdown: enabled/disabled`, `Remote Filter`, `Remote Sort Key`, `Remote Limit`, and `Remote Select`, making it easier to understand query translation and pushdown behavior.

## Bug Fixes

* Fix `lex()` to correctly handle doubled-quote escapes in literals.

  RDF literals containing double-quotes were being truncated, leading to invalid results of `sparql.lex()` or any function that depends on it. This has now being fixed.

# 2.1.0
Release date: **2025-09-25**

## Enhancements

* SPARQL Prefix Management:

  `rdf_fdw` now includes built-in support for SPARQL prefix management via a structured catalog and helper functions. This feature introduces:

  `prefix_contexts`: Named groups of reusable SPARQL prefixes.

  `prefixes`: Individual prefix → URI mappings associated with a context.

  A suite of SQL functions to add, update, delete, and override contexts and prefixes. This enhancement simplifies query generation, reduces redundancy, and makes SPARQL integration more maintainable — especially when dealing with multiple endpoints or vocabularies.

* Add `enable_xml_huge` server option to support large XML result sets

  The new `enable_xml_huge` option allows users to enable libxml2's `XML_PARSE_HUGE` flag when parsing SPARQL result sets. This is useful for consuming large XML responses that exceed libxml2's default safety limits. By default, this option is disabled for security reasons.

## Bug Fixes

* NULL RDFNodes:
    
  This fixes a bug that could potentially lead the system to crash if the triple store returns a `NULL` value for an specific node (edge case).

* xmlParseMemory errors

  An issue has been resolved where the system could potentially crash if libxml2 failed to parse a given XML string (for example, due to an out-of-memory error). A check has been added to detect and prevent such crashes.

* xmlDocGetRootElement failing to get the root element

  A safeguard has been introduced to handle cases where xmlDocGetRootElement fails to parse the root node of an XML document. Instead of proceeding with an empty set, an error message is now displayed to inform the user of the issue.

# 2.0.0
Release date: **2025-05-22**

This is a major release of `rdf_fdw` featuring substantial new features, improved standards compliance, and important infrastructure enhancements. Backward compatibility is preserved, but users are encouraged to review the new features and updated behavior.

## Enhancements

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

## Minor Changes
* The `FOREIGN TABLE` option `log_sparql` is now set to `true`, if omitted. If you don't want to log the SPARQL query, consider using [`ALTER FOREIGN TABLE`](https://github.com/jimjonesbr/rdf_fdw?tab=readme-ov-file#alter-foreign-table-and-alter-server) to disable this option manually, e.g.

  ```sql
  ALTER FOREIGN TABLE myrdftable OPTIONS (ADD log_sparql 'false');
  ```

## Bug Fixes

* Query cancellation support:

  Added `CHECK_FOR_INTERRUPTS()` in key execution points to allow PostgreSQL backends to detect user-initiated query cancellations (e.g., Ctrl+C), improving long-running query handling.

## External Libraries

 * Added a new dependency: Redland RDF Library (`librdf`) — used for parsing and serializing RDF data, and supporting `DESCRIBE` queries.

# 1.3.0
Release date: **2024-09-30**

## Enhancements

* Support for PostgreSQL 9.6, 10, and 17: This adds support for the long EOL'd PostgreSQL versions 9.6 and 10. It is definitely discouraged to use these unsupported versions, but in case you're for whatever reason unable to perform an upgrade you can now use the `rdf_fdw`. 

# 1.2.0
Release date: **2024-05-22**

## Enhancements

* Pushdown support for [Math](https://www.postgresql.org/docs/current/functions-math.html), [String](https://www.postgresql.org/docs/current/functions-string.html) and [Date/Time](https://www.postgresql.org/docs/current/functions-datetime.html) functions:
  * `abs`, `ceil`, `floor`, `round`
  * `length`, `upper`, `lower`, `starts_with`, `substring`, `md5`
  * `extract(year from x)`, `extract(month from x)`, `extract(year from x)`, `extract(hour from x)`, `extract(minute from x)`, `extract(second from x)`
  * `date_part(year, x)`, `date_part('month',x)`, `date_part('year', x)`, `date_part('hour', x)`, `date_part('minute', x)`, `date_part('second', x)`

  When used in the `WHERE` clause these functions will be translated to their correspondent SPARQL `FILTER` expressions.

## Bug Fixes

* Bug fix for WHERE conditions with "inverted" arguments - that is, value in the left side (T_Const) and column in the right side (T_Var): This fixes a bug that led the pushdown of `WHERE` condiditions containing "inverted" arguments to fail, e.g `"foo" = column`, `42 > column`. Now the order of T_Const and T_Var in the arguments is irrelevant.


# 1.1.0
Release date: **2024-04-10**

## Enhancements

* [`USER MAPPING`](https://github.com/jimjonesbr/rdf_fdw?tab=readme-ov-file#create-user-mapping) support: This feature defines a mapping of a PostgreSQL user to an user in the target triplestore - `user` and `password`, so that the user can be authenticated. Requested by [Matt Goldberg](https://github.com/mgberg). 

* Pushdown suuport for [`pattern matching operators`](https://www.postgresql.org/docs/current/functions-matching.html#FUNCTIONS-LIKE) `LIKE` and `ILIKE`: these operators are now translated into SPARQL `FILTER` expressions as `REGEX` and pushed down.

* Enables usage of non-pushable data types in `FOREIGN TABLE` columns: This disables a check that raised an excepetion when data types that cannot be pushed down were used. This includes non-standard data types, such as `geometry` or `geography` from PostGIS.

## Bug Fixes

* Empty SPARQL `SELECT` clause: This fixes a bug that led some SPARQL queries to be created without any variable in the `SELECT` clause. We now use `SELECT *` in case the planner cannot identify which nodes should be retrieved, which can be a bit inefficent if we're dealing with many columns, but it is much better than an error message.

* Missing schema from foreign tables in `rdf_fdw_clone_table` calls: This fixes a bug that led the `rdf_fdw_clone_table` procedure to always look for the given `FOREIGN TABLE` in the `public` schema.

* xmlDoc* memory leak: The xml document containing the resulst sets from the SPARQL queries wasn't beeing freed after the query was complete. This led to a memory leak that could potentially cause a system crash once all available memory was consumed by the orphan documents - which is an issue for rather modest server settings that execute mutliple queries in the same session. Reported by [Filipe Pessoa](https://github.com/lfpessoa).

# 1.0.0
Release date: **2024-03-15**

Initial release. 

Support for PostgreSQL 11, 12, 13, 14, 15 and 16.

## Main Features

* Pushdown: [`LIMIT`](https://github.com/jimjonesbr/rdf_fdw?tab=readme-ov-file#limit), [`ORDER BY`](https://github.com/jimjonesbr/rdf_fdw?tab=readme-ov-file#order-by), [`DISTINCT`](https://github.com/jimjonesbr/rdf_fdw?tab=readme-ov-file#distinct), [`WHERE`](https://github.com/jimjonesbr/rdf_fdw?tab=readme-ov-file#where) with several [data types and operators](https://github.com/jimjonesbr/rdf_fdw?tab=readme-ov-file#where)
* Table copy: This introduces the procedure [`rdf_fdw_clone_table()`](https://github.com/jimjonesbr/rdf_fdw?tab=readme-ov-file#rdf_fdw_clone_table), that is designed to copy data from a `FOREIGN TABLE` into an ordinary `TABLE`. It provides the possibility to retrieve the data set in batches.
* Proxy Support for [`SERVER`](https://github.com/jimjonesbr/rdf_fdw?tab=readme-ov-file#create-server): quite handy feature in case the PostgreSQL and SPARQL endpoint servers are in different networks and can only communicate through a proxy.