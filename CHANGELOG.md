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

  **Upgrading from an earlier version requires manual steps.** Replacing an operator class does not rewrite what was built with it, so `ALTER EXTENSION rdf_fdw UPDATE TO '2.8'` refuses to run while any index on an `rdfnode` exists, or any view, materialized view or SQL-body function that sorts, groups or de-duplicates on one. Save their definitions, drop them, upgrade, and recreate them. `REINDEX` is not enough — an index belongs to the operator class it was created with. A stored query that only compares `rdfnode`s does not have to be touched. Nothing is dropped automatically.

## Minor Changes

* **libcurl's trace moved from `DEBUG3` to `DEBUG5`**: The extension logged libcurl's verbose output, and the size of each chunk of a response body as it arrived, at the same level as its own tracing. None of it repeats between runs: it carries the response `Date`, whatever session cookie the server issues, the address the host resolved to, the server's own request counter, and chunk sizes decided by how the body happens to arrive rather than by what it contains. That made `client_min_messages = DEBUG3` unusable for anything comparing two runs — `make installcheck INCLUDE_DEBUG_TESTS=1` failed on a clean tree with 948 lines differing, and two runs of the unmodified tree disagreed with each other. `DEBUG3` now carries what the extension does and `DEBUG5` how the bytes travel, and the debug test passes and repeats.

* **The extension is no longer declared relocatable**: `rdf_fdw.control` set `relocatable = true`, but the extension creates a `sparql` schema and installs part of itself there, so its objects live in two schemas and `ALTER EXTENSION rdf_fdw SET SCHEMA ...` was refused by PostgreSQL regardless. The control file now says `relocatable = false`, which is what the extension actually is.

* **Regression tests that need a triplestore are now opt-in**: `make installcheck` used to run the full suite by default, including the tests that query locally deployed triplestores and public SPARQL endpoints, and four `SKIP_*` variables had to be set to get a run that needs nothing but PostgreSQL. That default made the extension awkward to test for anyone building it in a sandbox, such as a distribution packager. The polarity is now inverted: `make installcheck` runs only the tests that need no external service, and the groups that do are enabled with `INCLUDE_LOCAL_TESTS=1` (the triplestores deployed by `scripts/postgres-env`), `INCLUDE_EXTERNAL_TESTS=1` (public SPARQL endpoints), `INCLUDE_STRESS_TESTS=1`, `INCLUDE_DEBUG_TESTS=1`, or `INCLUDE_ALL_TESTS=1` for all of them.

## Bug Fixes

### Crashes, memory safety and leaks

* **A `bigint` cast to `rdfnode` lost its datatype on 32-bit builds**: `int8_to_rdfnode()` formatted the value with `%ld`. Where `long` is 32 bits and `int64` is 64 — which is every `i386` and `armhf` build, both of which PGDG produces — that conversion reads half the argument, and every conversion after it takes the wrong one: `42::bigint::rdfnode` came back as `"42"^^(null)` instead of `"42"^^xsd:long`. It uses `INT64_FORMAT` now. The same build also described a bounded option as an unbounded one, because the check distinguishing them compared the option's ceiling against `LONG_MAX`, and where `long` is 32 bits `PG_INT32_MAX` *is* `LONG_MAX`; which of the two an option is, is now recorded rather than inferred.

  These were found by building and running the suite on a 32-bit userspace for the first time. Thirteen of the twenty-two default tests failed there while all twenty-two passed on the same image, the same PostgreSQL and the same source at 64 bits; with these two fixed, one remains, and it is a test asserting a `connect_timeout` of three billion, which a 32-bit `long` cannot hold.

* **Fixed a crash when querying a foreign table with a dropped column**: An accidental null dereference could crash the backend; this is now safely handled. (Tomas Vondra <tomas@vondra.me>)

* **Fixed resource leaks when a query does not finish normally**: libcurl resources are now properly released on cancellation or errors, not just on normal completion. (Tomas Vondra <tomas@vondra.me>)

