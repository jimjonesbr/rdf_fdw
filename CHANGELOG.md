# 2.8
Release date: **unreleased**

## Enhancements

* **`request_max_redirect` is now the single option controlling HTTP redirects**: Redirection used to be governed by two options that had to agree with each other — `request_redirect` switched it on, and `request_max_redirect` bounded it — which made it possible to write server definitions whose two halves contradicted each other, and one of those combinations was silently broken (see the bug fix below). `request_max_redirect` now carries both meanings on its own: `0` (the default) refuses any redirect, and any higher value enables redirection and caps it at that many hops. The `-1` (unlimited) value has been dropped, since an unbounded redirect chain has no practical use against a SPARQL endpoint and invites never-ending redirect loops.

  ```sql
  -- follow at most 5 redirects
  CREATE SERVER dbpedia
  FOREIGN DATA WRAPPER rdf_fdw
  OPTIONS (endpoint 'https://dbpedia.org/sparql', request_max_redirect '5');
  ```

  `request_redirect` is deprecated but still accepted, so existing servers and dumps continue to work: setting it raises a warning, and `request_redirect 'true'` without an explicit `request_max_redirect` follows up to 30 redirects, which is what libcurl would have done before. It will be removed in a future major release.

## Breaking Changes

* **`rdfnode`s are sorted and grouped by the stored term**: `ORDER BY`, `GROUP BY`, `SELECT DISTINCT`, `UNION` and unique constraints take their comparisons from the type's default B-tree operator class, not from the `=` and `<` operators directly. That class declared the RDF value operators but ordered terms by how they are written, and the two do not agree — which gave wrong answers, described in the bug fix below.

  The class now compares the stored term throughout. Two terms are the same to it when they are written the same way, so `"1"^^xsd:integer` and `"01"^^xsd:integer` are one value and two terms: they sort apart, and they are two groups rather than one. Group or order by a cast where the value's ordering is the one wanted — `GROUP BY term::numeric`.

  `ORDER BY` itself is unchanged, since sorting already used this comparison. What changes is `GROUP BY`, `DISTINCT`, `UNION` and unique constraints, which previously merged value-equal spellings — but only sometimes, and never dependably.

  The value operators `=`, `<>`, `<`, `<=`, `>=` and `>` are untouched and still mean what they meant, including in a `WHERE` clause. The class is built on five operators of its own, `~=`, `~<~`, `~<=~`, `~>=~` and `~>~`, named after PostgreSQL's `text_pattern_ops`. They are seldom written by hand; where they matter is an index, which can answer a condition written with one of them, while a value comparison is applied as a filter to the rows the scan returns.

  **Upgrading from an earlier version requires manual steps.** Replacing an operator class does not rewrite what was built with it, so `ALTER EXTENSION rdf_fdw UPDATE TO '2.8'` refuses to run while any index on an `rdfnode` exists, or any view, materialized view or SQL-body function that sorts, groups or de-duplicates on one. Save their definitions, drop them, upgrade, and recreate them. `REINDEX` is not enough — an index belongs to the operator class it was created with. A stored query that only compares `rdfnode`s does not have to be touched. Nothing is dropped automatically.

## Minor Changes

* **Reproducible builds**: The build timestamp reported by `rdf_fdw_version()` and the `rdf_fdw_settings` view was always taken from the wall clock, which meant that building the same source twice produced two different binaries — something distribution builds are expected to avoid. The `Makefile` now uses `SOURCE_DATE_EPOCH` for that timestamp whenever it is set, as it is by `dpkg-buildpackage` and `rpmbuild`, so a packaged binary reports the release date of the source it was built from. Builds that do not set the variable, which includes every ordinary `make`, keep reporting the time the build actually ran.

* **The extension is no longer declared relocatable**: `rdf_fdw.control` set `relocatable = true`, but the extension creates a `sparql` schema and installs part of itself there, so its objects live in two schemas and `ALTER EXTENSION rdf_fdw SET SCHEMA ...` was refused by PostgreSQL regardless. The control file now says `relocatable = false`, which is what the extension actually is.

* **Regression tests that need a triplestore are now opt-in**: `make installcheck` used to run the full suite by default, including the tests that query locally deployed triplestores and public SPARQL endpoints, and four `SKIP_*` variables had to be set to get a run that needs nothing but PostgreSQL. That default made the extension awkward to test for anyone building it in a sandbox, such as a distribution packager. The polarity is now inverted: `make installcheck` runs only the tests that need no external service, and the groups that do are enabled with `INCLUDE_LOCAL_TESTS=1` (the triplestores deployed by `scripts/postgres-env`), `INCLUDE_EXTERNAL_TESTS=1` (public SPARQL endpoints), `INCLUDE_STRESS_TESTS=1`, `INCLUDE_DEBUG_TESTS=1`, or `INCLUDE_ALL_TESTS=1` for all of them.

## Bug Fixes

* **`SELECT DISTINCT` over `rdfnode`s changed its answer when an unrelated row was inserted**: `rdfnode_ops` declared `=` as its equality and `<` as its ordering, and neither is what the class actually compared — its support function compares terms as they are written. Sorted grouping trusts that agreement, because it compares only the terms the sort placed next to each other, and there was none to trust. Two value-equal literals were one group; inserting a third, unrelated literal that sorts between them made them two:

  ```
  {"01"^^xsd:integer, "1"^^xsd:integer}                     DISTINCT -> 1 row
  {"01"^^xsd:integer, "1"^^xsd:integer, "02"^^xsd:integer}  DISTINCT -> 3 rows
  ```

  The same disagreement let an index exclude rows a sequential scan returned. An index scan descended to where the searched-for term sorts and stopped, while the rows it should have found sat wherever their own spelling sorts, so the same `WHERE` clause answered differently depending on the plan.

  RDF value comparison cannot be a B-tree's. A B-tree needs a total order and an equality that is reflexive, symmetric and transitive. Terms of unlike kinds are incomparable rather than ordered; `NaN` is not equal to itself, because no numeric comparison involving `NaN` holds; and equality is not transitive, since numeric literals are compared in the wider of their two datatypes and the wider type may carry fewer significant digits, which lets one `xsd:float` literal be equal to two `xsd:integer` literals that are not equal to each other.

  The operator class is now built on operators that compare the stored term, which is what its support function has always done. See the breaking change above for what this means for existing databases.

* **`sparql.sum()` and `sparql.avg()` returned unbound for an empty group**: SPARQL gives the empty multiset a value of its own rather than leaving it unbound — §18.5.1.3 defines `Sum({})` as `"0"^^xsd:integer` and §18.5.1.4 gives `Avg` the same where the count is zero — and both functions returned SQL NULL instead, which is the rule SQL's own `sum()` and `avg()` follow. `sparql.group_concat()` already returned the empty string for this case, so the two contracts sat side by side in the same schema. Both now return `"0"^^xsd:integer`.

  This also settles what a group of unbound values means. §18.5.1.2 counts only bound values, so an unbound one never enters the multiset — which is why a NULL among real values is passed over rather than making the whole sum unbound — and a group whose values are all unbound is therefore an empty multiset and sums to zero as well. Values that are present but not numeric are a different matter: there is something to sum and it cannot be summed, so that stays unbound. `MIN`, `MAX` and `SAMPLE` have no value defined for the empty multiset and are unchanged.

  Implementations disagree here, so this follows the specification rather than a majority: asked to sum an empty group, GraphDB answers `0` and Virtuoso answers unbound, while Fuseki answers `0` for a group with no solutions and unbound as soon as an unbound value is involved.

* **A query against a foreign table with a dropped column terminated the backend**: A dropped column keeps its place in the foreign table's tuple descriptor, and the scan and `rdf_fdw_clone_table()` are both indexed by that descriptor, so both walk over it. It is mapped to no SPARQL variable, though, and both handed the absent mapping to a string function that does not accept one — `strcmp()` when matching a response binding to a column, `pstrdup()` when building the projection — which is `strlen(NULL)`. Any query returning at least one row, and any clone, crashed the backend and took every other session into crash recovery with it. Dropping a column is enough to arm it, and `EXPLAIN` does not trigger it, so a table could look healthy until it was read. Both now step over an unmapped column, which reads back as NULL, and the clone picks the first mapped column to order by rather than whichever column happens to be first.

