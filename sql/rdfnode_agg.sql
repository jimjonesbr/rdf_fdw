-- ==========================================
-- SPARQL SUM() Aggregate Tests
-- ==========================================

-- Test 1: Sum of integers → should return integer (not decimal)
WITH j (val) AS (
    VALUES
        ('"10"^^<http://www.w3.org/2001/XMLSchema#integer>'::rdfnode),
        ('"20"^^<http://www.w3.org/2001/XMLSchema#integer>'::rdfnode),
        ('"30"^^<http://www.w3.org/2001/XMLSchema#integer>'::rdfnode)
)
SELECT sparql.sum(val) FROM j;

-- Test 2: Sum of decimals → should return decimal
WITH j (val) AS (
    VALUES
        ('"10.5"^^<http://www.w3.org/2001/XMLSchema#decimal>'::rdfnode),
        ('"20.3"^^<http://www.w3.org/2001/XMLSchema#decimal>'::rdfnode),
        ('"30.2"^^<http://www.w3.org/2001/XMLSchema#decimal>'::rdfnode)
)
SELECT sparql.sum(val) FROM j;

-- Test 3: Sum of integer + decimal → should return decimal (type promotion)
WITH j (val) AS (
    VALUES
        ('"10"^^<http://www.w3.org/2001/XMLSchema#integer>'::rdfnode),
        ('"20.5"^^<http://www.w3.org/2001/XMLSchema#decimal>'::rdfnode),
        ('"30"^^<http://www.w3.org/2001/XMLSchema#integer>'::rdfnode)
)
SELECT sparql.sum(val) FROM j;

-- Test 4: Sum of decimal + float → should return float (type promotion)
WITH j (val) AS (
    VALUES
        ('"10.5"^^<http://www.w3.org/2001/XMLSchema#decimal>'::rdfnode),
        ('"20.3"^^<http://www.w3.org/2001/XMLSchema#float>'::rdfnode),
        ('"5"^^<http://www.w3.org/2001/XMLSchema#integer>'::rdfnode)
)
SELECT sparql.sum(val) FROM j;

-- Test 5: Sum of integer + decimal + double → should return double (highest type wins)
WITH j (val) AS (
    VALUES
        ('"10.4"^^<http://www.w3.org/2001/XMLSchema#decimal>'::rdfnode),
        ('"20"^^<http://www.w3.org/2001/XMLSchema#integer>'::rdfnode),
        ('"30.4"^^<http://www.w3.org/2001/XMLSchema#double>'::rdfnode)
)
SELECT sparql.sum(val) FROM j;

-- Test 6: Sum of single value → should preserve original type
WITH j (val) AS (
    VALUES
        ('"42"^^<http://www.w3.org/2001/XMLSchema#integer>'::rdfnode)
)
SELECT sparql.sum(val) FROM j;

-- Test 7: Sum with integer subtypes (xsd:int, xsd:long, etc.) → should return integer
WITH j (val) AS (
    VALUES
        ('"10"^^<http://www.w3.org/2001/XMLSchema#int>'::rdfnode),
        ('"20"^^<http://www.w3.org/2001/XMLSchema#long>'::rdfnode),
        ('"30"^^<http://www.w3.org/2001/XMLSchema#integer>'::rdfnode)
)
SELECT sparql.sum(val) FROM j;

-- Test 8: Sum with all four numeric types → should promote to double
WITH j (val) AS (
    VALUES
        ('"10"^^<http://www.w3.org/2001/XMLSchema#integer>'::rdfnode),
        ('"5.5"^^<http://www.w3.org/2001/XMLSchema#decimal>'::rdfnode),
        ('"2.5"^^<http://www.w3.org/2001/XMLSchema#float>'::rdfnode),
        ('"3.0"^^<http://www.w3.org/2001/XMLSchema#double>'::rdfnode)
)
SELECT sparql.sum(val) FROM j;

-- Test 9: Sum with integer + float (type promotion)
WITH j (val) AS (
    VALUES
        ('"100"^^<http://www.w3.org/2001/XMLSchema#integer>'::rdfnode),
        ('"0.1"^^<http://www.w3.org/2001/XMLSchema#float>'::rdfnode)
)
SELECT sparql.sum(val) FROM j;

-- Test 10: Sum with negative integers
WITH j (val) AS (
    VALUES
        ('"10"^^<http://www.w3.org/2001/XMLSchema#integer>'::rdfnode),
        ('"-5"^^<http://www.w3.org/2001/XMLSchema#integer>'::rdfnode),
        ('"-3"^^<http://www.w3.org/2001/XMLSchema#integer>'::rdfnode)
)
SELECT sparql.sum(val) FROM j;

