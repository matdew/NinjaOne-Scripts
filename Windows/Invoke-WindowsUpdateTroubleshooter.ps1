<#
.SYNOPSIS
    Diagnoses common Windows Update blockers and reports findings with recommended fixes.

.DESCRIPTION
    Windows Update troubleshooter for NinjaOne. Runs a series of focused checks and prints a
    sectioned report followed by an issue summary and recommended actions. Intended to explain
    WHY Windows Update is failing or stalled.

    All diagnostic checks are read-only. The one exception is the optional SetupDiag analysis:
    when (and only when) there is evidence of a recent feature-update attempt, the script may
    download Microsoft's SetupDiag.exe to %SystemRoot%\Temp\SetupDiag, verify its Authenticode
    signature, run it, and then delete it. Pass -SkipSetupDiag to make the run strictly
    read-only.

    Checks performed:
      - Windows Update service health and start mode (wuauserv, BITS, CryptSvc, TrustedInstaller,
        MSIServer, UsoSvc, DoSvc)
      - Pending reboot (CBS, Windows Update, PendingFileRename, ConfigMgr, App-V, Intune)
      - Last successful update scan / install recency
      - Recent Windows Update failure events with plain-English error-code diagnosis
      - Disk space (system drive and system/EFI partition) and SoftwareDistribution sizes
      - Windows Update source / WSUS / Group Policy and MDM (Intune) policy configuration
      - OS end-of-servicing status
      - Internet update-endpoint connectivity (DNS + TCP 443 + TLS interception) when not
        WSUS-managed
      - Date/time skew, TLS 1.2 availability, and proxy configuration
      - BITS transfer job state and SoftwareDistribution datastore heuristics
      - SetupDiag feature-update failure analysis (when a recent attempt is detected)

.PARAMETER FailureLookbackDays
    Days of Windows Update event history to scan. Defaults to the failureLookbackDays
    environment variable, then to 14.

.PARAMETER SkipSetupDiag
    Skip SetupDiag entirely, including reading Windows Setup's own results. Guarantees the run
    makes no changes to the device.

.PARAMETER AsObject
    Emit the finding objects to the pipeline instead of only printing the text report.

.PARAMETER Detailed
    Also print the full per-check sectioned report. By default only the summary (findings,
    passed checks, and informational notes) is shown.

.NOTES
    NinjaOne Script Variables (optional; define in the NinjaOne platform):
      - Failure Lookback Days (Integer): Days of Windows Update event history to scan. Default 14.
        Env var: failureLookbackDays
      - Detailed (Checkbox): Also print the full per-check report. Default off. Env var: detailed

    SetupDiag is only downloaded and run when there is evidence of a recent feature-update
    attempt (recent Panther setup logs, a rollback marker, or a feature-update failure event).
    Windows Setup's own auto-generated results are always preferred and cost nothing.

    Exit codes:
      0 - The troubleshooter ran successfully (regardless of what it found)
      1 - The troubleshooter itself failed to run

    Windows Update health is reported in the findings/summary, not via the exit code: a device
    with real update problems still exits 0 as long as the script completed successfully.

.EXAMPLE
    Runs via NinjaOne RMM. Review the script output for findings and recommended actions.

.EXAMPLE
    .\Invoke-WindowsUpdateTroubleshooter.ps1 -FailureLookbackDays 30 -SkipSetupDiag

    Scans 30 days of update history without touching the device at all.
#>

#Requires -Version 3.0

[CmdletBinding()]
param(
    [ValidateRange(1, 365)]
    [int]$FailureLookbackDays,

    [switch]$SkipSetupDiag,

    [switch]$AsObject,

    [switch]$Detailed
)

# Best-effort: allow this session's own web requests to negotiate TLS 1.2 (does not change the system).
try {
    [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
} catch { Write-Verbose ('Ignored: ' + $_.Exception.Message) }

$script:Findings = New-Object System.Collections.Generic.List[object]
$script:WsusServer = ''

# Under -AsObject the report text goes to Write-Host so findings are the only pipeline output.
$script:EmitObjects = [bool]$AsObject

# Per-section detail is suppressed by default; -Detailed (or the 'detailed' script var) turns it on. Resolved in Main.
$script:ShowDetails = [bool]$Detailed

#region Helpers

function Add-Finding {
    param(
        [Parameter(Mandatory = $true)][string]$Category,
        [Parameter(Mandatory = $true)][ValidateSet('OK', 'Info', 'Warning', 'Critical')][string]$Severity,
        [Parameter(Mandatory = $true)][string]$Detail,
        [string]$Recommendation = ''
    )

    $script:Findings.Add([PSCustomObject]@{
            Category       = $Category
            Severity       = $Severity
            Detail         = $Detail
            Recommendation = $Recommendation
        })
}

function Write-Summary {
    # Always-on output sink (headers + issue summary); routes to Write-Host under -AsObject like the detail sink.
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost', '',
        Justification = 'Deliberate: under -AsObject the success stream carries the finding objects, so report text must leave that stream. Normal runs still use Write-Output.')]
    param([Parameter(Position = 0)][AllowEmptyString()][AllowNull()][string]$Message = '')

    if ($script:EmitObjects) {
        Write-Host $Message
    } else {
        Write-Output $Message
    }
}

function Write-Report {
    # Per-section detail sink; suppressed unless -Detailed, so the default run shows only the summary.
    param([Parameter(Position = 0)][AllowEmptyString()][AllowNull()][string]$Message = '')

    if (-not $script:ShowDetails) { return }
    Write-Summary $Message
}

function Write-Section {
    param([Parameter(Mandatory = $true)][string]$Title)
    Write-Report ''
    Write-Report ('=' * 70)
    Write-Report "  $Title"
    Write-Report ('=' * 70)
}

function Write-SummarySection {
    param([Parameter(Mandatory = $true)][string]$Title)
    Write-Summary ''
    Write-Summary ('=' * 70)
    Write-Summary "  $Title"
    Write-Summary ('=' * 70)
}

function Get-ScriptVarString {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [string]$Default = ''
    )

    $value = [Environment]::GetEnvironmentVariable($Name)
    if ([string]::IsNullOrWhiteSpace($value)) {
        return $Default
    }
    return $value.Trim()
}

function Get-ScriptVarInt {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [int]$Default = 0
    )

    $raw = Get-ScriptVarString -Name $Name
    if ([string]::IsNullOrWhiteSpace($raw)) {
        return $Default
    }

    $parsed = 0
    if ([int]::TryParse($raw, [ref]$parsed)) {
        return $parsed
    }
    return $Default
}

function Get-ScriptVarBool {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [bool]$Default = $false
    )

    $raw = Get-ScriptVarString -Name $Name
    if ([string]::IsNullOrWhiteSpace($raw)) {
        return $Default
    }

    switch -Regex ($raw.Trim()) {
        '^(1|true|yes|on)$' { return $true }
        '^(0|false|no|off)$' { return $false }
        default { return $Default }
    }
}

function Format-Bytes {
    param([double]$Bytes)

    if ($Bytes -ge 1GB) { return ('{0:N2} GB' -f ($Bytes / 1GB)) }
    if ($Bytes -ge 1MB) { return ('{0:N2} MB' -f ($Bytes / 1MB)) }
    if ($Bytes -ge 1KB) { return ('{0:N2} KB' -f ($Bytes / 1KB)) }
    return ('{0} B' -f [int]$Bytes)
}

function Test-IsElevated {
    try {
        $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
        return ([Security.Principal.WindowsPrincipal]$identity).IsInRole(
            [Security.Principal.WindowsBuiltInRole]::Administrator)
    } catch {
        return $false
    }
}

function Get-FolderSize {
    # Recursive size with a wall-clock deadline; Complete=$false means the deadline was hit.
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [int]$TimeoutSeconds = 15
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        return $null
    }

    $sum = [double]0
    $count = 0
    $newest = [datetime]::MinValue
    $complete = $true
    $sw = [System.Diagnostics.Stopwatch]::StartNew()

    # Manual directory walk (not Get-ChildItem -Recurse) so the deadline can fire mid-traversal.
    try {
        $stack = New-Object System.Collections.Generic.Stack[string]
        $stack.Push($Path)

        while ($stack.Count -gt 0) {
            if ($sw.Elapsed.TotalSeconds -ge $TimeoutSeconds) {
                $complete = $false
                break
            }

            $dir = $stack.Pop()
            $children = Get-ChildItem -LiteralPath $dir -Force -ErrorAction SilentlyContinue
            foreach ($child in $children) {
                if ($child.PSIsContainer) {
                    # Skip junctions/symlinks so hardlinked trees cannot loop or double-count.
                    if (([int]$child.Attributes -band [int][IO.FileAttributes]::ReparsePoint) -eq 0) {
                        $stack.Push($child.FullName)
                    }
                } else {
                    $sum += [double]$child.Length
                    $count++
                    if ($child.LastWriteTime -gt $newest) { $newest = $child.LastWriteTime }
                }
            }
        }
    } catch {
        return $null
    } finally {
        $sw.Stop()
    }

    return [PSCustomObject]@{
        Bytes       = $sum
        FileCount   = $count
        NewestWrite = $newest
        Complete    = $complete
    }
}

function Test-TcpPort {
    param(
        [Parameter(Mandatory = $true)][string]$ComputerName,
        [Parameter(Mandatory = $true)][int]$Port,
        [int]$TimeoutMs = 3000
    )

    $client = New-Object System.Net.Sockets.TcpClient
    try {
        $async = $client.BeginConnect($ComputerName, $Port, $null, $null)
        $waited = $async.AsyncWaitHandle.WaitOne($TimeoutMs, $false)
        if ($waited -and $client.Connected) {
            $client.EndConnect($async)
            return $true
        }
        return $false
    } catch {
        return $false
    } finally {
        $client.Dispose()
    }
}

function Resolve-HostAddressList {
    # DNS lookup with an enforced timeout (Dns.GetHostAddresses has none of its own).
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [int]$TimeoutMs = 4000
    )

    try {
        $async = [System.Net.Dns]::BeginGetHostAddresses($Name, $null, $null)
        if (-not $async.AsyncWaitHandle.WaitOne($TimeoutMs, $false)) {
            # Abandon the lookup; the worker thread finishes on its own and is discarded.
            return $null
        }
        $addresses = [System.Net.Dns]::EndGetHostAddresses($async)
        if (-not $addresses -or $addresses.Count -eq 0) { return $null }
        return (($addresses | ForEach-Object { $_.IPAddressToString }) -join ', ')
    } catch {
        return $null
    }
}

