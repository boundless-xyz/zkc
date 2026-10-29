#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
report_dir="${SUNSET_REPORT_DIR:-$PWD/out/sunset-fork-reports}"
mkdir -p "$report_dir"
SUNSET_ARTIFACT_ROOT=out/sunset-fork FOUNDRY_BUILD_INFO_PATH=out/sunset-fork/build-info FOUNDRY_PROFILE=default FOUNDRY_FFI=false FOUNDRY_TEST=fork-test forge test --offline \
  --out out/sunset-fork --cache-path cache/sunset-fork \
  --fork-url "${ETHEREUM_RPC_URL:-https://eth.drpc.org}" \
  --fork-block-number "${SUNSET_BLOCK_NUMBER:-26276732}" --match-contract ZKCForkTest -vv \
  2>&1 | tee "$report_dir/zkc.log"