-- Test 11: Sum resulting in negative value
WITH j (val) AS (
    VALUES
        ('"5"^^<http://www.w3.org/2001/XMLSchema#integer>'::rdfnode),
        ('"-20"^^<http://www.w3.org/2001/XMLSchema#integer>'::rdfnode)
)
SELECT sparql.sum(val) FROM j;

-- Test 12: Sum with zero values
WITH j (val) AS (
    VALUES
        ('"0"^^<http://www.w3.org/2001/XMLSchema#integer>'::rdfnode),
        ('"10"^^<http://www.w3.org/2001/XMLSchema#integer>'::rdfnode),
        ('"0"^^<http://www.w3.org/2001/XMLSchema#integer>'::rdfnode)
)
SELECT sparql.sum(val) FROM j;

-- Test 13: Sum resulting in zero
WITH j (val) AS (
    VALUES
        ('"10"^^<http://www.w3.org/2001/XMLSchema#integer>'::rdfnode),
        ('"-10"^^<http://www.w3.org/2001/XMLSchema#integer>'::rdfnode)
)
SELECT sparql.sum(val) FROM j;

-- Test 14: Sum with NULL values → should skip NULLs
WITH j (val) AS (
    VALUES
        ('"10"^^<http://www.w3.org/2001/XMLSchema#integer>'::rdfnode),
        (NULL::rdfnode),
        ('"30"^^<http://www.w3.org/2001/XMLSchema#integer>'::rdfnode)
)
SELECT sparql.sum(val) FROM j;

-- Test 15: Sum of all NULLs → should return "0"^^xsd:integer per SPARQL 1.1
WITH j (val) AS (
    VALUES
        (NULL::rdfnode),
        (NULL::rdfnode),
        (NULL::rdfnode)
)
SELECT sparql.sum(val) FROM j;

-- Test 16: Sum of empty set (no rows) → should return "0"^^xsd:integer per SPARQL 1.1
WITH j (val) AS (
    VALUES
        ('"10"^^<http://www.w3.org/2001/XMLSchema#integer>'::rdfnode)
)
SELECT sparql.sum(val) FROM j WHERE val IS NULL;

-- ==========================================
-- SPARQL AVG() Aggregate Tests
-- ==========================================

-- Test 17: Average of integers → should return integer
WITH j (val) AS (
    VALUES
        ('"10"^^<http://www.w3.org/2001/XMLSchema#integer>'::rdfnode),
        ('"20"^^<http://www.w3.org/2001/XMLSchema#integer>'::rdfnode),
        ('"30"^^<http://www.w3.org/2001/XMLSchema#integer>'::rdfnode)
)
SELECT sparql.avg(val) FROM j;

-- Test 18: Average of decimals → should return decimal
WITH j (val) AS (
    VALUES
        ('"10.5"^^<http://www.w3.org/2001/XMLSchema#decimal>'::rdfnode),
        ('"20.3"^^<http://www.w3.org/2001/XMLSchema#decimal>'::rdfnode),
        ('"30.2"^^<http://www.w3.org/2001/XMLSchema#decimal>'::rdfnode)
)
SELECT sparql.avg(val) FROM j;

-- Test 19: Average of integer + decimal → should return decimal (type promotion)
WITH j (val) AS (
    VALUES
        ('"10"^^<http://www.w3.org/2001/XMLSchema#integer>'::rdfnode),
        ('"20.5"^^<http://www.w3.org/2001/XMLSchema#decimal>'::rdfnode),
        ('"30"^^<http://www.w3.org/2001/XMLSchema#integer>'::rdfnode)
)
SELECT sparql.avg(val) FROM j;

-- Test 20: Average of single value → should preserve original type
WITH j (val) AS (
    VALUES
        ('"42"^^<http://www.w3.org/2001/XMLSchema#decimal>'::rdfnode)
)
SELECT sparql.avg(val) FROM j;

-- Test 21: Average with all four numeric types → should promote to double
WITH j (val) AS (
    VALUES
        ('"12"^^<http://www.w3.org/2001/XMLSchema#integer>'::rdfnode),
        ('"8.0"^^<http://www.w3.org/2001/XMLSchema#decimal>'::rdfnode),
        ('"4.0"^^<http://www.w3.org/2001/XMLSchema#float>'::rdfnode),
        ('"16.0"^^<http://www.w3.org/2001/XMLSchema#double>'::rdfnode)
)
SELECT sparql.avg(val) FROM j;