# Windows Update error codes -> meaning, severity, and fix. Severity is per-code so transient codes stay Info. https://learn.microsoft.com/en-us/windows/deployment/update/windows-update-error-reference
$script:WuErrorMap = @{
    '0X80070002' = @{ Severity = 'Warning'; Text = 'File not found - update payload missing or corrupted (0x80070002).'; Fix = 'Reset SoftwareDistribution, then re-scan.' }
    '0X80070003' = @{ Severity = 'Warning'; Text = 'Path not found - servicing path missing or corrupted (0x80070003).'; Fix = 'Reset SoftwareDistribution, then re-scan.' }
    '0X80070005' = @{ Severity = 'Warning'; Text = 'Access denied during the update operation (0x80070005).'; Fix = 'Check permissions on SoftwareDistribution/catroot2 and that no security product is blocking servicing.' }
    '0X8007000E' = @{ Severity = 'Warning'; Text = 'Out of memory during the update operation (0x8007000E).'; Fix = 'Reboot to reclaim memory, then retry the update.' }
    '0X80070490' = @{ Severity = 'Critical'; Text = 'Element not found - component store / CBS corruption (0x80070490).'; Fix = 'Run DISM /Online /Cleanup-Image /RestoreHealth followed by SFC /scannow.' }
    '0X80070422' = @{ Severity = 'Critical'; Text = 'A required service is disabled (0x80070422).'; Fix = 'Ensure Windows Update-related services are not Disabled (see the Services section above).' }
    '0X800705B4' = @{ Severity = 'Info'; Text = 'Operation timed out (0x800705B4). Often transient.'; Fix = 'Retry the update; investigate only if it recurs.' }
    '0X80073701' = @{ Severity = 'Critical'; Text = 'A required servicing component is missing (0x80073701).'; Fix = 'Repair the component store with DISM /RestoreHealth.' }
    '0X80073D02' = @{ Severity = 'Info'; Text = 'A packaged (Store/UWP) app update is blocked because the app or its files are in use (0x80073D02). Usually transient.'; Fix = 'Close the app or reboot, then retry. No action needed if it does not recur.' }
    '0X800F0831' = @{ Severity = 'Critical'; Text = 'Component store corruption - a required package is missing (0x800F0831).'; Fix = 'Run DISM /RestoreHealth; may require a repair install if the source package is unavailable.' }
    '0X800F081F' = @{ Severity = 'Critical'; Text = 'Source files for component store repair could not be found (0x800F081F).'; Fix = 'Supply a known-good source with DISM /RestoreHealth /Source:.' }
    '0X80240022' = @{ Severity = 'Warning'; Text = 'The operation failed for all the updates (0x80240022, WU_E_ALL_UPDATES_FAILED); often security software blocking access to SoftwareDistribution.'; Fix = 'Check for antivirus/backup software locking SoftwareDistribution, then review CBS.log / WindowsUpdate.log for the per-update failure.' }
    '0X8024000B' = @{ Severity = 'Info'; Text = 'Operation was cancelled (0x8024000B).'; Fix = 'Usually benign - the scan or install was superseded or cancelled. Retry.' }
    '0X8024000E' = @{ Severity = 'Warning'; Text = 'Windows Update returned malformed/invalid data (0x8024000E).'; Fix = 'Reset SoftwareDistribution, then re-scan.' }
    '0X80240016' = @{ Severity = 'Info'; Text = 'An operation could not start because another install is in progress or a mandatory restart is pending (0x80240016).'; Fix = 'Wait for the in-flight scan/install to finish (or reboot if one is pending), then retry.' }
    '0X80244007' = @{ Severity = 'Warning'; Text = 'SOAP client failed - proxy or WSUS SOAP error (0x80244007).'; Fix = 'Verify the WSUS server health and any intercepting proxy.' }
    '0X80244010' = @{ Severity = 'Warning'; Text = 'Exceeded max round trips to the update server (0x80244010).'; Fix = 'Re-run the scan; if persistent, the WSUS catalog may be too large or the client metadata stale.' }
    '0X80244019' = @{ Severity = 'Warning'; Text = 'HTTP 404 from the update server - missing content/WSUS path (0x80244019).'; Fix = 'Verify WSUS content is present and the virtual directories are correctly published.' }
    '0X8024401B' = @{ Severity = 'Critical'; Text = 'HTTP 407 - proxy authentication required (0x8024401B).'; Fix = 'Configure the WinHTTP proxy (netsh winhttp set proxy) or allow update endpoints unauthenticated.' }
    '0X8024401C' = @{ Severity = 'Warning'; Text = 'HTTP 408 - request to the update source timed out (0x8024401C).'; Fix = 'Check network latency and update-server load, then retry.' }
    '0X80244022' = @{ Severity = 'Warning'; Text = 'HTTP 503 - update server/WSUS unavailable (0x80244022).'; Fix = 'Check the WSUS application pool / server health.' }
    '0X8024402C' = @{ Severity = 'Critical'; Text = 'Name resolution / proxy failure reaching the update server (0x8024402C).'; Fix = 'Check DNS, proxy, and the WUServer policy URL.' }
    '0X8024402F' = @{ Severity = 'Warning'; Text = 'External cab processing error (0x8024402F).'; Fix = 'Often a proxy altering content. Bypass content inspection for update endpoints.' }
    '0X80244018' = @{ Severity = 'Critical'; Text = 'HTTP 403 - forbidden by the update server/proxy (0x80244018).'; Fix = 'Allow the update endpoints through the proxy/firewall allow-list.' }
    '0X80248007' = @{ Severity = 'Critical'; Text = 'The information requested is not in the Windows Update datastore (0x80248007, WU_E_DS_NODATA).'; Fix = 'Reset SoftwareDistribution (stop wuauserv/bits, rename the folder), then re-scan.' }
    '0X80248014' = @{ Severity = 'Critical'; Text = 'The requested service is not in the Windows Update datastore (0x80248014, WU_E_DS_UNKNOWNSERVICE).'; Fix = 'Reset SoftwareDistribution, then re-scan.' }
    '0X80D02002' = @{ Severity = 'Info'; Text = 'Delivery Optimization / download timed out (0x80D02002). Often transient.'; Fix = 'Retry the download; investigate bandwidth/DO policy only if it recurs.' }
    '0X800B0109' = @{ Severity = 'Critical'; Text = 'A certificate chain terminated in an untrusted root (0x800B0109).'; Fix = 'Update root certificates, and check for a TLS-intercepting proxy.' }
    '0X80072EE2' = @{ Severity = 'Warning'; Text = 'Connection timed out reaching the update server (0x80072EE2).'; Fix = 'Check connectivity, proxy, and TLS configuration.' }
    '0X80072EE7' = @{ Severity = 'Critical'; Text = 'Server name could not be resolved (0x80072EE7).'; Fix = 'Fix DNS resolution for the update endpoints.' }
    '0X80072EFD' = @{ Severity = 'Warning'; Text = 'A connection to the update server could not be established (0x80072EFD).'; Fix = 'Check firewall/proxy egress on TCP 443.' }
    '0X80072F8F' = @{ Severity = 'Critical'; Text = 'A security (TLS) error occurred - often date/time or TLS 1.2 (0x80072F8F).'; Fix = 'Correct the system clock and ensure TLS 1.2 is enabled (see the Time and TLS sections above).' }
    '0X800F0922' = @{ Severity = 'Critical'; Text = 'Servicing failed, often insufficient System Reserved partition space (0x800F0922).'; Fix = 'Free space on the system/EFI partition (see the Disk section above).' }
    '0X80070070' = @{ Severity = 'Critical'; Text = 'Not enough disk space to download or install the update (0x80070070).'; Fix = 'Free disk space on the system drive (see the Disk section above), then retry.' }
    '0X80070020' = @{ Severity = 'Warning'; Text = 'A file needed by the update is in use by another process (0x80070020 sharing violation), often antivirus or backup.'; Fix = 'Reboot to release the file, or temporarily pause the interfering agent, then retry.' }
    '0X80070057' = @{ Severity = 'Warning'; Text = 'Invalid parameter - commonly a corrupted SoftwareDistribution store (0x80070057).'; Fix = 'Reset SoftwareDistribution, then re-scan.' }
    '0X8007000D' = @{ Severity = 'Warning'; Text = 'Invalid data - corrupted update content or metadata (0x8007000D).'; Fix = 'Reset SoftwareDistribution, then re-scan.' }
    '0X80070643' = @{ Severity = 'Critical'; Text = 'Fatal error during installation - often component store or .NET servicing failure (0x80070643).'; Fix = 'Run DISM /RestoreHealth + SFC; for .NET updates, repair the .NET Framework.' }
    '0X80070652' = @{ Severity = 'Info'; Text = 'Another installation is already in progress (0x80070652).'; Fix = 'Wait for the in-flight install to finish (or reboot), then retry.' }
    '0X80070424' = @{ Severity = 'Critical'; Text = 'A required Windows Update service does not exist / is unregistered (0x80070424).'; Fix = 'Re-register the Windows Update services (see the Services section above).' }
    '0X800F0984' = @{ Severity = 'Critical'; Text = 'Component store mismatch - a matching binary is missing (0x800F0984).'; Fix = 'Run DISM /Online /Cleanup-Image /RestoreHealth, then re-scan.' }
    '0X800F0986' = @{ Severity = 'Critical'; Text = 'Component store corruption - applying a forward delta failed (0x800F0986).'; Fix = 'Run DISM /RestoreHealth; may need a repair install if the source is unavailable.' }
    '0X80092003' = @{ Severity = 'Warning'; Text = 'Error reading or writing a file during a cryptographic operation (0x80092003), often catroot2.'; Fix = 'Reset catroot2 (rename with cryptsvc stopped), then re-scan.' }
    '0X80246002' = @{ Severity = 'Warning'; Text = 'Downloaded file hash did not match - corrupted download or a proxy altering content (0x80246002).'; Fix = 'Reset SoftwareDistribution and bypass content inspection for update endpoints, then re-scan.' }
    '0X80246007' = @{ Severity = 'Warning'; Text = 'The update has not been downloaded (0x80246007).'; Fix = 'Re-run the download/scan; check connectivity and BITS.' }
    '0X8024001E' = @{ Severity = 'Info'; Text = 'Operation did not complete because the service or system was shutting down (0x8024001E).'; Fix = 'Retry after the device is back up.' }
    '0X8024001F' = @{ Severity = 'Warning'; Text = 'Operation did not complete because network connectivity was unavailable (0x8024001F).'; Fix = 'Check connectivity/proxy (see the Connectivity section above), then retry.' }
    '0X80240020' = @{ Severity = 'Info'; Text = 'Operation did not complete because no interactive user is signed in (0x80240020).'; Fix = 'Runs when a user signs in, or configure automatic installation.' }
    '0X80240024' = @{ Severity = 'Info'; Text = 'There are no updates available (0x80240024, WU_E_NO_UPDATE).'; Fix = 'Usually benign; confirm the device should be receiving updates.' }
    '0X80240025' = @{ Severity = 'Warning'; Text = 'Windows Update access is disabled by policy (0x80240025).'; Fix = 'Clear the DisableWindowsUpdateAccess policy if updates should be allowed.' }
    '0X80244021' = @{ Severity = 'Warning'; Text = 'HTTP 502 bad gateway from the update server/proxy (0x80244021).'; Fix = 'Check the proxy/WSUS gateway health.' }
    '0X80072EFE' = @{ Severity = 'Warning'; Text = 'The connection to the update server was aborted mid-transfer (0x80072EFE).'; Fix = 'Check network stability, proxy, and TLS inspection.' }
    '0X80072F78' = @{ Severity = 'Warning'; Text = 'Invalid server response, frequently a proxy altering the reply (0x80072F78).'; Fix = 'Bypass content/TLS inspection for update endpoints, then retry.' }
    '0X800B0101' = @{ Severity = 'Critical'; Text = 'A required certificate has expired or is not yet valid, often a wrong system clock (0x800B0101).'; Fix = 'Correct the system clock (see the Time section above) and update root certificates.' }
    '0X80246005' = @{ Severity = 'Warning'; Text = 'Download could not complete because network connectivity was unavailable (0x80246005).'; Fix = 'Check connectivity/proxy (see the Connectivity section above), then retry.' }
    '0X80246008' = @{ Severity = 'Warning'; Text = 'The download manager could not connect to BITS (0x80246008).'; Fix = 'Ensure the BITS service is not Disabled and can start (see the Services section above), then retry.' }
    '0X80246009' = @{ Severity = 'Warning'; Text = 'A BITS transfer error occurred during download (0x80246009).'; Fix = 'Clear stuck BITS jobs and reset SoftwareDistribution, then re-scan.' }
    '0X8024200B' = @{ Severity = 'Warning'; Text = 'The installer failed to install (or uninstall) one or more updates (0x8024200B).'; Fix = 'Review CBS.log / WindowsUpdate.log for the per-update error; run DISM /RestoreHealth + SFC.' }
    '0X80242006' = @{ Severity = 'Warning'; Text = 'The update contains invalid metadata (0x80242006).'; Fix = 'Reset SoftwareDistribution, then re-scan.' }
    '0X80242007' = @{ Severity = 'Warning'; Text = 'The installer exceeded its time limit (0x80242007).'; Fix = 'Reboot to clear any hung installer, then retry.' }
    '0X80242017' = @{ Severity = 'Warning'; Text = 'The servicing stack must be updated before this update can be installed (0x80242017).'; Fix = 'Install the latest servicing stack update (SSU) for this OS, then retry.' }
    '0X80248008' = @{ Severity = 'Warning'; Text = 'The Windows Update datastore is missing required data (0x80248008).'; Fix = 'Reset SoftwareDistribution, then re-scan.' }
    '0X8024801C' = @{ Severity = 'Warning'; Text = 'The Windows Update datastore requires a session reset (0x8024801C).'; Fix = 'Reset SoftwareDistribution, then re-scan.' }
    '0X80240017' = @{ Severity = 'Info'; Text = 'No applicable updates - the operation was not performed because nothing applies (0x80240017).'; Fix = 'Usually benign; confirm the device should be receiving these updates.' }
    '0X8024001B' = @{ Severity = 'Info'; Text = 'The Windows Update Agent is self-updating; the operation could not run (0x8024001B).'; Fix = 'Retry shortly after the agent finishes updating.' }
    '0X8024001D' = @{ Severity = 'Warning'; Text = 'An update contains invalid metadata (0x8024001D).'; Fix = 'Reset SoftwareDistribution, then re-scan.' }
    '0X80240021' = @{ Severity = 'Warning'; Text = 'The operation timed out (0x80240021).'; Fix = 'Check connectivity/update-server load, then retry.' }
    '0X80240023' = @{ Severity = 'Warning'; Text = 'The license terms for all updates were declined (0x80240023).'; Fix = 'Accept the applicable license terms, or approve the updates in WSUS/Intune.' }
    '0X8024002E' = @{ Severity = 'Warning'; Text = 'Access to an unmanaged (Microsoft Update) server is not allowed by policy (0x8024002E).'; Fix = 'Point the client at an approved source (WSUS) or clear the policy blocking Microsoft Update.' }
    '0X8024002F' = @{ Severity = 'Warning'; Text = 'The operation was cancelled by the DisableWindowsUpdateAccess policy (0x8024002F).'; Fix = 'Clear the DisableWindowsUpdateAccess policy if updates should be allowed.' }
    '0X80240034' = @{ Severity = 'Warning'; Text = 'The update failed to download (0x80240034).'; Fix = 'Check connectivity, proxy, and BITS; reset SoftwareDistribution, then re-scan.' }
    '0X80244011' = @{ Severity = 'Warning'; Text = 'The WUServer policy value is missing in the registry (0x80244011).'; Fix = 'Set the WUServer/WUStatusServer policy, or clear UseWUServer to use Microsoft Update.' }
    '0X80244016' = @{ Severity = 'Warning'; Text = 'HTTP 400 bad request from the update server (0x80244016).'; Fix = 'Often a proxy mangling the request; bypass content inspection for update endpoints.' }
    '0X80244017' = @{ Severity = 'Critical'; Text = 'HTTP 401 - authentication required by the update server/proxy (0x80244017).'; Fix = 'Configure the WinHTTP proxy credentials, or allow update endpoints unauthenticated.' }
    '0X8024401F' = @{ Severity = 'Warning'; Text = 'HTTP 500 - internal error on the update server/proxy (0x8024401F).'; Fix = 'Check the WSUS/proxy server health, then retry.' }
    '0X80244023' = @{ Severity = 'Warning'; Text = 'HTTP 504 - gateway timeout reaching the update server (0x80244023).'; Fix = 'Check the proxy/gateway and network latency, then retry.' }
}