* **Fixed a buffer overrun in HTTP header collection**: Headers are now collected with the correct length bounds, safely handling all content types. (Tomas Vondra <tomas@vondra.me>)

* **Out-of-bounds read while deparsing a boolean test**: The column lookup for `IS TRUE`/`IS FALSE` scanned the mapped columns backwards and then dereferenced the result without checking that a column had actually matched, so a boolean `Var` with no corresponding mapping read past the start of the array. The lookup now reports the condition as not pushable instead.

* **Handle libcurl initialization failures, and stop writing to `stderr`**: A failure of `curl_easy_init()` or `curl_easy_escape()` went unnoticed: the request was quietly skipped and reported as an empty result set rather than as an error. Both are now checked and raise a proper error. On network failures the extension also wrote a partial `libcurl: (<code>)` line straight to the backend's `stderr`, bypassing the server log's formatting; that leftover has been removed, and the error code it printed was already part of the error message raised right after it.

* **Fixed a libcurl handle leak when `max_response_size` is exceeded**: The callback that collects the HTTP response body raised the "response exceeds max_response_size" error with `ereport(ERROR)` from inside libcurl. That longjmps out of the middle of `curl_easy_perform()`, so neither `curl_easy_cleanup()` nor `curl_slist_free_all()` ever ran — and since libcurl allocates the easy handle, its header list and its connection outside PostgreSQL's memory contexts, aborting the transaction did not reclaim them either. Every query that hit the limit therefore leaked a handle and a connection for the remaining life of the backend, on top of abandoning libcurl mid-transfer. The callback now flags the condition and aborts the transfer by returning a short write, which makes `curl_easy_perform()` fail cleanly; the very same error is raised afterwards, once the handle and the header list have been released. Requests aborted this way are also no longer retried, as every attempt would hit the same limit.

* **Fixed literal parsing with trailing backslashes**: Literals ending in backslashes were misparsed; escape sequences are now handled correctly and literals round-trip through `text` unchanged. (Tomas Vondra <tomas@vondra.me>)

* **Fixed language tag extraction**: The `lang()` function now safely bounds its buffer reads and correctly handles all literal formats. (Tomas Vondra <tomas@vondra.me>)

* **Fixed memory ownership in literal conversion**: `cstring_to_rdfliteral()` now properly manages memory across all code paths. (Tomas Vondra <tomas@vondra.me>)

* **Foreign table columns without a `variable` option are now rejected**: Columns with no options were never validated, causing `pstrdup(NULL)` segfaults when planning queries. The requirement is now enforced at table load time, with a clear error message. (Tomas Vondra <tomas@vondra.me>)

* **Fixed buffer handling in `rdf_fdw_clone_table()`**: The binding loop now correctly processes one value per column, with proper bounds checking. (Tomas Vondra <tomas@vondra.me>)

### Privileges and network safety

* **Fixed privilege checking in clones**: Privileges are now re-checked for each page, ensuring a `REVOKE` issued by another session is respected. (Tomas Vondra <tomas@vondra.me>)

* **Enabled access to SPARQL functions for all users**: The `sparql` schema is now properly granted to `PUBLIC`, making all 125 functions accessible. (Tomas Vondra <tomas@vondra.me>)

* **Restricted redirects to HTTP and HTTPS**: `rdf_fdw` limits requests to the `http` and `https` protocols, but that restriction only covers the initial request — libcurl governs the protocols a redirect may lead to with a separate option, whose default also permits `ftp` and `ftps`. An endpoint could therefore answer with a redirect to an `ftp://` URL and have the backend follow it. Redirect targets are now restricted to `http` and `https` as well.

* **Added privilege checks to `rdf_fdw_clone_table()` and `sparql.describe()`**: Both functions now properly validate `ACL_SELECT` and `ACL_USAGE` on their targets. (Tomas Vondra <tomas@vondra.me>)