-- Test 22: Average with negative decimals
WITH j (val) AS (
    VALUES
        ('"10.5"^^<http://www.w3.org/2001/XMLSchema#decimal>'::rdfnode),
        ('"-5.5"^^<http://www.w3.org/2001/XMLSchema#decimal>'::rdfnode),
        ('"-2.0"^^<http://www.w3.org/2001/XMLSchema#decimal>'::rdfnode)
)
SELECT sparql.avg(val) FROM j;

-- Test 23: Average with zero in the mix
WITH j (val) AS (
    VALUES
        ('"0.0"^^<http://www.w3.org/2001/XMLSchema#decimal>'::rdfnode),
        ('"10.0"^^<http://www.w3.org/2001/XMLSchema#decimal>'::rdfnode),
        ('"20.0"^^<http://www.w3.org/2001/XMLSchema#decimal>'::rdfnode)
)
SELECT sparql.avg(val) FROM j;

-- Test 24: Average with NULL values → should skip NULLs
WITH j (val) AS (
    VALUES
        ('"10"^^<http://www.w3.org/2001/XMLSchema#integer>'::rdfnode),
        (NULL::rdfnode),
        ('"30"^^<http://www.w3.org/2001/XMLSchema#integer>'::rdfnode)
)
SELECT sparql.avg(val) FROM j;

-- Test 25: Average of all NULLs → should return "0"^^xsd:integer per SPARQL 1.1
WITH j (val) AS (
    VALUES
        (NULL::rdfnode),
        (NULL::rdfnode)
)
SELECT sparql.avg(val) FROM j;

-- Test 26: Average of empty set (no rows) → should return "0"^^xsd:integer per SPARQL 1.1
WITH j (val) AS (
    VALUES
        ('"10"^^<http://www.w3.org/2001/XMLSchema#integer>'::rdfnode)
)
SELECT sparql.avg(val) FROM j WHERE val IS NULL;

-- ==========================================
-- SPARQL MIN() Aggregate Tests
-- ==========================================

-- Test 27: Minimum of integers → should return integer
WITH j (val) AS (
    VALUES
        ('"30"^^<http://www.w3.org/2001/XMLSchema#integer>'::rdfnode),
        ('"10"^^<http://www.w3.org/2001/XMLSchema#integer>'::rdfnode),
        ('"20"^^<http://www.w3.org/2001/XMLSchema#integer>'::rdfnode)
)
SELECT sparql.min(val) FROM j;

-- Test 28: Minimum of decimals → should return decimal
WITH j (val) AS (
    VALUES
        ('"30.2"^^<http://www.w3.org/2001/XMLSchema#decimal>'::rdfnode),
        ('"10.5"^^<http://www.w3.org/2001/XMLSchema#decimal>'::rdfnode),
        ('"20.3"^^<http://www.w3.org/2001/XMLSchema#decimal>'::rdfnode)
)
SELECT sparql.min(val) FROM j;

-- Test 29: Minimum of integer + decimal → should preserve type of minimum value
WITH j (val) AS (
    VALUES
        ('"30"^^<http://www.w3.org/2001/XMLSchema#integer>'::rdfnode),
        ('"10.5"^^<http://www.w3.org/2001/XMLSchema#decimal>'::rdfnode),
        ('"20"^^<http://www.w3.org/2001/XMLSchema#integer>'::rdfnode)
)
SELECT sparql.min(val) FROM j;

-- Test 30: Minimum with float values
WITH j (val) AS (
    VALUES
        ('"30.5"^^<http://www.w3.org/2001/XMLSchema#float>'::rdfnode),
        ('"10.1"^^<http://www.w3.org/2001/XMLSchema#float>'::rdfnode),
        ('"20.3"^^<http://www.w3.org/2001/XMLSchema#float>'::rdfnode)
)
SELECT sparql.min(val) FROM j;

-- Test 31: Minimum with mixed types → should preserve type of minimum value
WITH j (val) AS (
    VALUES
        ('"30"^^<http://www.w3.org/2001/XMLSchema#integer>'::rdfnode),
        ('"5.5"^^<http://www.w3.org/2001/XMLSchema#decimal>'::rdfnode),
        ('"10.0"^^<http://www.w3.org/2001/XMLSchema#float>'::rdfnode),
        ('"20.0"^^<http://www.w3.org/2001/XMLSchema#double>'::rdfnode)
)
SELECT sparql.min(val) FROM j;