function Get-WuErrorInfo {
    # Normalized {Severity,Text,Fix} for a WU error code; unknown codes fall back to Warning.
    param([AllowNull()][string]$ErrorCode)

    if ([string]::IsNullOrWhiteSpace($ErrorCode)) {
        return [PSCustomObject]@{
            Severity = 'Warning'
            Text     = 'No structured Windows Update error code was found.'
            Fix      = 'Review the event details and WindowsUpdate.log.'
        }
    }

    $entry = $script:WuErrorMap[$ErrorCode.ToUpper()]
    if ($entry) {
        return [PSCustomObject]@{
            Severity = $entry.Severity
            Text     = $entry.Text
            Fix      = $entry.Fix
        }
    }

    return [PSCustomObject]@{
        Severity = 'Warning'
        Text     = "Unmapped Windows Update error code $ErrorCode; review the event details and WindowsUpdate.log."
        Fix      = 'Look up the code in the Microsoft Windows Update error reference.'
    }
}

function Get-WuEventErrorCode {
    # Read the error code from structured EventData (language-independent); fall back to the message text.
    param([Parameter(Mandatory = $true)]$EventRecord)

    try {
        $data = ([xml]$EventRecord.ToXml()).Event.EventData.Data
        foreach ($d in $data) {
            if ($d.Name -in @('errorCode', 'hresult', 'ErrorCode', 'HResult', 'status')) {
                $raw = [string]$d.'#text'
                if ([string]::IsNullOrWhiteSpace($raw)) { continue }

                if ($raw -match '^0x[0-9A-Fa-f]+$') { return $raw }

                # Some providers log the HRESULT as a signed decimal.
                $asInt = 0
                if ([int]::TryParse($raw, [ref]$asInt) -and $asInt -ne 0) {
                    return ('0x{0:X8}' -f $asInt)
                }
            }
        }
    } catch { Write-Verbose ('Ignored: ' + $_.Exception.Message) }

    try {
        if ([string]$EventRecord.Message -match '(0x[0-9A-Fa-f]{8})') { return $matches[1] }
    } catch { Write-Verbose ('Ignored: ' + $_.Exception.Message) }

    return ''
}

#endregion Helpers

#region Checks

function Get-OsSummary {
    Write-Section -Title 'System Overview'
    try {
        $os = Get-CimInstance Win32_OperatingSystem -ErrorAction Stop
        $productType = [int]$os.ProductType
        $osType = 'Unknown'
        if ($productType -eq 1) { $osType = 'Workstation' } elseif ($productType -ge 2) { $osType = 'Server' }

        Write-Report "Computer   : $env:COMPUTERNAME"
        Write-Report "OS         : $($os.Caption)"
        Write-Report "Version    : $($os.Version) (Build $($os.BuildNumber))"
        Write-Report "Type       : $osType"
        Write-Report "PowerShell : $($PSVersionTable.PSVersion)"
        Write-Report "Last Boot  : $($os.LastBootUpTime)"
    } catch {
        Write-Report "Unable to read OS details: $($_.Exception.Message)"
    }
}

function Test-WuServiceHealth {
    Write-Section -Title 'Windows Update Services'
    Write-Report 'Note: most of these services are demand-start (Manual) and are only expected to be Running while an update scan/download/install is active. A Stopped state at idle is normal; what matters is that the service is not Disabled and can start on demand.'

    $definitions = @(
        [PSCustomObject]@{ Name = 'wuauserv'; Display = 'Windows Update'; MustNotBeDisabled = $true; ShouldRun = $false },
        [PSCustomObject]@{ Name = 'bits'; Display = 'Background Intelligent Transfer'; MustNotBeDisabled = $true; ShouldRun = $false },
        [PSCustomObject]@{ Name = 'cryptsvc'; Display = 'Cryptographic Services'; MustNotBeDisabled = $true; ShouldRun = $true },
        [PSCustomObject]@{ Name = 'trustedinstaller'; Display = 'Windows Modules Installer'; MustNotBeDisabled = $true; ShouldRun = $false },
        [PSCustomObject]@{ Name = 'msiserver'; Display = 'Windows Installer'; MustNotBeDisabled = $false; ShouldRun = $false },
        [PSCustomObject]@{ Name = 'usosvc'; Display = 'Update Orchestrator'; MustNotBeDisabled = $true; ShouldRun = $false },
        [PSCustomObject]@{ Name = 'dosvc'; Display = 'Delivery Optimization'; MustNotBeDisabled = $true; ShouldRun = $false }
    )

    # One CIM round-trip for every service, then look up locally.
    $serviceIndex = @{}
    try {
        foreach ($s in (Get-CimInstance Win32_Service -ErrorAction Stop)) {
            $serviceIndex[[string]$s.Name.ToLower()] = $s
        }
    } catch {
        Write-Report "Unable to enumerate services: $($_.Exception.Message)"
        Add-Finding -Category 'Services' -Severity 'Info' -Detail 'Service health could not be enumerated.'
        return
    }

    foreach ($def in $definitions) {
        $svc = $serviceIndex[$def.Name.ToLower()]
        if (-not $svc) {
            Write-Report ('{0,-32} not present' -f $def.Display)
            Add-Finding -Category 'Services' -Severity 'Info' -Detail "$($def.Display) ($($def.Name)) service is not present on this OS."
            continue
        }

        $state = [string]$svc.State
        $startMode = [string]$svc.StartMode
        Write-Report ('{0,-32} State: {1,-10} StartMode: {2}' -f $def.Display, $state, $startMode)

        if ($def.MustNotBeDisabled -and $startMode -match 'Disabled') {
            Add-Finding -Category 'Services' -Severity 'Critical' `
                -Detail "$($def.Display) ($($def.Name)) is Disabled." `
                -Recommendation "Set $($def.Name) start type to Manual (or Automatic for CryptSvc) and start it."
        } elseif ($def.ShouldRun -and $state -ne 'Running') {
            Add-Finding -Category 'Services' -Severity 'Warning' `
                -Detail "$($def.Display) ($($def.Name)) is not running (State: $state)." `
                -Recommendation "Start the $($def.Name) service."
        } else {
            Add-Finding -Category 'Services' -Severity 'OK' -Detail "$($def.Display) is healthy ($state / $startMode)."
        }
    }
}

