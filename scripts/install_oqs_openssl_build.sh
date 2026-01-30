#!/usr/bin/env bash
set -euo pipefail
set -x

# ======================================================
# Configuration
# ======================================================

ARCH="$(uname -m)"
LIBOQS_PREFIX="/opt/liboqs"
OPENSSL_PREFIX="/usr"
BUILD_DIR="/tmp/oqs-build"

# ======================================================
# Requirements
# ======================================================

apt-get update
apt-get install -y --no-install-recommends \
    build-essential \
    cmake \
    ninja-build \
    git \
    pkg-config \
    wget \
    perl \
    ca-certificates \
    libssl-dev \
    zlib1g-dev

rm -rf /var/lib/apt/lists/*

mkdir -p "${BUILD_DIR}"
cd "${BUILD_DIR}"

# ======================================================
# Build liboqs
# ======================================================

git clone --depth 1 https://github.com/open-quantum-safe/liboqs.git
cd liboqs

mkdir build && cd build

cmake -GNinja \
  -DBUILD_SHARED_LIBS=ON \
  -DOQS_ENABLE_KEM_HYBRID=ON \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_INSTALL_PREFIX="${LIBOQS_PREFIX}" \
  ..

ninja
ninja install

cd "${BUILD_DIR}"

# ======================================================
# Build oqs-provider
# ======================================================

git clone --depth 1 https://github.com/open-quantum-safe/oqs-provider.git
cd oqs-provider

mkdir build && cd build

cmake -GNinja \
  -DOPENSSL_ROOT_DIR="${OPENSSL_PREFIX}" \
  -DOQS_INSTALL_PATH="${LIBOQS_PREFIX}" \
  -DCMAKE_BUILD_TYPE=Release \
  ..

ninja
ninja install

# ======================================================
# OpenSSL provider configuration 
# ======================================================

cat <<EOF >> /etc/ssl/openssl.cnf

# ======================================================
# OQS provider (BUILD-TIME ENABLEMENT)
# ======================================================

openssl_conf = openssl_init

[openssl_init]
providers = provider_sect

[provider_sect]
default = default_sect
oqsprovider = oqsprovider_sect

[default_sect]
activate = 1

[oqsprovider_sect]
activate = 1
module = ${OPENSSL_PREFIX}/lib/${ARCH}-linux-gnu/ossl-modules/oqsprovider.so

EOF

export OPENSSL_CONF=/etc/ssl/openssl.cnf
export OPENSSL_MODULES="${OPENSSL_PREFIX}/lib/${ARCH}-linux-gnu/ossl-modules"
export LD_LIBRARY_PATH="${LIBOQS_PREFIX}/lib"

# ======================================================
# Tests BUILD
# ======================================================

echo "== OpenSSL version =="
openssl version

echo "== Providers =="
openssl list -providers | grep -i oqs

echo "== KEM algorithms =="
openssl list -kem-algorithms | grep -i kem

# ======================================================
# Cleanup BUILD
# ======================================================

rm -rf "${BUILD_DIR}"

echo "✅ OQS + oqs-provider BUILD SUCCESS"
