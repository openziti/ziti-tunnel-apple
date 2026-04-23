# Testing HTTP Proxy Support

Manual testing instructions using Squid in Docker.

## Prerequisites

- Docker installed and running
- A Ziti identity enrolled and functional (to verify traffic flows through the proxy)

## Basic Proxy (No Auth)

```bash
mkdir -p ~/squid-config

cat > ~/squid-config/squid.conf << 'EOF'
acl SSL_ports port 443
acl CONNECT method CONNECT
http_access allow CONNECT SSL_ports
http_access allow all
http_port 3128
access_log daemon:/var/log/squid/access.log
cache deny all
EOF

docker run -d --name squid -p 3128:3128 \
  -v ~/squid-config/squid.conf:/etc/squid/squid.conf \
  ubuntu/squid
```

Verify Squid is running:

```bash
curl -x http://localhost:3128 http://httpbin.org/ip
```

## Proxy With Basic Auth

```bash
# Create password file (user: testuser, password: testpass)
docker run --rm httpd:2 htpasswd -bn testuser testpass > ~/squid-config/passwords

cat > ~/squid-config/squid.conf << 'EOF'
auth_param basic program /usr/lib/squid/basic_ncsa_auth /etc/squid/passwords
auth_param basic realm Squid Proxy
acl authenticated proxy_auth REQUIRED
acl SSL_ports port 443
acl CONNECT method CONNECT
http_access allow CONNECT authenticated
http_access allow authenticated
http_access deny all
http_port 3128
access_log daemon:/var/log/squid/access.log
cache deny all
EOF

docker rm -f squid
docker run -d --name squid -p 3128:3128 \
  -v ~/squid-config/squid.conf:/etc/squid/squid.conf \
  -v ~/squid-config/passwords:/etc/squid/passwords \
  ubuntu/squid
```

Verify auth works:

```bash
# Should fail with 407
curl -x http://localhost:3128 http://httpbin.org/ip

# Should succeed
curl -x http://testuser:testpass@localhost:3128 http://httpbin.org/ip
```

## Monitoring Proxy Traffic

Tail the access log to confirm Ziti traffic is flowing through Squid:

```bash
docker exec squid tail -f /var/log/squid/access.log
```

- `TCP_TUNNEL/200` with `CONNECT` = successful HTTPS tunnel (expected for Ziti)
- `TCP_DENIED/403` = Squid blocked the request (check config)
- `TCP_DENIED/407` = auth required but not provided

## Testing via System Proxy

1. Open System Settings > Network > (your interface) > Details > Proxies
2. Enable "Web Proxy (HTTP)", set server to `localhost`, port to `3128`
3. Save
4. In Ziti Desktop Edge Config, select "System Proxy" - should show `localhost:3128`

## Test Matrix

| Mode | Auth | Expected |
|------|------|----------|
| No Proxy | n/a | Traffic bypasses proxy |
| Manual Proxy | No auth | Traffic flows through proxy, `TCP_TUNNEL/200` in logs |
| Manual Proxy | With auth | Same as above, with credentials |
| System Proxy | No auth | Detects system proxy, traffic flows through |
| System Proxy | With auth | Detects system proxy, uses stored credentials |
| System Proxy (disabled) | n/a | No proxy detected, fields empty |

## Cleanup

```bash
docker rm -f squid
rm -rf ~/squid-config
```