function Test-PendingRebootState {
    Write-Section -Title 'Pending Reboot'

    # PendingFileRenameOperations is non-empty on many healthy machines, so treat it as advisory, not blocking.
    $blocking = New-Object System.Collections.Generic.List[string]
    $advisory = New-Object System.Collections.Generic.List[string]

    $keyChecks = @(
        [PSCustomObject]@{ Path = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending'; Reason = 'Component Based Servicing' },
        [PSCustomObject]@{ Path = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\PackagesPending'; Reason = 'CBS packages pending' },
        [PSCustomObject]@{ Path = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired'; Reason = 'Windows Update' },
        [PSCustomObject]@{ Path = 'HKLM:\SOFTWARE\Microsoft\AppV\Client\PendingTasks'; Reason = 'App-V pending tasks' },
        [PSCustomObject]@{ Path = 'HKLM:\SOFTWARE\Microsoft\IntuneManagementExtension\RebootSettings\RebootFlag'; Reason = 'Intune Management Extension' }
    )
    # Not checking WindowsUpdate\Services\Pending: present on healthy machines (service registrations, not reboots).

    foreach ($check in $keyChecks) {
        if (Test-Path -LiteralPath $check.Path) {
            $blocking.Add($check.Reason)
        }
    }

    try {
        $sm = Get-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager' -ErrorAction SilentlyContinue
        if ($sm -and $sm.PSObject.Properties.Name -contains 'PendingFileRenameOperations' -and $sm.PendingFileRenameOperations) {
            $advisory.Add('Pending file rename operations')
        }
    } catch { Write-Verbose ('Ignored: ' + $_.Exception.Message) }

    try {
        $ccm = Invoke-CimMethod -Namespace 'root\ccm\ClientSDK' -ClassName 'CCM_ClientUtilities' -MethodName 'DetermineIfRebootPending' -ErrorAction Stop
        if ($ccm.RebootPending -or $ccm.IsHardRebootPending) {
            $blocking.Add('ConfigMgr client')
        }
    } catch { Write-Verbose ('Ignored: ' + $_.Exception.Message) }

    if ($blocking.Count -gt 0) {
        $joined = (($blocking + $advisory) | Select-Object -Unique) -join '; '
        Write-Report "Pending reboot detected: $joined"
        Add-Finding -Category 'Pending Reboot' -Severity 'Warning' `
            -Detail "A reboot is pending ($joined). This blocks new update installs from completing." `
            -Recommendation 'Reboot the device, then re-scan for updates.'
    } elseif ($advisory.Count -gt 0) {
        $joined = ($advisory | Select-Object -Unique) -join '; '
        Write-Report "Advisory only: $joined (no servicing-blocking reboot flag set)."
        Add-Finding -Category 'Pending Reboot' -Severity 'Info' `
            -Detail "$joined queued, but no CBS/Windows Update reboot flag is set. This is common on healthy devices and does not by itself block updates."
    } else {
        Write-Report 'No pending reboot detected.'
        Add-Finding -Category 'Pending Reboot' -Severity 'OK' -Detail 'No pending reboot detected.'
    }
}

function Test-DiskAndStore {
    Write-Section -Title 'Disk Space and Update Store'

    $sysDrive = $env:SystemDrive
    if ([string]::IsNullOrWhiteSpace($sysDrive)) { $sysDrive = 'C:' }

    try {
        $disk = Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='$sysDrive'" -ErrorAction Stop
        $freeGB = [math]::Round($disk.FreeSpace / 1GB, 2)
        $pctFree = 0
        if ($disk.Size -gt 0) { $pctFree = [math]::Round(($disk.FreeSpace / $disk.Size) * 100, 1) }
        Write-Report "$sysDrive free space   : $freeGB GB ($pctFree%)"

        if ($freeGB -lt 10) {
            Add-Finding -Category 'Disk' -Severity 'Critical' `
                -Detail "$sysDrive has only $freeGB GB free ($pctFree%), below the 10 GB critical threshold. Updates commonly fail this low, and feature updates need considerably more." `
                -Recommendation "Free disk space on $sysDrive (Disk Cleanup, temp files, WinSxS cleanup via DISM), then retry."
        } elseif ($freeGB -lt 20) {
            Add-Finding -Category 'Disk' -Severity 'Warning' `
                -Detail "$sysDrive free space is low ($freeGB GB / $pctFree%). Microsoft recommends at least 20 GB free for feature updates (e.g. annual Windows 11 version upgrades); cumulative/quality updates need less but can still fail on a near-full drive." `
                -Recommendation "Free disk space on $sysDrive (Disk Cleanup, temp files, WinSxS cleanup via DISM) before installing a feature update."
        } elseif ($pctFree -lt 10) {
            Add-Finding -Category 'Disk' -Severity 'Warning' `
                -Detail "$sysDrive free space is low ($freeGB GB / $pctFree%)." `
                -Recommendation "Free disk space on $sysDrive before large/feature updates."
        } else {
            Add-Finding -Category 'Disk' -Severity 'OK' -Detail "$sysDrive free space is adequate ($freeGB GB / $pctFree%)."
        }
    } catch {
        Write-Report "Unable to read $sysDrive disk info: $($_.Exception.Message)"
    }

    Test-SystemPartitionSpace

    $sdRoot = Join-Path $env:SystemRoot 'SoftwareDistribution'
    $downloadPath = Join-Path $sdRoot 'Download'
    $dataStore = Join-Path $sdRoot 'DataStore\DataStore.edb'
    $catroot2 = Join-Path $env:SystemRoot 'System32\catroot2'

    $download = Get-FolderSize -Path $downloadPath
    if ($null -ne $download) {
        $qualifier = ''
        if (-not $download.Complete) { $qualifier = ' (partial; measurement timed out)' }
        Write-Report "SoftwareDistribution\Download : $(Format-Bytes $download.Bytes)$qualifier across $($download.FileCount) files"

        # Flag only a large AND stale cache; a large but recently-written one is a normal staged update.
        $staleDays = 10
        $isStale = ($download.NewestWrite -ne [datetime]::MinValue) -and ($download.NewestWrite -lt (Get-Date).AddDays(-$staleDays))
        if ($download.Complete -and $download.Bytes -ge 10GB -and $isStale) {
            Add-Finding -Category 'Update Store' -Severity 'Warning' `
                -Detail "SoftwareDistribution\Download holds $(Format-Bytes $download.Bytes) with nothing written since $($download.NewestWrite.ToString('yyyy-MM-dd')), which suggests an abandoned/stalled download rather than an active one." `
                -Recommendation 'Stop wuauserv/bits, rename SoftwareDistribution to SoftwareDistribution.old, then re-scan.'
        } elseif ($download.Bytes -ge 10GB) {
            Add-Finding -Category 'Update Store' -Severity 'Info' `
                -Detail "SoftwareDistribution\Download is large ($(Format-Bytes $download.Bytes)) but was written recently, consistent with an in-progress or freshly staged update."
        }
    }

    if (Test-Path -LiteralPath $dataStore) {
        try {
            $edb = Get-Item -LiteralPath $dataStore -ErrorAction Stop
            $edbBytes = [double]$edb.Length
            Write-Report "DataStore.edb   : $(Format-Bytes $edbBytes) (modified $($edb.LastWriteTime))"
            if ($edbBytes -ge 4GB) {
                Add-Finding -Category 'Update Store' -Severity 'Warning' `
                    -Detail "DataStore.edb is very large ($(Format-Bytes $edbBytes)); the update datastore may be bloated or corrupt." `
                    -Recommendation 'Reset the Windows Update datastore (rename SoftwareDistribution), then re-scan.'
            } elseif ($edbBytes -ge 2GB) {
                Add-Finding -Category 'Update Store' -Severity 'Info' `
                    -Detail "DataStore.edb is moderately large ($(Format-Bytes $edbBytes)); usually benign, but worth noting if update scans are slow."
            }
        } catch { Write-Verbose ('Ignored: ' + $_.Exception.Message) }
    } else {
        Write-Report 'DataStore.edb   : not found'
    }

    $cat = Get-FolderSize -Path $catroot2
    if ($null -ne $cat) {
        $qualifier = ''
        if (-not $cat.Complete) { $qualifier = ' (partial; measurement timed out)' }
        Write-Report "catroot2        : $(Format-Bytes $cat.Bytes)$qualifier across $($cat.FileCount) files"

        # catroot2 size is a weak signal; only flag an extreme size, and never a timeout.
        if ($cat.Complete -and $cat.Bytes -ge 4GB) {
            Add-Finding -Category 'Update Store' -Severity 'Info' `
                -Detail "catroot2 is unusually large ($(Format-Bytes $cat.Bytes)); if update scans are slow, resetting it (rename catroot2 with cryptsvc stopped) can help."
        }
    }
}

function Test-SystemPartitionSpace {
    # System/EFI partition space; a well-known feature-update blocker (0x800F0922). Storage module, else Win32_Volume.
    $systemVolume = $null

    if (Get-Command Get-Partition -ErrorAction SilentlyContinue) {
        try {
            $part = Get-Partition -ErrorAction Stop |
                Where-Object { $_.IsSystem -or $_.GptType -eq '{c12a7328-f81f-11d2-ba4b-00a0c93ec93b}' } |
                Select-Object -First 1
            if ($part) {
                $systemVolume = Get-Volume -Partition $part -ErrorAction SilentlyContinue
            }
        } catch { Write-Verbose ('Ignored: ' + $_.Exception.Message) }
    }

    if (-not $systemVolume) {
        try {
            # BootVolume=TRUE with no drive letter is the usual shape of the hidden system partition.
            $systemVolume = Get-CimInstance Win32_Volume -ErrorAction Stop |
                Where-Object { $_.BootVolume -eq $true -and [string]::IsNullOrWhiteSpace($_.DriveLetter) } |
                Select-Object -First 1
        } catch { Write-Verbose ('Ignored: ' + $_.Exception.Message) }
    }

    if (-not $systemVolume) {
        Write-Report 'System/EFI partition : not identified (single-partition or non-standard layout).'
        return
    }

    $free = $null
    foreach ($prop in @('SizeRemaining', 'FreeSpace')) {
        if ($systemVolume.PSObject.Properties.Name -contains $prop -and $null -ne $systemVolume.$prop) {
            $free = [double]$systemVolume.$prop
            break
        }
    }

    if ($null -eq $free) {
        Write-Report 'System/EFI partition : free space unavailable.'
        return
    }

    Write-Report "System/EFI partition : $(Format-Bytes $free) free"

    if ($free -lt 50MB) {
        Add-Finding -Category 'Disk' -Severity 'Critical' `
            -Detail "The system/EFI partition has only $(Format-Bytes $free) free. This is a common cause of feature-update failure 0x800F0922." `
            -Recommendation 'Free space on the system partition (remove old language packs / stale boot font files), then retry the update.'
    } elseif ($free -lt 100MB) {
        Add-Finding -Category 'Disk' -Severity 'Warning' `
            -Detail "The system/EFI partition is low on space ($(Format-Bytes $free) free); feature updates may fail with 0x800F0922." `
            -Recommendation 'Free space on the system partition before attempting a feature update.'
    } else {
        Add-Finding -Category 'Disk' -Severity 'OK' -Detail "System/EFI partition has adequate space ($(Format-Bytes $free) free)."
    }
}

function Get-WuConfiguration {
    Write-Section -Title 'Windows Update Configuration'

    $wuPath = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate'
    $auPath = Join-Path $wuPath 'AU'
    $wu = Get-ItemProperty -Path $wuPath -ErrorAction SilentlyContinue
    $au = Get-ItemProperty -Path $auPath -ErrorAction SilentlyContinue

    $wsusServer = ''
    if ($wu -and -not [string]::IsNullOrWhiteSpace([string]$wu.WUServer)) {
        $wsusServer = [string]$wu.WUServer
    }

    if ($wsusServer) {
        Write-Report "Update source : WSUS ($wsusServer)"
    } else {
        Write-Report 'Update source : Microsoft Update / Windows Update (Internet)'
    }

    if ($au -and $null -ne $au.UseWUServer) {
        Write-Report "UseWUServer   : $($au.UseWUServer)"
        if ($au.UseWUServer -eq 1 -and -not $wsusServer) {
            Add-Finding -Category 'Configuration' -Severity 'Warning' `
                -Detail 'UseWUServer=1 but no WUServer is configured. Clients are pointed at a WSUS server that is not set.' `
                -Recommendation 'Set the WUServer policy or clear UseWUServer to use Microsoft Update.'
        }
    }
    if ($au -and $null -ne $au.NoAutoUpdate) {
        Write-Report "NoAutoUpdate  : $($au.NoAutoUpdate)"
        if ($au.NoAutoUpdate -eq 1) {
            Add-Finding -Category 'Configuration' -Severity 'Info' `
                -Detail 'NoAutoUpdate=1 - automatic updating is turned off by policy. This is expected when the device is patched by the RMM or another mechanism; it only matters if Windows is meant to self-update.'
        }
    }
    if ($au -and $null -ne $au.AUOptions) { Write-Report "AUOptions     : $($au.AUOptions)" }

    if ($wu -and $wu.DisableWindowsUpdateAccess -eq 1) {
        Add-Finding -Category 'Configuration' -Severity 'Warning' `
            -Detail 'DisableWindowsUpdateAccess=1 - Windows Update access is blocked by policy.' `
            -Recommendation 'Clear the DisableWindowsUpdateAccess policy if updates should be allowed.'
    }
    if ($wu -and $wu.DoNotConnectToWindowsUpdateInternetLocations -eq 1 -and -not $wsusServer) {
        Add-Finding -Category 'Configuration' -Severity 'Warning' `
            -Detail 'DoNotConnectToWindowsUpdateInternetLocations=1 without a WSUS server - the client cannot reach any update source.' `
            -Recommendation 'Provide a WSUS server or clear this policy.'
    }

    if ($wu) {
        foreach ($p in @('DeferQualityUpdatesPeriodInDays', 'DeferFeatureUpdatesPeriodInDays')) {
            if ($null -ne $wu.$p -and [int]$wu.$p -gt 0) {
                Write-Report "$p : $($wu.$p)"
                Add-Finding -Category 'Configuration' -Severity 'Info' `
                    -Detail "$p is set to $($wu.$p) days; updates are deliberately held back for that period."
            }
        }

        # A release pin is invisible in the UI and silently stops feature updates forever.
        if (-not [string]::IsNullOrWhiteSpace([string]$wu.TargetReleaseVersionInfo)) {
            $pin = [string]$wu.TargetReleaseVersionInfo
            $current = ''
            try {
                $current = [string](Get-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion' -Name DisplayVersion -ErrorAction Stop).DisplayVersion
            } catch {
                try {
                    $current = [string](Get-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion' -Name ReleaseId -ErrorAction Stop).ReleaseId
                } catch { Write-Verbose ('Ignored: ' + $_.Exception.Message) }
            }

            Write-Report "TargetReleaseVersionInfo : $pin (device is on '$current')"
            if ($current -and $pin -eq $current) {
                Add-Finding -Category 'Configuration' -Severity 'Info' `
                    -Detail "The device is pinned to Windows release '$pin' and is already running it. It will not receive a newer feature update while this policy is set - this is by design. Raise or clear TargetReleaseVersionInfo to allow a move to a newer release."
            } else {
                Add-Finding -Category 'Configuration' -Severity 'Info' `
                    -Detail "The device is pinned to Windows release '$pin' (currently on '$current'); it will upgrade only as far as the pinned release."
            }
        }

        if ($wu.PauseQualityUpdatesStartTime) {
            Add-Finding -Category 'Configuration' -Severity 'Info' `
                -Detail "Quality updates are paused (since $($wu.PauseQualityUpdatesStartTime))."
        }
        if ($wu.PauseFeatureUpdatesStartTime) {
            Add-Finding -Category 'Configuration' -Severity 'Info' `
                -Detail "Feature updates are paused (since $($wu.PauseFeatureUpdatesStartTime))."
        }
    }

    Get-MdmUpdatePolicy

    $script:WsusServer = $wsusServer
}

function Get-MdmUpdatePolicy {
    # Intune/MDM update policy lives here, not under Policies\...\WindowsUpdate.
    $mdmPath = 'HKLM:\SOFTWARE\Microsoft\PolicyManager\current\device\Update'
    if (-not (Test-Path -LiteralPath $mdmPath)) {
        Write-Report 'MDM policy    : none (device is not MDM-managed for Windows Update)'
        return
    }

    $mdm = Get-ItemProperty -Path $mdmPath -ErrorAction SilentlyContinue
    if (-not $mdm) { return }

    $values = @($mdm.PSObject.Properties | Where-Object { $_.Name -notlike 'PS*' })
    if ($values.Count -eq 0) { return }

    Write-Report "MDM policy    : device is MDM-managed for Windows Update ($($values.Count) setting(s))"
    foreach ($v in $values) {
        Write-Report ('  {0} = {1}' -f $v.Name, $v.Value)
    }

    Add-Finding -Category 'Configuration' -Severity 'Info' `
        -Detail "Windows Update is MDM-managed (Intune or equivalent); $($values.Count) policy value(s) are applied under PolicyManager. Local Group Policy settings are not the authority on this device."

    foreach ($name in @('DeferQualityUpdatesPeriodInDays', 'DeferFeatureUpdatesPeriodInDays')) {
        if ($mdm.PSObject.Properties.Name -contains $name -and [int]$mdm.$name -gt 0) {
            Add-Finding -Category 'Configuration' -Severity 'Info' `
                -Detail "MDM policy $name is set to $($mdm.$name) days; updates are deliberately held back for that period."
        }
    }
    foreach ($name in @('PauseQualityUpdates', 'PauseFeatureUpdates')) {
        if ($mdm.PSObject.Properties.Name -contains $name -and [int]$mdm.$name -eq 1) {
            Add-Finding -Category 'Configuration' -Severity 'Warning' `
                -Detail "MDM policy $name is enabled; the corresponding updates are currently paused." `
                -Recommendation 'Clear the pause in the MDM/Intune update ring if this device should be patching.'
        }
    }
    if ($mdm.PSObject.Properties.Name -contains 'TargetReleaseVersion' -and
        -not [string]::IsNullOrWhiteSpace([string]$mdm.TargetReleaseVersion)) {
        Add-Finding -Category 'Configuration' -Severity 'Info' `
            -Detail "MDM policy pins this device to Windows release '$($mdm.TargetReleaseVersion)'."
    }
}

function Test-UpdateConnectivity {
    param([AllowEmptyString()][string]$WsusServer = '')

    Write-Section -Title 'Update Endpoint Connectivity'

    if ($WsusServer) {
        try {
            $uri = [uri]$WsusServer
            $wsusHost = $uri.Host
            $wsusPort = $uri.Port
            if ($wsusPort -le 0) { $wsusPort = 80 }

            $ips = Resolve-HostAddressList -Name $wsusHost
            if ($ips) {
                Write-Report "WSUS DNS  : $wsusHost -> $ips"
            } else {
                Write-Report "WSUS DNS  : $wsusHost -> RESOLUTION FAILED"
                Add-Finding -Category 'Connectivity' -Severity 'Critical' `
                    -Detail "WSUS host '$wsusHost' does not resolve in DNS." `
                    -Recommendation 'Fix DNS or correct the WUServer policy URL.'
            }

            if (Test-TcpPort -ComputerName $wsusHost -Port $wsusPort) {
                Write-Report "WSUS TCP  : $wsusHost`:$wsusPort reachable"
                Add-Finding -Category 'Connectivity' -Severity 'OK' -Detail "WSUS server $wsusHost`:$wsusPort is reachable."
            } else {
                Write-Report "WSUS TCP  : $wsusHost`:$wsusPort UNREACHABLE"
                Add-Finding -Category 'Connectivity' -Severity 'Critical' `
                    -Detail "Cannot reach WSUS server $wsusHost on port $wsusPort." `
                    -Recommendation 'Verify the WSUS server is online and reachable (firewall/port).'
            }
        } catch {
            Write-Report "Unable to parse WUServer URL '$WsusServer': $($_.Exception.Message)"
        }
        return
    }

    $endpoints = @(
        'windowsupdate.microsoft.com',
        'download.windowsupdate.com',
        'fe3.delivery.mp.microsoft.com',
        'sls.update.microsoft.com',
        'catalog.update.microsoft.com'
    )

    $reachable = 0
    foreach ($endpoint in $endpoints) {
        $ips = Resolve-HostAddressList -Name $endpoint
        $ok = $false
        if ($ips) { $ok = Test-TcpPort -ComputerName $endpoint -Port 443 }
        $status = 'UNREACHABLE'
        if ($ok) { $status = 'reachable'; $reachable++ }
        Write-Report ('{0,-38} 443 {1}' -f $endpoint, $status)
    }

    if ($reachable -eq 0) {
        Add-Finding -Category 'Connectivity' -Severity 'Critical' `
            -Detail 'None of the Microsoft Update endpoints are reachable on TCP 443.' `
            -Recommendation 'Check internet connectivity, DNS, firewall, and proxy configuration.'
        return
    } elseif ($reachable -lt $endpoints.Count) {
        Add-Finding -Category 'Connectivity' -Severity 'Warning' `
            -Detail "Only $reachable of $($endpoints.Count) Microsoft Update endpoints are reachable." `
            -Recommendation 'Review firewall/proxy allow-lists for Windows Update endpoints.'
    } else {
        Add-Finding -Category 'Connectivity' -Severity 'OK' -Detail 'All tested Microsoft Update endpoints are reachable.'
    }

    Test-TlsInterception
}

