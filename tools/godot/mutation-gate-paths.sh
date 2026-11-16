#!/usr/bin/env bash
# Decides whether a pull request needs the mutation gate's expensive work (mutation-gate.yml).
# Reads the changed file names, one per line (for a rename, both the new and the old name), on standard input and
# prints one line, `docs_only=true` or `docs_only=false`, for $GITHUB_OUTPUT.
#
# The gate is a REQUIRED check, so its workflow must trigger on every pull request (a workflow skipped by a path
# filter never reports its check and a required check would stay pending for ever); instead, this decides inside it.
# docs_only=true only when EVERY changed file is one that cannot affect the game, its build or its checks:
#   docs/**                          documentation and its reference captures
#   *.md in the repository root      README, GLOSSARY, AGENTS, ...
#   .github/*.md                     contributing and similar notes
#   .github/ISSUE_TEMPLATE/**        issue templates
#   LICENSE*                         in the repository root
# Everything else gates the pull request by default: godot/**, tools/**, game/** (the Python behavioural reference
# the captures use), build-godot.sh, every workflow including build.yml, and any file or directory added tomorrow.
# An empty list (the API call failed, say) is NOT docs-only: when in doubt the gate runs.
set -Eeuo pipefail

ignored() { # path
  local path="$1"
  case "$path" in
    docs/*|.github/ISSUE_TEMPLATE/*) return 0 ;;
  esac
  if [[ "$path" != */* && ( "$path" == *.md || "$path" == LICENSE* ) ]]; then return 0; fi
  if [[ "$path" == .github/*.md && "${path#.github/}" != */* ]]; then return 0; fi
  return 1
}

seen=0
while IFS= read -r path; do
  [[ -n "$path" ]] || continue
  seen=1
  if ! ignored "$path"; then echo "docs_only=false"; exit 0; fi
done
if ((seen)); then echo "docs_only=true"; else echo "docs_only=false"; fi
