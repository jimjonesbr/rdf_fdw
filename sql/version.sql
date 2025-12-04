-- Test rdf_fdw_version() returns a non-empty string
SELECT length(rdf_fdw_version()) > 0 AS version_exists;

-- Test rdf_fdw_version() contains expected components
SELECT 
    rdf_fdw_version() ~ 'rdf_fdw\s+[0-9]+\.[0-9]+' AS has_rdf_fdw_version,
    rdf_fdw_version() ~ 'PostgreSQL\s+[0-9]+' AS has_postgresql_version,
    rdf_fdw_version() ~ 'libxml\s+[0-9]+\.[0-9]+' AS has_libxml_version,
    rdf_fdw_version() ~ 'librdf\s+[0-9]+\.[0-9]+' AS has_librdf_version,
    rdf_fdw_version() ~ 'libcurl\s+[0-9]+\.[0-9]+' AS has_libcurl_version;

-- Test rdf_fdw_settings() C function returns a non-empty string
SELECT length(rdf_fdw_settings()) > 0 AS settings_exists;

-- Test rdf_fdw_settings() C function contains expected core components
SELECT 
    rdf_fdw_settings() ~ 'rdf_fdw\s+[0-9]+\.[0-9]+' AS has_rdf_fdw,
    rdf_fdw_settings() ~ 'PostgreSQL\s+[0-9]+' AS has_postgresql,
    rdf_fdw_settings() ~ 'libxml\s+[0-9]+\.[0-9]+' AS has_libxml,
    rdf_fdw_settings() ~ 'librdf\s+[0-9]+\.[0-9]+' AS has_librdf,
    rdf_fdw_settings() ~ 'libcurl\s+[0-9]+\.[0-9]+' AS has_libcurl;

-- Test rdf_fdw_settings view returns expected components
SELECT component, version IS NOT NULL AS has_version
FROM rdf_fdw_settings
ORDER BY component COLLATE "C" DESC;

-- Test that rdf_fdw_settings view returns core components
SELECT 
    COUNT(*) >= 5 AS has_minimum_components,
    COUNT(*) FILTER (WHERE component = 'rdf_fdw') = 1 AS has_rdf_fdw,
    COUNT(*) FILTER (WHERE component = 'PostgreSQL') = 1 AS has_postgresql,
    COUNT(*) FILTER (WHERE component = 'libxml') = 1 AS has_libxml,
    COUNT(*) FILTER (WHERE component = 'librdf') = 1 AS has_librdf,
    COUNT(*) FILTER (WHERE component = 'libcurl') = 1 AS has_libcurl
FROM rdf_fdw_settings;
