# CLAUDE.md

This file provides guidance to Claude Code when working in this repository.

## Repository Overview

This repository contains PowerShell automation scripts for the NinjaOne RMM platform. Scripts integrate with the NinjaOne agent environment, REST API v2, and platform services (custom fields, tags, WYSIWYG reporting).

## Skills

All NinjaOne-specific knowledge lives in `.claude/skills/`. Invoke skills via the `Skill` tool by name.

| Skill | When to Use |
|-------|-------------|
| `ninjaone-api` | REST API v2 — OAuth2, pagination, device filters, bulk operations |
| `ninjaone-environment-variables` | `$env:NINJA_*` agent-provided context variables |
| `ninjaone-script-variables` | Script parameter types, type conversion, preset parameters |
| `ninjaone-custom-fields` | `Get-NinjaProperty` / `Set-NinjaProperty` with all field types |
| `ninjaone-cli` | `ninjarmm-cli` tool and legacy PowerShell commands |
| `ninjaone-wysiwyg` | HTML/CSS formatting for WYSIWYG custom fields |
| `ninjaone-tags` | Device tagging via PowerShell cmdlets and CLI |

For API reference material (pagination helpers, device filter examples), see:

- `.claude/skills/ninjaone-api/references/api-examples.md`
- `.claude/skills/ninjaone-api/references/device-filters.md`

## NinjaOne Expert Agent

The `ninjaone-expert` agent consolidates all seven skill domains into a single expert persona.

- **Location:** `.claude/agents/ninjaone-expert.md`
- **Model:** Sonnet
- **Memory:** Persistent at `.claude/agent-memory-local/ninjaone-expert/`

Invoke for any multi-domain NinjaOne question (e.g., read a dropdown field and write WYSIWYG output).

## Key Scripting Conventions

### Script Structure

Scripts follow a standard three-section pattern:

1. SYNOPSIS/DESCRIPTION block — document NinjaOne script variables and env vars used
2. `#region Script Variables Validation` — validate and convert all `$env:` script variables
3. `#region Main Script Logic` — wrapped in `try`/`catch` with exit codes

### Exit Codes

- `exit 0` — success
- `exit 1` — general failure
- `exit 2+` — specific error conditions (document meaning in script header)

### Script Variables

NinjaOne injects script variables as environment variables (`$env:variableName` — camelCase, lowercase first letter). All arrive as strings — convert explicitly:

```powershell
$enabled = [bool]::Parse($env:enableFeature)   # Checkbox -> bool
$count   = [int]$env:maxCount                  # Integer -> int
$date    = [datetime]$env:targetDate           # Date    -> datetime
```

### Custom Fields (Preferred Approach)

Use `Get-NinjaProperty` and `Set-NinjaProperty` (not legacy CLI) for custom field access:

```powershell
$value = Get-NinjaProperty -Name 'fieldName' -Type Text
Set-NinjaProperty -Name 'fieldName' -Type Text -Value 'result'
```

Character limits: Text: 200 chars, MultiLine: 10,000 chars, WYSIWYG: 200,000 chars. Fields auto-collapse above 10,000 chars.

### Secrets

Never hardcode credentials. Use `$env:` variables or prompt at runtime with `Read-Host -AsSecureString`.
