\pset null NULL
\set VERBOSITY terse
SET timezone <> 'UTC';
-- Tests for inequality (<>) operator on rdfnode type -- basically
-- the same tests in rdfnode_eq but with a <> operator. Just for 
-- peace of mind :)

-- Language-tagged literals (case-insensitive)
SELECT '"foo"@EN'::rdfnode <> '"foo"@en'::rdfnode;
SELECT '"foo"@en-us'::rdfnode <> '"foo"@EN-US'::rdfnode;
SELECT '"foo"@en'::rdfnode <> '"foo"@en-us'::rdfnode;
SELECT '"café"@fr'::rdfnode <> '"café"@fr'::rdfnode;
SELECT '"café"@fr'::rdfnode <> '"cafe"@fr'::rdfnode;
SELECT '"foo"^^xsd:string'::rdfnode <> '" foo "^^xsd:string'::rdfnode;

-- Unicode escapes
SELECT '"\u0020"^^xsd:string'::rdfnode <> '" "^^xsd:string'::rdfnode;
SELECT '"\U0001F600"^^xsd:string'::rdfnode <> '"😀"^^xsd:string'::rdfnode;
SELECT '"\U0001F600"^^xsd:string'::rdfnode <> '"😀"'::rdfnode;
SELECT '"\uD834\uDD1E"^^xsd:string'::rdfnode <> '𝄞'::rdfnode;
SELECT '"\""'::rdfnode <> '"'::rdfnode;  -- True
SELECT '"\\\\u0020"'::rdfnode <> '"\\u0020"'::rdfnode;  -- False, first is two literal backslashes
SELECT '"\u0020"'::rdfnode <> '" "'::rdfnode;  -- True
SELECT '"\u0009"'::rdfnode <> E'\t'::rdfnode;  -- True

SELECT '"\uD834"^^xsd:string'::rdfnode;  -- Invalid alone
SELECT '"\uDD1E"^^xsd:string'::rdfnode;  -- Invalid alone
SELECT '"\u12"^^xsd:string'::rdfnode;  -- Too short
SELECT '"\u12GZ"^^xsd:string'::rdfnode;  -- Invalid hex digits
SELECT '"\u123456"^^xsd:string'::rdfnode;  -- Overflow (only 4 digits allowed for \u)

-- Typed literals, same datatype IRI
SELECT '"foo"^^<http://example.org/custom>'::rdfnode <> '"foo"^^<http://example.org/custom>'::rdfnode;
SELECT '"foo"^^<http://example.org/custom>'::rdfnode <> '"foo"^^xsd:string'::rdfnode;
SELECT '"foo"^^<http://invalid>'::rdfnode <> '"foo"^^<http://invalid>'::rdfnode;

-- Integer comparisons
SELECT '"42"^^xsd:int'::rdfnode <> '"42"^^<http://www.w3.org/2001/XMLSchema#int>'::rdfnode;
SELECT '"-42"^^xsd:int'::rdfnode <> '"-42"^^xsd:int'::rdfnode;
SELECT '"42"^^xsd:int'::rdfnode <> '"-42"^^xsd:int'::rdfnode;
SELECT '"42"^^xsd:int'::rdfnode <> '"42.00"^^xsd:decimal'::rdfnode;
SELECT '"42"^^xsd:int'::rdfnode <> '"42"^^xsd:integer'::rdfnode;
SELECT '"42"^^xsd:int'::rdfnode <> '"42"^^<http://www.w3.org/2001/XMLSchema#integer>'::rdfnode;
SELECT '"42"^^xsd:int'::rdfnode <> '"42.0000000000"^^xsd:double'::rdfnode;
SELECT '"42"^^xsd:int'::rdfnode <> '"42"^^xsd:short'::rdfnode;
SELECT '"42"^^xsd:int'::rdfnode <> '"42.73"^^xsd:decimal'::rdfnode;
SELECT '"42"^^xsd:int'::rdfnode <> '"42.0000000001"^^xsd:double'::rdfnode;
SELECT '"42"^^xsd:int'::rdfnode <> '"foo"^^xsd:string'::rdfnode;
SELECT '"42"^^xsd:int'::rdfnode <> '"42"^^xsd:string'::rdfnode;
SELECT '"42"^^xsd:int'::rdfnode <> '"42"^^xsd:date'::rdfnode;
SELECT '"-0"^^xsd:int'::rdfnode <> '"0"^^xsd:int'::rdfnode;
SELECT '"999999999999999999"^^xsd:integer'::rdfnode <> '"999999999999999999.0"^^xsd:decimal'::rdfnode;

