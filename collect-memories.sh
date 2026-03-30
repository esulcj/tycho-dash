#!/bin/bash
# Collect Gas Town memories into JSON for the memory viewer widget.
# Output: memories.json to stdout

set -euo pipefail

MEMORIES_JSON="[]"

# Collect each type separately for structured output
for mtype in feedback user project reference general; do
  raw=$(gt memories --type "$mtype" 2>/dev/null || true)
  if [ -z "$raw" ] || echo "$raw" | grep -q "^No memories"; then
    continue
  fi

  # Parse the gt memories output: lines like:
  #   [type]
  #   key-slug
  #     Value text
  current_key=""
  current_value=""

  while IFS= read -r line; do
    # Skip empty lines and type headers
    if [ -z "$line" ] || echo "$line" | grep -qE '^\s*\['; then
      continue
    fi

    # Lines starting with spaces (2+) followed by non-space = key
    # Lines starting with 4+ spaces = value
    if echo "$line" | grep -qE '^  [^ ]'; then
      # Save previous entry if exists
      if [ -n "$current_key" ] && [ -n "$current_value" ]; then
        MEMORIES_JSON=$(echo "$MEMORIES_JSON" | jq --arg k "$current_key" --arg v "$current_value" --arg t "$mtype" \
          '. + [{"key": $k, "value": $v, "type": $t}]')
      fi
      current_key=$(echo "$line" | sed 's/^  //')
      current_value=""
    elif echo "$line" | grep -qE '^    '; then
      current_value=$(echo "$line" | sed 's/^    //')
    fi
  done <<< "$raw"

  # Save last entry
  if [ -n "$current_key" ] && [ -n "$current_value" ]; then
    MEMORIES_JSON=$(echo "$MEMORIES_JSON" | jq --arg k "$current_key" --arg v "$current_value" --arg t "$mtype" \
      '. + [{"key": $k, "value": $v, "type": $t}]')
  fi
done

TIMESTAMP=$(date -u +%Y-%m-%dT%H:%M:%SZ)
COUNT=$(echo "$MEMORIES_JSON" | jq 'length')

jq -n --argjson memories "$MEMORIES_JSON" --arg timestamp "$TIMESTAMP" --argjson count "$COUNT" \
  '{"timestamp": $timestamp, "count": $count, "memories": $memories}'