function Test-TlsInterception {
    # A 443 handshake proves the port is open; check the served cert's issuer for TLS interception.
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', '',
        Justification = 'The ServerCertificateValidationCallback delegate has a fixed four-parameter signature. Only $cert is needed, but the others cannot be omitted.')]
    param()

    $target = 'https://fe3.delivery.mp.microsoft.com'
    $issuer = $null
    $subject = $null
    $previous = [Net.ServicePointManager]::ServerCertificateValidationCallback

    try {
        [Net.ServicePointManager]::ServerCertificateValidationCallback = {
            param($senderObj, $cert, $chain, $errors)
            $script:CapturedIssuer = $cert.Issuer
            $script:CapturedSubject = $cert.Subject
            return $true   # accept regardless; we are inspecting, not validating
        }

        $req = [System.Net.HttpWebRequest]::Create($target)
        $req.Method = 'HEAD'
        $req.Timeout = 8000
        $req.AllowAutoRedirect = $false
        $req.Proxy = [System.Net.WebRequest]::GetSystemWebProxy()
        try {
            $resp = $req.GetResponse()
            $resp.Close()
        } catch {
            # A 4xx/5xx is fine - the TLS handshake completed, which is all we need.
            Write-Verbose ('Update endpoint returned an HTTP error (handshake still succeeded): ' + $_.Exception.Message)
        }

        $issuer = $script:CapturedIssuer
        $subject = $script:CapturedSubject
    } catch {
        Write-Report "TLS inspection check could not complete: $($_.Exception.Message)"
        return
    } finally {
        [Net.ServicePointManager]::ServerCertificateValidationCallback = $previous
    }

    if ([string]::IsNullOrWhiteSpace($issuer)) {
        Write-Report 'TLS cert  : issuer could not be determined.'
        return
    }

    Write-Report "TLS cert  : subject $subject"
    Write-Report "TLS cert  : issued by $issuer"

    # Warn only on a positively private/internal issuer; an unknown public CA is just Info.
    $selfSigned = (-not [string]::IsNullOrWhiteSpace($subject)) -and ($issuer -eq $subject)
    $inspectionVendor = $issuer -match '(?i)Fortinet|FortiGate|Palo Alto|PAN-OS|Zscaler|Netskope|Cisco Umbrella|Blue ?Coat|Symantec Web|Forcepoint|McAfee Web|Skyhigh|Check ?Point|SonicWall|WatchGuard|Barracuda|Sophos|Untangle|Squid|Kaspersky|ESET|Bitdefender|SSL ?Inspection|Deep ?Packet|Web ?Gateway|Web ?Filter'
    $internalPki = $issuer -match '(?i)\.local\b|\.corp\b|\.lan\b|\.internal\b|Active Directory|AD ?CS|Issuing CA|Enterprise CA|Intermediate CA|Root CA'

    if ($selfSigned -or $inspectionVendor -or $internalPki) {
        $why = 'self-signed'
        if ($inspectionVendor) { $why = 'a known TLS-inspection product' }
        elseif ($internalPki) { $why = 'an internal/private certificate authority' }
        Add-Finding -Category 'Connectivity' -Severity 'Warning' `
            -Detail "The TLS certificate served for the update endpoint was issued by '$issuer' ($why). Traffic to Windows Update appears to be intercepted and re-signed, a common cause of 0x800B0109 and 0x80072F8F." `
            -Recommendation 'Exempt the Windows Update endpoints from TLS/SSL inspection on the firewall or proxy.'
    } else {
        Add-Finding -Category 'Connectivity' -Severity 'Info' `
            -Detail "Update endpoint TLS certificate issuer: $issuer (no private/internal interception signature detected)."
    }
}

function Test-TimeSkew {
    Write-Section -Title 'System Time'

    Write-Report "Local time (UTC): $((Get-Date).ToUniversalTime())"

    try {
        $request = [System.Net.HttpWebRequest]::Create('http://www.msftconnecttest.com/connecttest.txt')
        $request.Method = 'GET'
        $request.Timeout = 8000
        $request.AllowAutoRedirect = $false
        $response = $request.GetResponse()
        $dateHeader = $response.Headers['Date']
        $response.Close()

        if ($dateHeader) {
            $serverUtc = ([datetime]$dateHeader).ToUniversalTime()
            $skew = [math]::Abs(((Get-Date).ToUniversalTime() - $serverUtc).TotalMinutes)
            Write-Report "Server time (UTC): $serverUtc"
            Write-Report ('Clock skew      : {0:N1} minutes' -f $skew)

            if ($skew -gt 5) {
                Add-Finding -Category 'Time' -Severity 'Warning' `
                    -Detail ('System clock differs from Microsoft by {0:N1} minutes. Large skew breaks TLS/WSUS auth.' -f $skew) `
                    -Recommendation 'Correct the system clock/time zone and resync time (w32tm /resync).'
            } else {
                Add-Finding -Category 'Time' -Severity 'OK' -Detail 'System clock is within tolerance.'
            }
        }
    } catch {
        Write-Report "Could not determine server time (offline or blocked): $($_.Exception.Message)"
        Add-Finding -Category 'Time' -Severity 'Info' -Detail 'Clock skew could not be measured (no reachable time reference).'
    }
}

function Get-Tls12Status {
    Write-Section -Title 'TLS 1.2'

    $tlsClient = 'HKLM:\SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Protocols\TLS 1.2\Client'
    $disabled = $false
    if (Test-Path -LiteralPath $tlsClient) {
        $props = Get-ItemProperty -Path $tlsClient -ErrorAction SilentlyContinue
        if ($props) {
            if ($props.PSObject.Properties.Name -contains 'Enabled' -and $props.Enabled -eq 0) { $disabled = $true }
            if ($props.PSObject.Properties.Name -contains 'DisabledByDefault' -and $props.DisabledByDefault -eq 1) { $disabled = $true }
        }
    }

    if ($disabled) {
        Write-Report 'TLS 1.2 client: explicitly DISABLED in SCHANNEL.'
        Add-Finding -Category 'TLS' -Severity 'Warning' `
            -Detail 'TLS 1.2 client is disabled in SCHANNEL. Modern Windows Update endpoints require TLS 1.2.' `
            -Recommendation 'Enable TLS 1.2 client in SCHANNEL and .NET strong crypto.'
    } else {
        Write-Report 'TLS 1.2 client: enabled (or OS default).'
        Add-Finding -Category 'TLS' -Severity 'OK' -Detail 'TLS 1.2 is enabled (or using the secure OS default).'
    }
}

function Get-ProxyConfiguration {
    Write-Section -Title 'Proxy Configuration'

    # netsh output is localized (display only); WinHttpSettings blob is the language-independent source.
    try {
        $winhttp = (& netsh winhttp show proxy 2>&1) | Out-String
        Write-Report 'WinHTTP (system) proxy:'
        Write-Report ($winhttp.Trim())
    } catch {
        Write-Report "Unable to read WinHTTP proxy: $($_.Exception.Message)"
    }

    try {
        $connPath = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Internet Settings\Connections'
        $conn = Get-ItemProperty -Path $connPath -Name WinHttpSettings -ErrorAction SilentlyContinue
        if ($conn -and $conn.WinHttpSettings) {
            # WinHttpSettings blob: [8-11] access type (1=direct, 3=proxy), [12-15] proxy string length, then that many ASCII bytes at [16..].
            $blob = [byte[]]$conn.WinHttpSettings

            if ($blob.Length -lt 16) {
                Write-Report 'WinHTTP proxy (registry): setting present but too short to parse.'
            } else {
                $accessType = [BitConverter]::ToUInt32($blob, 8)
                $proxyLen = [BitConverter]::ToUInt32($blob, 12)

                $proxyText = ''
                if ($proxyLen -gt 0 -and (16 + $proxyLen) -le $blob.Length) {
                    $proxyText = [System.Text.Encoding]::ASCII.GetString($blob, 16, $proxyLen)
                }

                if ($accessType -eq 1 -and $proxyLen -eq 0) {
                    Write-Report 'WinHTTP proxy (registry): direct access, no proxy.'
                } else {
                    $shown = $proxyText
                    if ([string]::IsNullOrWhiteSpace($shown)) { $shown = "access type $accessType" }
                    Write-Report "WinHTTP proxy configured (registry): $shown"
                    Add-Finding -Category 'Proxy' -Severity 'Info' `
                        -Detail "A WinHTTP proxy is configured ($shown). Windows Update uses this proxy; verify it allows the update endpoints and does not inspect their TLS." `
                        -Recommendation 'Confirm the proxy allow-lists Microsoft Update endpoints and bypasses TLS inspection for them.'
                }
            }
        }
    } catch {
        Write-Report "Unable to read WinHttpSettings: $($_.Exception.Message)"
    }

    # Runs as SYSTEM, so read the console user's hive explicitly instead of HKCU.
    try {
        $consoleUser = (Get-CimInstance Win32_ComputerSystem -ErrorAction Stop).UserName
        if ([string]::IsNullOrWhiteSpace($consoleUser)) {
            Write-Report 'WinINET (per-user) proxy: no interactive user signed in; not inspected.'
            return
        }

        $sid = $null
        try {
            $sid = (New-Object System.Security.Principal.NTAccount($consoleUser)).Translate(
                [System.Security.Principal.SecurityIdentifier]).Value
        } catch { Write-Verbose ('Ignored: ' + $_.Exception.Message) }

        if (-not $sid -or -not (Test-Path -LiteralPath "Registry::HKEY_USERS\$sid")) {
            Write-Report "WinINET (per-user) proxy: hive for $consoleUser not loaded; not inspected."
            return
        }

        $inet = Get-ItemProperty -Path "Registry::HKEY_USERS\$sid\Software\Microsoft\Windows\CurrentVersion\Internet Settings" -ErrorAction SilentlyContinue
        if ($inet -and $inet.ProxyEnable -eq 1 -and $inet.ProxyServer) {
            Write-Report "WinINET proxy for $consoleUser : $($inet.ProxyServer)"
            Add-Finding -Category 'Proxy' -Severity 'Info' `
                -Detail "The signed-in user ($consoleUser) has a WinINET proxy set ($($inet.ProxyServer)). Windows Update itself uses WinHTTP, not this, but a mismatch between the two often explains 'works in the browser, fails in Windows Update'."
        } else {
            Write-Report "WinINET proxy for $consoleUser : none."
        }
    } catch {
        Write-Report "Unable to inspect per-user proxy: $($_.Exception.Message)"
    }
}

function Test-BitsJobs {
    Write-Section -Title 'BITS Transfer Jobs'

    if (-not (Get-Command Get-BitsTransfer -ErrorAction SilentlyContinue)) {
        Write-Report 'BitsTransfer module not available on this system.'
        Add-Finding -Category 'BITS' -Severity 'Info' -Detail 'BITS job state could not be checked (module unavailable).'
        return
    }

    try {
        $jobs = @(Get-BitsTransfer -AllUsers -ErrorAction SilentlyContinue)
        if ($jobs.Count -eq 0) {
            Write-Report 'No active BITS jobs.'
            Add-Finding -Category 'BITS' -Severity 'OK' -Detail 'No stuck or errored BITS jobs found.'
            return
        }

        $problem = @($jobs | Where-Object { $_.JobState -match 'Error|TransientError|Suspended' })
        foreach ($job in $jobs) {
            Write-Report ('{0,-40} State: {1}' -f $job.DisplayName, $job.JobState)
        }

        if ($problem.Count -gt 0) {
            Add-Finding -Category 'BITS' -Severity 'Warning' `
                -Detail "$($problem.Count) BITS job(s) are in Error/TransientError/Suspended state." `
                -Recommendation 'Investigate/clear stuck BITS jobs (bitsadmin /reset /allusers), then re-scan.'
        } else {
            Add-Finding -Category 'BITS' -Severity 'OK' -Detail 'BITS jobs present but none in an error state.'
        }
    } catch {
        Write-Report "Unable to enumerate BITS jobs: $($_.Exception.Message)"
    }
}

