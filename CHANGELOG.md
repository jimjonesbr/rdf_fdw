# 3.0
Release date: **unreleased**

## Summary

This release fixes multiple correctness issues where queries returned wrong rows or crashed the backend, rewrites RDF comparison and arithmetic to match the SPARQL specification, and requires manual steps when upgrading from 2.x (see "Before you upgrade" below).

The most impactful bug fixes: out-of-bounds reads and heap overflows that could segfault or corrupt results; flawed comparison logic that let queries return wrong rows depending on INSERT order; pushdown restrictions that re-evaluate conditions that were previously sent to the endpoint, making queries slower but correct. Highlights: language tags are now fully normalized; `sparql.uri()` returns `rdfnode` not `text`; arithmetic on `rdfnode` now follows SPARQL; `GROUP BY` and `DISTINCT` now sort/group by written term, not by value; redirects are now configurable in a single option.

## Before you upgrade

**The upgrade will refuse to run** while any index exists on an `rdfnode`
column, or any view, materialized view or SQL-body function that sorts, groups
or de-duplicates on one. `rdfnode_ops` is rebuilt on comparisons of the stored
term, and replacing an operator class does not rewrite what was built with it.
Save the definitions, drop those objects, upgrade, and recreate them. `REINDEX`
is not enough. Stored queries that only compare `rdfnode`s are unaffected.

**One option value is no longer accepted.** `request_max_redirect '-1'` is
rejected; use a positive bound, or `0` to refuse redirects. `request_redirect`
is deprecated but still works.

**One function signature changed.** `sparql.uri()` returns `rdfnode` rather
than `text`, which is what its synonym `sparql.iri()` always returned;
assigning its result straight into a `text` column now needs an explicit
`::text`.

**Queries in specific cases might produce different results** to align with SPARQL specification and improve consistency:

* `GROUP BY`, `DISTINCT`, `UNION` and unique constraints on an `rdfnode` now
  compare terms by how they are written rather than by value, so `"1"^^xsd:integer`
  and `"01"^^xsd:integer` are treated as distinct. `ORDER BY` is unchanged.
* `sparql.sum()` and `sparql.avg()` now follow SPARQL specification for empty groups
  (returning `"0"^^xsd:integer` instead of NULL) and for NaN comparisons.
* Numeric literal comparisons and type coercion now follow SPARQL rules: literals
  compare in the wider of their two datatypes; IRIs and blank nodes are distinguished
  from literals; language tags compare case-insensitively.
* `ROUND()`, `ABS()`, `REPLACE()`, `GROUP_CONCAT()`, `SUBSTR()` and `float4` output
  now produce results consistent with SPARQL/RDF specifications.
* Arithmetic between an `rdfnode` and a PostgreSQL number now correctly produces an
  `rdfnode` result computed in RDF datatypes, e.g., `'"0.1"^^xsd:decimal'::rdfnode * 3.0`
  now answers `"0.3"^^xsd:decimal` instead of `0.30000000447034836` as a double.

**Some specific query patterns are now evaluated locally** for correctness: conditions that could not be safely sent to the endpoint without risking wrong rows now run in PostgreSQL. This is rare and affects edge cases like `LIMIT` with `ORDER BY`, comparisons between `rdfnode` and PostgreSQL temporal types, `DISTINCT` with aggregates, and a few `pg_catalog` functions with different SPARQL semantics. Most queries are unaffected. For performance-sensitive cases that do touch these patterns, explicit casts or column types can pin the comparison to PostgreSQL semantics and allow pushdown.

## Enhancements

* **Arithmetic on `rdfnode`**: `+`, `-`, `*` and `/` now combine two numeric `rdfnode`s, following the SPARQL 1.1 §17.3 operator mapping: the result takes the wider of the two datatypes, and dividing two `xsd:integer`s gives an `xsd:decimal`. The type had no arithmetic operators at all before, so `1::rdfnode + 1::rdfnode` did not fail for want of a definition — PostgreSQL fell back to resolving it through the type's casts, four of which are implicit, and reported that several candidates tied. The same gap left the extension recommending `rdfnode` while only the deprecated native-typed columns could reach the arithmetic the deparser pushes into a SPARQL `FILTER`. A term that is not a numeric literal raises an error rather than producing a number.

  The same four operators also combine an `rdfnode` with a PostgreSQL `smallint`, `int`, `bigint`, `real`, `double precision` or `numeric`, written on either side — the coverage the comparison operators already had. The PostgreSQL operand stands for the term its cast to `rdfnode` produces, so an `int` is an `xsd:int`, a `numeric` an `xsd:decimal` and a `double precision` an `xsd:double`, and the promotion and the result's datatype follow from the pair exactly as they do between two terms. Without these, PostgreSQL resolved such an expression through the type's implicit casts, which either tied — `'"1"^^xsd:integer'::rdfnode + 1` reported that the operator was not unique — or settled on the implicit `rdfnode` → `real` cast and did IEEE arithmetic, leaving RDF without saying so: `'"0.1"^^xsd:decimal'::rdfnode * 3.0` answered `0.30000000447034836` as a `double precision` where `xsd:decimal` arithmetic is exact and SPARQL answers `"0.3"^^xsd:decimal`. Such an expression could not be pushed down either, since the cast stood between the column and the operator.

  Arithmetic that mixes an `rdfnode` with a `real` or a `double precision` is evaluated in PostgreSQL rather than sent to the endpoint. SPARQL's bare numeric literals are `xsd:integer` and `xsd:decimal` — a double needs the exponent form, `2.5e0` — so the constant would arrive as an `xsd:decimal` and the endpoint would compute in a different datatype than the operator does. Integer and `numeric` operands are unaffected and still push down. Comparisons are unaffected as well: XPath promotes the decimal to the double before comparing, so the literal's datatype cannot change the answer there.

* **`request_max_redirect` is now the single option controlling HTTP redirects**: Redirection used to be governed by two options that had to agree with each other — `request_redirect` switched it on, and `request_max_redirect` bounded it — which made it possible to write server definitions whose two halves contradicted each other, and one of those combinations was silently broken (see the bug fix below). `request_max_redirect` now carries both meanings on its own: `0` (the default) refuses any redirect, and any higher value enables redirection and caps it at that many hops. The `-1` (unlimited) value has been dropped, since an unbounded redirect chain has no practical use against a SPARQL endpoint and invites never-ending redirect loops.

  ```sql
  -- follow at most 5 redirects
  CREATE SERVER dbpedia
  FOREIGN DATA WRAPPER rdf_fdw
  OPTIONS (endpoint 'https://dbpedia.org/sparql', request_max_redirect '5');
  ```

  `request_redirect` is deprecated but still accepted, so existing servers and dumps continue to work: setting it raises a warning, and `request_redirect 'true'` without an explicit `request_max_redirect` follows up to 30 redirects, which is what libcurl would have done before. It will be removed in a future major release.

## Breaking Changes

