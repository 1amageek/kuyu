#!/usr/bin/env bash
set -euo pipefail

CONFIGURATION="${1:-release}"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

case "$CONFIGURATION" in
  debug|release) ;;
  *)
    echo "usage: $0 [debug|release]" >&2
    exit 2
    ;;
esac

swift package resolve >/dev/null
MLX_SOURCE_DIR="$ROOT_DIR/.build/checkouts/mlx-swift/Source/Cmlx/mlx"
if [[ ! -d "$MLX_SOURCE_DIR" ]]; then
  echo "mlx-swift checkout not found at $MLX_SOURCE_DIR" >&2
  exit 1
fi

BUILD_DIR="${TMPDIR:-/tmp}/kuyu-mlx-metallib-$$"
trap 'rm -rf "$BUILD_DIR"' EXIT

cmake -S "$MLX_SOURCE_DIR" -B "$BUILD_DIR" \
  -DMLX_BUILD_TESTS=OFF \
  -DMLX_BUILD_EXAMPLES=OFF \
  -DMLX_BUILD_BENCHMARKS=OFF \
  -DMLX_BUILD_PYTHON_BINDINGS=OFF \
  -DCMAKE_BUILD_TYPE=Release >/dev/null
cmake --build "$BUILD_DIR" --target mlx-metallib -j "$(sysctl -n hw.ncpu)" >/dev/null

METALLIB="$BUILD_DIR/mlx/backend/metal/kernels/mlx.metallib"
if [[ ! -f "$METALLIB" ]]; then
  echo "mlx.metallib was not produced" >&2
  exit 1
fi

BIN_DIR="$(swift build -c "$CONFIGURATION" --show-bin-path)"
mkdir -p "$BIN_DIR"
cp "$METALLIB" "$BIN_DIR/mlx.metallib"
echo "$BIN_DIR/mlx.metallib"