* **Improved IRI and blank node validation**: Term syntax is now validated against the SPARQL grammar, preventing malformed terms from altering filter meaning or INSERT/DELETE statements. (Tomas Vondra <tomas@vondra.me>)

### RDF values, literals and functions

* **`sparql.min()` and `sparql.max()` raised on a negative `xsd:duration`**: a group holding a term such as `"-P1D"^^xsd:duration` failed with `invalid input syntax for type interval`, although `<`, `<=`, `>`, `>=` and `=` all compare the same pair. XSD 1.1 Part 2 §3.3.6 admits the leading `-`, and PostgreSQL's `interval_in()` does not; the comparison operators strip it and negate afterwards, and the aggregate comparator now does the same.

* **An `xsd:anyURI` literal was treated as a plain literal**: `"http://a"^^xsd:anyURI` compared equal to `"http://a"` and to `"http://a"^^xsd:string`, and two `xsd:anyURI` terms could be ordered against each other. SPARQL has no rule making `xsd:anyURI` an `xsd:string`: RDF 1.1 Concepts §3.3 makes two literals the same term only when lexical form, datatype IRI and language tag all agree, and SPARQL 1.1 §17.3 does not list `xsd:anyURI` among the datatypes `=` and the ordering operators are defined over. The datatype now behaves like any other unrecognised one — equal to a term written exactly as it is, unequal to one with a different datatype, and not ordered against anything. Fuseki and GraphDB report the same pairs as type errors.

  The mismatch was visible in a single query: a condition comparing an `xsd:anyURI` column to a plain literal answered differently depending on whether it was pushed down to the endpoint or evaluated in PostgreSQL.

* **`sparql.replace()` did not understand capture-group references**: SPARQL 1.1 §17.4.3.15 defines REPLACE as XPath's `fn:replace`, whose replacement string writes a captured group as `$1` to `$9`, a literal dollar as `\$` and a literal backslash as `\\`. The replacement was handed to PostgreSQL's `regexp_replace`, which spells a group `\1` instead, so `REPLACE("abab", "a(b)", "[$1]")` answered `"[$1][$1]"` where every endpoint answers `"[b][b]"`, and a `\1` in the replacement inserted a group rather than the digit. The replacement is now rewritten between the two syntaxes.

* **`sparql.tz()` raised for a literal with no timezone**: SPARQL 1.1 §17.4.5.8 says TZ "[r]eturns the empty string if there is no timezone", and gives `tz("2011-01-10T14:45:13.815"^^xsd:dateTime)` the value `""`. It raised `TZ(): datetime has no timezone` instead, which is what `sparql.timezone()` is meant to do and still does. Fuseki, GraphDB and QLever all return the empty string.

* **`sparql.sum()` and `sparql.avg()` over `xsd:double` or `xsd:float` did not compute in that datatype**: both accumulate in PostgreSQL's `numeric`, which is neither bounded by IEEE 754 nor spelled the way XSD spells its special values. A sum that ran past the largest finite double came back as a 309-digit integer, which no `xsd:double` holds, and one whose value was an infinity came back as `"Infinity"`, a lexical form XSD 1.1 Part 2 §3.3.5 does not admit. The result of a promoted sum or average is now written as the IEEE value it stands for, with the infinities spelled `INF` and `-INF`, matching what Fuseki and GraphDB answer.

* **Dividing two floating-point terms by zero raised an error**: `/` reported `division by zero` for every datatype. XPath 4.3.6 `op:numeric-divide`, which SPARQL 1.1 §17.3 maps `/` onto, raises only when both operands are `xs:decimal` or `xs:integer`; for `xsd:float` and `xsd:double` it asks for IEEE 754 division, so `"1"^^xsd:double / "0"^^xsd:double` is `"INF"^^xsd:double` and `"0"^^xsd:double / "0"^^xsd:double` is `"NaN"^^xsd:double`. The exact datatypes still raise.

