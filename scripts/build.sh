#!/usr/bin/env bash
set -euo pipefail

# ======================================================
# OQS Docker Images Build Script
# ======================================================
# This script standardizes the build process for
# cafe-oqs:build and cafe-oqs:runtime images
# ======================================================

# Source directory (repo root) and script location
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRCDIR="$(cd "$SCRIPT_DIR/.." && pwd)"

# Default values
BUILD_TAG="oleglod/cafe-crypto-backend:build-oqs"
RUNTIME_TAG="oleglod/cafe-crypto-backend:runtime-oqs"
BUILD_ONLY=false
RUNTIME_ONLY=false
NO_CACHE=false
PUSH=false
VERBOSE=false

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# ======================================================
# Functions
# ======================================================

usage() {
    cat <<EOF
Usage: $0 [OPTIONS]

Build OQS Docker images (cafe-crypto-backend:build-oqs and cafe-crypto-backend:runtime-oqs)

OPTIONS:
    --tag-build TAG          Tag for build image (default: cafe-crypto-backend:build-oqs)
    --tag-runtime TAG        Tag for runtime image (default: cafe-crypto-backend:runtime-oqs)
    --build-only             Build only the build image
    --runtime-only           Build only the runtime image (requires build image)
    --no-cache               Build without using cache
    --push                   Push images to registry (requires docker login)
    --verbose, -v            Enable verbose output
    --help, -h               Show this help message

EXAMPLES:
    # Build both images with default tags
    $0

    # Build with custom tags
    $0 --tag-build cafe-crypto-backend:build-oqs-v1.0 --tag-runtime cafe-crypto-backend:runtime-oqs-v1.0

    # Build only the build image
    $0 --build-only

    # Build without cache
    $0 --no-cache

    # Build and push to registry
    $0 --push
EOF
}

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
}

check_docker() {
    if ! command -v docker &> /dev/null; then
        log_error "Docker is not installed or not in PATH"
        exit 1
    fi

    if ! docker info &> /dev/null; then
        log_error "Docker daemon is not running"
        exit 1
    fi
}

check_build_image() {
    if [[ "$RUNTIME_ONLY" == true ]]; then
        if ! docker image inspect "$BUILD_TAG" &> /dev/null; then
            log_error "Build image '$BUILD_TAG' not found. Build it first or remove --runtime-only flag."
            exit 1
        fi
        log_info "Using existing build image: $BUILD_TAG"
    fi
}

build_build_image() {
    if [[ "$RUNTIME_ONLY" == true ]]; then
        log_info "Skipping build image (--runtime-only specified)"
        return 0
    fi

    log_info "Building build image: $BUILD_TAG"

    # Build docker command (context = SRCDIR)
    local docker_cmd=("docker" "build" "-f" "$SRCDIR/docker/Dockerfile-oqs-build" "-t" "$BUILD_TAG")
    
    if [[ "$NO_CACHE" == true ]]; then
        docker_cmd+=("--no-cache")
    fi
    if [[ "$VERBOSE" == true ]]; then
        docker_cmd+=("--progress=plain")
    fi
    
    docker_cmd+=("$SRCDIR")

    if "${docker_cmd[@]}"; then
        log_success "Build image created: $BUILD_TAG"
    else
        log_error "Failed to build build image"
        exit 1
    fi
}