* **`sparql.uri()` returns `rdfnode`, not `text`**: SPARQL 1.1 §17.4.2.8 defines `URI()` as another name for `IRI()`, and both give back an IRI. `sparql.uri()` has declared a return type of `text` since 2.1, although it calls the same C function as `sparql.iri()` and produces the same term — so its result could not be given to any other `sparql` function without a cast, and `sparql.isiri(sparql.uri(...))` was an error where `sparql.isiri(sparql.iri(...))` was not. It now returns `rdfnode`, and the two are interchangeable as the specification says they are. A query that assigned its result straight into a `text` column will need an explicit `::text`; there is no implicit cast from `rdfnode` to `text`.

* **`rdfnode`s are sorted and grouped by the stored term**: `ORDER BY`, `GROUP BY`, `SELECT DISTINCT`, `UNION` and unique constraints take their comparisons from the type's default B-tree operator class, not from the `=` and `<` operators directly. That class declared the RDF value operators but ordered terms by how they are written, and the two do not agree — which gave wrong answers, described in the bug fix below.

  The class now compares the stored term throughout. Two terms are the same to it when they are written the same way, so `"1"^^xsd:integer` and `"01"^^xsd:integer` are one value and two terms: they sort apart, and they are two groups rather than one. Group or order by a cast where the value's ordering is the one wanted — `GROUP BY term::numeric`.

  `ORDER BY` itself is unchanged, since sorting already used this comparison. What changes is `GROUP BY`, `DISTINCT`, `UNION` and unique constraints, which previously merged value-equal spellings — but only sometimes, and never dependably.

  The value operators `=`, `<>`, `<`, `<=`, `>=` and `>` are untouched and still mean what they meant, including in a `WHERE` clause. The class is built on five operators of its own, `~=`, `~<~`, `~<=~`, `~>=~` and `~>~`, named after PostgreSQL's `text_pattern_ops`. They are seldom written by hand; where they matter is an index, which can answer a condition written with one of them, while a value comparison is applied as a filter to the rows the scan returns.

  **Upgrading from an earlier version requires manual steps.** Replacing an operator class does not rewrite what was built with it, so `ALTER EXTENSION rdf_fdw UPDATE TO '3.0'` refuses to run while any index on an `rdfnode` exists, or any view, materialized view or SQL-body function that sorts, groups or de-duplicates on one. Save their definitions, drop them, upgrade, and recreate them. `REINDEX` is not enough — an index belongs to the operator class it was created with. A stored query that only compares `rdfnode`s does not have to be touched. Nothing is dropped automatically.

## Minor Changes

* **libcurl's trace moved from `DEBUG3` to `DEBUG5`**: The extension logged libcurl's verbose output, and the size of each chunk of a response body as it arrived, at the same level as its own tracing. None of it repeats between runs: it carries the response `Date`, whatever session cookie the server issues, the address the host resolved to, the server's own request counter, and chunk sizes decided by how the body happens to arrive rather than by what it contains. That made `client_min_messages = DEBUG3` unusable for anything comparing two runs — `make installcheck INCLUDE_DEBUG_TESTS=1` failed on a clean tree with 948 lines differing, and two runs of the unmodified tree disagreed with each other. `DEBUG3` now carries what the extension does and `DEBUG5` how the bytes travel, and the debug test passes and repeats.

* **The extension is no longer declared relocatable**: `rdf_fdw.control` set `relocatable = true`, but the extension creates a `sparql` schema and installs part of itself there, so its objects live in two schemas and `ALTER EXTENSION rdf_fdw SET SCHEMA ...` was refused by PostgreSQL regardless. The control file now says `relocatable = false`, which is what the extension actually is.

* **Regression tests that need a triplestore are now opt-in**: `make installcheck` used to run the full suite by default, including the tests that query locally deployed triplestores and public SPARQL endpoints, and four `SKIP_*` variables had to be set to get a run that needs nothing but PostgreSQL. That default made the extension awkward to test for anyone building it in a sandbox, such as a distribution packager. The polarity is now inverted: `make installcheck` runs only the tests that need no external service, and the groups that do are enabled with `INCLUDE_LOCAL_TESTS=1` (the triplestores deployed by `scripts/postgres-env`), `INCLUDE_EXTERNAL_TESTS=1` (public SPARQL endpoints), `INCLUDE_STRESS_TESTS=1`, `INCLUDE_DEBUG_TESTS=1`, or `INCLUDE_ALL_TESTS=1` for all of them.

## Bug Fixes

### Crashes, memory safety and leaks

* **Fixed datatype handling for `bigint` casts on 32-bit systems**: Casts to `rdfnode` now correctly use 64-bit integers. On 32-bit systems where `long` is 32 bits, the conversion was reading only half the argument, so `42::bigint::rdfnode` came back as `"42"^^(null)` instead of `"42"^^xsd:long`. Option validation also now correctly distinguishes bounded from unbounded settings on 32-bit systems. These fixes were found by building and testing on 32-bit platforms for the first time.

* **Fixed a crash when querying a foreign table with a dropped column**: An accidental null dereference could crash the backend; this is now safely handled. (Tomas Vondra <tomas@vondra.me>)

* **Fixed resource leaks when a query does not finish normally**: libcurl resources are now properly released on cancellation or errors, not just on normal completion. (Tomas Vondra <tomas@vondra.me>)

* **Fixed a buffer overrun in HTTP header collection**: Headers are now collected with the correct length bounds, safely handling all content types. (Tomas Vondra <tomas@vondra.me>)

* **Fixed out-of-bounds read in boolean test deparsing**: The column lookup for `IS TRUE`/`IS FALSE` now safely validates that a matching column exists before dereferencing, preventing reads past the array boundary. Conditions with no corresponding mapping are now correctly reported as not pushable.

* **Fixed libcurl initialization error handling and stderr output**: Failures of `curl_easy_init()` or `curl_easy_escape()` are now detected and raise proper errors instead of being silently skipped. The extension no longer writes partial diagnostic messages directly to `stderr`, bypassing the server log's formatting. (Tomas Vondra <tomas@vondra.me>)

* **Fixed a libcurl handle leak when `max_response_size` is exceeded**: The callback that collects the HTTP response body raised the "response exceeds max_response_size" error with `ereport(ERROR)` from inside libcurl. That longjmps out of the middle of `curl_easy_perform()`, so neither `curl_easy_cleanup()` nor `curl_slist_free_all()` ever ran — and since libcurl allocates the easy handle, its header list and its connection outside PostgreSQL's memory contexts, aborting the transaction did not reclaim them either. Every query that hit the limit therefore leaked a handle and a connection for the remaining life of the backend, on top of abandoning libcurl mid-transfer. The callback now flags the condition and aborts the transfer by returning a short write, which makes `curl_easy_perform()` fail cleanly; the very same error is raised afterwards, once the handle and the header list have been released. Requests aborted this way are also no longer retried, as every attempt would hit the same limit.

* **Fixed literal parsing with trailing backslashes**: Literals ending in backslashes were misparsed; escape sequences are now handled correctly and literals round-trip through `text` unchanged. (Tomas Vondra <tomas@vondra.me>)

* **Fixed language tag extraction**: The `lang()` function now safely bounds its buffer reads and correctly handles all literal formats. (Tomas Vondra <tomas@vondra.me>)

