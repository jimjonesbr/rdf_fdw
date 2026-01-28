#!/bin/bash

NETWORK_NAME=pgnet
PROXY_PORT=3128
PROXY_AUTH_PORT=3129

# Deploy Squid proxy WITHOUT authentication
echo -e "\n== Deploying Squid proxy (no auth) ==\n"

docker stop squid-no-auth 2>/dev/null || true
docker rm squid-no-auth 2>/dev/null || true

cat > /tmp/squid-no-auth.conf <<EOF
http_port 3128
acl localnet src 10.0.0.0/8
acl localnet src 172.16.0.0/12
http_access allow localnet
http_access deny all
EOF

docker run -d --name squid-no-auth \
  --network $NETWORK_NAME \
  --ip 172.19.42.100 \
  -v /tmp/squid-no-auth.conf:/etc/squid/squid.conf:ro \
  ubuntu/squid:latest

echo "Waiting for Squid (no auth) to start..."
sleep 1

# Verify Squid is running
if docker exec squid-no-auth squid -k check 2>/dev/null; then
    echo "Squid (no auth) is ready!"
else
    echo "ERROR: Squid failed to start"
    docker logs squid-no-auth
    exit 1
fi

# Deploy Squid proxy WITH authentication
echo -e "\n== Deploying Squid proxy (with auth) ==\n"

docker stop squid-auth 2>/dev/null || true
docker rm squid-auth 2>/dev/null || true

# Create password file (user: proxyuser, password: proxypass)
# Using openssl to create bcrypt hash instead of htpasswd
echo -n "proxyuser:" > /tmp/squid-passwords
openssl passwd -apr1 proxypass >> /tmp/squid-passwords

cat > /tmp/squid-auth.conf <<EOF
http_port 3128
auth_param basic program /usr/lib/squid/basic_ncsa_auth /etc/squid/passwords
auth_param basic children 5
auth_param basic realm Squid proxy
auth_param basic credentialsttl 2 hours
acl authenticated proxy_auth REQUIRED
http_access allow authenticated
http_access deny all
EOF

docker run -d --name squid-auth \
  --network $NETWORK_NAME \
  --ip 172.19.42.101 \
  -v /tmp/squid-auth.conf:/etc/squid/squid.conf:ro \
  -v /tmp/squid-passwords:/etc/squid/passwords:ro \
  ubuntu/squid:latest

echo "Waiting for Squid (with auth) to start..."
sleep 1

# Verify Squid is running
if docker exec squid-auth squid -k check 2>/dev/null; then
    echo "Squid (with auth) is ready!"
else
    echo "ERROR: Squid (with auth) failed to start"
    docker logs squid-auth
    exit 1
fi