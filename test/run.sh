#!/bin/bash

# Runs every test/*-test.sh and stops at the first failure. `bash test/run.sh`
# is what CI runs; each file also runs on its own.

set -euo pipefail

cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.."

status=0
for test in test/*-test.sh; do
  [[ $(basename "$test") == base-test.sh ]] && continue
  echo "# $test"
  if ! bash "$test"; then
    status=1
    break
  fi
done

if (( status == 0 )); then
  echo "# all tests passed"
else
  echo "# a test failed" >&2
fi
exit $status