* **Fixed memory ownership in literal conversion**: `cstring_to_rdfliteral()` now properly manages memory across all code paths. (Tomas Vondra <tomas@vondra.me>)

* **Fixed column validation to require `variable` option on foreign tables**: Columns are now validated at table load time, preventing `pstrdup(NULL)` segfaults that occurred when planning queries with unvalidated columns. Clear error messages are now provided for missing options. (Tomas Vondra <tomas@vondra.me>)

* **Fixed buffer handling in `rdf_fdw_clone_table()`**: The binding loop now correctly processes one value per column, with proper bounds checking. (Tomas Vondra <tomas@vondra.me>)

* **Fixed `sparql.coalesce()` to safely handle NULL variadic arrays**: Calling `sparql.coalesce(VARIADIC NULL::rdfnode[])` now correctly returns NULL instead of dereferencing a NULL array pointer. The function is non-`STRICT` to skip NULL arguments, so it gets called even when the variadic array itself is NULL. This issue affected all users and could cause sessions to crash.

### Privileges and network safety

* **Fixed privilege checking in clones**: Privileges are now re-checked for each page, ensuring a `REVOKE` issued by another session is respected. (Tomas Vondra <tomas@vondra.me>)

* **Enabled access to SPARQL functions for all users**: The `sparql` schema is now properly granted to `PUBLIC`, making all 125 functions accessible. (Tomas Vondra <tomas@vondra.me>)

* **Restricted redirects to HTTP and HTTPS**: `rdf_fdw` limits requests to the `http` and `https` protocols, but that restriction only covers the initial request — libcurl governs the protocols a redirect may lead to with a separate option, whose default also permits `ftp` and `ftps`. An endpoint could therefore answer with a redirect to an `ftp://` URL and have the backend follow it. Redirect targets are now restricted to `http` and `https` as well.

* **Added privilege checks to `rdf_fdw_clone_table()` and `sparql.describe()`**: Both functions now properly validate `ACL_SELECT` and `ACL_USAGE` on their targets. (Tomas Vondra <tomas@vondra.me>)

* **Improved IRI and blank node validation**: Term syntax is now validated against the SPARQL grammar, preventing malformed terms from altering filter meaning or INSERT/DELETE statements. (Tomas Vondra <tomas@vondra.me>)

### RDF values, literals and functions

* **Fixed literal value escaping when reading from SPARQL endpoints**: Backslashes in endpoint values are now properly escaped before storing as `rdfnode`. The XML of SPARQL results carries literal values with ordinary backslashes, but these weren't being escaped when stored, causing values like `C:\temp` to be read back as `C:`, tab, `emp`. This broke UPDATE/DELETE operations which send the stored term back to identify triples. Clones and `sparql.describe()` are also fixed and no longer strip quotes from values. (Tomas Vondra <tomas@vondra.me>)

* **Fixed string functions to handle both typed and received literal values consistently**: String functions now correctly interpret escape sequences in lexical forms, so typed and received values of the same string give the same answer. Previously, `sparql.strlen()` would count escape sequences (returning 4 for `"a\"b"` vs. 3 from the endpoint), `sparql.md5()` and `sparql.encode_for_uri()` would hash the raw backslashes, `sparql.ucase()` would produce invalid escapes like `\N` from `\n`, and substring operations would work with escape positions instead of actual characters. All string functions (`strlen`, `substr`, `contains`, `strstarts`, `strends`, `strbefore`, `strafter`, `md5`, `encode_for_uri`, `ucase`) now operate on the actual character values. (Tomas Vondra <tomas@vondra.me>)

* **Fixed `sparql.sum()` and `sparql.avg()` to correctly handle infinity on all PostgreSQL versions**: On PostgreSQL versions before 14, `numeric` lacks infinity support, so the accumulator would reject `"INF"^^xsd:double` and raise an error. An infinity is now recorded separately from the accumulator, letting IEEE 754 rules govern the answer: an infinity absorbs any finite value, and opposing infinities produce `NaN`. All versions now return results consistent with Fuseki, GraphDB, Virtuoso and QLever.

* **Fixed ordering comparison error messages for unsupported datatypes**: When comparing two literals with the same unsupported datatype (e.g., `xsd:anyURI`), the error message now correctly identifies the datatype and explains which datatypes SPARQL 1.1 supports for ordering. Previously, the message incorrectly suggested the datatypes were different.

* **Fixed `sparql.min()` and `sparql.max()` to handle negative `xsd:duration` values**: Negative durations like `"-P1D"^^xsd:duration` now parse correctly, matching the behavior of comparison operators which already handled them. XSD 1.1 admits the leading `-` sign, and the aggregate comparators now strip it and negate the result like the comparison operators do.

* **Fixed `xsd:anyURI` literals to preserve their datatype and not merge with plain literals**: `xsd:anyURI` terms now correctly remain distinct from plain string literals and from each other as written. Previously, `"http://a"^^xsd:anyURI` compared equal to `"http://a"` and `"http://a"^^xsd:string`, contradicting RDF 1.1 Concepts §3.3 and SPARQL 1.1 §17.3 which only define equality and ordering for specific datatypes. The datatype is now treated like other unrecognized datatypes: equal only to an identical term, unequal to different spellings or datatypes, and not ordered. This fixes result mismatches between pushdown and local evaluation.

* **Fixed `sparql.replace()` to correctly handle XPath capture-group references**: Replacement strings now correctly interpret XPath syntax (`$1` through `$9` for groups, `\$` for literal dollar, `\\` for literal backslash) and rewrite them to PostgreSQL's `regexp_replace` syntax. Previously, `REPLACE("abab", "a(b)", "[$1]")` returned `"[$1][$1]"` instead of the correct `"[b][b]"`.

* **Fixed `sparql.tz()` to return empty string for timezone-naive literals**: SPARQL 1.1 §17.4.5.8 specifies that `tz()` returns an empty string when there is no timezone. Now `tz("2011-01-10T14:45:13.815"^^xsd:dateTime)` correctly returns `""` instead of raising an error. This aligns with Fuseki, GraphDB and QLever behavior.

* **Fixed `sparql.sum()` and `sparql.avg()` to compute in promoted IEEE 754 datatypes with correct spellings**: Results are now written in proper IEEE 754 form with infinities spelled `INF` and `-INF` (not `Infinity`), matching Fuseki and GraphDB. Previously, accumulation in PostgreSQL's `numeric` type could produce very large integers or incorrectly-spelled special values outside the IEEE 754 range.

* **Fixed division by zero on floating-point terms to follow IEEE 754 semantics**: Dividing floating-point terms by zero now produces `INF`, `-INF`, or `NaN` according to IEEE 754 rules, as specified by XPath and SPARQL 1.1 §17.3. For example, `"1"^^xsd:double / "0"^^xsd:double` now correctly returns `"INF"^^xsd:double`. Exact numeric types (`xs:decimal`, `xs:integer`) still raise an error as specified.

