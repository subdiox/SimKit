#!/usr/bin/env bash
# Copies tracked git hooks into .git/hooks. Re-run after cloning the repo.
set -euo pipefail

repo_root=$(git -C "$(dirname "$0")" rev-parse --show-toplevel)
src="$repo_root/scripts/pre-commit"
dst="$repo_root/.git/hooks/pre-commit"

install -m 0755 "$src" "$dst"
echo "Installed $dst"
