#!/bin/bash
# Wrapper script to set OPENSSL_MODULES based on detected architecture
# This ensures OPENSSL_MODULES is correctly set for all architectures

# Detect architecture
ARCH=$(uname -m)
case "$ARCH" in
    x86_64)
        OPENSSL_MODULES_PATH="/usr/lib/x86_64-linux-gnu/ossl-modules"
        ;;
    aarch64|arm64)
        OPENSSL_MODULES_PATH="/usr/lib/aarch64-linux-gnu/ossl-modules"
        ;;
    *)
        # Fallback: try to find the directory
        OPENSSL_MODULES_PATH=$(find /usr/lib -type d -name "ossl-modules" 2>/dev/null | head -n1)
        if [ -z "$OPENSSL_MODULES_PATH" ]; then
            OPENSSL_MODULES_PATH="/usr/lib/x86_64-linux-gnu/ossl-modules"
        fi
        ;;
esac

# Export environment variables
export OPENSSL_CONF=${OPENSSL_CONF:-/etc/ssl/openssl.cnf}
export OPENSSL_MODULES=${OPENSSL_MODULES:-$OPENSSL_MODULES_PATH}
export LD_LIBRARY_PATH=${LD_LIBRARY_PATH:-/opt/liboqs/lib}:$LD_LIBRARY_PATH

# Execute openssl with all arguments
exec /usr/bin/openssl "$@"