* **Fixed numeric literal validation to check lexical form and value range against datatype**: The `isNumeric()` function now properly validates literals against their declared datatype's constraints. Previously, it accepted invalid spellings like hexadecimal in `xsd:integer` and ignored value ranges (e.g., `"99999"^^xsd:short` was incorrectly considered numeric). Validation now follows XSD specifications. (Tomas Vondra <tomas@vondra.me>)

* **Fixed blank node handling in `sparql.describe()`**: Unnamed blank nodes are now correctly reported with generated labels and their statements. (Tomas Vondra <tomas@vondra.me>)

* **Fixed language tag normalization to lowercase the entire tag**: Language tags are now fully normalized to lowercase per RDF 1.1 Concepts §3.3, not just the first component. Previously, only the part before the first hyphen was lowercased, causing `@EN-GB`, `@en-gb`, and `@ZH-Hant-TW` to be treated as three different terms. Existing data is unaffected until rewritten.

* **Fixed string functions to enforce correct types**: `STRLEN()`, `LANG()` and `REPLACE()` now correctly require literal arguments and properly count code points. (Tomas Vondra <tomas@vondra.me>)

* **Fixed rdfnode comparison consistency in GROUP BY and DISTINCT**: The operator class now correctly and consistently compares terms as stored, fixing results that varied based on data or query plan. (Tomas Vondra <tomas@vondra.me>)

* **Fixed `sparql.sum()` and `sparql.avg()` to return correct values for empty groups**: Both functions now return `"0"^^xsd:integer` for empty multisets per the SPARQL specification, instead of NULL. This aligns with `group_concat()` and other SPARQL aggregates.

* **Fixed NaN equality handling**: `"NaN"^^xsd:double` now correctly reports as not equal to itself, per the SPARQL specification. (Tomas Vondra <tomas@vondra.me>)

* **Fixed value accessor width on 32-bit systems**: Integer comparisons and temporal `Datum` handling now use the correct widths, fixing incorrect results on 32-bit platforms. (Tomas Vondra <tomas@vondra.me>)

* **Fixed type checking in string comparison functions**: `sparql.contains()`, `sparql.strstarts()`, `sparql.strends()`, `sparql.strbefore()` and `sparql.strafter()` now correctly reject IRIs and blank nodes instead of operating on their string representation. (Tomas Vondra <tomas@vondra.me>)

* **Fixed string comparison functions to handle language tags case-insensitively**: `sparql.contains()`, `sparql.strstarts()`, `sparql.strends()`, `sparql.strbefore()` and `sparql.strafter()` now correctly compare language tags without regard to case. Previously, literals with the same tag in different cases (e.g., `@en-GB` vs `@en-gb`) were treated as incompatible, causing these functions to return NULL instead of a result. This is especially important for literals from different sources, where case variations are common. (Tomas Vondra <tomas@vondra.me>)

* **Fixed numeric literal comparison to consistently promote to the wider datatype**: Comparisons now uniformly promote operands to the wider of their two datatypes per XPath specification, instead of using inconsistent logic based on operand order or comparison type. Previously, different operators made different decisions: ordering operators inspected only the left operand, equality promoted differently than aggregates, and `"16777217"^^xsd:float` could be equal to `"16777216"^^xsd:float` in `sparql.min()` but not in `=`. All comparisons now share one implementation, matching behavior across Fuseki, Virtuoso, and GraphDB. (Tomas Vondra <tomas@vondra.me>)

* **Fixed term classification to distinguish IRIs and blank nodes from literals**: IRIs and blank nodes now properly rank below literals in `sparql.min()`/`sparql.max()`, and are no longer compared equal to plain literals with similar spelling. For example, IRI `<http://example.org/v>` is now correctly distinct from literal `"<http://example.org/v>"`. (Tomas Vondra <tomas@vondra.me>)

* **Fixed `sparql.describe()` to correctly return blank-node subjects**: Blank nodes in `rdf:nodeID` subjects are now properly returned as blank nodes instead of being converted to IRIs. Previously, `_:b1` would be read as `<b1>`, causing a single blank node to appear under both spellings in results.

* **Fixed XML element content parsing**: Terms with CDATA or comments are now read completely instead of partially. (Tomas Vondra <tomas@vondra.me>)

* **Fixed type conversion for result values**: Result values are now converted with proper type modifiers and I/O parameters, fixing array columns and precision handling in temporal types. (Tomas Vondra <tomas@vondra.me>)

* **Fixed temporal type comparisons to handle incompatible datatypes gracefully**: Comparisons between RDF terms and PostgreSQL date/time types now return no match for incompatible datatypes instead of raising an error. All five temporal families now share one unified conversion function. (Tomas Vondra <tomas@vondra.me>)

* **Fixed annotation preservation in `REPLACE()`**: Language tags and datatypes are now correctly carried from the input literal to the result. (Tomas Vondra <tomas@vondra.me>)

* **Fixed `GROUP_CONCAT()` to return properly formatted RDF literals**: Empty results are now returned as `""` (a serialized RDF literal) instead of raw text, so `sparql.isliteral()` correctly returns true. (Tomas Vondra <tomas@vondra.me>)

* **Fixed Unicode escape parsing to respect exact widths**: `\u` takes exactly four hex digits and `\U` exactly eight, but a hex digit *following* an escape was treated as though it belonged to it, and the whole sequence was then left undecoded — `"\u004142"` stayed as written instead of becoming `"A42"`, and a surrogate pair followed by a hex digit lost its first half to a replacement character. An escaped backslash was also read as the start of an escape: `"\\u0041"` is a backslash followed by the characters `u0041`, but it decoded to `\A`, which is a different value. Each escape now consumes exactly its own width, and an escaped backslash is passed through.

* **Fixed `SUBSTR()` to handle positions outside string boundaries**: `SUBSTR()` now correctly handles positions outside the string per SPARQL's `fn:substring` specification, returning only the overlapping part. Starting positions below 1 and negative lengths are now processed correctly. (Tomas Vondra <tomas@vondra.me>)

* **Fixed `float4` precision in RDF output**: Values now round-trip correctly, using the type's own output function and respecting `extra_float_digits`. (Tomas Vondra <tomas@vondra.me>)

* **Fixed precision handling in `ABS()`**: Numeric datatypes other than floating-point now preserve their exact values and lexical form. (Tomas Vondra <tomas@vondra.me>)

* **Fixed rounding in `ROUND()`**: Now correctly implements SPARQL's rounding rule (round to nearest, ties toward positive infinity) for all numeric types. (Tomas Vondra <tomas@vondra.me>)

* **Fixed identifier generation in `BNODE()`, `UUID()` and `STRUUID()`**: These functions now generate unique values per row and use proper counter/timestamp combination to avoid duplicates. (Tomas Vondra <tomas@vondra.me>)

* **Fixed type caching in `rdf_fdw_clone_table()`**: The type OID cache is now properly initialized on entry, ensuring `rdfnode` columns are correctly recognized. (Tomas Vondra <tomas@vondra.me>)