* **A dropped column cost a foreign table its pushdown**: A table's columns are read from the catalogue together with the options that map each one to a SPARQL variable, and a column removed with `ALTER FOREIGN TABLE ... DROP COLUMN` was read along with the rest. PostgreSQL clears a dropped column's foreign-data options from version 18 on and leaves them in place before that, so on 17 and earlier the removed column still looked mapped — to a variable the supplied query does not select, since it was dropped from the table. A query is only rewritten when its projection names every mapped column, so the table stopped being rewritable: `EXPLAIN` reported `Pushdown: unsupported SPARQL`, and every filter, ordering and limit was evaluated in PostgreSQL instead of at the endpoint. Dropped columns are now skipped where the mapping is read, so a table plans the same way on every version.

* **`NaN` was equal to itself**: Comparing a term against a byte-identical copy of itself returned true without examining it. That is the rule for ill-typed literals, which have no value and so are compared as terms — `"25:00:00"^^xsd:time` is equal to itself. `"NaN"^^xsd:double` is not ill-typed, though: it has a value, and `op:numeric-equal` is false whenever either side is `NaN`, itself included. The shortcut now stands aside for a numeric term whose lexical form is exactly `NaN`, which is the only spelling XSD admits; any other spelling is ill-typed and stays equal to itself.

* **Functions were shipped to the endpoint by name alone**: A SQL function was translated into the SPARQL builtin sharing its name, without checking that it was the function the name was meant to reach. A user's own `contains(rdfnode, rdfnode)` was therefore sent as SPARQL `CONTAINS` and never ran — the endpoint answered a different question, and because the condition counted as pushed down, nothing evaluated it locally either. A function or operator is now shipped only when it belongs to `pg_catalog` or to `rdf_fdw` itself.

  Belonging to `pg_catalog` is not on its own enough, and a few of its functions are no longer sent because they do not mean what their SPARQL namesakes mean. `replace()` matches a literal substring where SPARQL `REPLACE` matches a regular expression: `replace('a.b.c', '.', 'X')` is `aXbXc` here and `XXXXX` there. `upper()` and `lower()` follow the database's locale where `UCASE` and `LCASE` apply Unicode's default case mapping, so `upper('straße')` is `STRAßE` here and `STRASSE` there. `concat()` skips a NULL argument where `CONCAT` gives an error. `extract()` reads a zoned timestamp in the session's `TimeZone` where `HOURS()` reads the value's own offset — the same instant gives 8 in one and 23 in the other. And `round()` breaks a tie away from zero where SPARQL `ROUND` breaks it towards positive infinity.

  A comparison that reaches the column through a cast is not sent either, since the cast is part of what is being compared rather than a wrapper around it. `o::int = 42` asks whether the term reads as the integer 42 in PostgreSQL, which is not what `FILTER(?o = 42)` asks the endpoint.

* **A keyword inside a single-quoted string cost a query its pushdown**: Deciding whether a word in the supplied SPARQL is a keyword or part of a string was done by counting the double quotes before it. SPARQL writes strings four ways, so a `SELECT` inside `'...'`, and anything written inside an IRI or a comment, was read as a keyword — a table defined over a query whose filter compared against `' SELECT '` looked as though it contained a subquery, and nothing was pushed down to it at all. The query is now read from the left, stepping over strings in any of the four quotings, IRIs and comments, so a keyword among them is not mistaken for one.

  A keyword is also matched as a whole word now, with any run of whitespace matching a space inside it, so `ORDER BY` is recognised however it is spaced, and one at the very end of a query is recognised at all.

* **A supplied SPARQL query was rewritten into one that asked something else**: A foreign table's `sparql` option is rewritten — its `SELECT` clause replaced, filters and solution modifiers added — whenever the extension judges the query simple enough. That judgement only asked whether the query had a single `SELECT` and no subquery, so a clause carrying meaning of its own was replaced along with the rest. A table defined over `SELECT DISTINCT ?p WHERE {...}` was queried as `SELECT DISTINCT *`, which is a different question: over one graph it answered with five rows where the query as written answers with two. `REDUCED`, an expression alias such as `(?o AS ?p)`, a `BASE` prologue and a projection that does not bind a mapped column's variable were all lost the same way. A query is now rewritten only when its `SELECT` clause names variables and nothing else, those variables include every mapped column, nothing follows the closing brace, and there is no `BASE`; anything else is sent as written and evaluated locally.

* **A SQL `DISTINCT` was applied to the scan even where something between the two counted rows**: `DISTINCT` describes what a statement returns, which is not what the scan beneath it reads. It was sent to the endpoint whenever the statement carried one, including where an aggregate, a window function or a grouping sat in between — and removing duplicate rows before counting them changes the count. `SELECT DISTINCT count(predicate)` over a graph of five triples with two distinct predicates answered `2` where the count is `5`. It is now sent only when nothing between the scan and the `DISTINCT` depends on how many rows there are, which leaves the ordinary `SELECT DISTINCT col FROM t` pushed down as before.

* **A clone past two billion rows paged from a negative offset**: `rdf_fdw_clone_table()` walks a result in pages, advancing an offset by the page size each time. That offset and the running row count were held in an `int`, so a clone whose offset passed 2147483647 wrapped: starting at `begin_offset` 2000000000 with a page of 1000000000, the second request asked the endpoint for `OFFSET -1294967296`, and the pages after it wandered over the result at random, reading some rows twice and never reaching others. Both are 64-bit now, each addition is checked before it is made, and the full width is carried into the request and the progress report.

* **`UPDATE` and `DELETE` found a row's old values by guessing where the planner had put them**: Building the SPARQL that removes a triple needs the values the row held before the statement, which the planner supplies as extra columns carried alongside the row. Those columns were named after the table's own columns and then looked for by name among everything sitting past the table's last column — a guess about where the planner had placed them and about no other column sharing the name. Where the guess failed, `UPDATE` fell back to the row's *new* values, which would have built a statement deleting a triple that does not exist, leaving the old one in the store beside the new. The columns now carry a name of their own, are registered through the planner's interface for row identity, and are resolved to their real positions once when the statement begins; a column that cannot be resolved is an error rather than a fallback.

  `DELETE ... RETURNING` also returned the row in the plan's shape rather than the table's.

* **The HTTP handle and the parsed response were leaked when a query did not finish normally**: libcurl's handle, the list of request headers, and the parsed XML document are allocated outside PostgreSQL's memory contexts, so nothing reclaims them when a context is discarded. They were released at the points where a scan was expected to end, which covered the ordinary path and each error the extension raises itself, but not a cancelled query, an error raised beneath the scan, or any path that had not been given its own release. Each one is now tied to the context that owns the scan's state, so they are handed back however the query ends, and the release is safe to run more than once.

* **A variable in an update template was substituted as text rather than as a variable**: `INSERT`, `UPDATE` and `DELETE` fill a foreign table's `sparql_update_pattern` by replacing each mapped variable with a value, and both the test for whether a variable occurs and the replacement itself worked on characters. A variable therefore matched inside a longer one: given the template `?s <http://example.org/p> ?subject .`, substituting `?s` also rewrote the beginning of `?subject`, and the statement sent was

  ```
  INSERT DATA { <http://example.org/a> <http://example.org/p> <http://example.org/a>ubject };
  ```

  which the endpoint accepted, storing a term the query never described. A `?s` written inside a literal or a comment was rewritten too, and a value containing one was rewritten again by the next variable's turn. Variables are matched as whole tokens now, text inside literals, IRIs and comments is passed over, and a value once substituted is not searched again.