function Test-WuActivityRecency {
    # Last successful scan/install via the Update Agent COM API (the old Results reg key is gone on Win10/11).
    Write-Section -Title 'Update Activity Recency'

    $lastSearch = $null
    $lastInstall = $null

    try {
        $au = New-Object -ComObject Microsoft.Update.AutoUpdate -ErrorAction Stop
        $results = $au.Results
        if ($results.LastSearchSuccessDate -and [datetime]$results.LastSearchSuccessDate -gt [datetime]'1980-01-01') {
            $lastSearch = [datetime]$results.LastSearchSuccessDate
        }
        if ($results.LastInstallationSuccessDate -and [datetime]$results.LastInstallationSuccessDate -gt [datetime]'1980-01-01') {
            $lastInstall = [datetime]$results.LastInstallationSuccessDate
        }
    } catch {
        Write-Report "Update Agent COM API unavailable: $($_.Exception.Message)"
        Add-Finding -Category 'Update Activity' -Severity 'Info' `
            -Detail 'Last scan/install times could not be read (Update Agent COM API unavailable on this device).'
        return
    }

    if ($lastSearch) {
        $age = [int]((Get-Date) - $lastSearch).TotalDays
        Write-Report "Last successful scan    : $lastSearch ($age days ago)"

        if ($age -ge 60) {
            Add-Finding -Category 'Update Activity' -Severity 'Critical' `
                -Detail "The Windows Update client has not completed a successful scan in $age days (last: $lastSearch). The client is stalled." `
                -Recommendation 'Trigger a scan (UsoClient StartScan), and review the connectivity and configuration findings above.'
        } elseif ($age -ge 30) {
            Add-Finding -Category 'Update Activity' -Severity 'Warning' `
                -Detail "The last successful update scan was $age days ago ($lastSearch). Healthy clients scan at least every few days." `
                -Recommendation 'Trigger a scan and confirm the device can reach its update source.'
        } else {
            Add-Finding -Category 'Update Activity' -Severity 'OK' -Detail "Last successful update scan was $age days ago ($lastSearch)."
        }
    } else {
        Write-Report 'Last successful scan    : never recorded'
        Add-Finding -Category 'Update Activity' -Severity 'Warning' `
            -Detail 'No successful update scan has ever been recorded on this device.' `
            -Recommendation 'Trigger a scan and review the configuration/connectivity findings above.'
    }

    if ($lastInstall) {
        $age = [int]((Get-Date) - $lastInstall).TotalDays
        Write-Report "Last successful install : $lastInstall ($age days ago)"
    } else {
        Write-Report 'Last successful install : never recorded'
    }

    # LastInstallationSuccessDate is skewed by daily Defender updates; hotfix history is the honest signal.
    try {
        $lastHotfix = Get-HotFix -ErrorAction Stop |
            Where-Object { $_.InstalledOn } |
            Sort-Object InstalledOn -Descending |
            Select-Object -First 1

        if ($lastHotfix) {
            $age = [int]((Get-Date) - $lastHotfix.InstalledOn).TotalDays
            Write-Report "Last OS update (hotfix) : $($lastHotfix.HotFixID) on $($lastHotfix.InstalledOn.ToString('yyyy-MM-dd')) ($age days ago)"

            if ($age -ge 120) {
                Add-Finding -Category 'Update Activity' -Severity 'Critical' `
                    -Detail "No operating-system update has installed in $age days (last: $($lastHotfix.HotFixID) on $($lastHotfix.InstalledOn.ToString('yyyy-MM-dd'))). Note that Defender definition updates do not count here and can make the client look active while no OS patching is happening." `
                    -Recommendation 'Check the servicing and configuration findings above - an end-of-service release or a policy pin is the usual cause.'
            } elseif ($age -ge 60) {
                Add-Finding -Category 'Update Activity' -Severity 'Warning' `
                    -Detail "The last operating-system update was $age days ago ($($lastHotfix.HotFixID) on $($lastHotfix.InstalledOn.ToString('yyyy-MM-dd')))." `
                    -Recommendation 'Confirm updates are being approved/offered for this device.'
            } else {
                Add-Finding -Category 'Update Activity' -Severity 'OK' `
                    -Detail "Last operating-system update was $age days ago ($($lastHotfix.HotFixID))."
            }
        }
    } catch {
        Write-Report "Could not read installed update history: $($_.Exception.Message)"
    }
}

# Windows client end-of-servicing by build. REVIEW PERIODICALLY - snapshot compiled 2026-09; servers excluded.
$script:OsServicingTable = @{
    # Windows 10
    19041 = @{ Name = 'Windows 10 2004'; Broad = '2021-12-14'; Enterprise = '2021-12-14' }
    19042 = @{ Name = 'Windows 10 20H2'; Broad = '2022-05-10'; Enterprise = '2023-05-09' }
    19043 = @{ Name = 'Windows 10 21H1'; Broad = '2022-12-13'; Enterprise = '2022-12-13' }
    19044 = @{ Name = 'Windows 10 21H2'; Broad = '2023-06-13'; Enterprise = '2024-06-11' }
    19045 = @{ Name = 'Windows 10 22H2'; Broad = '2025-10-14'; Enterprise = '2025-10-14' }
    # Windows 11
    22000 = @{ Name = 'Windows 11 21H2'; Broad = '2023-10-10'; Enterprise = '2024-10-08' }
    22621 = @{ Name = 'Windows 11 22H2'; Broad = '2024-10-08'; Enterprise = '2025-10-14' }
    22631 = @{ Name = 'Windows 11 23H2'; Broad = '2025-11-11'; Enterprise = '2026-11-10' }
    26100 = @{ Name = 'Windows 11 24H2'; Broad = '2026-10-13'; Enterprise = '2027-10-12' }
    26200 = @{ Name = 'Windows 11 25H2'; Broad = '2027-10-12'; Enterprise = '2028-10-10' }
}

# LTSB/LTSC end-of-servicing by build. These editions share a build number with the equivalent GA
# release above but have far longer lifecycles, so they are keyed separately and resolved by edition
# first. NonIoT = Enterprise/Education LTSC; IoT = IoT Enterprise LTSC (10-year lifecycle).
# REVIEW PERIODICALLY - snapshot compiled 2026-09. https://learn.microsoft.com/windows/release-health/supported-versions-windows-client
$script:LtscServicingTable = @{
    10240 = @{ Name = 'Windows 10 Enterprise 2015 LTSB'; NonIoT = '2025-10-14'; IoT = '2025-10-14' }
    14393 = @{ Name = 'Windows 10 Enterprise 2016 LTSB'; NonIoT = '2026-10-13'; IoT = '2026-10-13' }
    17763 = @{ Name = 'Windows 10 Enterprise LTSC 2019'; NonIoT = '2029-01-09'; IoT = '2029-01-09' }
    19044 = @{ Name = 'Windows 10 Enterprise LTSC 2021'; NonIoT = '2027-01-12'; IoT = '2032-01-13' }
    26100 = @{ Name = 'Windows 11 Enterprise LTSC 2024'; NonIoT = '2029-10-09'; IoT = '2034-10-10' }
}

function Test-OsServicingStatus {
    # A client past end-of-servicing receives nothing while every other check looks clean.
    Write-Section -Title 'OS Servicing Status'

    try {
        $os = Get-CimInstance Win32_OperatingSystem -ErrorAction Stop
    } catch {
        Write-Report "Unable to read OS details: $($_.Exception.Message)"
        return
    }

    if ([int]$os.ProductType -ne 1) {
        Write-Report 'Server OS - end-of-servicing is not evaluated by this check.'
        Add-Finding -Category 'Servicing' -Severity 'Info' `
            -Detail 'Server OS: end-of-servicing follows the server lifecycle and was not evaluated.'
        return
    }

    $build = 0
    [void][int]::TryParse(([string]$os.BuildNumber), [ref]$build)

    # Use EditionID, not Caption (Caption can say "Business" on Pro and misclassify the servicing lane).
    $editionId = ''
    try {
        $editionId = [string](Get-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion' -Name EditionID -ErrorAction Stop).EditionID
    } catch { Write-Verbose ('Ignored: ' + $_.Exception.Message) }

    # LTSB/LTSC editions carry an 'S' suffix (EnterpriseS, EnterpriseSN, IoTEnterpriseS) and have their
    # own, much longer lifecycles that share a build number with the GA release, so resolve them first.
    if ($editionId) {
        $isLtsc = ($editionId -match 'EnterpriseS')
    } else {
        $isLtsc = ([string]$os.Caption -match 'LTSC|LTSB')
    }

    if ($isLtsc) {
        $ltsc = $script:LtscServicingTable[$build]
        if (-not $ltsc) {
            Write-Report "LTSC/LTSB build $build is not in the servicing table (newer than this script, or an unsupported build)."
            Add-Finding -Category 'Servicing' -Severity 'Info' `
                -Detail "LTSC/LTSB OS build $build was not found in the script's end-of-servicing table; it may be newer than the table (compiled 2026-09)."
            return
        }

        # IoT Enterprise LTSC (EditionID IoTEnterpriseS) has a 10-year lifecycle; standard Enterprise LTSC is 5.
        if ($editionId) {
            $isIot = ($editionId -match 'IoTEnterpriseS')
        } else {
            $isIot = ([string]$os.Caption -match 'IoT')
        }
        $releaseName = $ltsc.Name
        $edition = if ($isIot) { 'IoT Enterprise LTSC' } else { 'Enterprise LTSC/LTSB' }
        $eos = if ($isIot) { [datetime]$ltsc.IoT } else { [datetime]$ltsc.NonIoT }
    } else {
        $entry = $script:OsServicingTable[$build]
        if (-not $entry) {
            Write-Report "Build $build is not in the servicing table (newer than this script, or an unsupported build)."
            Add-Finding -Category 'Servicing' -Severity 'Info' `
                -Detail "OS build $build was not found in the script's end-of-servicing table; it may be newer than the table (compiled 2026-09)."
            return
        }

        if ($editionId) {
            $isEnterprise = ($editionId -match 'Enterprise|Education')
        } else {
            $isEnterprise = ([string]$os.Caption -match 'Enterprise|Education')
        }
        $releaseName = $entry.Name
        $edition = if ($isEnterprise) { 'Enterprise/Education' } else { 'Home/Pro' }
        $eos = if ($isEnterprise) { [datetime]$entry.Enterprise } else { [datetime]$entry.Broad }
    }

    Write-Report "Release       : $releaseName (build $build)"
    Write-Report "Servicing lane: $edition"
    Write-Report "End of service: $($eos.ToString('yyyy-MM-dd'))"

    $daysLeft = [int]($eos - (Get-Date)).TotalDays

    if ($daysLeft -lt 0) {
        Add-Finding -Category 'Servicing' -Severity 'Critical' `
            -Detail "$releaseName ($edition) reached end of servicing on $($eos.ToString('yyyy-MM-dd')), $([math]::Abs($daysLeft)) days ago. This device no longer receives quality updates, which explains an absence of updates even when everything else is healthy." `
            -Recommendation 'Upgrade to a serviced Windows release (feature update or in-place upgrade).'
    } elseif ($daysLeft -le 90) {
        Add-Finding -Category 'Servicing' -Severity 'Warning' `
            -Detail "$releaseName ($edition) reaches end of servicing on $($eos.ToString('yyyy-MM-dd')), in $daysLeft days." `
            -Recommendation 'Plan the feature update before servicing ends.'
    } else {
        Add-Finding -Category 'Servicing' -Severity 'OK' `
            -Detail "$releaseName ($edition) is in servicing until $($eos.ToString('yyyy-MM-dd')) ($daysLeft days remaining)."
    }
}

function Test-WuFailureEvents {
    param([int]$LookbackDays = 14)

    Write-Section -Title "Recent Windows Update Failures (last $LookbackDays days)"

    $cutoff = (Get-Date).AddDays(-$LookbackDays)
    $collected = New-Object System.Collections.Generic.List[object]

    # System log filtered by failure IDs; Operational log by level - the same IDs mean different things there.
    $queries = @(
        [PSCustomObject]@{ LogName = 'System'; ProviderName = 'Microsoft-Windows-WindowsUpdateClient'; Ids = @(20, 25, 31, 34, 35); Levels = $null },
        [PSCustomObject]@{ LogName = 'Microsoft-Windows-WindowsUpdateClient/Operational'; ProviderName = $null; Ids = $null; Levels = @(1, 2) }
    )

    foreach ($q in $queries) {
        try {
            $filter = @{ LogName = $q.LogName; StartTime = $cutoff }
            if ($q.ProviderName) { $filter.ProviderName = $q.ProviderName }
            if ($q.Ids) { $filter.Id = $q.Ids }
            if ($q.Levels) { $filter.Level = $q.Levels }

            $events = Get-WinEvent -FilterHashtable $filter -MaxEvents 200 -ErrorAction Stop
            foreach ($evt in $events) {
                $collected.Add([PSCustomObject]@{
                        Time = $evt.TimeCreated
                        Id   = $evt.Id
                        Log  = $q.LogName
                        Code = (Get-WuEventErrorCode -EventRecord $evt)
                    })
            }
        } catch {
            # A missing/empty log throws here; that is not an error worth surfacing.
            Write-Verbose "Could not query '$($q.LogName)': $($_.Exception.Message)"
        }
    }

    if ($collected.Count -eq 0) {
        Write-Report 'No Windows Update failure events found in the lookback window.'
        Add-Finding -Category 'Update Events' -Severity 'OK' -Detail 'No recent Windows Update failure events.'
        return
    }

    # The same failure is often logged to both channels; collapse on (timestamp to the second, code).
    $seen = @{}
    $unique = New-Object System.Collections.Generic.List[object]
    foreach ($item in ($collected | Sort-Object Time -Descending)) {
        $key = '{0}|{1}' -f $item.Time.ToString('yyyyMMddHHmmss'), $item.Code
        if ($seen.ContainsKey($key)) { continue }
        $seen[$key] = $true
        $unique.Add($item)
    }

    foreach ($item in ($unique | Select-Object -First 10)) {
        $codeText = 'Unknown'
        if ($item.Code) { $codeText = $item.Code }
        $info = Get-WuErrorInfo -ErrorCode $item.Code
        Write-Report ('{0}  {1,-12} [{2}] event {3}' -f $item.Time.ToString('yyyy-MM-dd HH:mm'), $codeText, $info.Severity, $item.Id)
        Write-Report ('    -> {0}' -f $info.Text)
    }

    # Severity is the worst code actually seen, not the mere presence of events.
    $rank = @{ 'OK' = 0; 'Info' = 1; 'Warning' = 2; 'Critical' = 3 }
    $worst = $null
    foreach ($item in $unique) {
        $info = Get-WuErrorInfo -ErrorCode $item.Code
        if ($null -eq $worst -or $rank[$info.Severity] -gt $rank[$worst.Info.Severity]) {
            $worst = [PSCustomObject]@{ Item = $item; Info = $info }
        }
    }

    $worstCode = 'Unknown'
    if ($worst.Item.Code) { $worstCode = $worst.Item.Code }
    $latest = $unique[0]
    $latestCode = 'Unknown'
    if ($latest.Code) { $latestCode = $latest.Code }

    $detail = "$($unique.Count) recent Windows Update failure event(s). Most serious: $worstCode - $($worst.Info.Text)"
    if ($latestCode -ne $worstCode) {
        $detail += " Most recent was $latestCode on $($latest.Time.ToString('yyyy-MM-dd HH:mm'))."
    }

    if ($worst.Info.Severity -eq 'Info') {
        Add-Finding -Category 'Update Events' -Severity 'Info' `
            -Detail "$detail All codes seen are transient or benign." `
            -Recommendation $worst.Info.Fix
    } else {
        Add-Finding -Category 'Update Events' -Severity $worst.Info.Severity `
            -Detail $detail `
            -Recommendation $worst.Info.Fix
    }
}

