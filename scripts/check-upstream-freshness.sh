#!/usr/bin/env bash
set -euo pipefail

UPSTREAM="https://github.com/ballast-ai/token-station.git"
COMPATIBILITY="compatibility.json"
while [ $# -gt 0 ]; do
    case "$1" in
        --upstream) UPSTREAM=$2; shift 2 ;;
        --compatibility) COMPATIBILITY=$2; shift 2 ;;
        *) echo "unknown argument: $1" >&2; exit 2 ;;
    esac
done

MIRRORED_TAG=$(python3 -c \
    "import json; print(json.load(open('$COMPATIBILITY'))['mirror']['source_tag'])")
MIRRORED_COMMIT=$(python3 -c \
    "import json; print(json.load(open('$COMPATIBILITY'))['mirror']['source_commit'])")
REMOTE_TAGS=$(git ls-remote --tags "$UPSTREAM" 'kernel-v*')
LATEST=$(printf '%s\n' "$REMOTE_TAGS" \
    | awk '{print $2}' \
    | sed 's#refs/tags/##; s#\^{}##' \
    | sort -uV \
    | tail -1)

if [ -z "$LATEST" ]; then
    echo "could not list upstream kernel source tags" >&2
    exit 1
fi
PEELED_COMMIT=$(printf '%s\n' "$REMOTE_TAGS" \
    | awk -v ref="refs/tags/$LATEST^{}" '$2 == ref { print $1 }')
if [ -z "$PEELED_COMMIT" ]; then
    echo "latest upstream kernel source must be an annotated tag: $LATEST" >&2
    exit 1
fi

echo "mirrored_tag=$MIRRORED_TAG latest_tag=$LATEST"
echo "mirrored_commit=$MIRRORED_COMMIT latest_peeled_commit=$PEELED_COMMIT"
if [ "$MIRRORED_TAG" != "$LATEST" ]; then
    echo "mirror is at $MIRRORED_TAG but upstream's newest kernel source tag is $LATEST" >&2
    exit 1
fi
if [ "$MIRRORED_COMMIT" != "$PEELED_COMMIT" ]; then
    echo "mirror source commit $MIRRORED_COMMIT does not match $LATEST peeled commit $PEELED_COMMIT" >&2
    exit 1
fi