* **Fixed Unicode escapes being truncated on non-UTF8 servers**: Escape length was measured with `pg_utf_mblen()` after converting to server encoding, giving wrong results whenever the two differ. Buffers were also undersized. Length is now measured with `strlen()` on the result, and buffers are sized per PostgreSQL's contract. The compatibility shim for pre-13 servers also had the same issues and is now fixed.

### Pushdown

* **A string constant spelled like a column name was pushed down as that column**: The arguments of pushed-down functions and comparisons were recognised as columns by comparing their deparsed text with the column names, so a constant whose value equals a column's name was sent as that column's variable or `expression`. The endpoint then evaluated a different `FILTER` than the one written, and could return wrong results. A constant matching a dropped column also put a NULL pointer into the query, which some older PostgreSQL releases dereference, terminating the backend. Only column references are treated as columns now; constants are always sent as literals.

* **Fixed `!=` pushdown to avoid SPARQL type errors on unsupported datatypes**: Inequality comparisons against literals with unsupported datatypes (e.g., `xsd:anyURI`) are now evaluated locally instead of being sent to the endpoint. SPARQL raises a type error for such comparisons, which filters out matching rows, whereas PostgreSQL returns true for any non-matching term — causing queries to return fewer rows than expected. Equality (`=`) remains pushed down since both approaches select the same rows. Language-tagged literals and all supported datatypes continue to be pushed down. (Tomas Vondra <tomas@vondra.me>)

* **Fixed table planning to correctly handle dropped columns**: Dropped columns are now properly skipped when reading the mapping, ensuring consistent query planning across PostgreSQL versions. Previously, dropped columns on PostgreSQL 17 and earlier appeared as still mapped, blocking rewrite logic and breaking pushdown. (Tomas Vondra <tomas@vondra.me>)

* **Improved function pushdown selectivity**: Only functions from `pg_catalog` and `rdf_fdw` are sent to the endpoint, and semantic mismatches between PostgreSQL and SPARQL functions (like `replace`, `upper`/`lower`, `concat`, `extract`, `round`) are now avoided by keeping them local. (Tomas Vondra <tomas@vondra.me>)

* **Fixed SPARQL keyword detection to handle quoted strings correctly**: Keywords are now recognized accurately by properly parsing all four SPARQL string forms, IRIs, and comments instead of merely counting quotes. Keywords are matched as whole words and recognized even at the very end of a query. Previously, keywords inside single-quoted strings were mistaken for actual keywords, breaking pushdown for affected queries. (Tomas Vondra <tomas@vondra.me>)

* **Fixed SPARQL query rewriting to be more conservative and correct**: Queries are now rewritten only when provably safe: the `SELECT` clause names only variables including every mapped column, nothing follows the closing brace, and there is no `BASE`. Queries that don't meet these criteria are sent as-is and evaluated locally. This prevents incorrect behavior like dropping meaningful clauses (e.g., `SELECT DISTINCT`). (Tomas Vondra <tomas@vondra.me>)

* **Fixed `DISTINCT` pushdown to not apply when row count changes**: `DISTINCT` is now sent to the endpoint only when no aggregates or grouping operations are between the scan and the `DISTINCT`. Previously, `DISTINCT` would be pushed down even with such operations, changing results (e.g., `SELECT DISTINCT count(predicate)` would return `2` instead of the correct `5`). (Tomas Vondra <tomas@vondra.me>)

* **Fixed `LIKE` pattern translation to SPARQL regular expressions**: Patterns are now translated correctly with proper anchors, escaped literals, and control character handling. `ILIKE` is no longer pushed down because Unicode case-folding diverges from database collation, and non-constant patterns are also kept local. Previously, the translation had multiple bugs that could match different strings than the SQL pattern. (Tomas Vondra <tomas@vondra.me>)

* **Improved temporal type comparison handling**: Comparisons with PostgreSQL temporal types are evaluated locally to ensure consistent results across all SPARQL endpoints, avoiding semantic mismatches. (Tomas Vondra <tomas@vondra.me>)

* **Fixed `LIMIT` pushdown to apply only when it won't change results**: `LIMIT` is now sent to the endpoint only on a single scan with no sort above. Previously, it was sent with `ORDER BY` (which is undefined for non-comparable terms in SPARQL), with aggregates, window functions, and joins — all contexts where it changes results. `OFFSET` now uses 64-bit accessors, fixing large offsets like 3000000000. (Tomas Vondra <tomas@vondra.me>)

* **Fixed arithmetic expression parenthesization in pushed-down filters**: Arithmetic operators are now properly parenthesized to preserve correct order of operations. Previously, `(n + 1) * 2` could be written as `?n + 1 * 2` without parentheses, changing the calculation. (Tomas Vondra <tomas@vondra.me>)

* **Fixed variable mapping to accept both `?` and `$` SPARQL sigils**: Both `?x` and `$x` are valid in SPARQL and refer to the same variable, but the mapping only recognized the `?` sigil. Columns declared with `$`-prefixed variables now correctly match endpoint bindings. Previously, such columns would return NULL for all rows despite the endpoint returning correct values. (Tomas Vondra <tomas@vondra.me>)

* **Fixed `EXPLAIN` output to accurately report pushdown status**: When a SPARQL query cannot be rewritten (because it carries its own `LIMIT`, `ORDER BY`, `GROUP BY`, `UNION`, or `MINUS`), `EXPLAIN` now correctly shows `Pushdown: unsupported SPARQL` instead of `Pushdown: enabled` with misleading `Remote` clauses. Previously, queries executed entirely locally could be reported as having remote operations, confusing users about actual execution. The `Remote` lines are now omitted when they don't apply.

* **Fixed SPARQL keyword detection to find the earliest keyword occurrence**: The search now considers all keyword spellings and correctly scans past string literals. Previously, the search would return the first matched spelling rather than the earliest in the query, causing clauses to be lost when keywords appeared in different forms. (Tomas Vondra <tomas@vondra.me>)

* **Fixed SPARQL whitespace handling in `FROM` clauses**: All SPARQL whitespace forms (including newlines) are now correctly skipped when parsing `FROM` clauses. Previously, only literal spaces were recognized, causing multiline queries to lose graph IRIs. (Tomas Vondra <tomas@vondra.me>)

* **Fixed whole-row reference handling in SELECT**: Whole-row references now correctly mark all columns as used, ensuring complete rows are fetched and fixing `DELETE`/`UPDATE` subqueries. (Tomas Vondra <tomas@vondra.me>)

* **Fixed condition evaluation when pushdown is disabled**: Conditions in a `SPARQL` query are now only treated as remote when pushdown is enabled. Previously, with `enable_pushdown 'false'`, conditions were recorded as pushed down but not actually sent to the endpoint, causing them to be evaluated nowhere and returning unfiltered results. Conditions are now properly evaluated locally when pushdown is disabled.

### HTTP requests and responses

* **Fixed response validation to ensure proper SPARQL result format**: Responses are now validated as proper SPARQL results documents instead of silently accepting any XML as results. Non-element nodes are properly skipped, and the page counter is reset per document load. This prevents misdirected endpoints from silently returning empty result sets. (Tomas Vondra <tomas@vondra.me>)