-- Test 32: Minimum of single value → should preserve original type
WITH j (val) AS (
    VALUES
        ('"42"^^<http://www.w3.org/2001/XMLSchema#integer>'::rdfnode)
)
SELECT sparql.min(val) FROM j;

-- Test 33: Minimum with negative integers
WITH j (val) AS (
    VALUES
        ('"10"^^<http://www.w3.org/2001/XMLSchema#integer>'::rdfnode),
        ('"-5"^^<http://www.w3.org/2001/XMLSchema#integer>'::rdfnode),
        ('"3"^^<http://www.w3.org/2001/XMLSchema#integer>'::rdfnode)
)
SELECT sparql.min(val) FROM j;

-- Test 34: Minimum with all negative values
WITH j (val) AS (
    VALUES
        ('"-10"^^<http://www.w3.org/2001/XMLSchema#integer>'::rdfnode),
        ('"-5"^^<http://www.w3.org/2001/XMLSchema#integer>'::rdfnode),
        ('"-20"^^<http://www.w3.org/2001/XMLSchema#integer>'::rdfnode)
)
SELECT sparql.min(val) FROM j;

-- Test 35: Minimum with zero values
WITH j (val) AS (
    VALUES
        ('"0"^^<http://www.w3.org/2001/XMLSchema#integer>'::rdfnode),
        ('"10"^^<http://www.w3.org/2001/XMLSchema#integer>'::rdfnode),
        ('"-5"^^<http://www.w3.org/2001/XMLSchema#integer>'::rdfnode)
)
SELECT sparql.min(val) FROM j;

-- Test 36: Minimum with NULL values → should skip NULLs
WITH j (val) AS (
    VALUES
        ('"30"^^<http://www.w3.org/2001/XMLSchema#integer>'::rdfnode),
        (NULL::rdfnode),
        ('"10"^^<http://www.w3.org/2001/XMLSchema#integer>'::rdfnode),
        (NULL::rdfnode),
        ('"20"^^<http://www.w3.org/2001/XMLSchema#integer>'::rdfnode)
)
SELECT sparql.min(val) FROM j;

-- Test 37: Minimum of all NULLs → should return NULL (no values to select from)
WITH j (val) AS (
    VALUES
        (NULL::rdfnode),
        (NULL::rdfnode),
        (NULL::rdfnode)
)
SELECT sparql.min(val) FROM j;

-- Test 38: Minimum of empty set (no rows) → should return NULL (no rows to aggregate)
WITH j (val) AS (
    VALUES
        ('"10"^^<http://www.w3.org/2001/XMLSchema#integer>'::rdfnode)
)
SELECT sparql.min(val) FROM j WHERE val IS NULL;

-- Test 39: Minimum with equal values → should preserve type
WITH j (val) AS (
    VALUES
        ('"10"^^<http://www.w3.org/2001/XMLSchema#integer>'::rdfnode),
        ('"10.0"^^<http://www.w3.org/2001/XMLSchema#decimal>'::rdfnode),
        ('"10"^^<http://www.w3.org/2001/XMLSchema#integer>'::rdfnode)
)
SELECT sparql.min(val) FROM j;

-- ==========================================
-- Error Cases
-- ==========================================

-- Test 40: SUM on non-numeric rdfnode → should error
WITH j (val) AS (
    VALUES
        ('"not-a-number"^^<http://www.w3.org/2001/XMLSchema#string>'::rdfnode)
)
SELECT sparql.sum(val) FROM j;

-- Test 41: AVG on non-numeric rdfnode → should error
WITH j (val) AS (
    VALUES
        ('"2023-01-01"^^<http://www.w3.org/2001/XMLSchema#date>'::rdfnode)
)
SELECT sparql.avg(val) FROM j;

-- Test 42: SUM with mixed numeric and non-numeric → should error
WITH j (val) AS (
    VALUES
        ('"10"^^<http://www.w3.org/2001/XMLSchema#integer>'::rdfnode),
        ('"text"^^<http://www.w3.org/2001/XMLSchema#string>'::rdfnode)
)
SELECT sparql.sum(val) FROM j;

-- Test 43: MIN on non-numeric rdfnode → should error
WITH j (val) AS (
    VALUES
        ('"not-a-number"^^<http://www.w3.org/2001/XMLSchema#string>'::rdfnode)
)
SELECT sparql.min(val) FROM j;
