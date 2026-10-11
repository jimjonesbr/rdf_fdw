# SPARQL Functions

`rdf_fdw` implements most of the [SPARQL 1.1 built-in functions](https://www.w3.org/TR/sparql11-query/#funcs) as SQL functions in the `sparql` schema, which avoids clashes with PostgreSQL built-ins such as `round`, `replace` or `ceil`. They follow SPARQL semantics for literals, language tags, datatypes and unbound values. When used in the `WHERE` clause of a query on a `FOREIGN TABLE` they are [pushed down](../README.md#pushdown) to the endpoint wherever possible.

In the examples below, the result of each statement is shown as a comment. `NULL` stands for an unbound value or a SPARQL error.

- [Triplestores differ](#triplestores-differ)
- [Aggregates](#aggregates)
- [Functional forms](#functional-forms)
- [Functions on RDF terms](#functions-on-rdf-terms)
- [Functions on strings](#functions-on-strings)
- [Functions on numerics](#functions-on-numerics)
- [Functions on dates and times](#functions-on-dates-and-times)
- [Hash functions](#hash-functions)
- [Non-standard functions](#non-standard-functions)

## Triplestores differ

While most RDF triplestores claim SPARQL 1.1 compliance, their behaviour often diverges from the standard, particularly for literals with language tags or datatypes. For example:

```sparql
SELECT (REPLACE("foo"@en, "o"@de, "xx"@fr) AS ?str) {}
```

* Virtuoso → `"fxxxx"`
* Blazegraph → **Unknown error**: *incompatible operand for REPLACE: "o"@de*
* GraphDB → `"fxxxx"@en`

A pushed-down function is evaluated by the endpoint, and PostgreSQL re-checks the returned rows with its own implementation. When the two disagree, rows are silently filtered out locally. To avoid surprises:

* Test how your target triplestore handles tagged or typed literals.
* Consider simpler (less performant) alternatives, such as comparing [`str`](#functions-on-rdf-terms) values, when working with language-tagged literals.
* Compare the number of records returned by the endpoint with the number of rows you get, using [EXPLAIN](../README.md#explain-and-diagnostics) or the `log_sparql` table option. If the endpoint returned more records than you see, some were filtered out locally.

## Aggregates

| Function | Returns | Description |
|---|---|---|
| `sparql.sum(rdfnode)` | `rdfnode` | Sum of numeric values ([§18.5.1.3](https://www.w3.org/TR/sparql11-query/#aggregates)) |
| `sparql.avg(rdfnode)` | `rdfnode` | Arithmetic mean of numeric values ([§18.5.1.4](https://www.w3.org/TR/sparql11-query/#aggregates)) |
| `sparql.min(rdfnode)` | `rdfnode` | Smallest value ([§18.5.1.5](https://www.w3.org/TR/sparql11-query/#aggregates)) |
| `sparql.max(rdfnode)` | `rdfnode` | Largest value ([§18.5.1.6](https://www.w3.org/TR/sparql11-query/#aggregates)) |
| `sparql.group_concat(rdfnode, separator text)` | `rdfnode` | Joins the lexical forms into one simple literal ([§18.5.1.7](https://www.w3.org/TR/sparql11-query/#aggregates)) |
| `sparql.sample(rdfnode)` | `rdfnode` | An arbitrary value of the group, currently the first non-NULL one ([§18.5.1.8](https://www.w3.org/TR/sparql11-query/#aggregates)) |

> [!NOTE]
> Aggregates are always evaluated by PostgreSQL; they are not pushed down. For remote aggregation, put the aggregate in the foreign table's `sparql` option.

**Semantics**

* SQL `NULL` is treated as SPARQL UNDEF and skipped.
* If no values remain (an empty group, or only `NULL`s):
  * `sum`, `avg` → `"0"^^xsd:integer` (per spec: "the sum of no bindings is 0")
  * `group_concat` → `""`
  * `min`, `max`, `sample` → `NULL`
* `sum` and `avg` return `NULL` if any value is not numeric.
* Numeric types are promoted following XPath rules, `xsd:integer` < `xsd:decimal` < `xsd:float` < `xsd:double`, and the result has the highest type encountered. All integer subtypes (`xsd:int`, `xsd:long`, `xsd:short`, ...) count as `xsd:integer`. `avg` of a non-empty set is at least `xsd:decimal`.
* `min` and `max` keep the datatype of the value they return and also accept non-numeric values. Values of different kinds (e.g. numbers and strings) are ordered following [SPARQL 1.1 §15.1](https://www.w3.org/TR/sparql11-query/#modOrderBy). That ordering is only partially specified, so results for mixed sets may differ from other triplestores.
* `group_concat` strips datatypes, language tags and the angle brackets of IRIs. Unlike `string_agg`, the separator is required.

```sql
SELECT sparql.sum(v) FROM (VALUES ('"10"^^xsd:integer'::rdfnode), ('"20.5"^^xsd:decimal'), ('"30"^^xsd:integer')) t(v);
-- "60.5"^^<http://www.w3.org/2001/XMLSchema#decimal>

SELECT sparql.sum(v) FROM (VALUES ('"10.5"^^xsd:decimal'::rdfnode), ('"20.3"^^xsd:decimal'), ('"5"^^xsd:float')) t(v);
-- "35.8"^^<http://www.w3.org/2001/XMLSchema#float>

SELECT sparql.avg(v) FROM (VALUES ('"10"^^xsd:integer'::rdfnode), (NULL), ('"30"^^xsd:integer')) t(v);
-- "20.0"^^<http://www.w3.org/2001/XMLSchema#decimal>

SELECT sparql.min(v), sparql.max(v) FROM (VALUES ('"10"^^xsd:integer'::rdfnode), ('"-5"^^xsd:integer'), ('"3"^^xsd:integer')) t(v);
-- "-5"^^<http://www.w3.org/2001/XMLSchema#integer> | "10"^^<http://www.w3.org/2001/XMLSchema#integer>

SELECT sparql.group_concat(v, ' | ') FROM (VALUES ('"42"^^xsd:integer'::rdfnode), ('"hello"@en'), ('<http://example.org/r1>')) t(v);
-- "42 | hello | http://example.org/r1"

SELECT sparql.sample(v) FROM (VALUES ('"hello"@en'::rdfnode), ('"bonjour"@fr')) t(v);
-- "hello"@en

SELECT sparql.sum(v), sparql.avg(v), sparql.group_concat(v, ','), sparql.min(v) FROM (SELECT NULL::rdfnode WHERE false) t(v);
-- "0"^^<http://www.w3.org/2001/XMLSchema#integer> | "0"^^<http://www.w3.org/2001/XMLSchema#integer> | "" | NULL
```

## Functional forms

| Function | Returns | Description |
|---|---|---|
| [`sparql.bound(rdfnode)`](https://www.w3.org/TR/sparql11-query/#func-bound) | `boolean` | `true` if the value is not `NULL`. `NaN` and `INF` are bound. |
| [`sparql.coalesce(rdfnode, ...)`](https://www.w3.org/TR/sparql11-query/#func-coalesce) | `rdfnode` | The first argument that is not `NULL`, evaluated left to right |
| [`sparql.sameterm(rdfnode, rdfnode)`](https://www.w3.org/TR/sparql11-query/#func-sameTerm) | `boolean` | `true` if both are exactly the same term, including datatype and language tag, without any coercion |

```sql
SELECT sparql.bound(NULL), sparql.bound('"NaN"^^xsd:double');   -- f | t
SELECT sparql.coalesce(NULL, NULL, '"foo"@en');                 -- "foo"@en
SELECT sparql.sameterm('"42"^^xsd:int', '"42"^^xsd:long');      -- f
SELECT '"42"^^xsd:int'::rdfnode = '"42"^^xsd:long'::rdfnode;     -- t
SELECT sparql.sameterm('"foo"@en', '"foo"@en');                 -- t
```

Use `sameterm` for exact RDF identity. `=` compares values, with numeric promotion (see [Comparing, sorting and grouping](../README.md#comparing-sorting-and-grouping)).

## Functions on RDF terms

| Function | Returns | Description |
|---|---|---|
| [`sparql.isiri(rdfnode)`](https://www.w3.org/TR/sparql11-query/#func-isIRI), `sparql.isuri(rdfnode)` | `boolean` | `true` for IRIs |
| [`sparql.isblank(rdfnode)`](https://www.w3.org/TR/sparql11-query/#func-isBlank) | `boolean` | `true` for blank nodes |
| [`sparql.isliteral(rdfnode)`](https://www.w3.org/TR/sparql11-query/#func-isLiteral) | `boolean` | `true` for literals |
| [`sparql.isnumeric(rdfnode)`](https://www.w3.org/TR/sparql11-query/#func-isNumeric) | `boolean` | `true` for literals of a numeric datatype (`xsd:integer`, `xsd:int`, `xsd:decimal`, `xsd:double`, ...) |
| [`sparql.str(rdfnode)`](https://www.w3.org/TR/sparql11-query/#func-str) | `rdfnode` | Lexical form as a simple literal: drops language tag and datatype; IRIs become their string |
| [`sparql.lang(rdfnode)`](https://www.w3.org/TR/sparql11-query/#func-lang) | `rdfnode` | Language tag of a literal, or an empty string. IRIs and blank nodes raise an error. |
| [`sparql.datatype(rdfnode)`](https://www.w3.org/TR/sparql11-query/#func-datatype) | `rdfnode` | Datatype IRI: `xsd:string` for simple literals, `rdf:langString` for language-tagged ones, `NULL` for IRIs and blank nodes |
| [`sparql.iri(rdfnode)`](https://www.w3.org/TR/sparql11-query/#func-iri), `sparql.uri(rdfnode)` | `rdfnode` | Wraps a string as an IRI. No validation is performed. |
| [`sparql.bnode([rdfnode])`](https://www.w3.org/TR/sparql11-query/#func-bnode) | `rdfnode` | Blank node with the given label, or a fresh one without argument |
| [`sparql.strdt(lexical rdfnode, datatype rdfnode)`](https://www.w3.org/TR/sparql11-query/#func-strdt) | `rdfnode` | Typed literal. Applied to a literal, it replaces the datatype. |
| [`sparql.strlang(lexical rdfnode, lang rdfnode)`](https://www.w3.org/TR/sparql11-query/#func-strlang) | `rdfnode` | Language-tagged literal. Applied to a tagged literal, it replaces the tag. |
| [`sparql.uuid()`](https://www.w3.org/TR/sparql11-query/#func-uuid) | `rdfnode` | Fresh `urn:uuid:` IRI |
| [`sparql.struuid()`](https://www.w3.org/TR/sparql11-query/#func-struuid) | `rdfnode` | Fresh UUID as a simple literal |

```sql
SELECT sparql.isiri('<https://foo.bar/>'), sparql.isiri('_:bnode42');    -- t | f
SELECT sparql.isblank('_:bnode42');                                       -- t
SELECT sparql.isliteral('"foo"@es'), sparql.isliteral('<http://foo.bar>'); -- t | f
SELECT sparql.isnumeric('"42.73"^^xsd:decimal');                          -- t
SELECT sparql.isnumeric('"42.73"^^xsd:string');                           -- f
SELECT sparql.str('"foo"@en');                                            -- "foo"
SELECT sparql.str('<http://foo.bar>');                                    -- "http://foo.bar"
SELECT sparql.lang('"foo"@es');                                           -- es
SELECT sparql.datatype('"42"^^xsd:int');                                  -- <http://www.w3.org/2001/XMLSchema#int>
SELECT sparql.datatype('"foo"');                                          -- <http://www.w3.org/2001/XMLSchema#string>
SELECT sparql.datatype('"foo"@de');                                       -- <http://www.w3.org/1999/02/22-rdf-syntax-ns#langString>
SELECT sparql.datatype('<http://foo.bar>');                               -- NULL
SELECT sparql.iri('http://foo.bar');                                      -- <http://foo.bar>
SELECT sparql.bnode('foo');                                               -- _:foo
SELECT sparql.bnode();                                                    -- _:b844460685272636_0
SELECT sparql.strdt('"2025-01-01"^^xsd:string', 'http://www.w3.org/2001/XMLSchema#date');
-- "2025-01-01"^^<http://www.w3.org/2001/XMLSchema#date>
SELECT sparql.strlang('"foo"@pt', 'es');                                  -- "foo"@es
SELECT sparql.uuid();                                                     -- <urn:uuid:1beda602-2e35-4d13-a907-071454d2fce7>
SELECT sparql.struuid();                                                  -- "25a55e10-f789-4aab-bb7f-05f2ba495fd2"
```

> [!NOTE]
> Some triplestores (like Virtuoso) return `xsd:anyURI` as the `DATATYPE` of an IRI. This is not defined in SPARQL 1.1.

## Functions on strings

Unless stated otherwise, these functions work on the lexical form and the result keeps the language tag or datatype of the first argument. Where a function takes two string arguments, they must be [argument-compatible](https://www.w3.org/TR/sparql11-query/#func-arg-compatibility): a language-tagged second argument only matches a first argument with the same tag. Otherwise the result is `NULL`.

Most of these functions are only defined for string literals (simple, `xsd:string` or language-tagged). For other terms, SPARQL raises an error, which rdf_fdw reports either as an `ERROR` (e.g. `strlen`, `ucase`, `concat` on an IRI) or as `NULL` (e.g. `strstarts`, `contains`, `strbefore`). Don't rely on either; use `sparql.str()` to turn other terms into strings first.

| Function | Returns | Description |
|---|---|---|
| [`sparql.strlen(rdfnode)`](https://www.w3.org/TR/sparql11-query/#func-strlen) | `int` | Number of characters of a string literal. IRIs, blank nodes and non-string literals raise an error. |
| [`sparql.substr(rdfnode, start int [, length int])`](https://www.w3.org/TR/sparql11-query/#func-substr) | `rdfnode` | Substring; `start` is 1-based. Without `length`, it runs to the end. |
| [`sparql.ucase(rdfnode)`](https://www.w3.org/TR/sparql11-query/#func-ucase) / [`sparql.lcase(rdfnode)`](https://www.w3.org/TR/sparql11-query/#func-lcase) | `rdfnode` | Upper / lower case |
| [`sparql.strstarts(rdfnode, rdfnode)`](https://www.w3.org/TR/sparql11-query/#func-strstarts) | `boolean` | Starts with |
| [`sparql.strends(rdfnode, rdfnode)`](https://www.w3.org/TR/sparql11-query/#func-strends) | `boolean` | Ends with |
| [`sparql.contains(rdfnode, rdfnode)`](https://www.w3.org/TR/sparql11-query/#func-contains) | `boolean` | Contains |
| [`sparql.strbefore(rdfnode, rdfnode)`](https://www.w3.org/TR/sparql11-query/#func-strbefore) | `rdfnode` | Part before the first match, or an empty string |
| [`sparql.strafter(rdfnode, rdfnode)`](https://www.w3.org/TR/sparql11-query/#func-strafter) | `rdfnode` | Part after the first match, or an empty string |
| [`sparql.encode_for_uri(rdfnode)`](https://www.w3.org/TR/sparql11-query/#func-encode) | `rdfnode` | Percent-encodes reserved characters; always returns a simple literal |
| [`sparql.concat(rdfnode, ...)`](https://www.w3.org/TR/sparql11-query/#func-concat) | `rdfnode` | Concatenation. The result keeps a language tag or datatype only when all arguments share it. |
| [`sparql.langmatches(tag rdfnode, range rdfnode)`](https://www.w3.org/TR/sparql11-query/#func-langMatches) | `boolean` | Language tag matches a language range (`*` matches any tag) |
| [`sparql.replace(rdfnode, pattern rdfnode, replacement rdfnode [, flags rdfnode])`](https://www.w3.org/TR/sparql11-query/#func-replace) | `rdfnode` | Replaces all matches of a regular expression |

```sql
SELECT sparql.strlen('"🐘"@en');                                     -- 1
SELECT sparql.strlen(sparql.str('"42"^^xsd:int'));                   -- 2
SELECT sparql.substr('"foobar"', 1, 3), sparql.substr('"foobar"', 4); -- "foo" | "bar"
SELECT sparql.ucase('"foo"@en');                                     -- "FOO"@en
SELECT sparql.lcase('"FOO"^^xsd:string');                            -- "foo"^^<http://www.w3.org/2001/XMLSchema#string>
SELECT sparql.strstarts('"foobar"@en', '"foo"^^xsd:string');         -- t
SELECT sparql.strends('"foobar"^^xsd:string', '"bar"^^xsd:string'); -- t
SELECT sparql.contains('"_foobar_"@en', '"foo"');                   -- t
SELECT sparql.contains('"_foobar_"^^xsd:string', '"foo"@en');       -- NULL
SELECT sparql.strbefore('"foobar"@en', '"bar"^^xsd:string');         -- "foo"@en
SELECT sparql.strafter('"foobar"', '"foo"');                         -- "bar"
SELECT sparql.encode_for_uri('"foo&bar!"');                          -- "foo%26bar%21"
SELECT sparql.concat('"foo"@en', '"&"@en', '"bar"@en');              -- "foo&bar"@en
SELECT sparql.concat('"foo"', '"&"', '"bar"');                       -- "foo&bar"
SELECT sparql.langmatches('en-US', 'en'), sparql.langmatches('en', 'de'); -- t | f
SELECT sparql.langmatches('en', '*');                                -- t
SELECT sparql.replace('"foo bar foo"', 'foo', 'baz');                -- "baz bar baz"
SELECT sparql.replace('"abc"', '', 'Z');                             -- "ZaZbZcZ"
SELECT sparql.replace('"2025-01-02"', '"([0-9]{4})-([0-9]{2})-([0-9]{2})"', '"$3/$2/$1"'); -- "02/01/2025"
```

**REPLACE**

* Supports the `i`, `m` and `s` flags.
* An empty pattern matches at every position, so the replacement is inserted between all characters and at both ends.
* The replacement uses the XPath syntax required by the spec: `$1` to `$9` insert the captured groups, `\$` is a literal dollar and `\\` a literal backslash.
* The regex engine follows PostgreSQL's POSIX ERE dialect rather than the XPath dialect required by SPARQL 1.1. For most common patterns they are equivalent, but Unicode category escapes (`\p{L}`, `\p{N}`, ...) are not supported.

> [!WARNING]
> Some triplestores count bytes instead of characters in `STRLEN`. GraphDB, for instance, returns 2 for `STRLEN("🐘"@en)`, whereas Fuseki, Virtuoso and `sparql.strlen` return 1.

## Functions on numerics

All of these keep the datatype of their argument.

| Function | Returns | Description |
|---|---|---|
| [`sparql.abs(rdfnode)`](https://www.w3.org/TR/sparql11-query/#func-abs) | `rdfnode` | Absolute value |
| [`sparql.round(rdfnode)`](https://www.w3.org/TR/sparql11-query/#func-round) | `rdfnode` | Nearest integer; halves are rounded towards positive infinity |
| [`sparql.ceil(rdfnode)`](https://www.w3.org/TR/sparql11-query/#func-ceil) | `rdfnode` | Smallest integer not less than the value |
| [`sparql.floor(rdfnode)`](https://www.w3.org/TR/sparql11-query/#func-floor) | `rdfnode` | Largest integer not greater than the value |
| [`sparql.rand()`](https://www.w3.org/TR/sparql11-query/#idp2130040) | `rdfnode` | Random `xsd:double` between 0 and 1. Never pushed down. |

```sql
SELECT sparql.abs('"-42"^^xsd:int');        -- "42"^^<http://www.w3.org/2001/XMLSchema#int>
SELECT sparql.round('"2.5"^^xsd:decimal');  -- "3"^^<http://www.w3.org/2001/XMLSchema#decimal>
SELECT sparql.round('"-2.5"^^xsd:float');   -- "-2"^^<http://www.w3.org/2001/XMLSchema#float>
SELECT sparql.ceil('"3.14"^^xsd:decimal');  -- "4"^^<http://www.w3.org/2001/XMLSchema#decimal>
SELECT sparql.floor('"-2.1"^^xsd:float');   -- "-3"^^<http://www.w3.org/2001/XMLSchema#float>
SELECT sparql.rand();                       -- "0.14079881274421657"^^<http://www.w3.org/2001/XMLSchema#double>
```

## Functions on dates and times

The component functions accept `xsd:dateTime` and `xsd:date` literals (`hours`, `minutes` and `seconds` also `xsd:time`).

| Function | Returns | Description |
|---|---|---|
| [`sparql.now()`](https://www.w3.org/TR/sparql11-query/#func-now) | `rdfnode` | Current `xsd:dateTime`, constant within a transaction. Never pushed down. |
| [`sparql.year(rdfnode)`](https://www.w3.org/TR/sparql11-query/#func-year) | `int` | Year |
| [`sparql.month(rdfnode)`](https://www.w3.org/TR/sparql11-query/#func-month) | `int` | Month (1–12) |
| [`sparql.day(rdfnode)`](https://www.w3.org/TR/sparql11-query/#func-day) | `int` | Day of the month |
| [`sparql.hours(rdfnode)`](https://www.w3.org/TR/sparql11-query/#func-hours) | `int` | Hour (0–23) |
| [`sparql.minutes(rdfnode)`](https://www.w3.org/TR/sparql11-query/#func-minutes) | `int` | Minute (0–59) |
| [`sparql.seconds(rdfnode)`](https://www.w3.org/TR/sparql11-query/#func-seconds) | `numeric` | Seconds, including fractions |
| [`sparql.timezone(rdfnode)`](https://www.w3.org/TR/sparql11-query/#func-timezone) | `rdfnode` | Timezone offset as `xsd:dayTimeDuration`. A value without a timezone raises an error. |
| [`sparql.tz(rdfnode)`](https://www.w3.org/TR/sparql11-query/#func-tz) | `rdfnode` | Timezone offset as a simple literal (`"+02:00"`, `"Z"`), or `""` if there is none |

```sql
SELECT sparql.year('"2025-05-17T14:42:37Z"^^xsd:dateTime');        -- 2025
SELECT sparql.month('"2025-05-17T14:42:37Z"^^xsd:dateTime');       -- 5
SELECT sparql.day('"2025-05-17T14:42:37Z"^^xsd:dateTime');         -- 17
SELECT sparql.hours('"2025-05-17T14:42:37Z"^^xsd:dateTime');       -- 14
SELECT sparql.minutes('"2025-05-17T14:42:37Z"^^xsd:dateTime');     -- 42
SELECT sparql.seconds('"2025-05-17T14:42:37.5Z"^^xsd:dateTime');   -- 37.500000
SELECT sparql.timezone('"2025-05-17T10:00:00+02:00"^^xsd:dateTime');
-- "PT2H"^^<http://www.w3.org/2001/XMLSchema#dayTimeDuration>
SELECT sparql.tz('"2025-05-17T10:00:00+02:00"^^xsd:dateTime');     -- "+02:00"
SELECT sparql.tz('"2025-05-17T08:00:00Z"^^xsd:dateTime');          -- "Z"
SELECT sparql.tz('"2025-05-17T08:00:00"^^xsd:dateTime');           -- ""
SELECT sparql.now();                                               -- "2026-10-04T20:25:20.960274Z"^^<http://www.w3.org/2001/XMLSchema#dateTime>
```

## Hash functions

| Function | Returns | Description |
|---|---|---|
| [`sparql.md5(rdfnode)`](https://www.w3.org/TR/sparql11-query/#func-md5) | `rdfnode` | MD5 of the lexical form, as a lowercase hexadecimal simple literal |

```sql
SELECT sparql.md5('"foo"');  -- "acbd18db4cc2f85cedef654fccc4a4d8"
```

## Non-standard functions

| Function | Returns | Description |
|---|---|---|
| `sparql.lex(rdfnode)` | `text` | Lexical form as plain PostgreSQL `text`: no quotes, language tag or datatype. Handy for casting to other types, e.g. `sparql.lex(o)::geometry`. |

```sql
SELECT sparql.lex('"foo"@es');            -- foo
SELECT sparql.lex('"foo"^^xsd:string');   -- foo
```