* **A literal was treated as a number without its lexical form being checked against its datatype**: `isNumeric()` used `strtod()` which accepts spellings outside XSD (hexadecimal, `nan`, `inf`). Integer subtypes were never range-checked. Lexical forms are now validated against the datatype's lexical space and value range; `"0x10"^^xsd:integer` and `"99999"^^xsd:short` are now correctly non-numeric. (Tomas Vondra <tomas@vondra.me>)

* **Fixed blank node handling in `sparql.describe()`**: Unnamed blank nodes are now correctly reported with generated labels and their statements. (Tomas Vondra <tomas@vondra.me>)

* **A language tag was half normalised**: Only the part before the first hyphen was lowercased, so `@EN-GB`, `@en-gb` and `@ZH-Hant-TW` stored as three different terms. The whole tag is now lowercased per RDF 1.1 Concepts §3.3. Existing data is unaffected until rewritten.

* **Fixed string functions to enforce correct types**: `STRLEN()`, `LANG()` and `REPLACE()` now correctly require literal arguments and properly count code points. (Tomas Vondra <tomas@vondra.me>)

* **Fixed rdfnode comparison consistency in GROUP BY and DISTINCT**: The operator class now correctly and consistently compares terms as stored, fixing results that varied based on data or query plan. (Tomas Vondra <tomas@vondra.me>)

* **`sparql.sum()` and `sparql.avg()` returned unbound for an empty group**: SPARQL specifies both return `"0"^^xsd:integer` for an empty multiset, but they returned NULL. They now match `group_concat()`, which already returned the empty string, and the SPARQL specification.

* **Fixed NaN equality handling**: `"NaN"^^xsd:double` now correctly reports as not equal to itself, per the SPARQL specification. (Tomas Vondra <tomas@vondra.me>)

* **Fixed value accessor width on 32-bit systems**: Integer comparisons and temporal `Datum` handling now use the correct widths, fixing incorrect results on 32-bit platforms. (Tomas Vondra <tomas@vondra.me>)

* **Fixed type checking in string comparison functions**: `sparql.contains()`, `sparql.strstarts()`, `sparql.strends()`, `sparql.strbefore()` and `sparql.strafter()` now correctly reject IRIs and blank nodes instead of operating on their string representation. (Tomas Vondra <tomas@vondra.me>)

* **Two literals carrying one language tag written differently were treated as incompatible**: RDF compares a language tag without regard to case, so `@en-GB` and `@en-gb` are one tag. The rule that decides whether `sparql.contains()`, `sparql.strstarts()`, `sparql.strends()`, `sparql.strbefore()` and `sparql.strafter()` may be applied to a pair of literals compared the two tags character by character, and answered that a pair differing only in the case of a subtag had nothing in common — so those functions returned NULL rather than a result. The tags are compared without regard to case now.

  This was reachable because a term keeps its tag broadly as written: only the part before the first hyphen is lowercased when a term is read, so `@en-GB` is stored as `en-GB` and `@en-gb` as `en-gb`. Literals from different sources routinely differ this way. (Tomas Vondra <tomas@vondra.me>)

* **Comparing two numeric literals depended on which side each was written**: Each comparison chose how to compare by inspecting datatypes, and the ordering operators inspected only their left operand: with `xsd:double` on the left the pair was compared as floating point, and otherwise as exact decimals — so `a > b` and `b < a` could be decided by different arithmetic. Equality inspected both sides but promoted a pair of `xsd:float` literals to double precision, while the comparator behind `sparql.min()` and `sparql.max()` kept them at single precision. `"16777217"^^xsd:float` was therefore equal to `"16777216"^^xsd:float` for `sparql.min()` and not for `=`.

  Both operands are promoted to the wider of the two datatypes now, as XPath prescribes, and every comparison and the aggregate comparator share one implementation. A value with no representation in the promoted type compares as the value it becomes: against an `xsd:float`, `16777217` is `16777216`, so the two are one number for `=`, for `<`, and for `sparql.min()` alike. Of the four triplestores the local suite deploys, Fuseki, Virtuoso and GraphDB answer this way. (Tomas Vondra <tomas@vondra.me>)