* **Cloning a record left out the columns it did not bind**: `rdf_fdw_clone_table()` built its `INSERT` from the bindings a record happened to carry, naming only those columns. A variable the query selects but a particular record does not bind is not an absent column, though — it is a column whose value is unknown, and leaving it out of the statement handed the row to whatever default the target column carries instead of to NULL. A record binding nothing at all produced `INSERT INTO t () VALUES ()`, which is not a statement, and the clone stopped with a syntax error. Every column the query selects now takes a parameter, NULL unless the record binds it; a column the foreign table maps to no variable is still left out, so its default applies as before.

  The prepared statement built for each record was never freed, and neither was the buffer each value was built in.

* **A response that was not a SPARQL result was read as an empty one**: The scan looked for an element named `results` anywhere under the root and took whatever `result` elements it found, without asking what document it had been given. Any XML at all therefore parsed as a result set, an unrelated one simply as an empty set, so a misdirected endpoint reported no rows rather than a problem. The response must now be a SPARQL results document in its own namespace and carry exactly one SELECT results element, and a record must bind each variable once and give each binding exactly one RDF term.

  Nodes that are not elements — the whitespace between them, a comment — were also read as though they were bindings. They are skipped now, in each of the three places that walk a record.

  The page counter was not reset when a document was loaded, only the record list was, so a scan that fetched more than one page reported a count that included every page before it.

* **A write was acknowledged when the endpoint had not performed it**: A completed HTTP transfer was taken for a successful request, and the status it carried was only examined from 400 upwards. Redirects are refused by default, so an endpoint answering 3xx returns a status and no result while libcurl reports the transfer as fine. A read eventually noticed, complaining that it could not parse what came back; a write had nothing to read and so nothing to object to, and `INSERT` reported a row inserted against an endpoint that had never seen it. Only a 2xx status is treated as success now, and anything else is reported with the status that came back.

* **Comparing a term with an `integer` or `smallint` read the value at the wrong width**: The operators taking `int2` and `int4` fetched their argument with the 64-bit accessor and returned through the 64-bit one, which does not describe what a 32-bit build does with those. There a `Datum` is four bytes and a 64-bit integer is passed by reference, so the accessor takes the argument — the number itself — and reads memory at that address: `WHERE o = 42` looks at address 42. The comparison between two timezone-aware `xsd:dateTime` terms kept its timestamps in `Datum` variables in the same way, where a 64-bit timestamp does not fit. Both now use accessors of the declared width.

  On a 64-bit build a `Datum` is eight bytes and holds any of these, so nothing observable changes there; this is a fix for 32-bit platforms, which is where the extension is packaged for `i386` and `armhf`.

* **IRIs and blank nodes were accepted where a literal was required**: `sparql.contains()`, `sparql.strstarts()`, `sparql.strends()`, `sparql.strbefore()` and `sparql.strafter()` take literals, and the rule that admits a pair of arguments was written in terms of language tags and datatypes. An IRI and a blank node have neither, so both were read as simple literals and the function went on to work with the term's written form, brackets and all: `sparql.strbefore('<http://example.org/abc>', '"/"')` returned the literal `"<http:"`, whose content is a fragment of the way the IRI is spelled rather than of the IRI. The two kinds are rejected now, and such a call returns NULL, which is what a SPARQL endpoint answers.

* **Two literals carrying one language tag written differently were treated as incompatible**: RDF compares a language tag without regard to case, so `@en-GB` and `@en-gb` are one tag. The rule that decides whether `sparql.contains()`, `sparql.strstarts()`, `sparql.strends()`, `sparql.strbefore()` and `sparql.strafter()` may be applied to a pair of literals compared the two tags character by character, and answered that a pair differing only in the case of a subtag had nothing in common — so those functions returned NULL rather than a result. The tags are compared without regard to case now.

  This was reachable because a term keeps its tag broadly as written: only the part before the first hyphen is lowercased when a term is read, so `@en-GB` is stored as `en-GB` and `@en-gb` as `en-gb`. Literals from different sources routinely differ this way.

* **Comparing two numeric literals depended on which side each was written**: Each comparison chose how to compare by inspecting datatypes, and the ordering operators inspected only their left operand: with `xsd:double` on the left the pair was compared as floating point, and otherwise as exact decimals — so `a > b` and `b < a` could be decided by different arithmetic. Equality inspected both sides but promoted a pair of `xsd:float` literals to double precision, while the comparator behind `sparql.min()` and `sparql.max()` kept them at single precision. `"16777217"^^xsd:float` was therefore equal to `"16777216"^^xsd:float` for `sparql.min()` and not for `=`.

  Both operands are promoted to the wider of the two datatypes now, as XPath prescribes, and every comparison and the aggregate comparator share one implementation. A value with no representation in the promoted type compares as the value it becomes: against an `xsd:float`, `16777217` is `16777216`, so the two are one number for `=`, for `<`, and for `sparql.min()` alike. Of the four triplestores the local suite deploys, Fuseki, Virtuoso and GraphDB answer this way.

* **IRIs and blank nodes were treated as plain literals**: A term was classified by inspecting its language tag and datatype, and an IRI and a blank node have neither, so both were filed as simple literals — in addition to being recognised as an IRI, in that case. Two consequences followed. Comparing an IRI with a literal fell through to comparing text, so `<http://example.org/v>` was equal to the plain literal `"<http://example.org/v>"`, which is a string that merely looks like it; the same held for a blank node and `"_:b1"`. And `sparql.min()`/`sparql.max()` ranked both among the literals, where SPARQL puts blank nodes below IRIs and IRIs below every literal.

  A term is now classified as an IRI, a blank node, or a literal, and only then by its literal properties. An IRI is equal only to the same IRI and a blank node only to the same blank node; `sparql.min()` over a blank node, an IRI and a literal returns the blank node, and `sparql.max()` the literal.

* **Settings wider than 32 bits were cut down on the way from planning to execution**: A scan's configuration is written into the plan and read back when the scan starts. The five settings libcurl takes as a `long` — `request_max_redirect`, `connect_timeout`, `request_timeout`, `connect_retry` and `max_response_size` — were written out as 32-bit values, so anything larger arrived as its low 32 bits. A `max_response_size` of `4294967396` became a limit of 100 bytes and refused responses it was never meant to bound. They are carried at full width now.

  `enable_xml_huge` was not carried at all, so it was always off by the time the response was parsed and the option had no effect on a foreign scan. With a libxml2 that enforces its ten-megabyte ceiling on a single text node, that ceiling applied regardless of the setting, and a longer value was returned silently shortened rather than refused.

* **A numeric option larger than its setting could hold was accepted and then wrapped**: The seven options that take a number were each checked for being non-negative and nothing else, so a value too large for the field behind them passed and was truncated on the way in. `fetch_size` and `batch_size` are held in an `int`: `fetch_size '3000000000'` became `-1294967296`, which the clone procedure then sent to the endpoint as `LIMIT -1294967296` — a negative count no endpoint will parse. A value beyond any integer was not detected either, since the conversion's overflow was never examined. Every one of them is read through one checked conversion now, which refuses a value the setting cannot hold: `2147483647` for the two kept in an `int`, and whatever a `long` holds for the rest.

  The hint that comes with the error names the ceiling only for the two that have a meaningful one, and otherwise says what the number means and what `0` selects, which is the part that cannot be guessed.

* **A failing request was retried after the endpoint had answered**: Retrying is meant for a request that never reached the server, and the loop stopped for a successful transfer but not for an unsuccessful one that nonetheless carried an HTTP status. Such a request was repeated to no purpose, since the answer would not change. The loop now stops as soon as a status comes back, and checks for a cancellation between attempts, which a long series of retries previously ignored.

