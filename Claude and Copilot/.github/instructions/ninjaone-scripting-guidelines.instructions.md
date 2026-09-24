---
applyTo: '**/*.ps1,**/*.psm1'
description: 'NinjaOne RMM platform-specific PowerShell scripting guidelines for automation scripts, ensuring proper handling of environment variables, script variables, and platform integration.'
---

# NinjaOne PowerShell Scripting Guidelines

This guide provides NinjaOne RMM platform-specific instructions for GitHub Copilot to generate scripts that work seamlessly with the NinjaOne agent environment. These guidelines extend the general PowerShell cmdlet development guidelines with NinjaOne-specific patterns.

## Related Skills

This instruction set works with the following specialized skill files in `.claude/skills/`. Both Claude Code and VS Code GitHub Copilot discover these skills automatically; you can also load one on demand in Copilot chat with `#file:.claude/skills/<skill-name>/SKILL.md`.

- **ninjaone-api** (`#file:.claude/skills/ninjaone-api/SKILL.md`) - REST API v2 for automation, integration, and data retrieval via HTTP requests
- **ninjaone-environment-variables** (`#file:.claude/skills/ninjaone-environment-variables/SKILL.md`) - NinjaOne agent environment variables and organization context
- **ninjaone-script-variables** (`#file:.claude/skills/ninjaone-script-variables/SKILL.md`) - Script variables, preset parameters, and type conversion
- **ninjaone-custom-fields** (`#file:.claude/skills/ninjaone-custom-fields/SKILL.md`) - Custom fields access via PowerShell module (Get-NinjaProperty, Set-NinjaProperty)
- **ninjaone-cli** (`#file:.claude/skills/ninjaone-cli/SKILL.md`) - ninjarmm-cli tool usage and legacy PowerShell commands
- **ninjaone-wysiwyg** (`#file:.claude/skills/ninjaone-wysiwyg/SKILL.md`) - WYSIWYG fields, HTML formatting, Bootstrap 5, Charts.css, and visual reporting
- **ninjaone-tags** (`#file:.claude/skills/ninjaone-tags/SKILL.md`) - Device tagging operations via PowerShell cmdlets and CLI for classification and filtering

## Core NinjaOne Concepts

### Platform Overview

NinjaOne RMM provides three primary mechanisms for script configuration:

1. **Environment Variables** (`$env:NINJA_*`) - Agent-provided context (organization, location, paths)
2. **Script Variables** (`$env:variableName`) - User-defined parameters converted to environment variables
3. **Custom Fields** - Persistent device and organization data accessed via PowerShell module or CLI

> **Script variable and custom field name → env var conversion:**
> NinjaOne lowercases the first letter of the name and camelCases the rest (spaces removed).
> Both **script variable names** and **custom field names** follow this camelCase pattern — lowercase first letter, uppercase subsequent words, never PascalCase.
>
> - `Port` becomes `$env:port`
> - `Server Name` becomes `$env:serverName`
> - `Output File` becomes `$env:outputFile`
>
> Always reference variables with camelCase `$env:` names (lowercase first letter).

### Standard Script Structure

```powershell
<#
.SYNOPSIS
    Brief description of what the script does.

.DESCRIPTION
    Detailed description of the script functionality and NinjaOne integration.

.NOTES
    NinjaOne Script Variables (define these in the NinjaOne platform):
    - VariableName1 (Type): Description and default value if any
    - VariableName2 (Type): Description and default value if any

    NinjaOne Environment Variables Used:
    - NINJA_ORGANIZATION_NAME
    - NINJA_DATA_PATH (or other relevant variables)

.EXAMPLE
    This script is designed to run via NinjaOne RMM.
    Configure script variables in the NinjaOne platform before deployment.
#>

[CmdletBinding()]
param()

#region Script Variables Validation
Write-Verbose "Validating script variables for org: $env:NINJA_ORGANIZATION_NAME"

$requiredVar = $env:requiredVariable
if ([string]::IsNullOrWhiteSpace($requiredVar)) {
    Write-Error "Required variable 'requiredVariable' is not set"
    exit 1
}

$optionalPort    = ConvertTo-TypedValue -Value $env:port    -Type 'Int32'   -DefaultValue 443   -Min 1 -Max 65535
$optionalEnabled = ConvertTo-TypedValue -Value $env:enabled -Type 'Boolean' -DefaultValue $false

Write-Verbose "Variables validated"
#endregion

#region Main Script Logic
try {
    Write-Verbose "Starting in org: $env:NINJA_ORGANIZATION_NAME (node: $env:NINJA_AGENT_NODE_ID)"

    # Main script functionality here

    Write-Output "Script completed successfully"
    exit 0
} catch {
    Write-Error "Script failed: $_"
    exit 1
}
#endregion
```

## Quick Reference

### Environment Variables (`$env:NINJA_*`)

Available in all script types on all platforms. Require a device reboot to refresh if changed.

