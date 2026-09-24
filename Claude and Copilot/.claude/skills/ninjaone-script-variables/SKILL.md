---
name: ninjaone-script-variables
description: Use when creating NinjaOne automation scripts that accept runtime parameters, converting string environment variables to typed values, or user asks about NinjaOne script variables, preset parameters, or variable type conversion.
---

# NinjaOne Script Variables

NinjaOne converts script variables defined in the platform into environment variables when the script executes. All variables arrive as strings and require proper type conversion and validation.

## When to Use This Skill

- Create scripts that accept user-configurable parameters
- Convert string environment variables to proper types (Integer, Boolean, DateTime, etc.)
- Validate mandatory and optional script parameters
- Implement default values for non-mandatory variables
- Handle dropdown selections and checkbox inputs
- Parse date/time and IP address inputs with validation
- Create reusable type conversion helper functions

## Prerequisites

- **Variable Limits:** Maximum 20 script variables per script
- **Type Awareness:** All variables are strings; explicit conversion required
- **Empty Handling:** Non-mandatory variables may be empty strings
- **Special Characters:** Cannot use: `Å Ä Ö & | ; $ > < \` !`
- **Environment Conflicts:** Scripts fail if system has conflicting environment variable names

## Related Skills

- [ninjaone-environment-variables](../ninjaone-environment-variables/SKILL.md) - Agent-provided context variables like NINJA_ORGANIZATION_NAME
- [ninjaone-custom-fields](../ninjaone-custom-fields/SKILL.md) - Persistent device data that complements script variables
- [ninjaone-tags](../ninjaone-tags/SKILL.md) - Use script variables to configure tag names for flexible automation

## Script Variables Overview

NinjaOne converts script variables defined in the platform into environment variables when the script executes.

### Key Characteristics

- **Always Strings:** All script variables are sent as strings, regardless of intended type
- **Empty Values:** Empty (non-mandatory) variables are sent as empty strings (`""`)
- **Type Conversion Required:** Scripts must cast variables to appropriate types
- **No Strong Typing:** Platform does not enforce type constraints
- **Maximum Variables:** A script can have up to 20 variables maximum
- **Unicode Support:** Unicode characters (non-Latin scripts, symbols, Kanji, emojis) are supported
- **Special Characters:** The following characters **cannot** be used: `Å Ä Ö & | ; $ > < \` !`
- **Activity Logging:** Variable changes generate activity log entries in System and Device dashboards
- **Environment Conflicts:** Scripts fail if system already has an environment variable with the same name

### Variable Configuration

When creating script variables in the NinjaOne script editor:

| Configuration Field | Description | Applies To |
|---------------------|-------------|------------|
| **Make variable mandatory** | Toggle to require value when script runs | All except Checkbox |
| **Name** | Descriptive variable name displayed in UI | All |
| **Calculated name** | Auto-populated variable name used in script | All |
| **Description** | Optional tooltip shown when hovering over variable | All |
| **Set default value** | Pre-defined value used if not provided at runtime | All |
| **Option value** | List of selectable options for dropdown | Dropdown only |

### Script Variable Types and Formats

| Variable Type | Format Sent to Script | Example Value |
|--------------|----------------------|---------------|
| **String/Text** | Plain string as entered | `"Hello World"` |
| **Integer** | Whole numbers as string | `"314"` |
| **Decimal** | Floating-point numbers as string | `"3.14"` |
| **Checkbox** | String `"true"` when checked, `"false"` when unchecked | `"true"` or `"false"` |
| **Date** | ISO 8601 format: `YYYY-MM-ddT00:00:00.000+00:00` | `"2024-01-15T00:00:00.000+00:00"` |
| **Date/Time** | ISO 8601 format: `YYYY-MM-ddTHH:MM:SS.SSSZ` | `"2023-07-28T03:00:00.000+01:00"` |
| **DropDown** | Selected value as string | `"Production"` |
| **IP Address** | IP address as string | `"192.168.1.100"` |

## Referencing Variables by Script Type

Different scripting languages use different syntax to reference environment variables:

| Script Type | Reference Syntax | Example |
|-------------|------------------|---------|
| **PowerShell** | `$env:<variableName>` | `$env:serverName` |
| **Batch** | `%<variableName>%` | `%serverName%` |
| **VBScript** | `CreateObject("WScript.Shell").ExpandEnvironmentStrings("%variableName%")` | `serverName = CreateObject("WScript.Shell").ExpandEnvironmentStrings("%serverName%")` |
| **ShellScript** | `$<variableName>` | `$serverName` |

### Inserting Variables in Script Editor