* **`sparql.describe()` reported blank-node subjects as IRIs**: In the RDF/XML a `DESCRIBE` returns, the subject of an `rdf:Description` is an IRI when the element carries `rdf:about` and a blank node when it carries `rdf:nodeID`. Both were read as IRIs, so every statement made about a blank node came back as a statement about a resource named after that node's label — `_:b1` as `<b1>`, which is not an absolute IRI and identifies nothing in the store. Since the object side already told the two apart, one blank node could appear under both spellings inside a single triple. A subject taken from `rdf:nodeID` is returned as a blank node now.

* **A term was read from the first child of its XML element rather than the whole of it**: A `<literal>`, `<uri>` or `<bnode>` holds its text as character data, and an XML parser splits that data into several child nodes wherever something else sits between — a CDATA section or a comment. The value was taken from the first of those children, so a term written as `abc<![CDATA[def]]>ghi` arrived as `abc`. Nothing marked the value as incomplete: a language tag or datatype is an attribute of the element and survived intact, so the term was well formed and simply had the wrong text. The whole of the element's content is read now.

  Character data is not split by its length, nor by an entity such as `&amp;` or `&#10;`, so a response from a triplestore that writes each term as plain text was never affected.

* **A `FOREIGN TABLE`'s `fetch_size` was accepted and then ignored**: `fetch_size` is valid on a foreign table as well as on a server, and `rdf_fdw_clone_table()` is documented as taking the value from either. Only the server's was ever read, so a table that set its own was paged at the server's size, or at the default of 100 when the server set none — silently, since the option was accepted and validated as usual. The table's value is read now, and takes precedence over the server's, which is what the documentation already described. The procedure's own `fetch_size` argument still overrides both.

* **The HTTP header callback read and wrote past the buffer libcurl gave it**: libcurl hands a header callback a length and a pointer to that many bytes, and does not promise a terminator after them. The callback treated the pointer as a C string: it measured the header with `strlen()`, reading on past the end until it happened upon a zero byte, and then wrote a terminator of its own two bytes back from wherever that landed — into a buffer that belongs to libcurl and is not the callback's to modify. Headers are collected with the length libcurl supplies now, which is what the body callback already did, so one function serves both — headers and body stay apart because libcurl hands each callback its own buffer.

  A header whose content type was not one of four recognised spellings used to be left out of the collected headers. Nothing reads those headers apart from the debug log — the response's content type is not inspected anywhere — so they are simply all collected now, and a debug log at `DEBUG3` shows the whole response header rather than part of it.

* **A long prefix context name made every query against the server fail**: The lookup that reads a server's prefixes was assembled into a fixed 1024-byte buffer, and a `prefix_context` name too long to fit was cut off mid-statement rather than rejected. The result was not a shortened name but a malformed statement, so planning any scan on that server failed with `unterminated quoted string` and none of the context's prefixes could be reached. The name is passed as a query parameter now, so it is carried whole whatever its length.

  The name was escaped before being placed in the buffer, so a name could not alter the statement's meaning; the failure was the truncation alone.

* **Result values were converted without the type modifier or the I/O parameter their type needs**: A PostgreSQL input function takes three arguments — the text, an I/O parameter, and the type modifier — and `rdf_fdw` called them with one, from a call site with room for one. The other two were read from beyond the end of the argument array, so whatever happened to lie there became the type modifier and the I/O parameter.

  A type modifier was passed deliberately for six types (`real`, `double precision`, `numeric`, `timestamp`, `timestamptz` and `varchar`), and those behaved. Every other type modifier was read from that stale memory. A `char(5)` column came back blank-padded to whatever length was found there rather than to 5 — in one run, to 631056732 characters, having allocated the memory to hold it — and `time(n)`, `timetz(n)` and `interval(n)` columns kept the full precision of the value instead of the precision their column declared.

  The same read supplied the I/O parameter, which array and domain types need in order to know what they are converting. An array column therefore failed outright, with a `cache lookup failed for type` message naming whatever number had been read, and could not be used at all.

  All three conversion sites now call `getTypeInputInfo()` and `OidInputFunctionCall()`, which is the contract PostgreSQL defines for this, so every type receives its own modifier and I/O parameter. Arrays and domains work; `char(n)`, `time(n)`, `timetz(n)` and `interval(n)` convert to the precision the column declares, matching what PostgreSQL produces for the same value.  (Tomas Vondra <tomas@vondra.me>)

* **`LIKE` was translated into a regular expression that matched different strings**: A `LIKE` pattern and a regular expression do not mean the same thing, and the translation behind a pushed-down `LIKE` got several of the differences wrong.

  A `LIKE` pattern has to match the value end to end, so the regular expression needs anchoring at both ends — but the anchors were omitted whenever the pattern began or ended with a wildcard or a `^`. `LIKE '_foo'` became `.foo$`, which is unanchored at the front and matches `xafoo`; `LIKE 'foo_'` became `^foo.`, which matches `fooXbar`; and `LIKE '^foo'` became `\^foo$`, matching anything that ends in `^foo`. All three now anchor both ends.

  The backslash that escapes a wildcard in a `LIKE` pattern had no meaning in the translation, so an escaped wildcard was still translated as a wildcard: `LIKE 'a\%b'` — a request for the literal three characters `a%b` — became `^a\.*b$`, which asks for an `a`, any number of full stops, and a `b`. It matched neither `a%b` nor anything else the user could have meant, so the row they were looking for was simply not returned. An escape is now honoured, an escaped backslash stands for a literal one, and a pattern ending in a lone escape raises the same error PostgreSQL raises for it.

  Characters that mean nothing special in a regular expression were being escaped anyway — `-`, `/`, `:`, `=`, `#`, `@` — which produces escape sequences that XML Schema regular expressions, the flavour SPARQL uses, define as invalid. A newline, carriage return or tab in the pattern was copied into the SPARQL string literal as itself, where a raw control character cannot appear; they are written as escapes now. And the expression is sent with the `s` flag. Without it `.` does not match a newline, while `LIKE`'s `_` and `%` both do, so a value holding the three characters `a`, newline, `b` matched `LIKE 'a%b'` in PostgreSQL and not at the endpoint.

  `ILIKE` is no longer pushed down at all. SPARQL's `i` flag folds case by Unicode's rules, while `ILIKE` follows the database collation, and the two disagree: in a database collated `tr_TR`, `'Istanbul' ILIKE 'i%'` is false, where the endpoint's `REGEX(..., "i")` matches. This is the same divergence that keeps `upper()` and `lower()` from being sent.

  Separately, the test for whether the comparison was shaped like `column LIKE constant` required both halves to be wrong before it declined, so a pattern that was not a constant, or a left operand that was not a plain column, was still sent — built from a deparsed string rather than from the operand itself.

* **Comparing a term with a PostgreSQL date or time failed instead of reporting no match**: `o = '2015-01-01 00:00:00'::timestamp` raised `cannot cast RDF literal` as soon as it reached a term that was neither `xsd:dateTime` nor `xsd:date`, and the `time` and `timetz` operators raised `invalid input syntax` in the same situation. A predicate in a graph rarely carries one datatype throughout, so filtering on a timestamp over real data tended to fail outright rather than return the rows that did match. A term the temporal type cannot represent now simply does not match — `<>` answers true and every other operator false, so each pair stays the other's negation. This is what the `date` operators already did.

  The `timestamp` and `timestamptz` operators were also written in SQL, as wrappers around the cast to those types. PostgreSQL inlines such a wrapper into the query, which replaced the comparison with a cast expression and left the planner with no operator to reason about.

  All five families share one conversion now, which changes what the `date` operators accept: they used to hand any term's lexical form to `date_in` and compare whatever came back, so `"2020-05-12"^^xsd:string = date '2020-05-12'` was true. A literal that reads as a date is only treated as one when its datatype says it is; a plain literal, carrying no datatype to judge, is still accepted if `date_in` can read it. That shared conversion also stops suppressing errors that have nothing to do with the term: only a complaint about the lexical form means no match, and a statement timeout or an interrupt raised while parsing is propagated rather than reported as a non-matching row.  (Tomas Vondra <tomas@vondra.me>)

