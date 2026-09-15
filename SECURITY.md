# Security Policy

## Reporting a Vulnerability

Please **do not report security vulnerabilities through public GitHub issues**.
Use GitHub's private vulnerability reporting instead: go to the
[Security tab](https://github.com/jimjonesbr/rdf_fdw/security) and click
**Report a vulnerability**, or write to jim.jones@uni-muenster.de.

It helps if you can include the `rdf_fdw`, PostgreSQL, libcurl and libxml2
versions in use, the server and foreign table options involved, and the SQL
needed to reproduce the problem — with any real credentials redacted.

`rdf_fdw` is maintained by one person alongside other work. You will get an
answer as soon as I can manage, and I will keep you posted on the progress of a
fix.

## Supported Versions

Fixes are made on the `main` branch and go out in the next release; there are no
backports to earlier ones. If you are running an older version, the first step
is to upgrade.

## What Counts as a Vulnerability

`rdf_fdw` treats a remote SPARQL endpoint as untrusted. Anything it sends back —
response bodies, headers, redirects, error pages — must not be able to crash the
backend, corrupt data, exhaust server resources, or leak the credentials stored
in a `USER MAPPING`. This holds even for an endpoint you trust, since it may be
compromised or impersonated. Likewise, a user who can query a foreign table
should not be able to bend the generated SPARQL beyond what the pushdown rules
intend, or write through a server marked `readonly`.

Setting up a foreign server, on the other hand, already requires privileges that
allow a lot within the database, so pointing `rdf_fdw` at a deliberately
malicious endpoint is not in itself a vulnerability. Bugs in PostgreSQL, libcurl
or libxml2 belong to those projects — though `rdf_fdw` using them unsafely
belongs here.

Fixes are released before the details are published, and the
[CHANGELOG](CHANGELOG.md) credits reporters by name unless they prefer
otherwise.
