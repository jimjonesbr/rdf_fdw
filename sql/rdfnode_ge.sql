-- Tests for greater-than-or-equal (>=) operator on rdfnode type
\pset null NULL

-- Numeric comparisons
SELECT '"1"^^xsd:int'::rdfnode >= '"2"^^xsd:int'::rdfnode;
SELECT '"1"^^xsd:int'::rdfnode >= '"1"^^xsd:int'::rdfnode;
SELECT '"42.0"^^xsd:decimal'::rdfnode >= '"42.1"^^xsd:decimal'::rdfnode;
SELECT '"42.0"^^xsd:double'::rdfnode >= '"42.0"^^xsd:decimal'::rdfnode;
SELECT '"0.0"^^xsd:decimal'::rdfnode >= '"-0.0"^^xsd:decimal'::rdfnode;
SELECT '"1e308"^^xsd:double'::rdfnode >= '"INF"^^xsd:double'::rdfnode;
SELECT '"42"^^xsd:int'::rdfnode >= '"43"^^xsd:short'::rdfnode;
SELECT '"42"^^xsd:byte'::rdfnode >= '"42"^^xsd:int'::rdfnode;

-- Date
SELECT '"2020-01-01"^^xsd:date'::rdfnode >= '"2021-01-01"^^xsd:date'::rdfnode;

-- Datetime
SELECT '"2025-04-25T18:45:00"^^xsd:dateTime'::rdfnode >= '"2025-04-25T18:45:00"^^xsd:dateTime'::rdfnode;
SELECT '"2025-04-25T14:00:00+02:00"^^xsd:dateTime'::rdfnode >= '"2025-04-25T12:00:00Z"^^xsd:dateTime'::rdfnode;
SELECT '"2025-04-25T12:00:00"^^xsd:dateTime'::rdfnode >= '"2025-04-25T12:00:00Z"^^xsd:dateTime'::rdfnode;

-- Time
SELECT '"10:00:00"^^xsd:time'::rdfnode >= '"11:00:00"^^xsd:time'::rdfnode;
SELECT '"11:00:00"^^xsd:time'::rdfnode >= '"10:00:00"^^xsd:time'::rdfnode;
-- timezone-aware ordering
SELECT '"10:00:00+02:00"^^xsd:time'::rdfnode >= '"09:00:00+02:00"^^xsd:time'::rdfnode;
SELECT '"09:00:00+02:00"^^xsd:time'::rdfnode >= '"10:00:00+02:00"^^xsd:time'::rdfnode;
-- mixed tz/no-tz
SELECT '"10:00:00+02:00"^^xsd:time'::rdfnode >= '"10:00:00"^^xsd:time'::rdfnode;
SELECT '"10:00:00"^^xsd:time'::rdfnode >= '"10:00:00+02:00"^^xsd:time'::rdfnode;

-- String and simple literals
SELECT '"abc"^^xsd:string'::rdfnode >= '"abd"^^xsd:string'::rdfnode;
SELECT '"abc"^^xsd:string'::rdfnode >= '"abc"^^xsd:string'::rdfnode;
SELECT '"a"'::rdfnode >= '"b"'::rdfnode;
SELECT '""^^xsd:string'::rdfnode >= '"a"^^xsd:string'::rdfnode;
SELECT '"\u00E9"^^xsd:string'::rdfnode >= '"\u00EA"^^xsd:string'::rdfnode;

-- Language-tagged literals (cannot be compared)
SELECT '"a"@en'::rdfnode >= '"b"@en'::rdfnode;
SELECT '"chat"@en'::rdfnode >= '"chat"@fr'::rdfnode;
SELECT '"abc"@de'::rdfnode >= '"abc"@en'::rdfnode;
SELECT '"abc"@en'::rdfnode >= '"abc"@EN'::rdfnode;

-- xsd:anyURI comparisons
SELECT '"http://a"^^xsd:anyURI'::rdfnode >= '"http://b"^^xsd:anyURI'::rdfnode;
SELECT '"http://a"^^xsd:anyURI'::rdfnode >= '"http://a"^^xsd:anyURI'::rdfnode;
SELECT '""^^xsd:anyURI'::rdfnode >= '"http://b"^^xsd:anyURI'::rdfnode;
SELECT '"http://\u00E9"^^xsd:anyURI'::rdfnode >= '"http://\u00EA"^^xsd:anyURI'::rdfnode;

-- Incompatible datatype comparisons (cannot be compared)
SELECT '"41"'::rdfnode >= '"42"^^xsd:int'::rdfnode;
SELECT '"abc"^^xsd:string'::rdfnode >= '"2020-01-01"^^xsd:date'::rdfnode;
SELECT '"2020-01-01"^^xsd:date'::rdfnode >= '"abc"^^xsd:string'::rdfnode;
SELECT '"41"^^xsd:int'::rdfnode >= '"42"^^ex:customDatatype'::rdfnode;

-- NaN and infinities
SELECT '"42"^^xsd:double'::rdfnode >= '"NaN"^^xsd:double'::rdfnode;
SELECT '"NaN"^^xsd:double'::rdfnode >= '"NaN"^^xsd:double'::rdfnode;
SELECT '"NaN"^^xsd:double'::rdfnode >= '"42"^^xsd:double'::rdfnode;
SELECT '"999999999"^^xsd:double'::rdfnode >= '"INF"^^xsd:double'::rdfnode;
SELECT '"-999999999"^^xsd:double'::rdfnode >= '"-INF"^^xsd:double'::rdfnode;

-- Boolean comparisons
SELECT '"true"^^xsd:boolean'::rdfnode >= '"false"^^xsd:boolean'::rdfnode;
SELECT '"false"^^xsd:boolean'::rdfnode >= '"true"^^xsd:boolean'::rdfnode;
SELECT '"true"^^xsd:boolean'::rdfnode >= '"true"^^xsd:boolean'::rdfnode;
SELECT '"false"^^xsd:boolean'::rdfnode >= '"false"^^xsd:boolean'::rdfnode;

-- Durations
SELECT '"P1Y"^^xsd:duration'::rdfnode >= '"-P1Y"^^xsd:duration'::rdfnode;
SELECT '"-P1Y"^^xsd:duration'::rdfnode >= '"P1Y"^^xsd:duration'::rdfnode;
SELECT '"-P1Y"^^xsd:duration'::rdfnode >= '"-P1Y"^^xsd:duration'::rdfnode;
SELECT '"-P1Y"^^xsd:duration'::rdfnode >= '"-P2Y"^^xsd:duration'::rdfnode;
SELECT '"P7D"^^xsd:duration'::rdfnode >= '"P1W"^^xsd:duration'::rdfnode;
SELECT '"P1M"^^xsd:duration'::rdfnode >= '"P1M"^^xsd:duration'::rdfnode;
SELECT '"PT0S"^^xsd:duration'::rdfnode >= '"P0D"^^xsd:duration'::rdfnode;
SELECT '"PT1H"^^xsd:duration'::rdfnode >= '"P1D"^^xsd:duration'::rdfnode;