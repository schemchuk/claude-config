#!/usr/bin/env pwsh
# Restores MCP server configuration from mcp-servers.template.json via `claude mcp add --scope user`.
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

    Write-Host "Adding MCP server: $name"
    & claude mcp add $name --scope user @envArgs -- $cmd @cmdArgs
}

Write-Host "Done."