| Variable | Description |
| --- | --- |
| `$env:NINJA_EXECUTING_PATH` | Agent install directory |
| `$env:NINJA_AGENT_VERSION_INSTALLED` | Installed agent version |
| `$env:NINJA_PATCHER_VERSION_INSTALLED` | Installed patcher version |
| `$env:NINJA_DATA_PATH` | Agent data folder (scripts, logs, downloads) |
| `$env:NINJA_AGENT_PASSWORD` | Agent password for session key auth — never log in plain text |
| `$env:NINJA_AGENT_MACHINE_ID` | Machine ID on NinjaOne server |
| `$env:NINJA_AGENT_NODE_ID` | Node ID for API calls and device identification |
| `$env:NINJA_ORGANIZATION_NAME` | Organization name |
| `$env:NINJA_ORGANIZATION_ID` | Organization ID |
| `$env:NINJA_COMPANY_NAME` | Company name |
| `$env:NINJA_LOCATION_NAME` | Location name |
| `$env:NINJA_LOCATION_ID` | Location ID |

### Script Variable Wire Formats

NinjaOne converts all script variables to environment variables at runtime. **All arrive as strings — explicit type conversion is required.**

| Type | Wire Format | Example |
| --- | --- | --- |
| String/Text | Plain string | `"Hello World"` |
| Integer | String digits | `"314"` |
| Decimal | String float | `"3.14"` |
| Checkbox | `"true"` / `"false"` | `"true"` |
| Date | ISO 8601 | `"2024-01-15T00:00:00.000+00:00"` |
| Date/Time | ISO 8601 with time | `"2023-07-28T03:00:00.000+01:00"` |
| DropDown | Selected value string | `"Production"` |
| IP Address | IP string | `"192.168.1.100"` |

## Error Handling and Exit Codes

- **Exit Codes:** Use standard exit codes for NinjaOne monitoring
  - `exit 0` - Success
  - `exit 1` - General failure
  - `exit 2+` - Specific error conditions (document meaning)

- **Output Streams:**
  - Use `Write-Output` for results that should appear in NinjaOne script output
  - Use `Write-Verbose` for detailed logging (enable with `-Verbose` in script settings)
  - Use `Write-Warning` for non-critical issues
  - Use `Write-Error` for errors that should be visible in NinjaOne alerts

- **Logging:**
  - Script output is captured by NinjaOne and viewable in the activity log
  - Use structured output with `Write-Output` for important information
  - Consider external logging solutions for persistent logs if needed

### Example: NinjaOne Error Handling

```powershell
function Invoke-NinjaOperation {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$OperationName
    )

    begin {
        Write-Verbose "Starting operation: $OperationName"
    }

    process {
        try {
            Write-Verbose "Executing operation: $OperationName"

            # Operation logic here

            Write-Output "Operation '$OperationName' completed successfully"

        } catch {
            $errorMessage = $_.Exception.Message
            Write-Error "Operation '$OperationName' failed: $errorMessage"
            throw
        }
    }
}

# Main script execution with exit codes
try {
    Invoke-NinjaOperation -OperationName "SystemCheck"
    exit 0
} catch {
    Write-Error "Script failed: $_"
    exit 1
}
```

## Best Practices Summary

1. **Validate mandatory script variables** - Check for null or empty values and fail fast with a clear error message
2. **Use NinjaOne environment variables** - Use `$env:NINJA_*` variables for organization/location context
3. **Implement proper exit codes** - `0` success, `1+` failure; document each code in `.NOTES`
4. **Use Write-Output for results** - Script output is captured in NinjaOne activity log
5. **Document script variables** - Document expected types, defaults, and valid ranges in script header
6. **Use explicit type conversion when it adds value** - PowerShell handles most implicit conversions from string; reach for `ConvertTo-TypedValue` when you need range validation or safe fallback defaults
7. **Test with empty values** - Non-mandatory variables arrive as `""` — ensure scripts handle gracefully
8. **Consider multi-tenancy** - Include `$env:NINJA_ORGANIZATION_NAME` in log output
9. **Avoid naming conflicts** - Avoid naming script variables identically to existing system environment variables
10. **Use enhanced PowerShell cmdlets** - Prefer `Get-NinjaProperty` and `Set-NinjaProperty` over legacy `Ninja-Property-*` commands
11. **Secure field protection** - Only access secure fields during automation execution; never echo secure values
12. **Documentation organization** - Use documentation templates for structured, multi-device configuration data
13. **Custom field validation** - Validate custom field formats (email, IP, phone, URL) before writing
14. **Structure output for readability** - Structure script output for activity log readability — NinjaOne captures all output
15. **Unicode support** - Full Unicode including emojis is supported in all text fields and CLI
16. **Character limits** - Text (200), MultiLine (10,000), Secure (200–10,000), WYSIWYG (200,000)
17. **Reference related skills** - When using tags, custom fields, API operations, or WYSIWYG formatting, load the corresponding skill file in `.claude/skills/` for detailed patterns and examples