**Keyboard Shortcut:** Press `CTRL + Space` in the script editor to open the variable selector contextual menu.

- Hover over variables to see descriptions
- Custom fields also appear in the variable selector
- Variables are automatically formatted for the selected script language
- Variables can be reordered by dragging them up or down in the Script Variables pane

## Variable Handling Example

```powershell
# Script variables from NinjaOne (received as environment variables)
$serverName = $env:serverName
if ([string]::IsNullOrWhiteSpace($serverName)) {
    Write-Error "ServerName is required but was not provided"
    exit 1
}

# Convert and validate Port (Integer type)
$port = 443
if (-not [string]::IsNullOrWhiteSpace($env:port)) {
    try {
        $port = [int]$env:port
        if ($port -lt 1 -or $port -gt 65535) {
            Write-Warning "Port value '$port' is outside valid range. Using default: 443"
            $port = 443
        }
    } catch {
        Write-Warning "Failed to convert Port. Using default: 443"
        $port = 443
    }
}

# Convert checkbox/boolean
$enableLogging = $false
if (-not [string]::IsNullOrWhiteSpace($env:enableLogging)) {
    $enableLogging = $env:enableLogging -eq 'true'
}

# Convert Date/Time (ISO 8601 format)
$maintenanceWindow = $null
if (-not [string]::IsNullOrWhiteSpace($env:maintenanceWindow)) {
    try {
        $maintenanceWindow = [DateTime]::Parse($env:maintenanceWindow, $null, [System.Globalization.DateTimeStyles]::RoundtripKind)
    } catch {
        Write-Warning "Failed to parse MaintenanceWindow. Ignoring."
    }
}

# Validate IP Address
$ipAddress = $null
if (-not [string]::IsNullOrWhiteSpace($env:ipAddress)) {
    try {
        $ipAddress = [System.Net.IPAddress]::Parse($env:ipAddress)
    } catch {
        Write-Warning "Invalid IP Address format. Ignoring."
    }
}
```

## VBScript Example

```vbscript
' VBScript requires explicit environment variable expansion
Set wshShell = CreateObject("WScript.Shell")
serverName = wshShell.ExpandEnvironmentStrings("%serverName%")
port = wshShell.ExpandEnvironmentStrings("%port%")

If serverName = "" Then
    WScript.Echo "ServerName is required"
    WScript.Quit 1
End If

' Convert port to integer
If port <> "" Then
    portNumber = CInt(port)
Else
    portNumber = 443
End If
```

## Batch Script Example

```batch
@echo off
REM Batch script variables
SET SERVER_NAME=%serverName%
SET PORT=%port%

IF "%SERVER_NAME%"=="" (
    echo ServerName is required
    exit /b 1
)

IF "%PORT%"=="" (
    SET PORT=443
)

echo Connecting to %SERVER_NAME% on port %PORT%
```

## Type Conversion Helper

```powershell
function ConvertTo-TypedValue {
    <#
    .SYNOPSIS
        Converts NinjaOne script variable (string) to specified type with validation.

    .EXAMPLE
        $port = ConvertTo-TypedValue -Value $env:port -Type 'Int32' -DefaultValue 443 -Min 1 -Max 65535

    .EXAMPLE
        $enabled = ConvertTo-TypedValue -Value $env:enableFeature -Type 'Boolean' -DefaultValue $false
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string]$Value,

        [Parameter(Mandatory)]
        [ValidateSet('Int32', 'Int64', 'Boolean', 'DateTime', 'Double', 'Decimal', 'IPAddress')]
        [string]$Type,

        [Parameter()]
        $DefaultValue,

        [Parameter()]
        [object]$Min,

        [Parameter()]
        [object]$Max
    )

    process {
        if ([string]::IsNullOrWhiteSpace($Value)) {
            if ($PSBoundParameters.ContainsKey('DefaultValue')) {
                return $DefaultValue
            }
            return $null
        }

        try {
            $convertedValue = switch ($Type) {
                'Int32' { [int]$Value }
                'Int64' { [long]$Value }
                'Boolean' { $Value -eq 'true' }
                'DateTime' { [DateTime]::Parse($Value, $null, [System.Globalization.DateTimeStyles]::RoundtripKind) }
                'Double' { [double]$Value }
                'Decimal' { [decimal]$Value }
                'IPAddress' { [System.Net.IPAddress]::Parse($Value) }
            }

            # Range validation for numeric types
            if ($Type -in @('Int32', 'Int64', 'Double', 'Decimal')) {
                if ($PSBoundParameters.ContainsKey('Min') -and $convertedValue -lt $Min) {
                    Write-Warning "Value $convertedValue is below minimum $Min. Using default."
                    return $DefaultValue
                }
                if ($PSBoundParameters.ContainsKey('Max') -and $convertedValue -gt $Max) {
                    Write-Warning "Value $convertedValue is above maximum $Max. Using default."
                    return $DefaultValue
                }
            }

            return $convertedValue

        } catch {
            Write-Warning "Failed to convert '$Value' to $Type. Using default."
            if ($PSBoundParameters.ContainsKey('DefaultValue')) {
                return $DefaultValue
            }
            return $null
        }
    }
}
```