# ProfileName -> plain-English meaning, from https://learn.microsoft.com/windows/deployment/upgrade/setupdiag#rules
$script:SetupDiagRuleMap = @{
    'CompatScanOnly'                                = 'Setup was run as a compatibility-scan only; no upgrade was attempted.'
    'PlugInComplianceBlock'                         = 'A server compliance plug-in blocked the upgrade (server upgrades only).'
    'BitLockerHardblock'                            = "Target OS doesn't support BitLocker, but BitLocker is enabled on this device."
    'VHDHardblock'                                  = 'Host OS is booted from a VHD image; upgrade is not supported from a VHD boot.'
    'PortableWorkspaceHardblock'                    = 'Host OS is booted from a Windows To-Go device; upgrade is not supported.'
    'AuditModeHardblock'                            = 'Host OS is booted into Audit Mode; upgrade is not supported from this state.'
    'SafeModeHardblock'                             = 'Host OS is booted into Safe Mode; upgrade is not supported.'
    'InsufficientSystemPartitionDiskSpaceHardblock' = 'The system (boot) partition lacks enough space for updated boot files.'
    'CompatBlockedApplicationAutoUninstall'         = 'An installed application must be uninstalled before setup can continue.'
    'CompatBlockedApplicationDismissable'           = 'Setup ran in /quiet mode and hit a dismissible application block (needs /compat ignorewarning).'
    'CompatBlockedFODDismissable'                   = 'Setup ran in /quiet mode and hit a dismissible Feature-on-Demand block; the target image is missing an installed FOD.'
    'CompatBlockedApplicationManualUninstall'       = 'An application with no Add/Remove Programs entry is blocking setup; manual file removal is required.'
    'GenericCompatBlock'                            = 'The device does not meet a hardware requirement (e.g. TPM 2.0) for the target OS.'
    'GatedCompatBlock'                              = 'A temporary compatibility hold is in place for specific hardware/software pending a fix.'
    'HardblockDeviceOrDriver'                       = 'An installed device driver is incompatible with the target OS and must be removed first.'
    'HardblockMismatchedLanguage'                   = 'The host OS and target OS language editions do not match.'
    'HardblockFlightSigning'                        = 'The target OS is a pre-release/Insider build and Secure Boot is blocking it.'
    'DiskSpaceBlockInDownLevel'                     = 'The system ran out of disk space during the downlevel (pre-reboot) phase of upgrade.'
    'DiskSpaceFailure'                              = 'The system ran out of disk space after the first reboot into the upgrade.'
    'PreReleaseWimMountDriverFound'                 = 'An unrecognized/pre-release wimmount.sys driver is registered on the system.'
    'DebugSetupMemoryDump'                          = 'A bug check (BSOD) occurred during setup.'
    'DebugSetupCrash'                               = 'Setup itself crashed and produced a process memory dump.'
    'DebugMemoryDump'                               = 'A memory.dmp was produced during the setup/upgrade operation.'
    'DeviceInstallHang'                             = 'The system hung or bug-checked during the device installation phase.'
    'DriverPackageMissingFileFailure'               = 'A driver package had a missing file during device install.'
    'UnsignedDriverBootFailure'                     = 'An unsigned driver caused a boot failure.'
    'BootFailureDetected'                           = 'A boot failure occurred during a specific phase of the update.'
    'WinSetupBootFilterFailure'                     = 'A kernel-mode file operation failed during setup.'
    'FindDebugInfoFromRollbackLog'                  = 'A bug check occurred during setup/upgrade (identified from the rollback log).'
    'AdvancedInstallerFailed'                       = 'A critical advanced-installer operation failed during setup.'
    'AdvancedInstallerPluginInstallFailed'          = 'A component (Feature-on-Demand, language pack, .NET package) failed to install.'
    'AdvancedInstallerGenericFailure'               = 'A generic advanced-installer read/write failure occurred.'
    'FindMigApplyUnitFailure'                       = 'A migration "apply" unit failed.'
    'FindMigGatherUnitFailure'                      = 'A migration "gather" unit failed.'
    'FindMigGatherApplyFailure'                     = 'The migration engine failed on a gather or apply operation.'
    'OptionalComponentFailedToGetOCsFromPackage'    = 'Failed to enumerate optional components from a package.'
    'OptionalComponentOpenPackageFailed'            = 'Failed to open an optional-component package (check the Windows Modules Installer service).'
    'OptionalComponentInitCBSSessionFailed'         = 'Servicing stack (CBS) corruption was detected on the downlevel OS.'
    'CriticalSafeOSDUFailure'                       = 'Failed to apply a critical dynamic update to the SafeOS image.'
    'UserProfileCreationFailureDuringOnlineApply'   = 'A critical failure occurred creating/modifying a user profile during online apply.'
    'UserProfileCreationFailureDuringFinalize'      = 'A user profile creation error occurred during the finalize phase.'
    'UserProfileSuffixMismatch'                     = 'A file or object caused user profile migration to fail.'
    'DuplicateUserProfileFailure'                   = 'Multiple SIDs are mapped to one user profile, blocking migration; remove the unused duplicate account.'
    'WimMountFailure'                               = 'Failed to mount a WIM file.'
    'WimMountDriverIssue'                           = 'A WimMount.sys registration failure was detected.'
    'WimApplyExtractFailure'                        = 'A WIM apply failed during the extraction phase.'
    'UpdateAgentExpanderFailure'                    = 'A DPX expander failure occurred in the downlevel phase (Windows Update servicing).'
    'FindFatalPluginFailure'                        = 'A setup plug-in failure was fatal to setup.'
    'MigrationAbortedDueToPluginFailure'            = 'A migration plug-in failure aborted the migration.'
    'DISMAddPackageFailed'                          = 'DISM failed to add a package.'
    'DISMImageSessionFailure'                       = 'DISM failed to start an image session.'
    'DISMproviderFailure'                           = 'A DISM provider/plug-in failed a critical operation.'
    'SysPrepLaunchModuleFailure'                    = 'A Sysprep plug-in failed a critical operation.'
    'UserProvidedDriverInjectionFailure'            = 'A driver supplied via the setup command line failed to inject.'
    'DriverMigrationFailure'                        = 'A fatal failure occurred while migrating drivers.'
    'UnknownDriverMigrationFailure'                 = 'A bad driver package is blocking migration; remove or update the driver package.'
    'FindSuccessfulUpgrade'                         = 'Setup logs indicate the upgrade actually succeeded.'
    'FindSetupHostReportedFailure'                  = 'An early upgrade failure was reported by setuphost.exe.'
    'FindDownlevelFailure'                          = 'A failure was surfaced by SetupPlatform later in the downlevel phase.'
    'FindAbruptDownlevelFailure'                    = 'The downlevel-phase log ends abruptly (unexpected termination).'
    'FindEarlyDownlevelError'                       = 'A failure occurred before SetupPlatform was even invoked.'
    'FindSPFatalError'                              = 'SetupPlatform hit a fatal error.'
    'FindSetupPlatformFailedOperationInfo'          = 'SetupPlatform reported a critical failure at a specific phase/operation.'
    'FindRollbackFailure'                           = 'The upgrade rolled back; last operation/phase/error was captured.'
}