build_runtime_image() {
    if [[ "$BUILD_ONLY" == true ]]; then
        log_info "Skipping runtime image (--build-only specified)"
        return 0
    fi

    log_info "Building runtime image: $RUNTIME_TAG"
    log_info "Using build image: $BUILD_TAG"
    
    # Check if custom tags are used
    if [[ "$BUILD_TAG" != "cafe-crypto-backend:build-oqs" ]]; then
        log_warning "Custom build tag detected: $BUILD_TAG"
        log_warning "Dockerfile-oqs-runtime uses 'cafe-crypto-backend:build-oqs' by default."
        log_warning "Temporarily modifying Dockerfile to use custom tag..."
        
        # Create temporary Dockerfile with custom tag
        local temp_dockerfile="$SRCDIR/docker/Dockerfile-oqs-runtime.tmp"
        sed "s|FROM cafe-crypto-backend:build-oqs AS source|FROM $BUILD_TAG AS source|" \
            "$SRCDIR/docker/Dockerfile-oqs-runtime" > "$temp_dockerfile"
        
        local dockerfile_to_use="$temp_dockerfile"
    else
        local dockerfile_to_use="$SRCDIR/docker/Dockerfile-oqs-runtime"
    fi
    
    # Build docker command (context = SRCDIR)
    local docker_cmd=("docker" "build" "-f" "$dockerfile_to_use" "-t" "$RUNTIME_TAG")
    
    if [[ "$NO_CACHE" == true ]]; then
        docker_cmd+=("--no-cache")
    fi
    if [[ "$VERBOSE" == true ]]; then
        docker_cmd+=("--progress=plain")
    fi
    
    docker_cmd+=("$SRCDIR")

    if "${docker_cmd[@]}"; then
        log_success "Runtime image created: $RUNTIME_TAG"
    else
        log_error "Failed to build runtime image"
        [[ -n "${temp_dockerfile:-}" && -f "$temp_dockerfile" ]] && rm -f "$temp_dockerfile"
        exit 1
    fi
    
    # Cleanup temporary Dockerfile (only when we created one)
    if [[ "$BUILD_TAG" != "cafe-crypto-backend:build-oqs" ]]; then
        [[ -f "$temp_dockerfile" ]] && rm -f "$temp_dockerfile"
    fi
}

push_images() {
    if [[ "$PUSH" != true ]]; then
        return 0
    fi

    log_info "Pushing images to registry..."

    if [[ "$BUILD_ONLY" != true ]]; then
        if docker push "$BUILD_TAG"; then
            log_success "Pushed build image: $BUILD_TAG"
        else
            log_error "Failed to push build image"
            exit 1
        fi
    fi

    if [[ "$RUNTIME_ONLY" != true ]]; then
        if docker push "$RUNTIME_TAG"; then
            log_success "Pushed runtime image: $RUNTIME_TAG"
        else
            log_error "Failed to push runtime image"
            exit 1
        fi
    fi
}

show_summary() {
    echo ""
    log_info "Build Summary:"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    
    if [[ "$RUNTIME_ONLY" != true ]]; then
        if docker image inspect "$BUILD_TAG" &> /dev/null; then
            local build_size=$(docker image inspect "$BUILD_TAG" --format='{{.Size}}' | numfmt --to=iec-i --suffix=B 2>/dev/null || echo "unknown")
            echo "  Build Image:   $BUILD_TAG ($build_size)"
        fi
    fi
    
    if [[ "$BUILD_ONLY" != true ]]; then
        if docker image inspect "$RUNTIME_TAG" &> /dev/null; then
            local runtime_size=$(docker image inspect "$RUNTIME_TAG" --format='{{.Size}}' | numfmt --to=iec-i --suffix=B 2>/dev/null || echo "unknown")
            echo "  Runtime Image:  $RUNTIME_TAG ($runtime_size)"
        fi
    fi
    
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    
    log_info "To test the images:"
    if [[ "$RUNTIME_ONLY" != true ]]; then
        echo "  docker run --rm $BUILD_TAG openssl version"
    fi
    if [[ "$BUILD_ONLY" != true ]]; then
        echo "  docker run --rm $RUNTIME_TAG"
    fi
}

# ======================================================
# Parse Arguments
# ======================================================

while [[ $# -gt 0 ]]; do
    case $1 in
        --tag-build)
            BUILD_TAG="$2"
            shift 2
            ;;
        --tag-runtime)
            RUNTIME_TAG="$2"
            shift 2
            ;;
        --build-only)
            BUILD_ONLY=true
            shift
            ;;
        --runtime-only)
            RUNTIME_ONLY=true
            shift
            ;;
        --no-cache)
            NO_CACHE=true
            shift
            ;;
        --push)
            PUSH=true
            shift
            ;;
        --verbose|-v)
            VERBOSE=true
            shift
            ;;
        --help|-h)
            usage
            exit 0
            ;;
        *)
            log_error "Unknown option: $1"
            usage
            exit 1
            ;;
    esac
done

# ======================================================
# Validation
# ======================================================

if [[ "$BUILD_ONLY" == true && "$RUNTIME_ONLY" == true ]]; then
    log_error "Cannot specify both --build-only and --runtime-only"
    exit 1
fi

# ======================================================
# Main Execution
# ======================================================

log_info "Starting OQS Docker images build process"
echo ""

check_docker
check_build_image

# Build images (paths use SRCDIR)
build_build_image
build_runtime_image

# Push if requested
push_images

# Show summary
show_summary

log_success "Build process completed successfully!"
