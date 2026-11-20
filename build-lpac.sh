#!/bin/bash
# Build lpac with the gbinder (SIM slot) backend for Ubuntu Touch arm64,
# inside an Ubuntu 24.04 arm64 Docker container (same base as Ubuntu Touch 24.04).
#
# Output: ./lpac-ut.tar.gz  -> extract on the phone with: tar -xzf lpac-ut.tar.gz -C ~/.local
#
# Requirements on the build machine: docker, and arm64 emulation:
#   docker run --privileged --rm tonistiigi/binfmt --install arm64
#
# SPDX-License-Identifier: MIT

set -euo pipefail

PREFIX="${PREFIX:-/home/phablet/.local/lpac}"   # final path on the phone
LPAC_REF="${LPAC_REF:-main}"                    # lpac branch or tag
OUT="$(pwd)/lpac-arm64"

rm -rf "$OUT"
mkdir -p "$OUT"

docker run --rm --platform linux/arm64 -v "$OUT":/out -e P="$PREFIX" -e REF="$LPAC_REF" ubuntu:24.04 bash -c '
  set -e
  apt-get update
  apt-get install -y git cmake build-essential pkg-config \
    libglib2.0-dev libcurl4-openssl-dev libcriterion-dev

  # libglibutil + libgbinder are not packaged in Ubuntu 24.04.
  # They are only needed to COMPILE; at runtime the phone uses its own copies.
  git clone --depth 1 https://github.com/sailfishos/libglibutil /glibutil
  make -C /glibutil && make -C /glibutil install-dev
  git clone --depth 1 https://github.com/mer-hybris/libgbinder /gbinder
  make -C /gbinder && make -C /gbinder install-dev

  git clone --depth 1 --branch "$REF" https://github.com/estkme-group/lpac /src
  cd /src
  cmake -B build \
    -DBUILD_TESTING=OFF \
    -DLPAC_WITH_APDU_GBINDER=ON \
    -DLPAC_WITH_APDU_PCSC=OFF \
    -DLPAC_WITH_HTTP_CURL=ON \
    -DCMAKE_INSTALL_PREFIX="$P" \
    -DCMAKE_INSTALL_RPATH="$P/lib"
  cmake --build build -j"$(nproc)"
  DESTDIR=/out cmake --install build

  # lpac looks for its drivers in <first RUNPATH>/driver
  cd "/out$P/lib"
  mkdir -p driver
  mv driver_*.so driver/

  # Not needed on the phone
  rm -rf "/out$P/include" "/out$P/lib/pkgconfig" "/out$P/lib/cmake" /out"$P"/lib/*.a
'

tar -czf lpac-ut.tar.gz -C "$OUT$(dirname "$PREFIX")" "$(basename "$PREFIX")"
echo "Done: $(pwd)/lpac-ut.tar.gz"