* **IRIs and blank nodes were treated as plain literals**: IRI `<http://example.org/v>` was equal to literal `"<http://example.org/v>"`, and both were ranked with literals in `sparql.min()`/`sparql.max()` instead of below them. Term classification now distinguishes IRIs, blank nodes and literals first, then applies literal properties. (Tomas Vondra <tomas@vondra.me>)

* **`sparql.describe()` reported blank-node subjects as IRIs**: `rdf:nodeID` subjects were read as IRIs, so `_:b1` became `<b1>`, and one blank node appeared under both spellings in a single triple. `rdf:nodeID` subjects are now returned as blank nodes.

* **Fixed XML element content parsing**: Terms with CDATA or comments are now read completely instead of partially. (Tomas Vondra <tomas@vondra.me>)

* **Fixed type conversion for result values**: Result values are now converted with proper type modifiers and I/O parameters, fixing array columns and precision handling in temporal types. (Tomas Vondra <tomas@vondra.me>)

* **Comparing a term with a PostgreSQL date or time failed instead of reporting no match**: Temporal comparisons raised errors for incompatible datatypes instead of reporting no match. All five temporal families now share one conversion; a term that cannot be represented returns no match rather than an error. (Tomas Vondra <tomas@vondra.me>)

* **Fixed annotation preservation in `REPLACE()`**: Language tags and datatypes are now correctly carried from the input literal to the result. (Tomas Vondra <tomas@vondra.me>)

* **An empty `GROUP_CONCAT()` did not return an RDF literal**: Empty result was raw text instead of `""`, so `sparql.isliteral()` returned false. Both the wrapper and the aggregate's final function now return the serialised form. (Tomas Vondra <tomas@vondra.me>)

* **Unicode escapes were decoded at the wrong width**: `\u` takes exactly four hex digits and `\U` exactly eight, but a hex digit *following* an escape was treated as though it belonged to it, and the whole sequence was then left undecoded — `"\u004142"` stayed as written instead of becoming `"A42"`, and a surrogate pair followed by a hex digit lost its first half to a replacement character. An escaped backslash was also read as the start of an escape: `"\\u0041"` is a backslash followed by the characters `u0041`, but it decoded to `\A`, which is a different value. Each escape now consumes exactly its own width, and an escaped backslash is passed through.

* **`SUBSTR()` rejected valid starting positions**: Positions outside the string were rejected, but SPARQL's `fn:substring` treats them as ordinary and returns only the overlapping part. Starts below 1 and negative lengths are now handled correctly. (Tomas Vondra <tomas@vondra.me>)

* **Fixed `float4` precision in RDF output**: Values now round-trip correctly, using the type's own output function and respecting `extra_float_digits`. (Tomas Vondra <tomas@vondra.me>)

* **Fixed precision handling in `ABS()`**: Numeric datatypes other than floating-point now preserve their exact values and lexical form. (Tomas Vondra <tomas@vondra.me>)

* **Fixed rounding in `ROUND()`**: Now correctly implements SPARQL's rounding rule (round to nearest, ties toward positive infinity) for all numeric types. (Tomas Vondra <tomas@vondra.me>)

* **Fixed identifier generation in `BNODE()`, `UUID()` and `STRUUID()`**: These functions now generate unique values per row and use proper counter/timestamp combination to avoid duplicates. (Tomas Vondra <tomas@vondra.me>)

* **Fixed type caching in `rdf_fdw_clone_table()`**: The type OID cache is now properly initialized on entry, ensuring `rdfnode` columns are correctly recognized. (Tomas Vondra <tomas@vondra.me>)

