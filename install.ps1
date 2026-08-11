#!/usr/bin/env pwsh
# Restores MCP server configuration from mcp-servers.template.json via `claude mcp add --scope user`,
# then restores settings.json / skills/ / plugins backed up by backup.ps1 (claude-home/ + plugins.txt).
# Honors CLAUDE_CONFIG_DIR if set (defaults to ~/.claude).
$ErrorActionPreference = "Stop"

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$Template = Join-Path $ScriptDir "mcp-servers.template.json"
$EnvFile = Join-Path $ScriptDir ".env"

if (-not (Get-Command claude -ErrorAction SilentlyContinue)) {
    Write-Error "Error: 'claude' CLI not found in PATH."
    exit 1
}

$envVars = @{}
if (Test-Path $EnvFile) {
    Get-Content $EnvFile | ForEach-Object {
        $line = $_.Trim()
        if ($line -eq "" -or $line.StartsWith("#")) { return }
        $parts = $line -split "=", 2
        if ($parts.Count -eq 2) {
            $envVars[$parts[0].Trim()] = $parts[1].Trim()
        }
    }
} else {
    Write-Warning "$EnvFile not found. Copy .env.example to .env and fill in your keys first."
}

function Resolve-Value([string]$raw) {
    if ($raw -match '^\$\{([A-Za-z_][A-Za-z0-9_]*)\}$') {
        $varName = $Matches[1]
        if ($envVars.ContainsKey($varName)) { return $envVars[$varName] }
        $fromEnv = [Environment]::GetEnvironmentVariable($varName)
        if ($fromEnv) { return $fromEnv }
        return ""
    }
    return $raw
}

$config = Get-Content $Template -Raw | ConvertFrom-Json

foreach ($server in $config.servers) {
    $name = $server.name
    $cmd = $server.command
    $cmdArgs = @()
    if ($server.args) { $cmdArgs = @($server.args) }

    $envArgs = @()
    if ($server.env) {
        foreach ($prop in $server.env.PSObject.Properties) {
            $value = Resolve-Value $prop.Value
            if ([string]::IsNullOrEmpty($value)) {
                Write-Warning "Env var for $name/$($prop.Name) is empty. Set it in .env before running."
            }
            $envArgs += "-e"
            $envArgs += "$($prop.Name)=$value"
        }
    }

    & claude mcp get $name 2>&1 | Out-Null
    if ($LASTEXITCODE -eq 0) {
        Write-Host "MCP server $name already exists - skipped."
        continue
    }

    Write-Host "Adding MCP server: $name"
    & claude mcp add $name --scope user @envArgs -- $cmd @cmdArgs
}

# --- Restore settings.json / skills/ / plugins from backup ---
$ClaudeHome = if ($env:CLAUDE_CONFIG_DIR) { $env:CLAUDE_CONFIG_DIR } else { Join-Path $HOME ".claude" }
$BackupDir = Join-Path $ScriptDir "claude-home"
$Manifest = Join-Path $ScriptDir "plugins.txt"
$Stamp = Get-Date -Format yyyyMMddHHmmss

$BackupSettings = Join-Path $BackupDir "settings.json"
if (Test-Path $BackupSettings) {
    New-Item -ItemType Directory -Force -Path $ClaudeHome | Out-Null
    $target = Join-Path $ClaudeHome "settings.json"
    if ((Test-Path $target) -and
        ((Get-FileHash $BackupSettings).Hash -ne (Get-FileHash $target).Hash)) {
        $bak = "$target.bak.$Stamp"
        Copy-Item $target $bak -Force
        Write-Host "Existing $target saved to $bak"
    }
    Copy-Item $BackupSettings $target -Force
    Write-Host "Restored settings.json"
}

$BackupSkills = Join-Path $BackupDir "skills"
if (Test-Path $BackupSkills) {
    New-Item -ItemType Directory -Force -Path $ClaudeHome | Out-Null
    $target = Join-Path $ClaudeHome "skills"
    if (Test-Path $target) {
        $bak = "$target.bak.$Stamp"
        Move-Item $target $bak
        Write-Host "Existing skills directory moved to $bak"
    }
    Copy-Item $BackupSkills $target -Recurse -Force
    Write-Host "Restored skills/"
}

if (Test-Path $Manifest) {
    $existing = @(claude plugin marketplace list --json | ConvertFrom-Json | ForEach-Object { $_.name })
    foreach ($line in Get-Content $Manifest) {
        if ($line -match '^\s*($|#)') { continue }
        $parts = $line -split ' ', 3
        if ($parts[0] -eq "marketplace") {
            if ($existing -contains $parts[1]) {
                Write-Host "Marketplace $($parts[1]) already configured - skipped."
            } else {
                Write-Host "Adding marketplace: $($parts[1]) ($($parts[2]))"
                claude plugin marketplace add $parts[2]
            }
        } elseif ($parts[0] -eq "plugin") {
            Write-Host "Installing plugin: $($parts[1])"
            claude plugin install $parts[1]
        }
    }
}

Write-Host "Done."
