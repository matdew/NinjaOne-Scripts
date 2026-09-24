# AGENTS.md

Shared project guidance for AI coding agents (GitHub Copilot, Claude Code, and other
AGENTS.md-aware tools) working in this repository.

## Repository Overview

This repository contains PowerShell automation scripts for the NinjaOne RMM
platform. Scripts integrate with the NinjaOne agent environment, REST API v2, and platform
services (custom fields, tags, WYSIWYG reporting).

## Where the NinjaOne knowledge lives

All customizations are stored in locations that both Claude Code and VS Code GitHub Copilot
discover **natively** — no manual loading required:

| Type | Location | Discovered by |
| --- | --- | --- |
| Skills (7 domains) | `.claude/skills/<name>/SKILL.md` | Claude Code + VS Code Copilot |
| Expert agent | `.claude/agents/ninjaone-expert.md` | Claude Code + VS Code Copilot |
| PowerShell scripting rules | `.github/instructions/ninjaone-scripting-guidelines.instructions.md` | VS Code Copilot (auto-applied to `*.ps1`/`*.psm1`) |
| Always-on project context | `CLAUDE.md` (Claude Code), this `AGENTS.md` (Copilot/Codex) | Both |

### Skills

| Skill | When to use |
| --- | --- |
| `ninjaone-api` | REST API v2 — OAuth2, pagination, device filters, bulk operations |
| `ninjaone-environment-variables` | `$env:NINJA_*` agent-provided context variables |
| `ninjaone-script-variables` | Script parameter types, type conversion, preset parameters |
| `ninjaone-custom-fields` | `Get-NinjaProperty` / `Set-NinjaProperty` with all field types |
| `ninjaone-cli` | `ninjarmm-cli` tool and legacy PowerShell commands |
| `ninjaone-wysiwyg` | HTML/CSS formatting for WYSIWYG custom fields |
| `ninjaone-tags` | Device tagging via PowerShell cmdlets and CLI |

For multi-domain questions, use the `ninjaone-expert` agent, which consolidates all seven
skill domains into a single expert persona.

## Key Scripting Conventions

### Script structure

Scripts follow a standard three-section pattern:

1. `SYNOPSIS`/`DESCRIPTION` block — document NinjaOne script variables and env vars used
2. `#region Script Variables Validation` — validate and convert all `$env:` script variables
3. `#region Main Script Logic` — wrapped in `try`/`catch` with exit codes

### Exit codes

- `exit 0` — success
- `exit 1` — general failure
- `exit 2+` — specific error conditions (document meaning in the script header)

### Script variables

NinjaOne injects script variables as environment variables using **camelCase** — the first
letter is lowercased and subsequent words are capitalized (never PascalCase). Custom field
names follow the same pattern. All values arrive as strings; convert explicitly:

```powershell
$enabled = [bool]::Parse($env:enableFeature)   # Checkbox -> bool  (variable "Enable Feature")
$count   = [int]$env:maxCount                  # Integer  -> int   (variable "Max Count")
$date    = [datetime]$env:targetDate           # Date     -> datetime
```

Guard non-mandatory variables with `[string]::IsNullOrWhiteSpace(...)` — they arrive as `""`.

### Custom fields (preferred approach)

Use `Get-NinjaProperty` and `Set-NinjaProperty` (not legacy CLI) for custom field access:

```powershell
$value = Get-NinjaProperty -Name 'fieldName' -Type Text
Set-NinjaProperty -Name 'fieldName' -Type Text -Value 'result'
```

Character limits: Text (200), MultiLine (10,000), Secure (200–10,000), WYSIWYG (200,000).
Fields auto-collapse above 10,000 chars.

### Secrets

Never hardcode credentials. Use `$env:` variables or prompt at runtime with
`Read-Host -AsSecureString`. Only access secure custom fields during automation execution;
never echo secure values.
