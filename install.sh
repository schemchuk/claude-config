#!/usr/bin/env bash
# Restores MCP server configuration from mcp-servers.template.json via `claude mcp add --scope user`.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMPLATE="$SCRIPT_DIR/mcp-servers.template.json"
ENV_FILE="$SCRIPT_DIR/.env"

command -v claude >/dev/null 2>&1 || { echo "Error: 'claude' CLI not found in PATH." >&2; exit 1; }
command -v jq >/dev/null 2>&1 || { echo "Error: 'jq' is required (e.g. 'brew install jq' or 'sudo apt install jq')." >&2; exit 1; }

if [[ -f "$ENV_FILE" ]]; then
  set -a
  # shellcheck disable=SC1090
  source "$ENV_FILE"
  set +a
else
  echo "Warning: $ENV_FILE not found. Copy .env.example to .env and fill in your keys first." >&2
fi

count=$(jq '.servers | length' "$TEMPLATE")

for ((i = 0; i < count; i++)); do
  name=$(jq -r ".servers[$i].name" "$TEMPLATE")
  cmd=$(jq -r ".servers[$i].command" "$TEMPLATE")
  mapfile -t args < <(jq -r ".servers[$i].args[]?" "$TEMPLATE")

  env_args=()
  while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    key="${line%%=*}"
    raw_value="${line#*=}"

    # Resolve ${VAR} placeholders against the current environment without eval.
    if [[ "$raw_value" =~ ^\$\{([A-Za-z_][A-Za-z0-9_]*)\}$ ]]; then
      var_name="${BASH_REMATCH[1]}"
      expanded_value="${!var_name:-}"
    else
      expanded_value="$raw_value"
    fi

    if [[ -z "$expanded_value" ]]; then
      echo "Warning: env var for $name/$key is empty. Set it in .env before running." >&2
    fi
    env_args+=(-e "$key=$expanded_value")
  done < <(jq -r ".servers[$i].env // {} | to_entries[] | \"\(.key)=\(.value)\"" "$TEMPLATE")

  echo "Adding MCP server: $name"
  claude mcp add "$name" --scope user "${env_args[@]}" -- "$cmd" "${args[@]}"
done

echo "Done."
