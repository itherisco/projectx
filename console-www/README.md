# ITHERIS WASM Console

Zero-install browser interface for the ITHERIS Full OS Interface (ProjectX Jarvis).

This is Phase 3 of the ITHERIS architecture - a WASM-only console that runs directly in browsers without requiring any installation or native applications.

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                        Browser                               │
│  ┌─────────────────────────────────────────────────────┐     │
│  │              ITHERIS WASM Console                   │     │
│  │  ┌─────────┐  ┌──────────┐  ┌─────────────────┐   │     │
│  │  │ Leptos  │  │  Bento   │  │    gRPC-Web    │   │     │
│  │  │   UI    │  │   Grid   │  │     Client      │   │     │
│  │  └────┬────┘  └────┬─────┘  └────────┬────────┘   │     │
│  └───────┼────────────┼─────────────────┼─────────────┘     │
└──────────┼────────────┼─────────────────┼────────────────────┘
           │            │                  │
           ▼            ▼                  ▼
     ┌─────────────────────────────────────────────┐
     │            gRPC-Web Proxy                    │
     │  (nginx / envoy / traefik)                  │
     └────────────────────┬────────────────────────┘
                         │
                         ▼
     ┌─────────────────────────────────────────────┐
     │         Warden gRPC Service                 │
     │  (localhost:50051 or remote)               │
     └─────────────────────────────────────────────┘
```

## Features

- **Zero Installation**: Runs entirely in the browser using WebAssembly
- **100% Code Sharing**: Uses the same components as the Tauri desktop app
- **gRPC-Web Compatible**: Communicates with Warden via HTTP/1.1
- **Responsive Design**: Works on desktop and mobile browsers
- **Real-time Updates**: Streaming metabolic telemetry and decision proposals

## Prerequisites

### Build Requirements

- Rust 1.70+
- `wasm32-unknown-unknown` target: `rustup target add wasm32-unknown-unknown`
- `wasm-pack`: `cargo install wasm-pack`

### Runtime Requirements

- Modern browser with WebAssembly support
- gRPC-Web proxy (nginx, envoy, or similar)
- Warden gRPC service accessible via proxy

## Build Instructions

### 1. Build the WASM Module

```bash
# From the project root
cd console

# Build with wasm-pack
wasm-pack build --target web --out-dir www/pkg
```

### 2. Copy HTML Files

The build output will be in `console/www/pkg`. You'll need:

```bash
# Create www directory if it doesn't exist
mkdir -p console-www

# Copy the generated JavaScript
cp -r console/www/pkg/* console-www/

# Copy index.html (already in console-www)
```

### 3. Serve the Files

```bash
# Using Python
cd console-www
python3 -m http.server 8080

# Using Node.js
npx serve .
```

## gRPC-Web Proxy Setup

Since browsers cannot make direct gRPC calls, you need a gRPC-Web proxy.

### Option 1: Using nginx

```bash
# Copy the nginx configuration
sudo cp grpc-web-proxy.conf /etc/nginx/sites-available/itheris-grpc-web
sudo ln -s /etc/nginx/sites-available/itheris-grpc-web /etc/nginx/sites-enabled/

# Test and reload
sudo nginx -t
sudo systemctl reload nginx
```

### Option 2: Using envoy (Recommended for Production)

```bash
# Install envoy
# https://www.envoyproxy.io/docs/envoy/latest/start/install

# Run with the embedded config
envoy -c grpc-web-proxy.conf
```

### Option 3: Using Docker

```bash
# Using grpc-web-proxy Docker image
docker run -p 8080:8080 \
  -e GRPC_HOST=host.docker.internal \
  -e GRPC_PORT=50051 \
  ghcr.io/grpc-ecosystem/grpc-web/docker-forwarder
```

## Configuration

### Setting the gRPC-Web Endpoint

The console defaults to `http://localhost:8080`. To change this:

**Via JavaScript (before loading):**
```html
<script>
  window.GRPC_WEB_ENDPOINT = 'http://your-server:8080';
</script>
```

**Via environment (build-time):**
Set the `GRPC_WEB_ENDPOINT` environment variable.

### Warden Service Configuration

Update the gRPC-Web proxy configuration to point to your Warden service:

```nginx
grpc_pass grpc://warden-host:50051;
```

## Development

### Running in Development Mode

```bash
# Start the WASM dev server
cd console
wasm-pack build --target web --out-dir www/pkg --dev

# Start the HTTP server
cd console-www
python3 -m http.server 8080
```

### Watching for Changes

Use `wasm-pack serve` for automatic rebuilds:

```bash
cd console
wasm-pack serve --target web --out-dir ../console-www/pkg
```

## Browser Compatibility

- Chrome 89+
- Firefox 89+
- Safari 15+
- Edge 89+

## Security Considerations

1. **CORS**: Configure appropriate CORS headers for production
2. **HTTPS**: Always use HTTPS in production (required for some browser features)
3. **Authentication**: The gRPC-Web proxy should handle authentication
4. **Rate Limiting**: Implement rate limiting at the proxy level

## Troubleshooting

### "Failed to initialize"

Check the browser console for detailed error messages. Common causes:
- WASM file not found (check the import path)
- CORS errors (proxy misconfiguration)
- Network connectivity issues

### "Connection Failed"

1. Verify the gRPC-Web proxy is running: `curl http://localhost:8080/health`
2. Check proxy logs for errors
3. Verify Warden service is accessible from the proxy host

### Slow Loading

- Enable WASM compression (brotli/gzip)
- Use a CDN for static assets
- Enable HTTP/2

## File Structure

```
console-www/
├── index.html              # WASM console entry point
├── grpc-web-proxy.conf    # nginx/envoy proxy configuration
├── README.md              # This file
└── pkg/                   # Generated WASM artifacts
    ├── itheris_console.js
    ├── itheris_console_bg.wasm
    └── ...
```

## Related Documentation

- [ITHERIS Architecture](../ARCHITECTURE.md)
- [Phase 2: Tauri Desktop App](../console/src-tauri)
- [gRPC Service Contracts](../console/proto/warden.proto)

## License

Copyright © 2024 ITHERIS Team. All rights reserved.