* **Comparisons between a term and a PostgreSQL temporal type are no longer pushed down**: `o > '2025-01-01 00:00:00'::timestamp` was sent as `FILTER(?o > "2025-01-01T00:00:00"^^xsd:dateTime)`, which is not the same question. SPARQL compares two temporal terms only when they carry the same datatype, and the timezone offset of an `xsd:dateTime` takes part in the comparison; the PostgreSQL operator has neither property, since it reads the term's lexical form with the temporal type's input function, which accepts an `xsd:date` where an `xsd:dateTime` was asked for and discards the offset.

  Endpoints then part company over the terms that do not compare at all — a string, an IRI, a literal of another datatype. Some drop them as the specification suggests, some place them against the constant in a total order of their own and return them, and some refuse the filter outright and answer with an error. Since the condition counted as pushed, nothing re-checked it locally, and whatever the endpoint did became the result: one store answered a comparison against a timestamp with IRIs and language-tagged strings, and rejected every `xsd:time` filter it was sent; even the stores that treated the condition as a plain temporal question selected different rows from identical data. No rule `rdf_fdw` could adopt locally would agree with whichever store is being queried, so these comparisons are now always evaluated in PostgreSQL — `date`, `time`, `timetz`, `timestamp` and `timestamptz` alike — which is what makes the answer the same everywhere.

  The cost is traffic rather than accuracy: where an endpoint already agreed, the rows are unchanged and only the scan is wider, since the terms are fetched and filtered locally instead of arriving pre-filtered.

  This holds however the term is written, including one built to carry a chosen datatype: `date '2015-01-01' = sparql.strdt(sparql.substr(sparql.str(o), 1, 10), 'xsd:date')` used to be sent and is now evaluated locally. Pinning the datatype settles what the endpoint compares, but the operator PostgreSQL picks is still the lenient one, and for `timetz` a lexical form written without an offset is read in the session's `TimeZone` — so the two sides can still disagree. A comparison between two terms is unaffected, and so is one against a value of the column's own type.

* **`LIMIT` was pushed down where it changed the result**: A remote `LIMIT` decides which rows the endpoint sends, so it is only sound where those are the rows the query wants. It was being sent regardless of what sat above the scan.

  Under an `ORDER BY` it keeps whichever rows come first in the endpoint's ordering, and SPARQL does not fully define that ordering. It fixes the order between kinds of term, and between literals whose values are comparable, but leaves the rest to the implementation — and implementations disagree: asked to sort the same eight terms, Fuseki returns IRIs first, Virtuoso strings first and QLever booleans first. No ordering `rdf_fdw` could adopt locally would match the store being queried, so the rows the endpoint kept are not reliably the rows the query wanted, and the local sort cannot recover one that was never fetched. Concretely, over three integers, `ORDER BY o LIMIT 1` returned a different row than the first row of the same query without the `LIMIT`.

  The limit was also sent when the sort could not be pushed at all, handing back an arbitrary `n` rows to sort; applied to each side of a join independently, where the join decides how many rows survive; and applied beneath window functions, `HAVING` and set-returning functions. Such queries now fetch their rows and apply the limit locally. A `LIMIT` on a single scan with no sort above it is unaffected.

  Separately, `LIMIT` and `OFFSET` are read as 64-bit values. Both are `bigint` in SQL, but the offset was taken through a 32-bit accessor, so `OFFSET 3000000000 LIMIT 10` was sent as `LIMIT -1294967286` — not merely the wrong count, but a negative one no endpoint will parse.

* **Arithmetic in a pushed-down filter lost its grouping**: The deparser wrote an expression's operands and operators out in order without parentheses, so the shape of the SQL expression tree was left for SPARQL to reconstruct from precedence alone. `WHERE (n + 1) * 2 = 10` was sent as `FILTER(?n + 1 * 2 = 10)`, which SPARQL reads as `?n + (1 * 2)`, and `WHERE (n + 2) * (n + 3) = 20` as `FILTER(?n + 2 * ?n + 3 = 20)` — different conditions selecting different rows, with no error anywhere. Arithmetic operators are now parenthesised so the grouping survives. Comparisons are not: their result only ever reaches `&&` or `||`, which already parenthesise their operands, so existing plans are unchanged.

  A unary operator reaching the same code produced an empty string rather than declining, which made the condition look pushable and dropped it from the scan's local filter without putting anything in its place. Such an operator is now left to the executor.

* **`REPLACE()` discarded the literal's language tag and datatype**: Replacing part of `"hello"@en` returned `"heLLo"` rather than `"heLLo"@en`, and a datatyped literal lost its datatype the same way, so a value that went through `REPLACE` came back as a different kind of RDF term than it started as. All three overloads now carry the first argument's language tag or datatype over to the result. An `xsd:string` input still yields a simple literal, since RDF 1.1 makes those the same thing.

  The result is also built as a literal from lexical content rather than cast from text. A cast reads its input back as a serialised term, so a replacement that happened to look like `<...>` or to contain `"@` was taken for an IRI or an annotated literal instead of the string it was, and content ending in a backslash produced a literal whose closing quote was escaped away.

* **An empty `GROUP_CONCAT()` did not return an RDF literal**: With nothing to concatenate the result was raw empty text rather than `""`, the serialisation of an empty string literal. The two print almost alike — a blank cell against an empty pair of quotes — but only one of them is an RDF term, so `sparql.isliteral()` on the result was false and any function expecting a literal was working on something that was not one. Both the wrapper and the aggregate's own final function now return the serialised form.

* **Unicode escapes were decoded at the wrong width**: `\u` takes exactly four hex digits and `\U` exactly eight, but a hex digit *following* an escape was treated as though it belonged to it, and the whole sequence was then left undecoded — `"\u004142"` stayed as written instead of becoming `"A42"`, and a surrogate pair followed by a hex digit lost its first half to a replacement character. An escaped backslash was also read as the start of an escape: `"\\u0041"` is a backslash followed by the characters `u0041`, but it decoded to `\A`, which is a different value. Each escape now consumes exactly its own width, and an escaped backslash is passed through.

* **`SUBSTR()` rejected valid starting positions**: A start below 1 raised `SUBSTR start position must be >= 1`. SPARQL follows XPath's `fn:substring`, which returns the characters whose position falls in the interval `[start, start + length)` and treats a start outside the string as ordinary — only the part of the interval that overlaps the string is returned, and nothing is an error. `SUBSTR("foobar", 0, 2)` is `"f"`, since the interval covers position 1 alone; `SUBSTR("foobar", -2, 3)` is the empty string; and a start at or before the first character with no length returns the whole string. All of these were refused. A negative length is likewise clipped to an empty result rather than misread as a large one.

* **`float4` values were serialised with six significant digits**: A `real` was converted to RDF with `%g`, whose default precision is six significant digits, while a `float4` needs up to nine to survive a round trip. Values with more precision came back changed — `1.1234567` became `1.12346`, and `16777217` became `1.67772e+07` — so a column read from a triplestore and written back no longer held the value it started with. The type's own output function is used now.  (Tomas Vondra <tomas@vondra.me>)

  That function honours `extra_float_digits`, which `%g` ignored, so how many digits appear is a setting rather than something fixed in the conversion. On PostgreSQL 12 and later the default of `1` prints the shortest text that reads back exactly, and these values now round-trip out of the box. On earlier releases the default of `0` still asks for six digits; exact output is available there with `SET extra_float_digits = 3`, which `%g` gave no way to obtain at all.

* **`ABS()` destroyed exact numeric values**: Whatever its argument's datatype, it converted the value to `double precision` before taking the absolute value. Anything an IEEE double cannot hold exactly came back changed — `ABS("-9007199254740993"^^xsd:integer)` returned `9007199254740992` — and the result was printed in the exponent notation a double round-trip produces, which is not in the lexical space of either `xsd:integer` or `xsd:decimal`: that same call returned `"9.007199254740992e+15"^^xsd:integer`, and `ABS("-0.000000000000001"^^xsd:decimal)` returned `"1e-15"^^xsd:decimal`. Trailing zeros, which are part of an `xsd:decimal` value, were lost as well. Only `xsd:float` and `xsd:double` arguments are computed in floating arithmetic now; every other numeric datatype is handled exactly and keeps its lexical form.

