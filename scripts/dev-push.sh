#!/usr/bin/env bash
set -e
cd "$(git rev-parse --show-toplevel)"
msg="${1:-wip}"
git add -A
git commit -m "$msg"
git push