* **Fixed Unicode escapes being truncated on non-UTF8 servers**: Escape length was measured with `pg_utf_mblen()` after converting to server encoding, giving wrong results whenever the two differ. Buffers were also undersized. Length is now measured with `strlen()` on the result, and buffers are sized per PostgreSQL's contract. The compatibility shim for pre-13 servers also had the same issues and is now fixed.

### Pushdown

* **`!=` against a literal SPARQL cannot compare was sent to the endpoint**: a literal carrying a datatype outside the operator table of SPARQL 1.1 §17.3 — `xsd:anyURI`, or one of the application's own — falls to RDFterm-equal in §17.4.1.7, which raises a type error for two literals that are not the same term. A `FILTER` drops the row an error comes from, so `?o != C` keeps nothing at the endpoint, while the operator in PostgreSQL answers true for every term that is not `C`. A scan carrying such a condition returned fewer rows than the query asked for. It is now evaluated locally. `=` is unaffected and still pushes down, since there the endpoint's TRUE and type error select the same rows as the operator's true and false; so are language-tagged literals, IRIs, and every datatype the table does cover.

* **A dropped column cost a foreign table its pushdown**: Dropped columns still looked mapped on PostgreSQL 17 and earlier, blocking rewrite logic since the query doesn't select a dropped variable. Dropped columns are now skipped when the mapping is read, so tables plan consistently across versions. (Tomas Vondra <tomas@vondra.me>)

* **Improved function pushdown selectivity**: Only functions from `pg_catalog` and `rdf_fdw` are sent to the endpoint, and semantic mismatches between PostgreSQL and SPARQL functions (like `replace`, `upper`/`lower`, `concat`, `extract`, `round`) are now avoided by keeping them local. (Tomas Vondra <tomas@vondra.me>)

* **A keyword inside a single-quoted string cost a query its pushdown**: Keywords were detected by counting double quotes, so a `SELECT` in a single-quoted string was mistaken for a keyword. Query is now parsed properly, skipping over all four SPARQL string forms, IRIs and comments. Keywords are matched as whole words and recognized even at the very end of a query. (Tomas Vondra <tomas@vondra.me>)

* **A supplied SPARQL query was rewritten into one that asked something else**: The rewrite logic only checked for a single `SELECT` and no subquery, so meaningful clauses like `SELECT DISTINCT` were discarded. A query is now rewritten only when safe: its `SELECT` clause names only variables including every mapped column, nothing follows the closing brace, and there is no `BASE`. Everything else is sent as-is and evaluated locally. (Tomas Vondra <tomas@vondra.me>)

* **A SQL `DISTINCT` was applied to the scan even where something between the two counted rows**: `DISTINCT` was sent to the endpoint even with aggregates or grouping between the scan and the `DISTINCT`, changing the result. `SELECT DISTINCT count(predicate)` answered `2` where the actual count is `5`. It's now sent only when nothing between depends on the row count. (Tomas Vondra <tomas@vondra.me>)

* **`LIKE` was translated into a regular expression that matched different strings**: The translation had multiple bugs: missing anchors when patterns start/end with wildcards; unescaped literals in patterns; unnecessary escape sequences invalid in XML Schema regex; missing handling of control characters and the `s` flag for newline matching. Patterns are now translated correctly. `ILIKE` is no longer pushed down because Unicode case-folding diverges from database collation. Non-constant patterns and non-column operands are also no longer sent. (Tomas Vondra <tomas@vondra.me>)

* **Improved temporal type comparison handling**: Comparisons with PostgreSQL temporal types are evaluated locally to ensure consistent results across all SPARQL endpoints, avoiding semantic mismatches. (Tomas Vondra <tomas@vondra.me>)

* **`LIMIT` was pushed down where it changed the result**: `LIMIT` was sent with `ORDER BY` even though SPARQL ordering is undefined for non-comparable terms, causing different endpoints to return different rows. Also sent with aggregates, window functions, joins and other contexts where it changes results. `LIMIT` on a single scan with no sort above is unchanged. `OFFSET` also now uses 64-bit accessors instead of 32-bit, fixing large offsets like 3000000000. (Tomas Vondra <tomas@vondra.me>)

