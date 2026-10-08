#!/usr/bin/env bash
#
# This file is part of REANA.
# Copyright (C) 2026 CERN.
#
# REANA is free software; you can redistribute it and/or modify it
# under the terms of the MIT License; see LICENSE file for more details.

# Validate REANA specification files without a REANA server, by loading them
# with the same REANA-Workflow-Validator image that a REANA cluster uses.
#
# Usage: VALIDATOR_IMAGE=<image> validate.sh <reana-spec>...

set -o errexit
set -o nounset
set -o pipefail

image=${VALIDATOR_IMAGE:?"VALIDATOR_IMAGE is not set"}
report_start="===REANA-VALIDATION-REPORT-START==="
report_end="===REANA-VALIDATION-REPORT-END==="

if [ $# -eq 0 ]; then
    echo "==> ERROR: No REANA specification file to validate."
    exit 1
fi

failed=0
for file in "$@"; do
    echo "==> Verifying REANA specification file... $file"
    if [ ! -f "$file" ]; then
        echo "  -> ERROR: File not found."
        failed=1
        continue
    fi

    # The validator loads the specification named `reana.yaml` from a
    # read-only copy of the directory it lives in.
    bundle=$(mktemp -d "${RUNNER_TEMP:-${TMPDIR:-/tmp}}/reana-validate.XXXXXX")
    tar -cf - --exclude=./.git -C "$(dirname "$file")" . | tar -xf - -C "$bundle"
    if [ "$(basename "$file")" != "reana.yaml" ]; then
        rm -f "$bundle/reana.yml"
        cp "$file" "$bundle/reana.yaml"
    fi
    chmod -R a+rX "$bundle"

    status=0
    output=$(docker run --rm \
        --volume "$bundle:/validation/input:ro" \
        --tmpfs /validation/work:uid=1000 \
        "$image" 2>/dev/null) || status=$?
    rm -rf "$bundle"

    if [ "$status" -eq 0 ]; then
        echo "  -> SUCCESS: Valid REANA specification file."
    else
        report=$(echo "$output" | grep -F "$report_start" || true)
        report=${report#"$report_start"}
        report=${report%"$report_end"}
        message=$(echo "$report" | jq -r '.error.message // empty' 2>/dev/null || true)
        echo "  -> ERROR: ${message:-validator exited with status $status}"
        failed=1
    fi
done

exit $failed
