#!/usr/bin/env bash
# Build a flake package with an explicit psi executable expectation.

set -euo pipefail

: "${PACKAGE_ATTR:?PACKAGE_ATTR must name the flake package to build}"
: "${EXPECT_PSI:?EXPECT_PSI must be true or false}"
case "$EXPECT_PSI" in
  true|false) ;;
  *) echo "EXPECT_PSI must be true or false" >&2; exit 1 ;;
esac

nix_build_args=(--no-link --print-out-paths)
if [ -n "${NIX_BUILD_FLAGS:-}" ]; then
  read -r -a extra_nix_build_args <<< "$NIX_BUILD_FLAGS"
  nix_build_args+=("${extra_nix_build_args[@]}")
fi

out="$(nix build "${nix_build_args[@]}" ".#${PACKAGE_ATTR}")"
psi_bin="$out/bin/psi"

if [ "$EXPECT_PSI" = false ]; then
  echo "package ${PACKAGE_ATTR} built at ${out}; psi smoke test not requested"
  exit 0
fi
if [ ! -x "$psi_bin" ]; then
  echo "error: package ${PACKAGE_ATTR} is missing expected executable ${psi_bin}" >&2
  exit 1
fi

smoke_args=(--psi "$psi_bin" --no-live)
if [ -n "${SMOKE_EXCLUDES:-}" ]; then
  IFS=, read -r -a excludes <<< "$SMOKE_EXCLUDES"
  for exclude in "${excludes[@]}"; do
    smoke_args+=(--exclude "$exclude")
  done
fi

nix develop --command python3 tests/smoke.py "${smoke_args[@]}"