* **The extension could not be installed into a schema other than `public`**: `CREATE EXTENSION rdf_fdw SCHEMA ...` was accepted and created its objects in the requested schema, but the C code then looked the `rdfnode` type up under the name `public.rdfnode`, so every query that had to resolve the type failed with `type "public.rdfnode" does not exist`. The type is created by the extension script without a schema and therefore lands wherever the extension went; the lookup now reads that schema from `pg_extension`. Together with the qualification of the SQL function bodies, an installation in a schema of its own now works — put that schema on the `search_path` to use it, since the `rdfnode` operators, like all operators, are resolved that way.
* **The `sparql.*` functions depended on the caller's `search_path`**: Their bodies referred to the `rdfnode` type without naming a schema, and a PL/pgSQL body is parsed when it first runs, not when it is created. A caller whose `search_path` did not include the schema the extension was installed into therefore got `type "rdfnode" does not exist` from `sparql.round()`, `sparql.abs()` and 35 other functions — `SET search_path = pg_catalog` was enough to break them. The 50 places that resolve the type at call time now name the installation schema, so the functions work whatever the caller's `search_path` is, and an unqualified name in it can no longer be captured by an object someone else defined. Function signatures are unchanged: those are resolved once, while the extension script runs.

  This also removes one of the two reasons `CREATE EXTENSION rdf_fdw SCHEMA ...` does not work with a schema other than `public`. The other is in C and still stands.

* **`ROUND()` was wrong for zero and for every negative fraction above -1**: All four overloads chose between `floor(x + 0.5)` and `ceil(x + 0.5)` on the sign of the argument, which is not the SPARQL rule. SPARQL returns the number with no fractional part nearest the argument, and on a tie the one closer to positive infinity — that is `floor(x + 0.5)` for every argument, negative ones included. Taking the ceiling instead moved negative values a whole step in the wrong direction: `ROUND(-1.2)` and `ROUND(-0.6)` both returned `0` rather than `-1`, and because zero itself failed the `> 0` test, `ROUND(0)` returned `1`.

  The floating-point overloads compare the fractional part against one half rather than adding the half first, since in binary floating point `x + 0.5` can carry to the next integer on its own and take a value such as `0.49999999999999994` up to `1`. An argument in `[-0.5, 0)` now yields negative zero for `xsd:float` and `xsd:double`, as XPath requires; `xsd:decimal` and `xsd:integer` have no negative zero and are unaffected. The datatype of the argument is preserved throughout, and `NaN` and the infinities pass through unchanged.

* **The SPARQL function API was unreachable for non-superusers**: The extension puts its 125 `sparql.*` functions in a schema of their own, and they carry the default `PUBLIC EXECUTE`, but nothing ever granted `USAGE` on the schema itself. Any role that did not own the extension got `permission denied for schema sparql` for every one of them, so a DBA had to grant schema usage by hand before ordinary users could call `sparql.str()`, `sparql.lang()` or any of the rest. The schema is now granted to `PUBLIC` on a fresh install and on upgrade from 2.7. The two tables in the schema keep their default privileges and remain readable only by their owner, and the entry points reached through the schema check their own privileges, so this widens no access beyond the function API itself.

* **`BNODE()`, `UUID()` and `STRUUID()` did not generate a new value per row**: The three zero-argument generators were declared `IMMUTABLE`, so the planner folded each call to a constant and every row of a result got the same identifier — `SELECT sparql.uuid() FROM t` returned one UUID repeated. They are now `VOLATILE`, in both a fresh install and the 2.7 upgrade.

  That alone was not enough, because two further defects were masked by the folding. `BNODE()` and the UUID generator both built their value by XOR-ing a call counter into the current timestamp; between consecutive calls both operands advance by one, which cancels in the low bits, so roughly half of all calls reproduced a value already returned. Over 1000 calls `BNODE()` yielded 530 distinct identifiers, and `UUID()` was no better — a duplicate blank node conflates two RDF resources, and duplicate UUIDs are not UUIDs at all. The counter and the timestamp are now combined so that they cannot cancel. Separately, `uuid()` and `struuid()` share one C function and cache which of the two they are in `fn_extra`, but that cache was allocated in the per-tuple memory context, which is reset between rows; from the second row on it read freed memory, and `struuid()` could start returning the IRI form belonging to `uuid()`.

* **Columns mapped to a `$`-prefixed SPARQL variable returned only NULLs**: SPARQL names a variable with either sigil, and `?x` and `$x` are the same variable, but `rdf_fdw` only ever built the name to match against a result binding with `?`. A column declared as `OPTIONS (variable '$name')` was accepted, and the query sent to the endpoint was valid and returned the right bindings — but none of them matched the mapping, so every row came back with that column NULL. The sigil is now normalised when the table's options are loaded, so both spellings behave alike. (Tomas Vondra <tomas@vondra.me>)

* **`EXPLAIN` reported clauses that were never sent**: When the query in a table's `sparql` option cannot be rewritten — because it already carries its own `LIMIT`, `ORDER BY`, `GROUP BY`, `UNION` or `MINUS` — `rdf_fdw` sends it exactly as supplied and evaluates every SQL clause locally. The plan nevertheless said `Pushdown: enabled` and showed the `Remote Select`, `Remote Sort Key` and `Remote Limit` it had built while planning, so a scan answered entirely by PostgreSQL could be reported as having its projection, sorting and row limit pushed down. That is the opposite of what those lines exist to say, and the `Remote Limit` in particular named a row count far smaller than the one the endpoint was actually asked for. `Pushdown` now reports what the scan does rather than what the option asks for, and reads `unsupported SPARQL` in this case, with the `Remote` lines omitted.

* **SPARQL keyword detection ignored where the keyword actually was**: `LocateKeyword()` searches for a keyword once per combination of an accepted preceding and following delimiter, and returned whichever combination happened to match first rather than whichever match sat earliest in the query. Two things followed from that. A query mixing spellings of the same clause lost parts of it: in `FROM<http://g1> FROM <http://g2>`, the space-delimited spelling matched first, so the first graph was dropped from the reconstructed query and it was sent naming fewer graphs than the user wrote — silently, since the result is still a valid query. And a keyword appearing inside a string literal was rejected, correctly, but ended the search for that spelling, hiding any real keyword after it: a query such as `SELECT * WHERE { ?s ?p ?o . FILTER(?o != " LIMIT ") } LIMIT 5` was judged rewritable, and its `LIMIT 5` was discarded during the rewrite. The search now considers every spelling before choosing the earliest match, and keeps scanning past an occurrence that turns out to be inside a literal.

* **A graph name on the line after `FROM` was lost**: When reconstructing a query, `rdf_fdw` looked for the graph IRI by skipping literal space characters after `FROM` (and after `NAMED`). SPARQL allows any whitespace there, so a query written across several lines — `FROM` followed by a newline and an indented `<http://...>` — left the parser on the newline, which it read as the end of the IRI. The rewritten query then carried a bare `FROM` with no graph at all and was rejected by the endpoint as a syntax error. All SPARQL whitespace forms are now accepted around the graph IRI. (Tomas Vondra <tomas@vondra.me>)

* **Whole-row references returned incomplete rows**: A whole-row reference such as `SELECT t FROM ft t` marks no individual column as used, so it contributed nothing to the generated SPARQL `SELECT` clause. On its own the query still worked, because an empty projection falls back to `SELECT *`, but combined with a column reference — `SELECT t, t.object FROM ft t` — only `?o` was requested and every other field of `t` came back as `NULL`. A whole-row reference now marks all of the table's columns as used, which is also what PostgreSQL's own `postgres_fdw` does. The same applies to the whole-row references PostgreSQL adds by itself, for instance as the row identity of a semi-join, so `DELETE`/`UPDATE` statements whose subquery reads the same foreign table now request every mapped variable. (Tomas Vondra <tomas@vondra.me>)

