# claude-config

Backup/restore for my Claude Code MCP server configuration (`--scope user`), so I can set it up
identically on any new machine.

## Contents

- `mcp-servers.template.json` — list of MCP servers and their launch commands. API keys are
  placeholders like `${FIRECRAWL_API_KEY}`, resolved from environment variables at install time.
- `.env.example` — list of required environment variables (no real values).
- `install.sh` — installer for macOS/Linux (requires `jq`).
- `install.ps1` — installer for Windows (PowerShell).

> **Note:** only `playwright` was present in the original `~/.claude.json` when this repo was
> created. The `chrome-devtools`, `firecrawl`, and `perplexity` entries are scaffolding — verify
> the package names and required env vars still match before running the install script, then
> remove the `_comment` field from the template once confirmed.

## Setup on a new computer

1. Clone this repository:

   ```bash
   git clone <URL_ВАШОГО_РЕПО>
   cd claude-config
   ```

2. Copy `.env.example` to `.env` and fill in your real API keys:

   ```bash
   cp .env.example .env
   # edit .env in your editor
   ```

   `.env` is git-ignored and never committed.

3. Make sure the [Claude Code CLI](https://docs.claude.com/en/docs/claude-code) is installed and
   on your `PATH` (`claude --version`).

4. Run the installer for your OS.

   **macOS / Linux:**

   ```bash
   chmod +x install.sh
   ./install.sh
   ```

   Requires `jq` (`brew install jq` or `sudo apt install jq`).

   **Windows (PowerShell):**

   ```powershell
   .\install.ps1
   ```

5. Verify the servers were added:

   ```bash
   claude mcp list
   ```

## Updating the template

If you add/remove/reconfigure an MCP server locally, update `mcp-servers.template.json` to match
(replace any secret values with `${ENV_VAR_NAME}` placeholders) and add the corresponding variable
to `.env.example`, then commit.