* **Fixed HTTP status code validation for write operations**: Only 2xx HTTP status codes are now treated as successful requests; any other status is reported with the actual code. Previously, a completed transfer was assumed successful unless the status was 400 or higher, allowing 3xx responses to be silently treated as success. This caused `INSERT` and other writes to be acknowledged even when the endpoint had not performed them. (Tomas Vondra <tomas@vondra.me>)

* **Fixed request retry logic to stop when endpoint responds**: The retry loop now stops as soon as an HTTP status is received, instead of continuing to retry failed transfers that already got a response from the server. Retrying is intended for requests that never reached the server; a response means the endpoint has answered. Cancellation requests are now checked between retry attempts.

* **Fixed long prefix context names to be passed as query parameters**: Prefix context names are now passed as query parameters instead of being concatenated into the query string, preventing truncation. Previously, long names were truncated mid-statement, producing malformed SQL. (Tomas Vondra <tomas@vondra.me>)

* **Fixed response handling on connection retry**: Response buffers are now properly cleared before each retry, preventing concatenation of partial and complete responses. (Tomas Vondra <tomas@vondra.me>)

* **Fixed the `custom` server option having no effect**: Custom parameters weren't appended; the SPARQL query was appended twice instead, doubling request size. Custom parameters are now appended correctly.

* **Fixed `request_max_redirect '0'` being silently ignored**: The limit was only set for non-zero values, so `'0'` inherited libcurl's default of 30 redirects. The limit is now always set explicitly. The option is also validated at `CREATE SERVER` time, rejecting non-integers and negative values.

### Writes, cloning and configuration

* **Fixed count queries on foreign tables with no columns**: Tables with no columns can now return counts by fetching results from the endpoint, which correctly answers `count(*)` queries even without mapped columns. (Tomas Vondra <tomas@vondra.me>)

* **Fixed large offset handling in table cloning**: Offset and row count are now 64-bit values with overflow checking, supporting clones past two billion rows. Previously, they were held as 32-bit integers, causing large offsets to wrap to negative counts. (Tomas Vondra <tomas@vondra.me>)

* **Fixed old value retrieval in UPDATE and DELETE**: Row identity columns are now resolved through the planner's interface, ensuring correct old values and proper `DELETE ... RETURNING` behavior. (Tomas Vondra <tomas@vondra.me>)

* **Fixed variable substitution in SPARQL update templates**: Variables are now matched as whole tokens, preventing partial matches (e.g., `?s` matching inside `?subject`) and preventing substitution of variables inside literals, IRIs, and comments. Multiple variables that modify the same value are now handled correctly. (Tomas Vondra <tomas@vondra.me>)

* **Fixed column binding in cloned records**: Unbound columns are now properly represented as NULL instead of using table defaults, and memory is correctly freed for each record. (Tomas Vondra <tomas@vondra.me>)

* **Fixed 64-bit setting truncation during query execution**: Settings are now carried at full width from planning to execution instead of being truncated to 32 bits. This fixes `max_response_size` silently becoming tiny limits and `enable_xml_huge` not being passed to libcurl. (Tomas Vondra <tomas@vondra.me>)

* **Fixed numeric option validation to prevent truncation and wrapping**: Options are now validated with checked conversion at `CREATE SERVER` time, rejecting out-of-range values with clear error messages. Previously, large values were silently truncated or wrapped to negative numbers. (Tomas Vondra <tomas@vondra.me>)

* **Fixed `fetch_size` precedence on foreign tables**: The table-level `fetch_size` option is now correctly read and takes precedence over the server-level value. Previously, only the server's value was used. The procedure's `fetch_size` argument still overrides both. (Tomas Vondra <tomas@vondra.me>)

* **Enabled custom schema installation**: The extension can now be installed into schemas other than `public` with proper type resolution. (Tomas Vondra <tomas@vondra.me>)

* **Fixed `sparql.*` functions to work regardless of caller's `search_path`**: All type references now explicitly name the installation schema instead of relying on unqualified lookups at call time. This makes functions work correctly even when the extension is installed in non-standard schemas. (Tomas Vondra <tomas@vondra.me>)

# 2.7
Release date: **2026-07-26**

## Bug Fixes