-- Date and time comparisons
SELECT '"2011-10-08"^^xsd:date'::rdfnode <> '"2011-10-08"^^xsd:date'::rdfnode;
SELECT '"2011-10-08"^^xsd:date'::rdfnode <> '"2011-10-08"^^xsd:string'::rdfnode;
SELECT '"2011-10-08"^^xsd:date'::rdfnode <> '"2011-10-08"'::rdfnode;
SELECT '"2011-10-08"^^xsd:date'::rdfnode <> '"2011-10-11"^^xsd:date'::rdfnode;
SELECT '"2011-10-08"^^xsd:date'::rdfnode <> '""^^xsd:date'::rdfnode;
SELECT '"0001-01-01"^^xsd:date'::rdfnode <> '"0001-01-01"^^xsd:date'::rdfnode;

-- Invalid datetime
SELECT '"2025-13-01T12:00:00"^^xsd:dateTime'::rdfnode <> '"2025-13-01T12:00:00"^^xsd:dateTime'::rdfnode;
SELECT '"2025-04-25T25:00:00Z"^^xsd:dateTime'::rdfnode <> '"2025-04-25T25:00:00Z"^^xsd:dateTime'::rdfnode;
SELECT '"1.0E308"^^xsd:double'::rdfnode <> '"1.0E308"^^xsd:double'::rdfnode;
SELECT '"invalid"^^xsd:dateTime'::rdfnode <> '"invalid"^^xsd:dateTime'::rdfnode;

-- Time
SELECT '"18:44:38"^^xsd:time'::rdfnode <> '"18:44:38"^^xsd:time'::rdfnode;
SELECT '"18:44:38"^^xsd:time'::rdfnode <> '"18:44:38"^^<http://www.w3.org/2001/XMLSchema#time>'::rdfnode;
SELECT '"18:44:38"^^xsd:time'::rdfnode <> '"20:44:38"^^xsd:time'::rdfnode;
SELECT '"18:44:38"^^xsd:time'::rdfnode <> '"18:44:38"'::rdfnode;
-- timezone-naive equality
SELECT '"10:00:00"^^xsd:time'::rdfnode <> '"10:00:00"^^xsd:time'::rdfnode;
SELECT '"10:00:00"^^xsd:time'::rdfnode <> '"11:00:00"^^xsd:time'::rdfnode;
-- timezone-aware equality
SELECT '"10:00:00+02:00"^^xsd:time'::rdfnode <> '"10:00:00+02:00"^^xsd:time'::rdfnode;
SELECT '"10:00:00+02:00"^^xsd:time'::rdfnode <> '"11:00:00+02:00"^^xsd:time'::rdfnode;
-- UTC variants
SELECT '"10:00:00Z"^^xsd:time'::rdfnode <> '"10:00:00+00:00"^^xsd:time'::rdfnode;
-- mixed tz/no-tz
SELECT '"10:00:00"^^xsd:time'::rdfnode <> '"10:00:00+02:00"^^xsd:time'::rdfnode;
SELECT '"10:00:00+02:00"^^xsd:time'::rdfnode <> '"10:00:00"^^xsd:time'::rdfnode;

-- String comparison fallbacks
SELECT '"2025-04-25 18:44:38"^^xsd:dateTime'::rdfnode <> '"2025-04-25 18:44:38"^^xsd:dateTime'::rdfnode;
SELECT '"2025-04-25 18:44:38"^^xsd:dateTime'::rdfnode <> '"2025-04-25 18:44:38"^^<http://www.w3.org/2001/XMLSchema#time>'::rdfnode;
SELECT '"2025-04-25T18:44:38.149101Z"^^xsd:dateTime'::rdfnode <> '"2025-04-25T18:44:38.149101Z"^^xsd:dateTime'::rdfnode;
SELECT '"2025-04-25T18:44:38.149101Z"^^xsd:dateTime'::rdfnode <> '"2025-04-25T18:44:38.149101Z"^^<http://www.w3.org/2001/XMLSchema#dateTime>'::rdfnode;
SELECT '"2025-04-25T18:44:38"^^xsd:dateTime'::rdfnode <> '"2025-04-25T18:44:38Z"^^xsd:dateTime'::rdfnode;
SELECT '"2025-04-25T18:44:38+00:00"^^xsd:dateTime'::rdfnode <> '"2025-04-25T18:44:38Z"^^xsd:dateTime'::rdfnode; -- Both are TZ-aware and equal in UTC; +00:00 and Z are the same offset
SELECT '"2025-04-25T12:00:00+02:00"^^xsd:dateTime'::rdfnode <> '"2025-04-25T10:00:00Z"^^xsd:dateTime'::rdfnode; -- Different offsets, same UTC instant
SELECT '"2025-04-25T12:00:00+02:00"^^xsd:dateTime'::rdfnode <> '"2025-04-25T12:00:00Z"^^xsd:dateTime'::rdfnode; -- Same clock time, different UTC instant
SELECT '"2025-04-25T12:00:00"^^xsd:dateTime'::rdfnode <> '"2025-04-25T12:00:00"^^xsd:dateTime'::rdfnode; -- Both naive: equal
SELECT '"2025-04-25T12:00:00"^^xsd:dateTime'::rdfnode <> '"2025-04-25T13:00:00"^^xsd:dateTime'::rdfnode; -- Both naive, different times
SELECT '"2025-04-25T12:00:00"^^xsd:dateTime'::rdfnode <> '"2025-04-25T12:00:00Z"^^xsd:dateTime'::rdfnode; -- The canonical mixed-tz case

