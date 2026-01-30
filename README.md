# cafe-crypto-backend

Docker images and tooling for building and running applications with Post-Quantum Cryptography (PQC) support. **Open Quantum Safe (OQS) via OpenSSL is currently the only use case**, but the repository is designed so that other PQC libraries can be used later, and pure Go when standard library or third-party support are made easy.

**Migrated from cafe-infra/oqs**; the canonical OQS images are published as `oleglod/cafe-crypto-backend:build-oqs` and `oleglod/cafe-crypto-backend:runtime-oqs`.

## Overview

The **OQS** stack (current use case) consists of two Docker images:

1. **`oleglod/cafe-crypto-backend:build-oqs`** (local: `cafe-crypto-backend:build-oqs`) - Build image containing the full build environment with liboqs and oqs-provider compiled
2. **`oleglod/cafe-crypto-backend:runtime-oqs`** (local: `cafe-crypto-backend:runtime-oqs`) - Runtime image containing only the necessary binaries and libraries for running applications; this makes the image as small as possible

## Images

### `cafe-crypto-backend:build-oqs`

**Purpose**: Build environment for compiling liboqs and oqs-provider with OpenSSL.

**Base Image**: `debian:trixie`

**Contains**:
- Build tools (cmake, ninja-build, git, etc.)
- Compiled liboqs library
- Compiled oqs-provider for OpenSSL
- OpenSSL with OQS provider enabled

**Usage**:
- Used as a build stage in multi-stage Docker builds
- Provides the compiled binaries for the runtime image

**Dockerfile**: `Dockerfile-oqs-build`

### `cafe-crypto-backend:runtime-oqs`

**Purpose**: Minimal runtime image with OQS-enabled OpenSSL.

**Base Image**: `debian:trixie-slim`

**Contains**:
- OpenSSL binary with OQS support
- liboqs shared libraries
- oqs-provider module
- OpenSSL configuration

**Environment Variables** (automatically set in the image):
- `OPENSSL_CONF=/etc/ssl/openssl.cnf` - OpenSSL configuration file
- `OPENSSL_MODULES=/usr/lib/x86_64-linux-gnu/ossl-modules` - Path to OpenSSL provider modules (default: x86_64, auto-detected by wrapper script)
- `LD_LIBRARY_PATH=/opt/liboqs/lib` - Library path for liboqs

**Note**: All environment variables are automatically set in the Docker image, so they are available in all containers using `cafe-crypto-backend:build-oqs` or `cafe-crypto-backend:runtime-oqs`. For ARM64 architectures, you may need to override `OPENSSL_MODULES`:
```bash
export OPENSSL_MODULES=/usr/lib/aarch64-linux-gnu/ossl-modules
```
Or use the provided `openssl-wrapper` script which auto-detects the architecture.

**Default Command**: `openssl version`

**Dockerfile**: `Dockerfile-oqs-runtime`

## Building the Images

### Prerequisites

- Docker installed and running
- Sufficient disk space (build process requires several GB)

### Quick Start

Use the provided build script:

```bash
./build.sh
```

This will build both images in the correct order (run from repo root):
1. First builds `oleglod/cafe-crypto-backend:build-oqs`
2. Then builds `oleglod/cafe-crypto-backend:runtime-oqs` (which depends on the build image)

### Manual Build

If you prefer to build manually:

```bash
# From repo root: build the build image first
docker build -f docker/Dockerfile-oqs-build -t oleglod/cafe-crypto-backend:build-oqs .

# Build the runtime image (depends on build image)
docker build -f docker/Dockerfile-oqs-runtime -t oleglod/cafe-crypto-backend:runtime-oqs .
```

### Build Options

The build script supports the different options.
One can retrieve all the options using `--help`.

```bash
./build.sh --help
```

## Multi-Architecture Builds

The OQS Docker images can be built for multiple architectures (e.g., amd64, arm64) using Docker Buildx. This allows you to create images that work on different CPU architectures.

### Prerequisites

- Docker Buildx enabled (usually available by default in Docker Desktop)
- For cross-platform builds, you may need to set up QEMU emulation

### Setting Up Buildx

First, ensure Buildx is available and create a builder instance if needed:

```bash
# Check if buildx is available
docker buildx version

# Create a new builder instance (optional, for better performance)
docker buildx create --name multiarch-builder --use

# Inspect the builder to see supported platforms
docker buildx inspect --bootstrap
```

### Building for Multiple Architectures

To build images for multiple architectures, use `docker buildx build` with the `--platform` flag:

```bash
# Build for both amd64 and arm64 (from repo root)
docker buildx build \
  --platform linux/amd64,linux/arm64 \
  -f docker/Dockerfile-oqs-build \
  -t oleglod/cafe-crypto-backend:build-oqs \
  --load .

# Build runtime image for multiple architectures
docker buildx build \
  --platform linux/amd64,linux/arm64 \
  -f docker/Dockerfile-oqs-runtime \
  -t oleglod/cafe-crypto-backend:runtime-oqs \
  --load .
```

**Note**: The `--load` flag only works for single-platform builds. For multi-platform builds, you need to use `--push` to push to a registry, or use `docker buildx build` without `--load` and then create a manifest.

### Creating Multi-Architecture Manifests

To create a multi-architecture manifest that works across platforms:

```bash
# Build and push for multiple platforms
docker buildx build \
  --platform linux/amd64,linux/arm64 \
  -f docker/Dockerfile-oqs-build \
  -t your-registry/cafe-crypto-backend:build-oqs \
  --push .

docker buildx build \
  --platform linux/amd64,linux/arm64 \
  -f docker/Dockerfile-oqs-runtime \
  -t your-registry/cafe-crypto-backend:runtime-oqs \
  --push .
```