* **Arithmetic in a pushed-down filter lost its grouping**: Expressions were written without parentheses, so `(n + 1) * 2` became `?n + 1 * 2` and changed meaning. Arithmetic operators are now parenthesized. Unary operators that produced empty strings are now left to the executor. (Tomas Vondra <tomas@vondra.me>)

* **Columns mapped to a `$`-prefixed SPARQL variable returned only NULLs**: SPARQL names a variable with either sigil, and `?x` and `$x` are the same variable, but `rdf_fdw` only ever built the name to match against a result binding with `?`. A column declared as `OPTIONS (variable '$name')` was accepted, and the query sent to the endpoint was valid and returned the right bindings — but none of them matched the mapping, so every row came back with that column NULL. The sigil is now normalised when the table's options are loaded, so both spellings behave alike. (Tomas Vondra <tomas@vondra.me>)

* **`EXPLAIN` reported clauses that were never sent**: When the query in a table's `sparql` option cannot be rewritten — because it already carries its own `LIMIT`, `ORDER BY`, `GROUP BY`, `UNION` or `MINUS` — `rdf_fdw` sends it exactly as supplied and evaluates every SQL clause locally. The plan nevertheless said `Pushdown: enabled` and showed the `Remote Select`, `Remote Sort Key` and `Remote Limit` it had built while planning, so a scan answered entirely by PostgreSQL could be reported as having its projection, sorting and row limit pushed down. That is the opposite of what those lines exist to say, and the `Remote Limit` in particular named a row count far smaller than the one the endpoint was actually asked for. `Pushdown` now reports what the scan does rather than what the option asks for, and reads `unsupported SPARQL` in this case, with the `Remote` lines omitted.

* **SPARQL keyword detection ignored where the keyword actually was**: The search returned the first matched spelling rather than the earliest, so mixed spacing lost clauses and keywords inside strings hid real keywords later. The search now considers all spellings and keeps scanning past string literals. (Tomas Vondra <tomas@vondra.me>)

* **A graph name on the line after `FROM` was lost**: Only literal space was skipped, not newlines, so multiline queries lost the graph IRI. All SPARQL whitespace forms are now accepted. (Tomas Vondra <tomas@vondra.me>)

* **Fixed whole-row reference handling in SELECT**: Whole-row references now correctly mark all columns as used, ensuring complete rows are fetched and fixing `DELETE`/`UPDATE` subqueries. (Tomas Vondra <tomas@vondra.me>)

* **`WHERE` conditions were dropped when pushdown was disabled**: With `enable_pushdown 'false'` on a `SERVER` or `FOREIGN TABLE`, the conditions of a parsable `SPARQL` query were still deparsed and recorded as pushed down, so PostgreSQL left them out of the foreign scan's local filter — but the query actually sent to the endpoint was the unmodified raw one, without the corresponding `FILTER`. The conditions were therefore evaluated nowhere and the scan returned rows that should have been filtered out. Conditions are now only treated as remote when pushdown is enabled, and are otherwise evaluated locally.

### HTTP requests and responses

* **A response that was not a SPARQL result was read as an empty one**: Any XML parsed as a result set, with misdirected endpoints silently returning no rows. Responses are now validated as proper SPARQL results documents. Non-element nodes are skipped, and the page counter is reset per document load. (Tomas Vondra <tomas@vondra.me>)

* **A write was acknowledged when the endpoint had not performed it**: A completed HTTP transfer was taken for a successful request, and the status it carried was only examined from 400 upwards. Redirects are refused by default, so an endpoint answering 3xx returns a status and no result while libcurl reports the transfer as fine. A read eventually noticed, complaining that it could not parse what came back; a write had nothing to read and so nothing to object to, and `INSERT` reported a row inserted against an endpoint that had never seen it. Only a 2xx status is treated as success now, and anything else is reported with the status that came back. (Tomas Vondra <tomas@vondra.me>)