* **Out-of-bounds read while deparsing a boolean test**: The column lookup for `IS TRUE`/`IS FALSE` scanned the mapped columns backwards and then dereferenced the result without checking that a column had actually matched, so a boolean `Var` with no corresponding mapping read past the start of the array. The lookup now reports the condition as not pushable instead.

* **`WHERE` conditions were dropped when pushdown was disabled**: With `enable_pushdown 'false'` on a `SERVER` or `FOREIGN TABLE`, the conditions of a parsable `SPARQL` query were still deparsed and recorded as pushed down, so PostgreSQL left them out of the foreign scan's local filter — but the query actually sent to the endpoint was the unmodified raw one, without the corresponding `FILTER`. The conditions were therefore evaluated nowhere and the scan returned rows that should have been filtered out. Conditions are now only treated as remote when pushdown is enabled, and are otherwise evaluated locally.

* **Handle libcurl initialization failures, and stop writing to `stderr`**: A failure of `curl_easy_init()` or `curl_easy_escape()` went unnoticed: the request was quietly skipped and reported as an empty result set rather than as an error. Both are now checked and raise a proper error. On network failures the extension also wrote a partial `libcurl: (<code>)` line straight to the backend's `stderr`, bypassing the server log's formatting; that leftover has been removed, and the error code it printed was already part of the error message raised right after it.

* **Restricted redirects to HTTP and HTTPS**: `rdf_fdw` limits requests to the `http` and `https` protocols, but that restriction only covers the initial request — libcurl governs the protocols a redirect may lead to with a separate option, whose default also permits `ftp` and `ftps`. An endpoint could therefore answer with a redirect to an `ftp://` URL and have the backend follow it. Redirect targets are now restricted to `http` and `https` as well.

* **Fixed corrupted responses when a retried request succeeds**: The retry loop performed each new request in the loop condition but only cleared the response buffer in the loop body, so the clearing always happened one step too late. A connection that dropped after the endpoint had already sent part of the body left those bytes in the buffer, and the first retry appended its own response right after them; if that retry succeeded, the loop exited before ever clearing, and the concatenation of a truncated response and a complete one was handed to the XML parser. The buffer — body and headers alike — is now cleared before each retry, and the retry loop was rewritten so the request is performed in the loop body rather than in its condition.

* **Fixed a libcurl handle leak when `max_response_size` is exceeded**: The callback that collects the HTTP response body raised the "response exceeds max_response_size" error with `ereport(ERROR)` from inside libcurl. That longjmps out of the middle of `curl_easy_perform()`, so neither `curl_easy_cleanup()` nor `curl_slist_free_all()` ever ran — and since libcurl allocates the easy handle, its header list and its connection outside PostgreSQL's memory contexts, aborting the transaction did not reclaim them either. Every query that hit the limit therefore leaked a handle and a connection for the remaining life of the backend, on top of abandoning libcurl mid-transfer. The callback now flags the condition and aborts the transfer by returning a short write, which makes `curl_easy_perform()` fail cleanly; the very same error is raised afterwards, once the handle and the header list have been released. Requests aborted this way are also no longer retried, as every attempt would hit the same limit.

* **Fixed the `custom` server option having no effect**: When building the request for a SPARQL `SELECT`/`DESCRIBE`, the parameters configured in the `custom` server option were appended to the request as `&<the URL-encoded SPARQL query>` instead of `&<the custom parameters>`. Triplestore-specific parameters such as `signal_void=on` were therefore never sent to the endpoint, and the SPARQL query was sent twice in the same request, needlessly doubling its size. The configured parameters are now appended as intended.

* **Fixed `request_max_redirect '0'` being silently ignored**: The redirect limit was only handed to libcurl when the configured value was non-zero (`if (state->request_max_redirect)`), so a `FOREIGN SERVER` with `request_redirect 'true'` and `request_max_redirect '0'` never set `CURLOPT_MAXREDIRS` at all and instead inherited libcurl's own default — 30 redirects since libcurl 8.3.0, and *unlimited* on older libcurl releases. Instead of refusing redirects, such a server would happily follow them. The limit is now always set explicitly, so it never depends on the libcurl release `rdf_fdw` happens to be linked against, and `request_max_redirect '0'` genuinely refuses redirects.

  The option is also validated at `CREATE SERVER`/`ALTER SERVER` time now, as the other numeric server options already were. Non-numeric values such as `request_max_redirect 'foo'` used to be silently accepted and turned into `0`, and negative values were passed straight to libcurl. Values that aren't non-negative integers are now rejected with an error.

* **Fixed `lex()` misreading the closing quote of a literal ending in backslashes**: `lex()` decided whether a `"` was escaped using the same single-character lookbehind that was corrected in `cstring_to_rdfliteral()` and `EscapeSPARQLLiteral()` in 2.7 — it was simply missed at the time. That check cannot tell an odd-length backslash run, which does escape the quote that follows it, from an even-length one, whose backslashes form complete escape pairs and leave the quote unescaped. A literal whose lexical value ended in an even number of backslashes therefore hid its own closing quote: `lex()` ran to the end of the string, reported the literal as malformed, and callers fell back to escaping the whole input as raw content. `'"\\\\"'::rdfnode` came back as `"\"\\\\\""`, with the delimiting quotes folded into the lexical value, while the otherwise identical `'"\\\\"@en'` kept them. The lookbehind has been removed: escape pairs are consumed two bytes at a time, so a genuinely escaped quote never reaches that check, and the only way to arrive there with a backslash behind was to have just consumed `\\`, where the quote does close the literal — the check could only fire when it was wrong. Plain and language-tagged literals now agree on the lexical value, and a literal ending in a backslash run survives a round trip through `text` unchanged. (Tomas Vondra <tomas@vondra.me>)

* **Fixed an out-of-bounds read in `lang()`**: `lang()` located the language tag by rebuilding its scan position arithmetically — it skipped the opening quote of the input and then advanced by `strlen(lex(input))`. That only works if `lex()` returns a substring of its argument, and for a quoted literal it does not: it collapses a doubled quote (`""`) into a single one, and when the literal has no closing quote at all it returns the whole input, opening quote included. In that case the offset is the length of the entire input, applied *after* the opening quote had already been skipped, so the pointer landed one byte past the end of the allocation. That byte was read, and whenever it happened to be `@` the tag scan kept walking adjacent heap memory and copied it into the returned language tag. The input needed to reach this is an ordinary literal that no privileges are required to write, and every comparison operator, cast and aggregate on `rdfnode` re-enters `lang()`, so bytes that were never supplied by the client came back attached to the stored value. Because the read was outside the allocation, the same `IMMUTABLE` expression could also answer differently in a `WHERE` clause and in the target list. `lang()` now scans the input itself for the closing quote, consuming escape pairs two bytes at a time and treating a doubled quote as an escape exactly as `lex()` does, and stops at the end of the buffer; a literal with no closing quote is malformed and simply has no language tag. The unquoted branch still uses `lex()`, which genuinely does return a prefix of the input there, with the offset clamped so the two can no longer drift apart, and the tag scan is bounded by the end of the input as well. (Tomas Vondra <tomas@vondra.me>)