* **Fixed a literal-escaping bug that could break out of the generated query**: When serializing an RDF literal into the SPARQL/Turtle text sent to a triplestore — in `FILTER` pushdown, and in `INSERT DATA`/`DELETE DATA` bodies — both `cstring_to_rdfliteral()` and `EscapeSPARQLLiteral()` decided whether a `"` character needed a new escaping backslash using a single-character lookbehind ("was the byte immediately before this quote a backslash?"). That check only gives the right answer when at most one backslash precedes the quote: it cannot distinguish an even-length run of backslashes (which does **not** escape the quote — it's `N/2` independent, already-complete backslash-escape pairs) from an odd-length run (which does). A literal value ending in an unexpected number of backslashes could therefore desync the extension's idea of escaping from the SPARQL/Turtle lexer that later parses the generated query on the endpoint, producing a stray, unescaped quote and letting content after it be interpreted as SPARQL syntax rather than string data. Both functions now determine escaping by counting the full backslash run and checking its parity (and, for locating a literal's closing quote in `EscapeSPARQLLiteral()`, by scanning forward and consuming escape pairs as they're found), which is correct for a run of any length. `EscapeSPARQLLiteral()` was also tightened so that a value with no unambiguous closing quote or with trailing bytes that don't form a valid `@lang`/`^^datatype` suffix is always safely re-escaped as raw content, instead of being returned unmodified as before.

  Thanks **Devrim Gündüz** (@devrimgunduz) for reporting and fixing this issue!

* **Fixed libcurl lifecycle**: `curl_global_init()`/`curl_global_cleanup()` were being called on every SPARQL request instead of once per backend process. This could interfere with other libcurl users loaded in the same backend (e.g. other FDWs). Global initialization now happens once in `_PG_init()`; cleanup is left to the OS at process exit.

# 2.6
Release date: **2026-06-23**

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

* **Pushdown now handles `NOT` boolean expressions**: this allows `NOT BOUND()`, `NOT isIRI()`, `NOT isLiteral()`, and `NOT isNumeric()` to be translated to SPARQL `FILTER (!...)` and executed at the remote endpoint instead of being evaluated locally after fetching. This reduces the number of rows transferred from the endpoint when these conditions are selective.

* **Add support for BCE dates and timestamps in rdfnode casts**: PostgreSQL represents BCE years using BC notation and has no year 0, while XML Schema uses astronomical year numbering (`0000 = 1 BC`, `-0001 = 2 BC`, etc.). Add conversion logic for date, `timestamp`, and `timestamptz` casts to ensure correct round-tripping of BCE values between PostgreSQL and RDF literals.

## Deprecations

* **Native PostgreSQL column types in `FOREIGN TABLE` definitions**: Declaring foreign table columns with standard PostgreSQL types (e.g. `text`, `int`, `date`, `timestamp`) is deprecated. The `rdfnode` type must be used instead, as it correctly represents the full RDF term — including IRIs, language tags, and XSD datatypes — and is required by all SPARQL functions. Existing tables continue to work but will emit a `WARNING` on every query listing the affected columns. The column options `expression`, `language`, `literal_type`, and `nodetype` are also deprecated, as they are only meaningful for native-typed columns. Support for native column types will be removed in a future release.

## Bug Fixes

* **Fixed `CURLE_WRITE_ERROR(23)` on SPARQL UPDATE and unrecognised `Content-Type` responses**: `HeaderCallbackFunction` was returning `0` for any `Content-Type` not recognised as an RDF or SPARQL XML type. Returning `0` from a libcurl write callback signals an abort and triggers `CURLE_WRITE_ERROR(23)`, causing endpoints that respond with `application/json` — such as QLever on successful UPDATEs or Fuseki on HTTP 400 errors — to produce a spurious "unable to connect" error instead of the real outcome. Fixed by returning `realsize` for unrecognised `Content-Type` headers.

* **SPARQL UPDATE response body is now discarded**: For `INSERT`, `DELETE`, and `UPDATE` operations only the HTTP status code matters; the response body is irrelevant. Previously the full body was accumulated in memory, which wasted resources for endpoints that return large JSON documents on success or failure. It now sets `chunk.max_size = 0` to bypass the `max_response_size` limit.

* **HTTP error response bodies are now truncated in log and error messages**: Error bodies included in `errdetail()` and server-log `elog()` calls were previously unbounded. A misconfigured proxy returning a large HTML error page would be written verbatim into the PostgreSQL server log. Error bodies are now truncated to 512 bytes (`RDF_FDW_MAX_ERROR_BODY`) before being included in any message.

* **Encoded credentials are no longer written to server logs via libcurl verbose output**: When `client_min_messages` is set to `DEBUG3`, libcurl's verbose output is now routed through PostgreSQL's `elog(DEBUG3)` via a custom `CURLOPT_DEBUGFUNCTION` callback (`CurlDebugCallback`) instead of being written directly to `stderr`. Crucially, any outgoing or incoming HTTP header whose name matches `Authorization:` or `Proxy-Authorization:` has its value replaced with `[REDACTED]` before being logged, so Bearer tokens, Basic auth credentials (base64-encoded), and proxy passwords never appear in plaintext in the PostgreSQL server log.

* **rdfnodes with invalid trailing content now triggers an error**: rdfnodes with trailing content, which can contain malicious SPARQL instructions, were being silently truncated. While this avoided any attempt at SPARQL injection, it could lead to confusion, since the user was never aware of this truncation. The function `rdfnode_in` now raises an error if such content is detected.

* **Fixes trailing whitespace truncation in rdfnode**: `rdfnode` generated from strings containing trailing whitespaces were being truncated. This is now fixed.

* **Blank nodes in FILTER expressions**: Blank nodes in FILTER expressions are now passed as blank nodes; previously, they were cast as literals. This allows triplestores that deviate from the SPARQL specification to handle blank nodes according to their own implementation.

* **Fixed wrong ordering of string and language-tagged literals in `sparql.min()` / `sparql.max()`**: The aggregate comparator (`rdfnode_cmp_for_aggregate`) was using `varstr_cmp` with `DEFAULT_COLLATION_OID` for lexical comparisons of plain literals, `xsd:string` literals, and language-tagged literals. On databases whose locale is not `C`, this produces locale-dependent ordering (e.g., accented characters may be folded or reordered), which violates [SPARQL 1.1 §17.3](https://www.w3.org/TR/sparql11-query/#OperatorMapping) — string ordering must follow Unicode codepoint order. Both calls have been replaced with `strcmp`.

* **Fixed negative `xsd:duration` round-trip**: Casting a negative PostgreSQL `interval` to `rdfnode` produces a valid XSD duration with a leading `-` (e.g., `-P1Y2M`), but casting that value back to `interval` failed with `invalid input syntax for type interval: "-P1Y2M"` because PostgreSQL's `interval_in` does not accept the XSD negative-duration notation. A helper `xsd_duration_to_pg_interval` now strips the leading `-`, parses the positive form, and negates the result.

* **Fixed trailing zeros in fractional seconds of `xsd:duration` output**: `interval_to_rdfnode` was always formatting sub-second values with six decimal places (e.g., `PT1M0.500000S`). It now strips trailing zeros, producing the canonical lexical form (e.g., `PT1M0.5S`).

* **Fixed `LANGMATCHES` to correctly return `false` when the language tag is empty**: Previously, `LANGMATCHES("", "*")` returned `true`, violating SPARQL 1.1 and RFC 4647 basic filtering semantics, which require `"*"` to match only non-empty language tags. This affected queries filtering untagged literals via `FILTER LANGMATCHES(LANG(?x), "*")`, which would incorrectly include
  untagged literals in results.

* **Fixed `SECONDS()` return type and value**: the `text` overload was incorrectly declared as returning `int` instead of `numeric`, causing fractional seconds to be truncated. Additionally, timezone-aware `xsd:dateTime` values were returning the wrong seconds value due to implicit session timezone adjustment during timestamp casting; the lexical form is now cast to `timestamptz` to preserve the correct component.

* **Fixed `TZ()` to reject invalid timezone offsets**: when given an `xsd:dateTime` literal with an out-of-range timezone offset (e.g., `"2020-12-01T08:00:00+25:00"^^xsd:dateTime`), the function would previously extract and return the offset as-is without validation. It now raises an error for offsets outside the valid XSD range of `±14:00`.

* **Fixed session-timezone-dependent `xsd:dateTime` comparisons**: All `rdfnode` comparison operators (`=`, `<>`, `<`, `<=`, `>`, `>=`) and the aggregate comparator were calling PostgreSQL's `timestamptz_in()` for every `xsd:dateTime` literal, including timezone-naive ones. This caused two bugs: (1) comparing a timezone-naive literal with a timezone-aware one could return `true` instead of the correct SPARQL result of incomparable (`false`), depending on the session timezone; (2) the old timezone-detection heuristic used `strpbrk(lex, "+-")`, which matched the `-` separators in the date portion (e.g., `2025-04-25`) and incorrectly classified every well-formed dateTime as timezone-aware. The fix introduces a `datetime_has_tz()` helper that restricts the search for `Z`, `+`, and `-` to the time portion of the lexical form (after the `T` or space separator). Timezone-aware pairs are compared via `timestamptz_in()` / `timestamptz_cmp_internal()`; timezone-naive pairs via `timestamp_in()` without any session-timezone influence; and mixed pairs return `false` (incomparable) per XSD §3.2.7.4 and SPARQL 1.1 §17.3 (Operator Mapping).

* **Fixed incomplete `xsd:time` support in `rdfnode` comparison operators**: `rdfnode_eq` (`=`, `<>`) was missing `xsd:time` value-space comparison entirely, falling back to lexical comparison. The ordering operators (`<`, `<=`, `>`, `>=`) had `xsd:time` support but lacked timezone handling, unconditionally using `time_in()` for all literals. The fix adds `xsd:time` equality to `rdfnode_eq` and introduces a `time_has_tz()` helper that detects timezone designators (`Z`, `+`, `-`) in the time lexical form; timezone-aware pairs are now compared via `timetz_in()` / `timetz_eq()` (with UTC normalisation); timezone-naive pairs via `time_in()` without session-timezone influence; and mixed pairs return `false` (incomparable).

* **Fixed NaN‑NaN comparison bug**: Previously the expression `?a = ?b` returned true when both operands were the literal `"NaN"^^xsd:double` (or `"NaN"^^xsd:float`). According to SPARQL 1.1 (which follows the XSD 1.1 definition of xsd:double and the IEEE‑754 rules), a `NaN` value is never equal to any value, including another `NaN`; all numeric comparison operators must therefore evaluate to `false` for `NaN` operands. See [XPath and XQuery Functions and Operators 3.1](https://www.w3.org/TR/xpath-functions/) at [4.3.1 op:numeric-equal](https://www.w3.org/TR/xpath-functions/#func-numeric-equal), [4.3.2 op:numeric-less-than](https://www.w3.org/TR/xpath-functions/#func-numeric-less-than), and [4.3.3 op:numeric-greater-than](https://www.w3.org/TR/xpath-functions/#func-numeric-greater-than).

* **Add missing boolean-boolean comparison**: This adds `xsd:boolean` support to `rdfnode` comparison operators (`=`, `<>`, `<`, `<=`, `>`, `>=`), using PostgreSQL's `boolin` / `booleq` / `boollt` / `boolle` / `boolgt` / `boolge` functions.

* **Fixed invalid XSD lexical forms for infinity in `rdfnode` cast functions**: `float4_to_rdfnode`, `float8_to_rdfnode`, and `numeric_to_rdfnode` were producing `"Infinity"` and `"-Infinity"` as lexical forms, which are not valid XSD representations. XSD 1.1 Part 2 §3.3.4/§3.3.5 defines `INF` and `-INF` as the only valid lexical forms for positive and negative infinity in `xsd:float` and `xsd:double`. 

* **Reject blank nodes in `IRI`, `STRDT`, and `STRLANG`**: These functions require a simple literal as their first argument. Previously, passing a blank node (e.g. `_:b1` or the result of `sparql.bnode()`) silently produced an invalid RDF term such as `_:b1@en` or a blank node with an attached datatype. Now these functions raise an error with a descriptive message when given a blank node.

* Fixed `cstring_to_rdfliteral()` incorrectly treating literal content that resembles a blank node label (`_:...`) or IRI (`<...>`) as an actual blank node/IRI term, causing `rdfnode_in()` to strip quotes from literals such as `"_:b1"` and `"<http://example.org>"`, making `sparql.isblank()` and  `sparql.isiri()` return incorrect results for these literals.

* **Fixed SPARQL pushdown for IRI-valued constants**: rdfnodes containing IRIs, when placed in the **left side** in an operation, were being incorrectly rendered as quoted literals, e.g. `WHERE '<http://example.org/property>'::rdfnode = sparql.iri(p)` was being pushed down as `Remote Filter: (("http://example.org/property" = IRI(?p)))` instead of `Remote Filter: ((<http://example.org/property> = IRI(?p)))`. The `T_OpExpr` path in `DeparseExpr` now skips the rdfnode normalisation when dealing with IRIs and blank nodes.

* **Fixes isBlank result for NULL inputs**: the SQL declaration of isBlank was defined as `STRICT` which led function calls with `NULL` inputs to directly return `NULL`, but isBlank should return `false` instead, as its companions `isIRI`, `isLiteral`, and `isNumeric` already do.

* **Fixed `CONTAINS()` result for incompatible arguments**: `CONTAINS()` now correctly returns `NULL` instead of `false` when argument types are incompatible, e.g. a plain literal paired with a language-tagged literal such as `@en`). It now also now correctly returns `NULL` instead of true when either argument carries a non-string datatype (i.e. anything other than `xsd:string` or `rdf:langString`). The function was previously operating on the raw lexical form regardless of the datatype, which produced incorrect results for custom-typed literals such as `"123"^^<http://example.com/int>`.

* **Fixed incorrect XSD data type for numeric arguments in `ROUND()`**: The function `ROUND()` was incorrectly returning `xsd:double` for PG `numeric` arguments, and it now returns `xsd:decimal` as also defined in other numeric functions, such as `CEIL()`, `FLOOR()`, or `ABS()`.

* **Fixed TIMEZONE() consistently for invalid XSD types**: `TIMEZONE()` now consistently raises an error when the argument carries a non-xsd:dateTime datatype (e.g. `xsd:string`) instead of returning `NULL`. A wrong datatype is a type error, not an unknown value, and should be surfaced explicitly.

* **Fixed `DATATYPE()` handling of malformed literals**: `DATATYPE()` now correctly raises an error for syntactically malformed literals passed as `text` (e.g. `"foo"^<xsd:string>` with a single caret, or `"foo"^^xsd:string>` with an unbalanced angle bracket) by delegating validation to the rdfnode type cast before processing.

* **Fixed `rdfnode` input parser**: `rdfnode_in` now correctly rejects typed literals with an unterminated IRI in the datatype annotation (e.g. `"foo"^^<xsd:string` missing the closing `>`). Previously the parser silently dropped the malformed datatype annotation and returned a plain literal (`"foo"`), which was incorrect and could mask data quality issues. Inputs to `rdfnode_in` that are not a (syntactically) valid RDF literal, IRI, or blank node now raise `ERRCODE_INVALID_TEXT_REPRESENTATION` instead of being silently coerced. IRIs and blank nodes are returned as-is without unnecessary literal parsing.

* **Accept ill-typed literals**: Ill-typed literals are no longer rejected by `rdfnode_in` -- a literal is ill-typed if its lexical form falls outside the lexical space of its datatype (e.g., `"foo"^^xsd:int`). While semantically inconsistent under RDF 1.1, these literals are syntactically valid RDF. Validation is now deferred to the underlying triplestore rather than being enforced at the database level.
 
* **Fixed `REPLACE()` to use regex semantics**: `REPLACE()` now uses `regexp_replace` for the
3-argument form, consistent with the 4-argument form and the SPARQL 1.1 spec, which defines REPLACE() in terms of XPath regex in all forms. It now accepts empty string patterns, which are valid per XPath regex semantics and match at every position in the input string.

* **Fixed `timetz` to `rdfnode` cast**: the function `timetz_to_rdfnode` relied entirely on PostgreSQL's `timetz_out` to convert the strings, which led to a minute truncation when the timestamp's minutes was `:00`. It now produces well-formed `xsd:time` timezone offsets (`+02:00` instead of `+02`).

* **Fixed small memory leaks in `ExecuteSPARQL`**: the buffer returned by `curl_easy_escape` was not being released with `curl_free`, and curl handles (`curl_easy_cleanup`, `curl_slist_free_all`, `curl_global_cleanup`) were not called on HTTP and network error paths.

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

* **Fixed `rdfReScanForeignScan` to reset the row index**, making it correct for any future plan shape where PostgreSQL omits the Materialize node above a foreign scan.

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