* **A failing request was retried after the endpoint had answered**: Retrying is meant for a request that never reached the server, and the loop stopped for a successful transfer but not for an unsuccessful one that nonetheless carried an HTTP status. Such a request was repeated to no purpose, since the answer would not change. The loop now stops as soon as a status comes back, and checks for a cancellation between attempts, which a long series of retries previously ignored.

* **A long prefix context name made every query against the server fail**: Long names were truncated mid-statement, producing malformed SQL. The name is now passed as a query parameter and carried whole. (Tomas Vondra <tomas@vondra.me>)

* **Fixed response handling on connection retry**: Response buffers are now properly cleared before each retry, preventing concatenation of partial and complete responses. (Tomas Vondra <tomas@vondra.me>)

* **Fixed the `custom` server option having no effect**: Custom parameters weren't appended; the SPARQL query was appended twice instead, doubling request size. Custom parameters are now appended correctly.

* **Fixed `request_max_redirect '0'` being silently ignored**: The limit was only set for non-zero values, so `'0'` inherited libcurl's default of 30 redirects. The limit is now always set explicitly. The option is also validated at `CREATE SERVER` time, rejecting non-integers and negative values.

### Writes, cloning and configuration

* **A foreign table with no columns counted no rows**: Scans gave up before making the request, but the generated SPARQL is valid and the endpoint can answer `count(*)`. Scans now fetch results and apply counts correctly. (Tomas Vondra <tomas@vondra.me>)

* **A clone past two billion rows paged from a negative offset**: Offset and row count were held in `int`, so large offsets wrapped and produced negative counts. Both are now 64-bit with overflow checking. (Tomas Vondra <tomas@vondra.me>)

* **Fixed old value retrieval in UPDATE and DELETE**: Row identity columns are now resolved through the planner's interface, ensuring correct old values and proper `DELETE ... RETURNING` behavior. (Tomas Vondra <tomas@vondra.me>)

* **A variable in an update template was substituted as text rather than as a variable**: `?s` matched inside `?subject`, and variables inside literals and comments were also rewritten. Multiple variables could rewrite the same value. Variables are now matched as whole tokens, and text inside literals, IRIs and comments is skipped. (Tomas Vondra <tomas@vondra.me>)

* **Fixed column binding in cloned records**: Unbound columns are now properly represented as NULL instead of using table defaults, and memory is correctly freed for each record. (Tomas Vondra <tomas@vondra.me>)

* **Settings wider than 32 bits were cut down on the way from planning to execution**: Five libcurl settings were written as 32-bit values and truncated. Large `max_response_size` values silently became tiny limits. `enable_xml_huge` was not carried at all. All settings are now carried at full width and `enable_xml_huge` is passed through. (Tomas Vondra <tomas@vondra.me>)

* **A numeric option larger than its setting could hold was accepted and then wrapped**: Large values were accepted and silently truncated or wrapped to negative. Each option is now read through checked conversion and refuses out-of-range values with a clear error message. (Tomas Vondra <tomas@vondra.me>)

* **A `FOREIGN TABLE`'s `fetch_size` was accepted and then ignored**: Only the server's value was read. The table's value is now read and takes precedence over the server's. The procedure's `fetch_size` argument still overrides both. (Tomas Vondra <tomas@vondra.me>)

* **Enabled custom schema installation**: The extension can now be installed into schemas other than `public` with proper type resolution. (Tomas Vondra <tomas@vondra.me>)

* **The `sparql.*` functions depended on the caller's `search_path`**: Unqualified `rdfnode` type references were parsed at call time and failed if `search_path` didn't include the extension schema. The 50 resolution sites now name the installation schema, so functions work regardless of `search_path`. This also removes one reason that installation in a schema other than `public` didn't work (the C code issue remains). (Tomas Vondra <tomas@vondra.me>)

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