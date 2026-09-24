---
name: ninjaone-environment-variables
description: Use when code references $env:NINJA_* variables (NINJA_ORGANIZATION_NAME, NINJA_AGENT_NODE_ID, NINJA_DATA_PATH, etc.), or user asks about NinjaOne agent environment variables or organization context.
---

# NinjaOne Environment Variables

The NinjaOne agent provides built-in environment variables accessible via `$env:VARIABLE_NAME` that expose agent information, organization context, and device identification.

## When to Use This Skill

- Access organization and location context for multi-tenant scripts
- Reference agent installation paths and data directories
- Obtain node IDs for API calls and unique device identification
- Check agent versions for compatibility before running features
- Include organization information in logs for debugging
- Use agent password for session key authentication
- Build context-aware automation based on organization metadata

## Prerequisites

- **Cross-Platform:** Variables work on Windows, macOS, and Linux
- **Reboot Required:** If variables don't update, reboot the target device
- **Automation Context:** Variables only available when running via NinjaOne agent

## Related Skills

- [ninjaone-script-variables](../ninjaone-script-variables/SKILL.md) - User-defined parameters that complement agent variables
- [ninjaone-api](../ninjaone-api/SKILL.md) - Use NINJA_AGENT_NODE_ID for API device identification
- [ninjaone-tags](../ninjaone-tags/SKILL.md) - Tag devices based on NINJA_ORGANIZATION_NAME patterns
- [ninjaone-custom-fields](../ninjaone-custom-fields/SKILL.md) - Store environment context in custom fields for visibility

## NinjaOne Agent Environment Variables

The NinjaOne agent provides the following built-in environment variables accessible via `$env:VARIABLE_NAME`:

- **Agent Information:**
  - `$env:NINJA_EXECUTING_PATH` - Agent install location
  - `$env:NINJA_AGENT_VERSION_INSTALLED` - Current agent version
  - `$env:NINJA_PATCHER_VERSION_INSTALLED` - Current patcher version
  - `$env:NINJA_DATA_PATH` - Agent data folder (scripts, policy, downloads, logs)
  - `$env:NINJA_AGENT_MACHINE_ID` - Machine ID used on the server

- **Organization Context:**
  - `$env:NINJA_ORGANIZATION_NAME` - Organization name
  - `$env:NINJA_ORGANIZATION_ID` - Organization ID
  - `$env:NINJA_COMPANY_NAME` - Company name
  - `$env:NINJA_LOCATION_ID` - Location ID
  - `$env:NINJA_LOCATION_NAME` - Location name
  - `$env:NINJA_AGENT_NODE_ID` - Node ID used on the server

**Important:** These environment variables are available across all script types (PowerShell, Batch, ShellScript, VBScript) on all platforms (Windows, macOS, Linux).

## Variable Update Behavior

If you change an environment variable value and find it has not updated when executing a script, **reboot the target device** to refresh the environment variables.

## Usage Example

```powershell
function Get-NinjaEnvironmentInfo {
    <#
    .SYNOPSIS
        Retrieves NinjaOne agent environment information.

    .DESCRIPTION
        Collects and returns NinjaOne agent environment variables as a structured object.

    .OUTPUTS
        PSCustomObject with NinjaOne environment details

    .EXAMPLE
        Get-NinjaEnvironmentInfo
    #>
    [CmdletBinding()]
    param()

    process {
        [PSCustomObject]@{
            AgentPath       = $env:NINJA_EXECUTING_PATH
            AgentVersion    = $env:NINJA_AGENT_VERSION_INSTALLED
            PatcherVersion  = $env:NINJA_PATCHER_VERSION_INSTALLED
            DataPath        = $env:NINJA_DATA_PATH
            MachineId       = $env:NINJA_AGENT_MACHINE_ID
            NodeId          = $env:NINJA_AGENT_NODE_ID
            Organization    = $env:NINJA_ORGANIZATION_NAME
            OrganizationId  = $env:NINJA_ORGANIZATION_ID
            Company         = $env:NINJA_COMPANY_NAME
            Location        = $env:NINJA_LOCATION_NAME
            LocationId      = $env:NINJA_LOCATION_ID
        }
    }
}
```

## Batch Script Example

```batch
@echo off
REM Access NinjaOne environment variables in Batch

echo Agent Path: %NINJA_EXECUTING_PATH%
echo Agent Version: %NINJA_AGENT_VERSION_INSTALLED%
echo Organization: %NINJA_ORGANIZATION_NAME%
echo Node ID: %NINJA_AGENT_NODE_ID%
echo Data Path: %NINJA_DATA_PATH%
```

## Shell Script Example

```bash
#!/bin/bash
# Access NinjaOne environment variables in Shell Script

echo "Agent Path: $NINJA_EXECUTING_PATH"
echo "Agent Version: $NINJA_AGENT_VERSION_INSTALLED"
echo "Organization: $NINJA_ORGANIZATION_NAME"
echo "Node ID: $NINJA_AGENT_NODE_ID"
echo "Data Path: $NINJA_DATA_PATH"
```

## Best Practices

1. **Multi-Tenancy Support** - Always use `$env:NINJA_ORGANIZATION_NAME` and `$env:NINJA_LOCATION_NAME` for organization context
2. **Logging Context** - Include organization/location information in logs for debugging multi-tenant environments
3. **File Operations** - Use `$env:NINJA_DATA_PATH` for agent-related file operations and temporary files
4. **Agent Executables** - Reference `$env:NINJA_EXECUTING_PATH` when calling agent executables or binaries
5. **Node Identification** - Use `$env:NINJA_AGENT_NODE_ID` for unique device identification in APIs
6. **Cross-Platform Scripts** - These variables work across Windows, macOS, and Linux
7. **Reboot After Changes** - If variables don't update, reboot the target device
8. **Version Checks** - Use version variables for compatibility checks before running features