## Variable Visualization in UI

When running a script with variables, NinjaOne renders an interactive form:

- **Mandatory fields** are marked with an asterisk (*)
- **Empty mandatory fields** turn red when attempting to run the script
- **Description tooltips** appear as info icons next to variable names
- **Default values** are pre-populated in form fields
- **Dropdown options** appear as selectable lists

## Preset Parameters

NinjaOne supports passing parameters directly to scripts at runtime using preset parameter strings.

### Key Characteristics

- **Runtime Input:** Parameters passed when script executes
- **Positional Parameters:** Consumed in order
- **Space-Delimited:** Multiple parameters separated by spaces
- **Quote Support:** Values with spaces must be quoted

### PowerShell Example

```powershell
<#
.NOTES
    NinjaOne Preset Parameters:
    - Parameter 1: Username (supports spaces when quoted)
    - Parameter 2: Password

    Example preset parameter strings:
    - "John Doe" SecurePass123
    - Alice P@ssw0rd!
#>

param(
    [Parameter(Position = 0, Mandatory = $true)]
    [string]$Username,

    [Parameter(Position = 1, Mandatory = $true)]
    [string]$Password
)

# Validation
if ([string]::IsNullOrWhiteSpace($Username)) {
    Write-Error "Username is required"
    exit 1
}

# Main logic
net user "$Username" "$Password" /add
```

## When to Use Each Approach

| Feature | Preset Parameters | Script Variables |
|---------|------------------|------------------|
| **Configuration** | Set at runtime | Configured in script definition |
| **Flexibility** | Ad-hoc values | Structured inputs with UI validation |
| **Use Case** | Quick actions, testing | Standardized operations, policies |
| **Validation** | Manual in script | Platform UI validation |

## Common Mistakes

1. **Not handling empty strings for non-mandatory variables** - Non-mandatory variables arrive as empty strings `""` when not filled in, not as `$null`. Direct type casts like `[int]$env:port` throw an exception on an empty string. Always guard with `[string]::IsNullOrWhiteSpace($env:port)` before converting.
2. **Checkbox comparison against the wrong value** - Checkbox variables send `"true"` or `"false"` as strings, not PowerShell booleans. `if ($env:enableFeature)` is always `$true` for a non-empty string. Use `$env:enableFeature -eq 'true'` for correct boolean evaluation.
3. **Special characters in variable names** - Characters like `&`, `|`, `;`, `$`, and backtick cannot be used in variable names or values. Scripts with these characters fail at runtime without a clear error.
4. **Naming conflicts with system environment variables** - If a script variable shares a name with an existing system environment variable (e.g., `PATH`, `TEMP`), the script will fail or use the wrong value. Prefix custom variable names (e.g., `NR_Port`) to avoid collisions.
5. **Assuming DateTime locale** - Date/Time variables use ISO 8601 with timezone (`YYYY-MM-ddTHH:MM:SS.SSSZ`). Parsing with `[DateTime]::Parse($value)` without `DateTimeStyles.RoundtripKind` loses timezone info and can shift the time. Use `[DateTime]::Parse($value, $null, [System.Globalization.DateTimeStyles]::RoundtripKind)`.

## Best Practices

1. **Always Validate Input** - Check for empty strings and validate data types
2. **Use Descriptive Names** - Clear variable names improve maintainability
3. **Set Defaults** - Provide sensible defaults for non-mandatory variables
4. **Add Descriptions** - Use tooltips to guide technicians using the script
5. **Handle Conversion Errors** - Always wrap type conversions in try-catch blocks
6. **Log Activities** - Remember that variable changes are logged to activity feeds
7. **Check Environment Conflicts** - Be aware of existing system environment variables
8. **Limit Variables** - Stay under the 20-variable maximum per script
9. **Avoid Special Characters** - Don't use: `Å Ä Ö & | ; $ > < \` !`
10. **Use Unicode Carefully** - While supported, test Unicode characters thoroughly
11. **Order Logically** - Arrange variables in a logical order for the technician UI
12. **Leverage Custom Fields** - Custom fields are also available in the variable selector
