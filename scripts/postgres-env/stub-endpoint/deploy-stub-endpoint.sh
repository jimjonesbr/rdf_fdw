#!/bin/bash

# Deploys a stub SPARQL endpoint that serves canned SPARQL XML results.
#
# The triplestores deployed by the other scripts in this directory all answer
# correctly, which is exactly why they cannot cover what rdf_fdw does with a
# malformed or hostile response. A real endpoint never repeats a variable
# inside a single <result>, for instance, so the only way to test that the
# extension survives one is to serve the response ourselves.
#
# The responses are static, so nginx serves them straight from disk. rdf_fdw
# sends SPARQL SELECT queries as POST, which a static file server answers with
# 405, hence the error_page directive below that serves the file anyway.

NETWORK_NAME=pgnet
CONTAINER_NAME=stub-endpoint
CONTAINER_IP=172.19.42.102

echo -e "\n== Deploying stub SPARQL endpoint ==\n"

podman stop $CONTAINER_NAME 2>/dev/null || true
podman rm $CONTAINER_NAME 2>/dev/null || true

cat > /tmp/stub-endpoint.conf <<EOF
server {
    listen 80;
    default_type application/sparql-results+xml;

    location / {
        root /usr/share/nginx/html;
        # rdf_fdw sends SELECT queries as POST; serve the static file anyway
        error_page 405 =200 \$uri;
    }

    # A redirect the client is not configured to follow. libcurl reports the
    # transfer as successful and hands back the 302, which is not a result.
    location = /redirect {
        return 302 /single-binding.xml;
    }

    # A 3xx that carries no body at all, so nothing reaches the XML parser to
    # fail on and the request looks like it succeeded.
    location = /not-modified {
        return 304;
    }
}
EOF

XML_HEAD='<?xml version="1.0"?><sparql xmlns="http://www.w3.org/2005/sparql-results#">'

# One <result> carrying 400 bindings for the same variable. A response like
# this used to make InsertRetrievedData() advance its column index once per
# binding rather than once per column, writing past the end of the three
# arrays it sizes by the number of foreign table columns.
BINDING='<binding name="s"><literal>x</literal></binding>'
DUPLICATES=""
for _ in $(seq 1 400); do
    DUPLICATES="$DUPLICATES$BINDING"
done

printf '%s<head><variable name="s"/></head><results><result>%s</result></results></sparql>' \
    "$XML_HEAD" "$DUPLICATES" > /tmp/stub-repeated-binding.xml

# The same shape, but well formed: one binding for the one variable.
printf '%s<head><variable name="s"/></head><results><result>%s</result></results></sparql>' \
    "$XML_HEAD" "$BINDING" > /tmp/stub-single-binding.xml

# A <literal> whose text is broken into several XML child nodes. A CDATA
# section or a comment inside the element splits the character data around it,
# so reading only the first child returns the text up to the split and drops
# the rest. Endpoints in the wild answer with a single text node, which is why
# no test against a real triplestore can produce this.
SPLIT_TEXT='<head><variable name="cdata"/><variable name="commented"/><variable name="empty"/><variable name="tagged"/></head><results><result>'
SPLIT_TEXT=$SPLIT_TEXT'<binding name="cdata"><literal>abc<![CDATA[def]]>ghi</literal></binding>'
SPLIT_TEXT=$SPLIT_TEXT'<binding name="commented"><literal>abc<!--dropped-->def</literal></binding>'
SPLIT_TEXT=$SPLIT_TEXT'<binding name="empty"><literal></literal></binding>'
SPLIT_TEXT=$SPLIT_TEXT'<binding name="tagged"><literal xml:lang="en">one<![CDATA[ two]]></literal></binding>'
SPLIT_TEXT=$SPLIT_TEXT'</result></results></sparql>'

printf '%s%s' "$XML_HEAD" "$SPLIT_TEXT" > /tmp/stub-split-text.xml

# One row exercising each RDF node type, to check that a clone preserves them.
printf '%s<head><variable name="iri"/><variable name="bnode"/><variable name="tagged"/></head><results><result><binding name="iri"><uri>http://example.org/thing</uri></binding><binding name="bnode"><bnode>b1</bnode></binding><binding name="tagged"><literal xml:lang="en">hello</literal></binding></result></results></sparql>' \
    "$XML_HEAD" > /tmp/stub-node-types.xml

# A DESCRIBE answer, which is RDF/XML rather than SPARQL results XML. The
# subject of an rdf:Description is an IRI when it carries rdf:about and a blank
# node when it carries rdf:nodeID; a store only emits the second when the
# described resource actually reaches a blank node, and the labels it picks are
# its own, so a stable test needs the answer written out here.
cat > /tmp/stub-describe-bnode.xml <<'XMLEOF'
<?xml version="1.0"?>
<rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#"
         xmlns:ex="http://example.org/">
  <rdf:Description rdf:about="http://example.org/s">
    <ex:knows rdf:nodeID="b1"/>
  </rdf:Description>
  <rdf:Description rdf:nodeID="b1">
    <ex:name>a blank node</ex:name>
    <ex:sameAs rdf:nodeID="b1"/>
  </rdf:Description>
</rdf:RDF>
XMLEOF

podman run -d --name $CONTAINER_NAME \
  --network $NETWORK_NAME \
  --ip $CONTAINER_IP \
  --no-hosts \
  -v /tmp/stub-endpoint.conf:/etc/nginx/conf.d/default.conf:ro,z \
  -v /tmp/stub-repeated-binding.xml:/usr/share/nginx/html/repeated-binding.xml:ro,z \
  -v /tmp/stub-single-binding.xml:/usr/share/nginx/html/single-binding.xml:ro,z \
  -v /tmp/stub-node-types.xml:/usr/share/nginx/html/node-types.xml:ro,z \
  -v /tmp/stub-split-text.xml:/usr/share/nginx/html/split-text.xml:ro,z \
  -v /tmp/stub-describe-bnode.xml:/usr/share/nginx/html/describe-bnode.xml:ro,z \
  docker.io/library/nginx:alpine

echo "Waiting for the stub endpoint to start..."
sleep 1

if podman exec $CONTAINER_NAME wget -qO- http://127.0.0.1/single-binding.xml >/dev/null 2>&1; then
    echo "Stub SPARQL endpoint is ready!"
else
    echo "ERROR: stub SPARQL endpoint failed to start"
    podman logs $CONTAINER_NAME
    exit 1
fi
