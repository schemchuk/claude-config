#!/usr/bin/env bash
# Restores MCP server configuration from mcp-servers.template.json via `claude mcp add --scope user`,
# then restores settings.json / skills/ / plugins backed up by backup.sh (claude-home/ + plugins.txt).
# Honors CLAUDE_CONFIG_DIR if set (defaults to ~/.claude).
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

  if claude mcp get "$name" >/dev/null 2>&1; then
    echo "MCP server $name already exists — skipped."
    continue
  fi

  echo "Adding MCP server: $name"
  claude mcp add "$name" --scope user "${env_args[@]}" -- "$cmd" "${args[@]}"
done

# --- Restore settings.json / skills/ / plugins from backup ---
CLAUDE_HOME="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
BACKUP_DIR="$SCRIPT_DIR/claude-home"
MANIFEST="$SCRIPT_DIR/plugins.txt"

if [[ -f "$BACKUP_DIR/settings.json" || -d "$BACKUP_DIR/skills" ]]; then
  mkdir -p "$CLAUDE_HOME"
fi

if [[ -f "$BACKUP_DIR/settings.json" ]]; then
  target="$CLAUDE_HOME/settings.json"
  if [[ -e "$target" ]] && ! cmp -s "$BACKUP_DIR/settings.json" "$target"; then
    bak="$target.bak.$(date +%Y%m%d%H%M%S)"
    cp -a "$target" "$bak"
    echo "Existing $target saved to $bak"
  fi
  cp -a "$BACKUP_DIR/settings.json" "$target"
  echo "Restored settings.json"
fi

if [[ -d "$BACKUP_DIR/skills" ]]; then
  target="$CLAUDE_HOME/skills"
  if [[ -d "$target" ]]; then
    bak="$target.bak.$(date +%Y%m%d%H%M%S)"
    mv "$target" "$bak"
    echo "Existing skills directory moved to $bak"
  fi
  cp -R "$BACKUP_DIR/skills" "$target"
  echo "Restored skills/"
fi

if [[ -f "$MANIFEST" ]]; then
  existing_marketplaces="$(claude plugin marketplace list --json | jq -r '.[].name')"
  while IFS= read -r line; do
    [[ "$line" =~ ^[[:space:]]*($|#) ]] && continue
    kind="${line%% *}"
    rest="${line#* }"
    case "$kind" in
      marketplace)
        name="${rest%% *}"
        source="${rest#* }"
        if grep -qxF "$name" <<<"$existing_marketplaces"; then
          echo "Marketplace $name already configured — skipped."
        else
          echo "Adding marketplace: $name ($source)"
          claude plugin marketplace add "$source" || echo "Warning: failed to add marketplace $name" >&2
        fi
        ;;
      plugin)
        echo "Installing plugin: $rest"
        claude plugin install "$rest" || echo "Warning: failed to install plugin $rest" >&2
        ;;
    esac
  done < "$MANIFEST"
fi

echo "Current MCP servers:"
claude mcp list

echo "Done."