* **Fixed `cstring_to_rdfliteral()` returning memory it did not own**: The function had two return paths that allocated nothing — a string constant for empty input, and the argument itself when the input already looked like a complete literal. Its callers do not treat the result that way: `concat()`, `lcase()`, `ucase()`, `substr()` and `strafter()` all `pfree()` the buffer they passed in right after storing the return value, so whenever one of those paths was taken they freed the very chunk they were about to return and handed a dangling pointer back to the caller. On PostgreSQL 16 and later `AllocSetFree()` writes the freelist link into the freed chunk, so the first bytes of the returned string were overwritten with a live heap pointer. `rdf_fdw_concat()` compounded it: it keeps the returned pointer across loop iterations and `pfree()`s it again while processing the next element, so the same chunk was pushed onto the freelist twice and two later independent `palloc()` calls could be handed the same memory. For empty input the pointer was the string constant instead, and `pfree()` read the eight bytes in front of it as a chunk header, so `sparql.concat(''::rdfnode, ''::rdfnode, 'x'::rdfnode)` failed outright with `pfree called with invalid pointer`. The function now returns `pstrdup()` of the constant and of the input, so ownership of the result is unconditional and the existing `pfree()` calls are correct as written. The `StringInfo` buffer that was allocated before the complete-literal check, and leaked on that path, is now initialised after it. (Tomas Vondra <tomas@vondra.me>)

* **Foreign table columns without a `variable` option are now rejected**: The `variable` column option is documented and declared as required, but PostgreSQL only invokes an FDW validator for columns that actually carry an `OPTIONS` clause. A column declared with no options at all never reached the validator, so the requirement was never enforced anywhere and the SPARQL variable stayed unset. Every consumer dereferences it unconditionally — building the SPARQL `SELECT` clause does `pstrdup(cols[i]->sparqlvar)`, and `pstrdup(NULL)` is `strlen(NULL)` — so planning a query against such a table terminated the backend with a segmentation fault and took the whole cluster into crash recovery, ending every other session with it. `EXPLAIN` was enough to trigger it, and since no request is made to the endpoint the server option could point anywhere; any role allowed to create a foreign table could do this at will. The requirement is now enforced in the one place where column options are read, naming the offending column (Tomas Vondra <tomas@vondra.me>):

  ```
  ERROR:  column "name" of foreign table "t" has no "variable" option
  HINT:  Every column of an rdf_fdw foreign table must be mapped to a SPARQL variable, e.g. OPTIONS (variable '?name').
  ```

  Note that this is checked for every column of the table, not only for the columns a given query happens to select, so a table carrying such a column is now refused at plan time rather than whenever that column is first touched. Dropped columns are exempt: they carry no options by construction and are never mapped to a SPARQL variable. They are also no longer named by the warning about columns using deprecated native PostgreSQL types, which used to report them as `........pg.dropped.N........`.


* **Fixed a heap buffer overflow in `rdf_fdw_clone_table()`**: `InsertRetrievedData()` sizes the type, value and null arrays it passes to SPI by the number of foreign table columns, but advanced the index it writes them at once per matching `<binding>` element in the response instead of once per column. For each column the inner loop walked every binding of the current `<result>` and did not stop at the first match, so a response that repeats a variable inside a single row kept incrementing that index, writing an `Oid`, a `char` and a full 8-byte `Datum` past the end of all three allocations for every extra binding. Both the length of the overflow and its contents are chosen by whoever answers the HTTP request; for a `bigint` or `float8` column the out-of-bounds `Datum` is an entirely attacker-chosen 64-bit value. Once enough of the neighbouring chunk header has been overwritten the allocator notices, and the statement fails with `repalloc called with invalid pointer`. Any role holding `USAGE` on the foreign-data wrapper can aim a server at a host it controls, and for foreign tables that already exist the same primitive is available to a compromised endpoint or to an on-path attacker, since endpoint URLs are frequently plain `http://`. A column now takes its value from a single binding, which is the intended one-value-per-column-per-row semantics and a no-op for well-formed SPARQL XML results, and the index is bounded explicitly before it is used so the invariant is enforced rather than merely argued. Ordinary foreign scans were never affected; only `rdf_fdw_clone_table()` reaches this code. (Tomas Vondra <tomas@vondra.me>)

* **`rdf_fdw_clone_table()` and `sparql.describe()` now check privileges**: Both entry points take the name of an object rather than the object itself, so the executor never builds a range table entry for it and none of the permission checks a plain query would get ever run — and neither function made up for that. `rdf_fdw_clone_table()` resolved its `foreign_table` argument with a lookup that only validates the relation kind, then loaded the server options and the user mapping behind it, ran the SPARQL query and inserted the answer into a table of the caller's choosing. `EXECUTE` on the procedure is granted to `PUBLIC`, since the extension script issues no `REVOKE`, so any role that could connect was able to read through foreign tables it had been explicitly denied, by way of the procedure rather than by selecting from them. `sparql.describe()` had the same gap for its `SERVER` argument, shielded only by the `sparql` schema not being granted to `PUBLIC` — which stops being true the moment a DBA grants usage on it. Both also reach the endpoint with whatever credentials the DBA configured in the server's user mapping, so this was not only a read of data the caller was denied, but a request authenticated as somebody else. `ACL_SELECT` on the foreign table and `ACL_USAGE` on the server it belongs to are now both required, reported through the same machinery a direct `SELECT` uses so the message matches. Privileges on the target table were already enforced, because the `INSERT` runs through SPI as the calling user (Tomas Vondra <tomas@vondra.me>).

* **Fixed `rdf_fdw_clone_table()` flattening IRIs, blank nodes and language tags**: `RDFNODEOID` is a cached type OID looked up once per backend. Every other entry point refreshes it on the way in; `rdf_fdw_clone_table()` did not, so whenever the procedure was the first `rdf_fdw` call of a session it ran with the cache still unset. Nothing then matched an `rdfnode` column: the decision of how to serialize a binding turns on comparing the column type against that OID, and with the cache unset the comparison was false even for genuine `rdfnode` columns, so the `<uri>`, `<bnode>` and `<literal>` branches were all skipped and the raw XML content was inserted as a bare string. Cloning silently degraded every node — an IRI, a blank node and a language-tagged literal came back as `"http://example.org/thing"`, `"b1"` and `"hello"` instead of `<http://example.org/thing>`, `_:b1` and `"hello"@en` — so the clone no longer matched what selecting from the same foreign table returned, and the IRI brackets, blank node labels and language tags were lost with no error and no warning. For the same reason `LoadRDFTableInfo()` also reported every `rdfnode` column as using a deprecated native PostgreSQL type. The cache is now initialised on entry, as it is everywhere else. Note that a session which had already run any other `rdf_fdw` operation initialised the OID as a side effect, so whether a clone was affected depended on what the session happened to have done beforehand (Tomas Vondra <tomas@vondra.me>).

* **Fixed Unicode escapes being truncated on non-UTF8 servers**: `unescape_unicode()` converts `\uXXXX` and `\UXXXXXXXX` escapes into the server encoding with `pg_unicode_to_server()`, but measured the length of the result with `pg_utf_mblen()`, which decodes a UTF-8 lead byte. After the conversion the buffer holds server-encoding bytes, not UTF-8, so the length was simply wrong whenever the two differ. In `EUC_JP`, for example, U+3042 converts to two bytes whose first is not a valid UTF-8 lead byte at all, so the length came out as 1 and only that first byte was emitted. The resulting value is not valid in the server encoding, yet it could still be stored in a table, after which reading it back through any encoding conversion failed with `invalid byte sequence for encoding`. The length is now taken with `strlen()` on the NUL-terminated result, which is also correct for the conversions that expand one code point into several characters. Separately, every call site declared a 5-byte destination buffer, while `pg_unicode_to_server()` requires at least `MAX_UNICODE_EQUIVALENT_STRING + 1` bytes because for a non-UTF8 server encoding it hands that buffer straight to the conversion procedure, which writes the entire converted string without any length limit; the buffers are now sized as the contract requires. The compatibility shim used on servers predating PostgreSQL 13 had the same problem in a more direct form — it copied the converted string with an unbounded `memcpy()` and then terminated it at the UTF-8 length — and now measures the string, rejects anything that does not fit, and terminates at the right offset. Both defects were invisible in a UTF8 database, where `pg_unicode_to_server()` emits UTF-8 and the UTF-8 length function happens to be correct.


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