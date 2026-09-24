# NinjaOne Scripts: AI Assistance for GitHub Copilot and Claude Code

This repository adds NinjaOne RMM platform knowledge to **GitHub Copilot** and **Claude Code**. Copy the included directories and files into your existing NinjaOne scripts repository to get contextual suggestions, type-conversion helpers, API patterns, and WYSIWYG formatting guidance — specific to the NinjaOne platform.

---

## Repository Structure

```
AGENTS.md                                           # Shared project overview (Copilot/Codex)
CLAUDE.md                                           # Claude Code project instructions

.github/
  instructions/
    ninjaone-scripting-guidelines.instructions.md   # Auto-applied to *.ps1 files (Copilot)

.claude/
  .markdownlint.jsonc                               # Lint config for skill/agent Markdown
  skills/
    ninjaone-api/SKILL.md                           # REST API v2
    ninjaone-environment-variables/SKILL.md         # $env:NINJA_* variables
    ninjaone-script-variables/SKILL.md              # Type conversion, ConvertTo-TypedValue
    ninjaone-custom-fields/SKILL.md                 # Get-NinjaProperty / Set-NinjaProperty
    ninjaone-cli/SKILL.md                           # ninjarmm-cli and legacy cmdlets
    ninjaone-wysiwyg/SKILL.md                       # HTML/CSS for WYSIWYG fields
    ninjaone-tags/SKILL.md                          # Device tagging
  agents/
    ninjaone-expert.md                              # All-domains expert agent (both tools)
```

---

## Available Skills

Seven skill files cover all major NinjaOne platform domains:

| Skill | What it covers |
|-------|----------------|
| `ninjaone-api` | REST API v2: OAuth2, pagination, device filters (`df=`), bulk operations, rate limiting |
| `ninjaone-environment-variables` | All `$env:NINJA_*` agent-provided variables — org name, node ID, data path, and more |
| `ninjaone-script-variables` | Script parameter types, wire formats, and the `ConvertTo-TypedValue` type conversion helper |
| `ninjaone-custom-fields` | `Get-NinjaProperty` / `Set-NinjaProperty` with all field types; GUID vs friendly name for dropdowns |
| `ninjaone-cli` | `ninjarmm-cli` commands, documentation template access, legacy `Ninja-Property-*` cmdlets |
| `ninjaone-wysiwyg` | Allowed HTML/CSS, NinjaOne CSS classes, Charts.css, Bootstrap 5, Font Awesome 6 |
| `ninjaone-tags` | Device tagging via PowerShell module and CLI; automation-only constraints |

Both Copilot and Claude Code read from the same skill files — answers are consistent regardless of which tool you use.

---

## Setup

Copy these directories and files into the root of your scripting repository:

```
.github/
.claude/
AGENTS.md
CLAUDE.md
```

Both GitHub Copilot and Claude Code discover the skills, expert agent, and instructions natively. No other configuration is required.

---

## Using with GitHub Copilot

### Automatic context (inline suggestions)

The instructions file is applied automatically to all `.ps1` and `.psm1` files via the `applyTo` field in its frontmatter. Once copied, Copilot will use NinjaOne-aware guidance whenever you edit a PowerShell script — no extra steps needed.

The instructions file includes:

- A standard script template with `ConvertTo-TypedValue` usage
- Quick-reference tables for all `$env:NINJA_*` environment variables and script variable wire formats
- A 16-item best practices summary

### Loading skill files in Copilot chat

Copilot discovers the skills in `.claude/skills/` automatically and loads the relevant one when your request matches its description. To force a specific skill into context, reference it directly in Copilot chat using the `#file:` syntax:

```
#file:.claude/skills/ninjaone-api/SKILL.md
How do I query all offline Windows servers in org 123?
```

```
#file:.claude/skills/ninjaone-script-variables/SKILL.md
How do I convert a checkbox script variable to a boolean?
```

```
#file:.claude/skills/ninjaone-wysiwyg/SKILL.md
Generate an HTML status card for a service health report.
```

### The ninjaone-expert agent in Copilot

The `ninjaone-expert` agent in `.claude/agents/` is also discovered by Copilot. Select it from the agent picker in the Chat view for multi-domain NinjaOne questions.

---

## Using with Claude Code

[Claude Code](https://claude.ai/code) is Anthropic's official CLI for Claude — it runs in your terminal alongside your codebase and has direct access to your local files. Install it from `claude.ai/code`.

### Automatic context

When you open this repository in Claude Code, `CLAUDE.md` is loaded automatically as project context. Claude Code will use NinjaOne-aware guidance in all responses without any extra steps.

### Loading skills

Invoke a skill by name using the `Skill` tool or by asking Claude Code to use it:

```
Use ninjaone-script-variables to help me convert these script variables
```

```
Load the ninjaone-api skill and show me how to page through all devices
```

### The ninjaone-expert agent

For multi-domain questions — for example, reading a dropdown custom field and writing WYSIWYG output — use the `ninjaone-expert` agent. It consolidates all seven skill domains into a single expert persona with persistent memory for project-specific patterns.

Invoke it with:

```
Use the ninjaone-expert agent
```

Example questions well-suited to the expert agent:

- "Write a script that reads a Dropdown field and generates a WYSIWYG status report"
- "What environment variables does NinjaOne inject, and how do I use the node ID in an API call?"
- "How do I handle a secure field safely in an automation script?"

---

## Tips

- **Start simple** — for most scripts, the auto-applied instructions file is enough. Load a skill file only when you need deep reference on a specific domain.
- **Use the standard template** — ask either tool to "use the standard NinjaOne script template" when starting a new script. Both will use the same `ConvertTo-TypedValue`-based template.
- **Keep skills up to date** — when NinjaOne releases new platform features, update the relevant SKILL.md file. Both Copilot and Claude Code will benefit immediately.
- **Character limits to remember** — Text: 200 chars, MultiLine: 10,000, Secure: 200–10,000, WYSIWYG: 200,000.