### Architecture-Specific Considerations

The images automatically handle architecture differences:

- **Module Path**: The `OPENSSL_MODULES` environment variable is architecture-dependent:
  - `x86_64` (amd64): `/usr/lib/x86_64-linux-gnu/ossl-modules`
  - `aarch64` (arm64): `/usr/lib/aarch64-linux-gnu/ossl-modules`

- **Auto-Detection**: The `openssl-wrapper` script automatically detects the architecture and sets the correct module path:

```bash
# Works on both amd64 and arm64
docker run --rm oleglod/cafe-crypto-backend:runtime-oqs /usr/local/bin/openssl-wrapper version
```

### Testing Multi-Architecture Builds

To test a build for a specific architecture:

```bash
# Test on amd64
docker run --rm --platform linux/amd64 oleglod/cafe-crypto-backend:runtime-oqs openssl version

# Test on arm64 (requires arm64 host or emulation)
docker run --rm --platform linux/arm64 oleglod/cafe-crypto-backend:runtime-oqs openssl version

# Verify the architecture of the running container
docker run --rm --platform linux/arm64 oleglod/cafe-crypto-backend:runtime-oqs uname -m
# Should output: aarch64
```

### Build Script with Multi-Architecture

The provided `build.sh` script currently builds for the host architecture only. For multi-architecture builds, use `docker buildx build` directly as shown above, or extend the build script to support the `--platform` flag.

## Testing the Images

### Test the build image:

```bash
docker run --rm oleglod/cafe-crypto-backend:build-oqs openssl version
# Should output OpenSSL version (3.5+)

docker run --rm oleglod/cafe-crypto-backend:build-oqs openssl list -providers
# Should show oqsprovider

docker run --rm oleglod/cafe-crypto-backend:build-oqs openssl list -kem-algorithms
# Should list available KEM algorithms
```

### Test the runtime image:

```bash
docker run --rm oleglod/cafe-crypto-backend:runtime-oqs
# Should output OpenSSL version (3.5+)

docker run --rm oleglod/cafe-crypto-backend:runtime-oqs list -providers
# Should show oqsprovider

docker run --rm oleglod/cafe-crypto-backend:runtime-oqs list -kem-algorithms
# Should list available KEM algorithms
```

### Using in Multi-stage Builds

One can use the build image to build its own PQC application.

Please refer to [../nginx](../nginx/), as example.

## Architecture

The build process:

1. liboqs: Core library implementing post-quantum cryptographic algorithms
2. oqs-provider: OpenSSL 3.x provider that integrates liboqs
3. OpenSSL: Standard OpenSSL with OQS provider enabled

### Supported Algorithms

The images include support for:
- Hybrid KEM algorithms (combining classical and post-quantum cryptography)
- Various post-quantum key exchange mechanisms
- Post-quantum signature schemes

To see available algorithms:

```bash
docker run --rm oleglod/cafe-crypto-backend:runtime-oqs list -kem-algorithms
docker run --rm oleglod/cafe-crypto-backend:runtime-oqs list -signature-algorithms
```

## Configuration

### OpenSSL Configuration

The OpenSSL configuration is located at `/etc/ssl/openssl.cnf` and includes:

- Default provider activation
- OQS provider activation
- Module path configuration

### Environment Variables

**All environment variables are automatically set in both `cafe-crypto-backend:build-oqs` and `cafe-crypto-backend:runtime-oqs` images.** You don't need to set them manually unless you want to override them.

The following variables are pre-configured:

```bash
OPENSSL_CONF=/etc/ssl/openssl.cnf
OPENSSL_MODULES=/usr/lib/x86_64-linux-gnu/ossl-modules  # Default for x86_64
LD_LIBRARY_PATH=/opt/liboqs/lib
```

**For ARM64 architectures**, you may need to override `OPENSSL_MODULES`:

```bash
export OPENSSL_MODULES=/usr/lib/aarch64-linux-gnu/ossl-modules
```

**Alternative**: Use the provided `openssl-wrapper` script which auto-detects the architecture:

```bash
/usr/local/bin/openssl-wrapper version
```

The wrapper script automatically detects the architecture and sets `OPENSSL_MODULES` correctly.

These are already set in the runtime image, but may need to be adjusted for custom setups.

## Troubleshooting

### Build Fails

- Ensure you have sufficient disk space (build requires ~5-10GB)
- Check Docker has enough memory allocated
- Verify network connectivity (build downloads from GitHub)

### Runtime Issues

- Verify the image was built successfully: `docker images | grep cafe-crypto-backend`
- Check that `oleglod/cafe-crypto-backend:build-oqs` exists before building runtime
- Ensure environment variables are properly set

### Provider Not Found

If OpenSSL can't find the OQS provider:

```bash
# Check module path
docker run --rm oleglod/cafe-crypto-backend:runtime-oqs ls -la /usr/lib/*-linux-gnu/ossl-modules/

# Verify configuration
docker run --rm oleglod/cafe-crypto-backend:runtime-oqs cat /etc/ssl/openssl.cnf
```

## Files

- `docker/Dockerfile-oqs-build` - Build image definition
- `docker/Dockerfile-oqs-runtime` - Runtime image definition
- `scripts/install_oqs_openssl_build.sh` - Installation script for build image
- `scripts/build.sh` - Build script (run from repo root)
- `README.md` - This file

## References

- [liboqs](https://github.com/open-quantum-safe/liboqs)
- [oqs-provider](https://github.com/open-quantum-safe/oqs-provider)
- [Open Quantum Safe](https://openquantumsafe.org/)

## License

The OQS libraries and tools are licensed under their respective licenses. Please refer to the upstream projects for license information.
