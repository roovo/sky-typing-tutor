#!/bin/bash
# Run all test files under tests/
set -e

failed=0
for f in tests/*Tests.sky; do
  echo "=== $f ==="
  if ! sky test "$f"; then
    failed=1
  fi
  echo
done

exit $failed
