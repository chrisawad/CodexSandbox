# Hosting applications with Nginx in this container

This workspace runs inside a Docker container managed by an external Compose
deployment. Nginx is already running and is the supported way to expose a built
application for testing.

## Port mapping

| Protocol | Container listener | Host-port environment variable | Default |
| --- | ---: | --- | ---: |
| HTTP | `80` | `NGINX_HOST_HTTP_PORT` | `8080` |
| HTTPS | `443` | `NGINX_HOST_HTTPS_PORT` | `4443` |

Container ports are useful for internal diagnostics only. Before reporting a
URL, read the current host ports from the environment:

```bash
http_port="${NGINX_HOST_HTTP_PORT:-8080}"
https_port="${NGINX_HOST_HTTPS_PORT:-4443}"
printf 'HTTP:  http://127.0.0.1:%s\n' "$http_port"
printf 'HTTPS: https://127.0.0.1:%s\n' "$https_port"
```

Always provide the resolved IPv4 host URLs to the user. Do not substitute
`localhost`, because it can resolve to IPv6 and cause connection delays. Never
use container ports `80` or `443` in a user-facing URL. The default HTTPS
certificate is self-signed, so a browser may display a certificate warning.

## Web root

Nginx serves files from the directory stored in `NGINX_WEB_ROOT`:

```text
/usr/share/nginx/html
```

That is the default value. Use the environment variable's current value if the
external Compose deployment overrides it.

## Publishing workflow

1. Build the application using its production build command.
2. Identify the generated static distribution directory, commonly `dist`,
   `build`, `out`, or `public`.
3. Replace the contents of `NGINX_WEB_ROOT` with the contents of that generated
   distribution. Copy the distribution's contents, not the containing
   directory, so its `index.html` is at the web root.
4. Validate the nginx configuration with `nginx -t`.
5. Test HTTP internally through nginx on `http://127.0.0.1:80`. Test HTTPS on
   `https://127.0.0.1:443` when relevant, allowing for the self-signed
   certificate.
6. Read `NGINX_HOST_HTTP_PORT` and `NGINX_HOST_HTTPS_PORT`, then tell the user
   to open the corresponding `127.0.0.1` URL.

Do not leave a framework development server as the user-facing test endpoint
when a static distribution can be hosted by nginx.
