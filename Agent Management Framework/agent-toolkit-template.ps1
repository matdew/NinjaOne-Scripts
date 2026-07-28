<#
.SYNOPSIS
    Multipurpose "toolkit" template for ancillary management of an MSP-sold agent in NinjaOne.

.DESCRIPTION
    This template is a companion to the Agent Management Framework. Where the
    "Agent Management" script handles install/uninstall/reinstall lifecycle,
    this toolkit handles the *ancillary* actions you run against an agent that
    is already installed - tweaking settings, restarting the service, gathering
    diagnostics, etc.

    The action to perform is selected by the NinjaOne operator and passed in via
    the $env:action environment variable (a NinjaOne script variable / dropdown
    selection). The switch statement at the bottom routes to the matching
    function.

    The examples below are intentionally generic placeholders. Replace them with
    the real actions your agent supports and delete any you don't need.

.NOTES
    Designed to run via NinjaOne. Add an 'Action' Dropdown script variable whose
    option values EXACTLY match the labels in the switch statement below.
#>

# Set environment variables
$env:agentDisplayName = '' # Friendly name for the agent, used in logging and messages.
$env:agentServiceName = '' # The actual Windows Service Name (not Display Name) for status checks and restarts.
$env:logDirectory = 'C:\ProgramData\AgentToolkit' # Local folder for logs and diagnostic output. Adjust to your standard.

$ProgressPreference = 'SilentlyContinue'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

#region Helpers
function Write-ToolkitLog {
    param([string]$Message)
    if (!(Test-Path $env:logDirectory)) {
        New-Item -Path $env:logDirectory -ItemType Directory -Force | Out-Null
    }
    $line = '{0}  {1}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Message
    $logFile = Join-Path $env:logDirectory 'toolkit.log'
    $line | Tee-Object -FilePath $logFile -Append
}
#endregion

#region Toolkit Actions

# EXAMPLE 1: Restart the agent's Windows service.
function Restart-AgentService {
    try {
        $service = Get-Service -Name $env:agentServiceName -ErrorAction Stop
        Write-ToolkitLog "Restarting $($service.DisplayName) ($($service.Name))..."
        $service | Restart-Service -Force
        $service | Select-Object -Property Name, Status, StartType
        Write-ToolkitLog "$env:agentDisplayName service restarted successfully."
    } catch {
        Write-ToolkitLog "ERROR: Failed to restart $env:agentServiceName - $($_.Exception.Message)"
        exit 1
    }
}

# EXAMPLE 2: Apply a configuration tweak (shown here as a registry setting).
# Replace with whatever "change a setting" means for your agent - registry,
# config file edit, CLI call, etc.
function Set-AgentConfiguration {
    try {
        # -----------  SETTING CHANGE LOGIC GOES HERE  -----------
        # Example placeholder:
        # Set-ItemProperty -Path 'HKLM:\SOFTWARE\<Vendor>\<Agent>' -Name '<SettingName>' -Value '<Value>' -Type String

        # Many settings changes require a service restart to take effect.
        Get-Service -Name $env:agentServiceName -ErrorAction Stop | Restart-Service -Force
        Write-ToolkitLog "$env:agentDisplayName configuration applied and service restarted."
    } catch {
        Write-ToolkitLog "ERROR: Failed to apply configuration - $($_.Exception.Message)"
        exit 1
    }
}

# EXAMPLE 3: Gather diagnostic logs and compress them for retrieval.
function Get-AgentDiagnostics {
    try {
        # -----------  DIAGNOSTIC COLLECTION LOGIC GOES HERE  -----------
        # Example: run a vendor diagnostics tool, then collect its output folder.
        # $sourceDir points at whatever the agent produces; adjust as needed.
        $sourceDir = 'C:\ProgramData\<Vendor>\<Agent>\Logs'

        if (!(Test-Path $sourceDir)) {
            Write-ToolkitLog "ERROR: Diagnostic source folder not found: $sourceDir"
            exit 1
        }

        if (!(Test-Path $env:logDirectory)) {
            New-Item -Path $env:logDirectory -ItemType Directory -Force | Out-Null
        }

        $zipStamp = (Get-Date).ToString('yyyyMMdd-HHmmss')
        $zipPath = Join-Path $env:logDirectory ("$env:agentDisplayName-Diagnostics-$zipStamp.zip")
        Compress-Archive -Path (Join-Path $sourceDir '*') -DestinationPath $zipPath -Force

        Write-ToolkitLog "Diagnostics collected: $zipPath"
        Write-Output "Diagnostics zip: $zipPath"
    } catch {
        Write-ToolkitLog "ERROR: Failed to gather diagnostics - $($_.Exception.Message)"
        exit 1
    }
}

#endregion

#region Action Router
switch ($env:action) {
    'Restart Service' { Restart-AgentService }
    'Apply Configuration' { Set-AgentConfiguration }
    'Gather Diagnostics' { Get-AgentDiagnostics }
    default {
        Write-Output "ERROR: Unknown or unset action: '$($env:action)'"
        exit 1
    }
}
#endregion

exit 0