function Test-DotNetForSetupDiag {
    # SetupDiag requires .NET Framework 4.7.2 or later. 461808 = 4.7.2 on Windows 10 1803; 461814 = 4.7.2 elsewhere.
    try {
        $release = (Get-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\NET Framework Setup\NDP\v4\Full' -Name Release -ErrorAction Stop).Release
        return ($release -ge 461808)
    } catch {
        return $false
    }
}

function ConvertFrom-SetupDiagXml {
    param([Parameter(Mandatory = $true)][string]$Path)

    try {
        [xml]$xml = Get-Content -LiteralPath $Path -Raw -ErrorAction Stop
    } catch {
        return $null
    }

    $root = $xml.SetupDiag
    if (-not $root -or [string]::IsNullOrWhiteSpace([string]$root.ProfileName)) { return $null }

    $failureBlocks = @($root.FailureData) | Where-Object { $_ -and ([string]$_) -match '\S' } | ForEach-Object { ([string]$_).Trim() }
    $remediationBlocks = @($root.Remediation) | Where-Object { $_ -and ([string]$_) -match '\S' } | ForEach-Object { ([string]$_).Trim() }

    [PSCustomObject]@{
        ProfileName    = [string]$root.ProfileName
        FailureDetails = [string]$root.FailureDetails
        PrimaryFailure = if ($failureBlocks.Count -gt 0) { $failureBlocks[-1] } else { '' }
        AllFailureData = $failureBlocks
        Remediation    = ($remediationBlocks -join ' ')
    }
}

function Write-SetupDiagFinding {
    param(
        [Parameter(Mandatory = $true)]$Result,
        [Parameter(Mandatory = $true)][string]$Source
    )

    $friendly = $script:SetupDiagRuleMap[$Result.ProfileName]
    if (-not $friendly) { $friendly = 'No plain-English mapping for this rule; see the rules table below.' }

    Write-Report "Matched rule ($Source): $($Result.ProfileName)"
    Write-Report "  $friendly"
    if ($Result.PrimaryFailure) { Write-Report "  $($Result.PrimaryFailure -replace "`r?`n", "`n  ")" }

    # The fix is usually a "Recommend you..." line inside FailureData, not the Remediation field.
    $recommendation = $Result.Remediation
    if ([string]::IsNullOrWhiteSpace($recommendation)) {
        $recLines = @($Result.PrimaryFailure -split "`r?`n") | Where-Object { $_ -match '^\s*Recommend' }
        $recommendation = ($recLines -join ' ').Trim()
    }
    if ([string]::IsNullOrWhiteSpace($recommendation)) {
        $recommendation = "See rule '$($Result.ProfileName)' at https://learn.microsoft.com/windows/deployment/upgrade/setupdiag#rules for guidance."
    }

    Add-Finding -Category 'SetupDiag' -Severity 'Critical' `
        -Detail "SetupDiag ($Source) matched rule $($Result.ProfileName): $friendly" `
        -Recommendation $recommendation
}

function Test-FeatureUpdateAttempted {
    # Evidence of a recent feature-update attempt: a recent Panther setup log or a fresh rollback marker.
    param([int]$LookbackDays = 14)

    $cutoff = (Get-Date).AddDays(-$LookbackDays)

    $pantherLogs = @(
        (Join-Path $env:SystemRoot 'Panther\setupact.log'),
        (Join-Path $env:SystemRoot 'Panther\NewOS\setupact.log')
    )
    foreach ($log in $pantherLogs) {
        if (Test-Path -LiteralPath $log) {
            try {
                $lastWrite = (Get-Item -LiteralPath $log -ErrorAction Stop).LastWriteTime
                if ($lastWrite -ge $cutoff) {
                    return [PSCustomObject]@{ Found = $true; Reason = "recent setup activity in $log ($lastWrite)" }
                }
            } catch { Write-Verbose ('Ignored: ' + $_.Exception.Message) }
        }
    }

    # A rollback leaves these behind and is unambiguous evidence of a failed upgrade.
    foreach ($marker in @("$env:SystemDrive\`$WINDOWS.~BT", "$env:SystemDrive\Windows.old")) {
        if (Test-Path -LiteralPath $marker) {
            try {
                $lastWrite = (Get-Item -LiteralPath $marker -Force -ErrorAction Stop).LastWriteTime
                if ($lastWrite -ge $cutoff) {
                    return [PSCustomObject]@{ Found = $true; Reason = "upgrade rollback marker $marker ($lastWrite)" }
                }
            } catch { Write-Verbose ('Ignored: ' + $_.Exception.Message) }
        }
    }

    return [PSCustomObject]@{ Found = $false; Reason = 'no feature-update attempt in the lookback window' }
}

function Test-IsMicrosoftSigned {
    # Refuse to run a network-fetched binary unless it has a valid Microsoft Authenticode signature.
    param([Parameter(Mandatory = $true)][string]$Path)

    try {
        $sig = Get-AuthenticodeSignature -LiteralPath $Path -ErrorAction Stop
        if ($sig.Status -ne 'Valid') {
            return [PSCustomObject]@{ Ok = $false; Reason = "signature status is $($sig.Status)" }
        }
        $subject = [string]$sig.SignerCertificate.Subject
        if ($subject -notmatch 'O=Microsoft Corporation') {
            return [PSCustomObject]@{ Ok = $false; Reason = "signer is not Microsoft ($subject)" }
        }
        return [PSCustomObject]@{ Ok = $true; Reason = $subject }
    } catch {
        return [PSCustomObject]@{ Ok = $false; Reason = $_.Exception.Message }
    }
}

function Invoke-SetupDiag {
    param(
        [string]$ExplicitPath = '',
        [bool]$AllowDownload = $false,
        [int]$LookbackDays = 14
    )

    Write-Section -Title 'SetupDiag (feature-update failure analysis)'

    # Prefer Windows Setup's own SetupDiag results (no elevation, download, or re-run needed).
    $autoXmlPath = Join-Path $env:SystemRoot 'Logs\SetupDiag\SetupDiagResults.xml'
    if (Test-Path -LiteralPath $autoXmlPath) {
        $parsed = ConvertFrom-SetupDiagXml -Path $autoXmlPath
        if ($parsed) {
            Write-Report "Found Windows Setup's own SetupDiag results: $autoXmlPath"
            Write-SetupDiagFinding -Result $parsed -Source 'auto-generated by Windows Setup'
            return
        } else {
            Write-Report "$autoXmlPath exists but did not contain a matched failure rule."
        }
    }

    # Registry mirror can outlive the XML (e.g. after Windows.old cleanup); dump it generically.
    $autoRegPath = 'HKLM:\SYSTEM\Setup\SetupDiag\Results'
    if (Test-Path -LiteralPath $autoRegPath) {
        $regProps = Get-ItemProperty -Path $autoRegPath -ErrorAction SilentlyContinue |
            Select-Object * -ExcludeProperty PS*
        if ($regProps -and @($regProps.PSObject.Properties).Count -gt 0) {
            Write-Report "SetupDiag auto-run registry marker found at $autoRegPath :"
            $regProps.PSObject.Properties | ForEach-Object { Write-Report ('  {0} = {1}' -f $_.Name, $_.Value) }
            Add-Finding -Category 'SetupDiag' -Severity 'Warning' `
                -Detail "Windows Setup previously ran SetupDiag and recorded results in the registry ($autoRegPath), but the XML report is no longer present." `
                -Recommendation 'Review the registry values above, or re-run SetupDiag manually for full detail.'
            return
        }
    }

    # Below here may download/execute a binary, so it is gated on real feature-update evidence.
    $evidence = Test-FeatureUpdateAttempted -LookbackDays $LookbackDays
    if (-not $evidence.Found) {
        Write-Report "No recent feature-update attempt detected ($($evidence.Reason)). Skipping SetupDiag - nothing downloaded or run."
        Add-Finding -Category 'SetupDiag' -Severity 'Info' `
            -Detail "SetupDiag not run: $($evidence.Reason). Windows Setup also left no results of its own."
        return
    }
    Write-Report "Feature-update attempt detected: $($evidence.Reason)"

    if (-not (Test-DotNetForSetupDiag)) {
        Write-Report 'SetupDiag requires .NET Framework 4.7.2 or later, which was not detected. Skipping manual SetupDiag run.'
        Add-Finding -Category 'SetupDiag' -Severity 'Info' `
            -Detail 'SetupDiag analysis skipped: .NET Framework 4.7.2 or later was not detected on this device.' `
            -Recommendation 'Install .NET Framework 4.7.2 or later, then re-run this check.'
        return
    }

    if (-not (Test-IsElevated)) {
        Write-Report 'SetupDiag requires administrative rights. Skipping.'
        Add-Finding -Category 'SetupDiag' -Severity 'Info' `
            -Detail 'SetupDiag analysis skipped: the script is not running elevated.' `
            -Recommendation 'Re-run this script with administrative rights to enable SetupDiag analysis.'
        return
    }

    $workDir = Join-Path $env:SystemRoot 'Temp\SetupDiag'
    $downloaded = $false
    # Only remove the working directory if this run is what created it.
    $createdWorkDir = -not (Test-Path -LiteralPath $workDir)

    $setupDiag = $null
    $candidates = New-Object System.Collections.Generic.List[string]
    if (-not [string]::IsNullOrWhiteSpace($ExplicitPath)) { $candidates.Add($ExplicitPath) }
    $candidates.Add((Join-Path $workDir 'SetupDiag.exe'))
    $candidates.Add((Join-Path $env:ProgramData 'SetupDiag\SetupDiag.exe'))

    foreach ($candidate in $candidates) {
        if (-not [string]::IsNullOrWhiteSpace($candidate) -and (Test-Path -LiteralPath $candidate)) {
            $setupDiag = $candidate
            break
        }
    }

    if (-not $setupDiag -and $AllowDownload) {
        try {
            if (-not (Test-Path -LiteralPath $workDir)) { New-Item -Path $workDir -ItemType Directory -Force | Out-Null }
            $setupDiag = Join-Path $workDir 'SetupDiag.exe'
            Write-Report 'Downloading SetupDiag.exe from Microsoft...'

            $downloadUri = 'https://go.microsoft.com/fwlink/?linkid=870142'
            $request = @{
                Uri             = $downloadUri
                OutFile         = $setupDiag
                UseBasicParsing = $true
                ErrorAction     = 'Stop'
            }

            # Route through the system proxy only when one exists (-Proxy $null is a binding error).
            try {
                $sysProxy = [System.Net.WebRequest]::GetSystemWebProxy().GetProxy([Uri]$downloadUri)
                if ($sysProxy -and $sysProxy.AbsoluteUri -ne ([Uri]$downloadUri).AbsoluteUri) {
                    $request.Proxy = $sysProxy.AbsoluteUri
                    $request.ProxyUseDefaultCredentials = $true
                    Write-Report "Using system proxy: $($sysProxy.AbsoluteUri)"
                }
            } catch { Write-Verbose ('Ignored: ' + $_.Exception.Message) }

            Invoke-WebRequest @request
            $downloaded = $true
        } catch {
            Write-Report "SetupDiag download failed: $($_.Exception.Message)"
            $setupDiag = $null
        }
    }

    if (-not $setupDiag) {
        Write-Report 'SetupDiag.exe could not be found or downloaded. Skipping.'
        Add-Finding -Category 'SetupDiag' -Severity 'Info' -Detail 'SetupDiag analysis skipped (executable not available).'
        if ($createdWorkDir) { Remove-Item -LiteralPath $workDir -Recurse -Force -ErrorAction SilentlyContinue }
        return
    }

    $signature = Test-IsMicrosoftSigned -Path $setupDiag
    if (-not $signature.Ok) {
        Write-Report "Refusing to run SetupDiag.exe: $($signature.Reason)"
        Add-Finding -Category 'SetupDiag' -Severity 'Warning' `
            -Detail "SetupDiag.exe was not run because its Authenticode signature did not verify as Microsoft ($($signature.Reason))." `
            -Recommendation 'Remove the untrusted file and investigate how it got there.'
        if ($downloaded) {
            Remove-Item -LiteralPath $setupDiag -Force -ErrorAction SilentlyContinue
            if ($createdWorkDir) { Remove-Item -LiteralPath $workDir -Recurse -Force -ErrorAction SilentlyContinue }
        }
        return
    }
    Write-Report "Verified Microsoft signature: $($signature.Reason)"

    $resultXml = Join-Path $workDir 'SetupDiagResults.xml'
    $stdOutFile = Join-Path $workDir 'setupdiag.out'
    $stdErrFile = Join-Path $workDir 'setupdiag.err'

    try {
        if (-not (Test-Path -LiteralPath $workDir)) { New-Item -Path $workDir -ItemType Directory -Force | Out-Null }
        Write-Report "Running SetupDiag: $setupDiag"

        # Bounded run; capture stdout because SetupDiag explains itself there but returns an opaque exit code.
        $proc = Start-Process -FilePath $setupDiag `
            -ArgumentList @(('/Output:"{0}"' -f $resultXml), '/Format:xml', '/ZipLogs:False') `
            -WindowStyle Hidden -PassThru -ErrorAction Stop `
            -RedirectStandardOutput $stdOutFile -RedirectStandardError $stdErrFile

        if (-not $proc.WaitForExit(300000)) {
            try { $proc.Kill() } catch { Write-Verbose ('Ignored: ' + $_.Exception.Message) }
            Write-Report 'SetupDiag exceeded its 5 minute time limit and was terminated.'
            Add-Finding -Category 'SetupDiag' -Severity 'Info' `
                -Detail 'SetupDiag did not finish within 5 minutes and was terminated; no verdict available.'
            return
        }

        # Last non-empty, non-banner line is the operative message.
        $message = ''
        try {
            $lines = @(Get-Content -LiteralPath $stdOutFile -ErrorAction SilentlyContinue |
                    Where-Object { $_ -match '\S' -and $_ -notmatch 'Copyright|^SetupDiag v' })
            if ($lines.Count -gt 0) { $message = $lines[-1].Trim() }
        } catch { Write-Verbose ('Ignored: ' + $_.Exception.Message) }

        if ($message) { Write-Report "SetupDiag: $message" }

        if (Test-Path -LiteralPath $resultXml) {
            $parsed = ConvertFrom-SetupDiagXml -Path $resultXml
            if ($parsed) {
                Write-SetupDiagFinding -Result $parsed -Source 'manual SetupDiag run'
            } else {
                Write-Report 'SetupDiag completed; no matching failure rule (no recent feature-update failure).'
                Add-Finding -Category 'SetupDiag' -Severity 'OK' -Detail 'SetupDiag found no feature-update failure signature.'
            }
        } elseif ($message -match 'unable to find a relevant log') {
            # Expected outcome when there is no analyzable upgrade attempt; not a fault.
            Write-Report 'SetupDiag found no analyzable setup logs.'
            Add-Finding -Category 'SetupDiag' -Severity 'Info' `
                -Detail 'SetupDiag ran but found no relevant setup logs to analyze.'
        } else {
            $suffix = ''
            if ($message) { $suffix = " - $message" }
            Write-Report "SetupDiag produced no results file (exit code $($proc.ExitCode))$suffix"
            Add-Finding -Category 'SetupDiag' -Severity 'Info' `
                -Detail "SetupDiag produced no results (exit code $($proc.ExitCode))$suffix"
        }
    } catch {
        Write-Report "SetupDiag execution failed: $($_.Exception.Message)"
        Add-Finding -Category 'SetupDiag' -Severity 'Info' -Detail "SetupDiag execution failed: $($_.Exception.Message)"
    } finally {
        # Leave the device as we found it.
        foreach ($tmp in @($resultXml, $stdOutFile, $stdErrFile)) {
            Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue
        }
        if ($downloaded) {
            Remove-Item -LiteralPath $setupDiag -Force -ErrorAction SilentlyContinue
        }
        if ($createdWorkDir) {
            Remove-Item -LiteralPath $workDir -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

#endregion Checks

#region Main

$exitCode = 0

try {
    # Explicit -FailureLookbackDays wins; else the NinjaOne script variable; else the default.
    $lookbackDays = $FailureLookbackDays
    if (-not $PSBoundParameters.ContainsKey('FailureLookbackDays')) {
        $lookbackDays = Get-ScriptVarInt -Name 'failureLookbackDays' -Default 14
    }
    if ($lookbackDays -lt 1) { $lookbackDays = 14 }

    # Explicit -Detailed wins; else the NinjaOne script variable; else off.
    if ($PSBoundParameters.ContainsKey('Detailed')) {
        $script:ShowDetails = [bool]$Detailed
    } else {
        $script:ShowDetails = Get-ScriptVarBool -Name 'detailed' -Default $false
    }

    Write-Summary 'Windows Update Troubleshooter (diagnostics)'
    Write-Summary "Started: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
    Write-Summary "Lookback: $lookbackDays days"

    $elevated = Test-IsElevated
    if (-not $elevated) {
        Write-Summary 'NOTE: not running elevated - BITS job state and SetupDiag analysis will be skipped.'
        Add-Finding -Category 'Environment' -Severity 'Warning' `
            -Detail 'The script is not running with administrative rights, so some checks (BITS job state, SetupDiag) were skipped. A clean result from this run is therefore incomplete.' `
            -Recommendation 'Re-run as SYSTEM or an administrator for full coverage.'
    }

    Get-OsSummary
    Test-OsServicingStatus
    Test-WuServiceHealth
    Test-PendingRebootState
    Test-WuActivityRecency
    Test-DiskAndStore
    Get-WuConfiguration
    Test-UpdateConnectivity -WsusServer $script:WsusServer
    Test-TimeSkew
    Get-Tls12Status
    Get-ProxyConfiguration

    if ($elevated) {
        Test-BitsJobs
    } else {
        Write-Section -Title 'BITS Transfer Jobs'
        Write-Report 'Skipped: enumerating all users'' BITS jobs requires administrative rights.'
    }

    Test-WuFailureEvents -LookbackDays $lookbackDays

    if ($SkipSetupDiag) {
        Write-Section -Title 'SetupDiag (feature-update failure analysis)'
        Write-Report 'Skipped by -SkipSetupDiag. No files were downloaded, written, or executed.'
    } else {
        Invoke-SetupDiag -AllowDownload $true -LookbackDays $lookbackDays
    }

    # Summary
    Write-SummarySection -Title 'Issue Summary'

    $critical = @($script:Findings | Where-Object { $_.Severity -eq 'Critical' })
    $warning = @($script:Findings | Where-Object { $_.Severity -eq 'Warning' })
    $ok = @($script:Findings | Where-Object { $_.Severity -eq 'OK' })
    $info = @($script:Findings | Where-Object { $_.Severity -eq 'Info' })

    Write-Summary "Critical: $($critical.Count)   Warning: $($warning.Count)   OK: $($ok.Count)   Info: $($info.Count)"

    if ($critical.Count -eq 0 -and $warning.Count -eq 0) {
        Write-Summary ''
        Write-Summary 'No Windows Update blockers detected.'
    } else {
        foreach ($finding in ($critical + $warning)) {
            Write-Summary ''
            Write-Summary "[$($finding.Severity)] ($($finding.Category)) $($finding.Detail)"
            if (-not [string]::IsNullOrWhiteSpace($finding.Recommendation)) {
                Write-Summary "    Fix: $($finding.Recommendation)"
            }
        }
    }

    # The checks that passed, with their detail retained.
    if ($ok.Count -gt 0) {
        Write-Summary ''
        Write-Summary '--- Checks Passed ---'
        foreach ($finding in $ok) {
            Write-Summary "[OK] ($($finding.Category)) $($finding.Detail)"
        }
    }

    # Info findings never affect the exit code but often hold the actual explanation.
    if ($info.Count -gt 0) {
        Write-Summary ''
        Write-Summary '--- Informational ---'
        foreach ($finding in $info) {
            Write-Summary "[Info] ($($finding.Category)) $($finding.Detail)"
        }
    }

    Write-Summary ''
    if (-not $script:ShowDetails) {
        Write-Summary 'Tip: re-run with -Detailed (or set the ''detailed'' script variable) for the full per-check report.'
    }
    Write-Summary "Completed: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"

    if ($AsObject) {
        $script:Findings
    }
} catch {
    Write-Summary "Troubleshooter failed: $($_.Exception.Message)"
    Write-Summary $_.ScriptStackTrace
    $exitCode = 1
}

exit $exitCode

#endregion Main