-- === RDF 1.1 §17.4.1.7: term equality of identical ill-typed literals ===
-- These all must return TRUE, not raise type errors.
SELECT '"forty-two"^^xsd:int'::rdfnode <> '"forty-two"^^xsd:int'::rdfnode;        -- t
SELECT '"2025-13-01"^^xsd:date'::rdfnode <> '"2025-13-01"^^xsd:date'::rdfnode;    -- t
SELECT '"25:00:00"^^xsd:time'::rdfnode <> '"25:00:00"^^xsd:time'::rdfnode;        -- t
SELECT '"nAn"^^xsd:double'::rdfnode <> '"nAn"^^xsd:double'::rdfnode;              -- t
SELECT '""^^xsd:integer'::rdfnode <> '""^^xsd:integer'::rdfnode;                  -- t
SELECT '"NaN"^^xsd:double'::rdfnode <> '"NaN"^^xsd:double'::rdfnode;              -- f
SELECT '"NaN"^^xsd:double'::rdfnode <> '"4.2"^^xsd:double'::rdfnode;              -- f
SELECT '"4.2"^^xsd:double'::rdfnode <> '"NaN"^^xsd:double'::rdfnode;              -- f

-- Datatype prefix expansion: these are byte-equal after normalization
SELECT '"42"^^xsd:int'::rdfnode 
     <> '"42"^^<http://www.w3.org/2001/XMLSchema#int>'::rdfnode;                  -- t

-- Different ill-typed literals: behavior depends on policy
-- (currently raises ERROR; that's allowed per SPARQL §17.3.1)
-- SELECT '"foo"^^xsd:int'::rdfnode <> '"bar"^^xsd:int'::rdfnode;

-- Datatype mismatch with ill-typed values: should return f, not error
SELECT '"42"^^xsd:int'::rdfnode <> '"42"^^xsd:date'::rdfnode;                     -- f
SELECT '"invalid"^^xsd:dateTime'::rdfnode <> '"invalid"^^xsd:time'::rdfnode;      -- f

-- Boolean comparisons
SELECT '"true"^^xsd:boolean'::rdfnode <> '"false"^^xsd:boolean'::rdfnode;
SELECT '"false"^^xsd:boolean'::rdfnode <> '"true"^^xsd:boolean'::rdfnode;
SELECT '"true"^^xsd:boolean'::rdfnode <> '"true"^^xsd:boolean'::rdfnode;
SELECT '"false"^^xsd:boolean'::rdfnode <> '"false"^^xsd:boolean'::rdfnode;

-- Durations
SELECT '"P1Y"^^xsd:duration'::rdfnode <> '"-P1Y"^^xsd:duration'::rdfnode;
SELECT '"-P1Y"^^xsd:duration'::rdfnode <> '"P1Y"^^xsd:duration'::rdfnode;
SELECT '"-P1Y"^^xsd:duration'::rdfnode <> '"-P1Y"^^xsd:duration'::rdfnode;
SELECT '"-P1Y"^^xsd:duration'::rdfnode <> '"-P2Y"^^xsd:duration'::rdfnode;
SELECT '"P7D"^^xsd:duration'::rdfnode <> '"P1W"^^xsd:duration'::rdfnode;
SELECT '"P1M"^^xsd:duration'::rdfnode <> '"P1M"^^xsd:duration'::rdfnode;
SELECT '"PT0S"^^xsd:duration'::rdfnode <> '"P0D"^^xsd:duration'::rdfnode;