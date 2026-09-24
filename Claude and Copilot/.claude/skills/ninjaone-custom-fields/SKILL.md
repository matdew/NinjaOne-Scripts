---
name: ninjaone-custom-fields
description: Using the NinjaOne PowerShell module (Get-NinjaProperty, Set-NinjaProperty) to access and manage custom fields with automatic type conversion. Use when scripts need to read or write device custom fields, documentation fields, dropdown values (with friendly names not GUIDs), checkboxes, dates, secure fields, multi-select options, or WYSIWYG reports. Handles 20+ field types including attachments, device/organization dropdowns, and documentation templates.
---

# NinjaOne Custom Fields

The NinjaOne agent deploys a custom PowerShell module that provides enhanced cmdlets for interacting with custom fields. The module automatically handles type conversion and friendly name resolution for dropdowns and multi-select fields.

## When to Use This Skill

- Read device or organization custom fields in automation scripts
- Write calculated values or automation results to custom fields
- Store configuration data persistently across script executions
- Use dropdown fields with friendly names instead of GUIDs
- Manage documentation templates with multiple documents per device
- Store secure credentials or API keys in secure fields
- Create visual reports in WYSIWYG fields with HTML formatting
- Validate and convert date, time, email, IP address, and phone fields

## Prerequisites

- **PowerShell Module:** Automatically deployed with NinjaOne agent
- **Field Types:** 20+ supported types with automatic conversion
- **Secure Fields:** Only accessible during automation execution (never in terminal)
- **Documentation:** Templates support single or multi-document configurations
- **Help Available:** Run `Get-Help Get-NinjaProperty -Full` or `Get-Help Set-NinjaProperty -Full`

## Related Skills

- [ninjaone-cli](../ninjaone-cli/SKILL.md) - Alternative CLI tool and legacy PowerShell commands for custom fields
- [ninjaone-wysiwyg](../ninjaone-wysiwyg/SKILL.md) - HTML formatting, Bootstrap 5, and Charts.css for WYSIWYG fields
- [ninjaone-script-variables](../ninjaone-script-variables/SKILL.md) - Runtime parameters that complement persistent custom fields
- [ninjaone-tags](../ninjaone-tags/SKILL.md) - Report current device tags to custom fields for visibility
- [ninjaone-api](../ninjaone-api/SKILL.md) - Bulk custom field operations via REST API

# Get-NinjaProperty

Retrieves and converts custom field values based on field name and type.

**Syntax:**
```powershell
Get-NinjaProperty [-Name] <String[]> [[-Type] <String>] [[-DocumentName] <String>] [<CommonParameters>]
```

**Supported Types:**
- Attachment, Checkbox, Date, DateTime, Decimal
- Device Dropdown, Device MultiSelect
- Dropdown, Email, Integer, IP Address
- MultiLine, MultiSelect
- Organization Dropdown, Organization Location Dropdown
- Organization Location MultiSelect, Organization MultiSelect
- Phone, Secure, Text, Time, WYSIWYG, URL

**Examples:**
```powershell
# Get dropdown field with type - returns user-friendly value
$dropdownValue = Get-NinjaProperty -Name "Environment" -Type "Dropdown"

# Get date field with automatic conversion
$maintenanceDate = Get-NinjaProperty -Name "NextMaintenance" -Type "Date"

# Get checkbox field as boolean
$isEnabled = Get-NinjaProperty -Name "FeatureEnabled" -Type "Checkbox"

# Get documentation field
$serverIP = Get-NinjaProperty -Name "IPAddress" -Type "IP Address" -DocumentName "Server Config"
```

## Set-NinjaProperty

Sets custom field values with automatic type conversion.

**Syntax:**
```powershell
Set-NinjaProperty [-Name] <String> [-Value] <Object> [[-Type] <String>] [[-DocumentName] <String>] [<CommonParameters>]
```

**Supported Types:**
- Checkbox, Date, Date or Date Time, DateTime, Decimal
- Dropdown, Email, Integer, IP Address
- MultiLine, MultiSelect
- Phone, Secure, Text, Time, URL, WYSIWYG

**Examples:**
```powershell
# Set dropdown field using friendly name
Set-NinjaProperty -Name "Environment" -Value "Production" -Type "Dropdown"

# Set date field with DateTime object
Set-NinjaProperty -Name "NextMaintenance" -Value (Get-Date).AddDays(30) -Type "Date"

# Set checkbox field
Set-NinjaProperty -Name "FeatureEnabled" -Value $true -Type "Checkbox"

# Set secure field
Set-NinjaProperty -Name "APIKey" -Value "secret-key-value" -Type "Secure"

# Set multi-select field with friendly names
Set-NinjaProperty -Name "InstalledFeatures" -Value @("Feature1", "Feature2") -Type "MultiSelect"
```

## Custom Field Types

### Attachment Fields

```powershell
# Get attachment info (read-only via module)
$attachment = Get-NinjaProperty -Name "Document" -Type "Attachment"
# Returns JSON object with file information

# Note: Attachments are managed through the NinjaOne web interface
# - Maximum 20 MB file size by default
# - One file at a time per field
# - CLI/Module access is read-only
```

### Checkbox Fields

```powershell
# Get (returns boolean)
$enabled = Get-NinjaProperty -Name "IsEnabled" -Type "Checkbox"

# Set (accepts boolean or 0/1)
Set-NinjaProperty -Name "IsEnabled" -Value $true -Type "Checkbox"
Set-NinjaProperty -Name "IsEnabled" -Value 1 -Type "Checkbox"
```

### Date Fields

```powershell
# Get Date (Unix epoch seconds or DateTime object)
$maintenanceDate = Get-NinjaProperty -Name "MaintenanceDate" -Type "Date"

# Set Date (accepts DateTime object, epoch seconds, or ISO format)
Set-NinjaProperty -Name "MaintenanceDate" -Value (Get-Date "2024-12-31") -Type "Date"
Set-NinjaProperty -Name "MaintenanceDate" -Value 1735689600 -Type "Date"
Set-NinjaProperty -Name "MaintenanceDate" -Value "2024-12-31" -Type "Date"
```

### DateTime Fields

```powershell
# Get DateTime (epoch seconds or DateTime object)
$scheduledTime = Get-NinjaProperty -Name "ScheduledTime" -Type "DateTime"

# Set DateTime (accepts DateTime object, epoch seconds, or ISO format)
Set-NinjaProperty -Name "ScheduledTime" -Value (Get-Date) -Type "DateTime"
Set-NinjaProperty -Name "ScheduledTime" -Value 1705330200 -Type "DateTime"
Set-NinjaProperty -Name "ScheduledTime" -Value "2024-01-15T14:30:00" -Type "DateTime"
```

### Decimal Fields

```powershell
# Get (range: -9999999.999999 to 9999999.999999)
$threshold = Get-NinjaProperty -Name "DiskThreshold" -Type "Decimal"

# Set (truncated to max precision)
Set-NinjaProperty -Name "DiskThreshold" -Value 95.5 -Type "Decimal"
Set-NinjaProperty -Name "DiskThreshold" -Value 95.123456 -Type "Decimal"
```

### Device Dropdown Fields

```powershell
# Get (read-only via module, returns device link)
$linkedDevice = Get-NinjaProperty -Name "PrimaryServer" -Type "Device Dropdown"

# Note: Device dropdowns are managed through the NinjaOne web interface
# - Can be restricted to specific organizations or device types
# - Clicking the data navigates to the device dashboard
```

### Device MultiSelect Fields

```powershell
# Get (read-only via module, returns array of device links)
$relatedDevices = Get-NinjaProperty -Name "RelatedServers" -Type "Device MultiSelect"

# Note: Device multi-selects are managed through the NinjaOne web interface
# - Can be restricted to specific organizations or device types
# - Clicking the data navigates to the device dashboard
```

### Dropdown Fields

```powershell
# WITHOUT type - returns GUID
$envGuid = Get-NinjaProperty -Name "Environment"

# WITH type - returns friendly name
$env = Get-NinjaProperty -Name "Environment" -Type "Dropdown"

# Set with friendly name (when type specified)
Set-NinjaProperty -Name "Environment" -Value "Production" -Type "Dropdown"

# Set with GUID (when type not specified)
Set-NinjaProperty -Name "Environment" -Value "f1ba449c-fd34-49df-b878-af3877180d17"

# List available options
Ninja-Property-Options "Environment"
```

### Email Fields

```powershell
# Get (returns email address string)
$adminEmail = Get-NinjaProperty -Name "AdminEmail" -Type "Email"

# Set (validates email format xxx@domain.xxx)
Set-NinjaProperty -Name "AdminEmail" -Value "admin@example.com" -Type "Email"
```

### Integer Fields

```powershell
# Get (range: -2147483648 to 2147483647)
$port = Get-NinjaProperty -Name "ServicePort" -Type "Integer"

# Set
Set-NinjaProperty -Name "ServicePort" -Value 8080 -Type "Integer"
```

### IP Address Fields

```powershell
# Get (returns IP address string)
$serverIP = Get-NinjaProperty -Name "ServerIP" -Type "IP Address"

# Set (accepts IPv4 or IPv6 format)
Set-NinjaProperty -Name "ServerIP" -Value "192.168.1.100" -Type "IP Address"
Set-NinjaProperty -Name "ServerIP" -Value "2001:0db8::1" -Type "IP Address"
```

### MultiLine Text Fields

```powershell
# Get (returns multi-line string)
$notes = Get-NinjaProperty -Name "Notes" -Type "MultiLine"

# Set (limit: 10,000 characters)
$multiLineText = @"
Line 1
Line 2
Line 3
"@
Set-NinjaProperty -Name "Notes" -Value $multiLineText -Type "MultiLine"
```

### MultiSelect Fields

```powershell
# WITHOUT type - returns comma-separated GUIDs
$featureGuids = Get-NinjaProperty -Name "EnabledFeatures"

# WITH type - returns array of friendly names
$features = Get-NinjaProperty -Name "EnabledFeatures" -Type "MultiSelect"

# Set with friendly names (when type specified)
Set-NinjaProperty -Name "EnabledFeatures" -Value @("Feature1", "Feature2") -Type "MultiSelect"

# List available options
Ninja-Property-Options "EnabledFeatures"
```

### Organization Dropdown Fields

```powershell
# Get (read-only via module, returns organization link)
$linkedOrg = Get-NinjaProperty -Name "LinkedOrganization" -Type "Organization Dropdown"

# Note: Organization dropdowns are managed through the NinjaOne web interface
# - Clicking the data navigates to the organization dashboard
```

### Organization Location Dropdown Fields

```powershell
# Get (read-only via module, returns location link)
$location = Get-NinjaProperty -Name "PrimaryLocation" -Type "Organization Location Dropdown"

# Note: Organization location dropdowns are managed through the NinjaOne web interface
# - Can be restricted to specific organizations
# - Clicking the data navigates to the location dashboard
```

### Organization Location MultiSelect Fields

```powershell
# Get (read-only via module, returns array of location links)
$locations = Get-NinjaProperty -Name "ServicedLocations" -Type "Organization Location MultiSelect"

# Note: Organization location multi-selects are managed through the NinjaOne web interface
# - Can be restricted to specific organizations
# - Clicking the data navigates to the location dashboard
```

### Organization MultiSelect Fields

```powershell
# Get (read-only via module, returns array of organization links)
$organizations = Get-NinjaProperty -Name "AffectedOrganizations" -Type "Organization MultiSelect"

# Note: Organization multi-selects are managed through the NinjaOne web interface
# - Clicking the data navigates to the organization dashboard
```

### Phone Number Fields

```powershell
# Get (returns phone string in E.164 format)
$phone = Get-NinjaProperty -Name "SupportPhone" -Type "Phone"

# Set (accepts E.164 format, up to 17 characters)
Set-NinjaProperty -Name "SupportPhone" -Value "+12345678901" -Type "Phone"
Set-NinjaProperty -Name "SupportPhone" -Value "12345678901234567" -Type "Phone"
```

### Secure Fields

```powershell
# Get (only accessible during automation execution)
$apiKey = Get-NinjaProperty -Name "APIKey" -Type "Secure"

# Set (limit: 200-10,000 characters, configurable)
Set-NinjaProperty -Name "APIKey" -Value "secret-value" -Type "Secure"

# Note: Secure fields are hidden by default and not exported in CSV files
# Complexity rules can be configured (uppercase, lowercase, integer, min 6 chars)
```

### Text Fields

```powershell
# Get (returns string, limit: 200 characters)
$serverName = Get-NinjaProperty -Name "ServerName" -Type "Text"

# Set
Set-NinjaProperty -Name "ServerName" -Value "PROD-WEB-01" -Type "Text"
```

### Time Fields

```powershell
# Get (returns time as seconds or TimeSpan)
$backupTime = Get-NinjaProperty -Name "BackupTime" -Type "Time"

# Set (accepts seconds or ISO format HH:mm:ss)
Set-NinjaProperty -Name "BackupTime" -Value 7200 -Type "Time"  # 2 hours
Set-NinjaProperty -Name "BackupTime" -Value "02:00:00" -Type "Time"
```

### URL Fields

```powershell
# Get (returns URL string)
$dashboardUrl = Get-NinjaProperty -Name "DashboardURL" -Type "URL"

# Set (must start with https://, max 200 characters)
Set-NinjaProperty -Name "DashboardURL" -Value "https://dashboard.example.com" -Type "URL"
```

### WYSIWYG Fields

```powershell
# Get (read-only via module, returns JSON with HTML and TEXT content)
$formattedContent = Get-NinjaProperty -Name "Report" -Type "WYSIWYG"

# Set (accepts HTML string, max 200,000 characters)
$htmlContent = @"
<div class="card">
  <div class="card-body">
    <h3>Server Status</h3>
    <p>Status: <strong>Online</strong></p>
  </div>
</div>
"@
Set-NinjaProperty -Name "Report" -Value $htmlContent -Type "WYSIWYG"

# Note: WYSIWYG fields support HTML, Bootstrap 5, Font Awesome 6, and Charts.css
# Fields > 10,000 characters auto-collapse
# Refer to ninjaone-wysiwyg skill for formatting details
```

## Documentation Fields

> **Preferred approach:** Use `Get-NinjaProperty`/`Set-NinjaProperty` with `-DocumentName` for reading and writing documentation fields — they handle type conversion automatically (see examples above). The legacy `Ninja-Property-Docs-*` commands shown below are retained for compatibility with older scripts or environments that cannot use the PowerShell module.

```powershell
# List all templates
$templates = Ninja-Property-Docs-Templates

# List documents in template
$documents = Ninja-Property-Docs-Names "Server Config"

# Get field from multi-document template
$serverIP = Get-NinjaProperty -Name "IPAddress" -Type "IP Address" -DocumentName "PROD-WEB-01"

# Set field in multi-document template
Set-NinjaProperty -Name "IPAddress" -Value "192.168.1.100" -Type "IP Address" -DocumentName "PROD-WEB-01"

# Get field from single-document template
$value = Ninja-Property-Docs-Get-Single "Network Config" "Gateway"

# Set field in single-document template
Ninja-Property-Docs-Set-Single "Network Config" "Gateway" "192.168.1.1"

# Clear documentation field
Ninja-Property-Docs-Clear "Server Config" "PROD-WEB-01" "IPAddress"
Ninja-Property-Docs-Clear-Single "Network Config" "Gateway"

# Get options for documentation dropdown
Ninja-Property-Docs-Options "Server Config" "PROD-WEB-01" "Environment"
Ninja-Property-Docs-Options-Single "Network Config" "ConnectionType"
```

## Complete Example

```powershell
<#
.SYNOPSIS
    Manages server configuration using custom fields.
#>

[CmdletBinding()]
param()

#region Get Custom Fields
$environment = Get-NinjaProperty -Name "ServerEnvironment" -Type "Dropdown"
$maintenanceEnabled = Get-NinjaProperty -Name "MaintenanceEnabled" -Type "Checkbox"
$maxConnections = Get-NinjaProperty -Name "MaxConnections" -Type "Integer"
$adminEmail = Get-NinjaProperty -Name "AdminEmail" -Type "Email"
$supportPhone = Get-NinjaProperty -Name "SupportPhone" -Type "Phone"
$dashboardUrl = Get-NinjaProperty -Name "DashboardURL" -Type "URL"
#endregion

#region Set Custom Fields
Set-NinjaProperty -Name "MaintenanceEnabled" -Value $true -Type "Checkbox"
Set-NinjaProperty -Name "LastMaintenanceDate" -Value (Get-Date) -Type "Date"

$nextMaintenance = (Get-Date).AddDays(30).Date.AddHours(2)
Set-NinjaProperty -Name "NextScheduledMaintenance" -Value $nextMaintenance -Type "DateTime"

Set-NinjaProperty -Name "BackupTime" -Value "02:00:00" -Type "Time"
#endregion

#region Documentation
$serverName = $env:COMPUTERNAME
$actualIP = (Get-NetIPAddress -AddressFamily IPv4 | Where-Object {$_.PrefixOrigin -eq 'Manual'} | Select-Object -First 1).IPAddress

Set-NinjaProperty -Name "IPAddress" -Value $actualIP -Type "IP Address" -DocumentName $serverName

$notes = @"
Last Maintenance: $(Get-Date -Format 'yyyy-MM-dd')
Environment: $environment
Status: Active
Admin: $adminEmail
Support: $supportPhone
"@
Set-NinjaProperty -Name "Notes" -Value $notes -Type "MultiLine" -DocumentName $serverName

# Set WYSIWYG report
$htmlReport = @"
<div class="card">
  <div class="card-title-box">
    <div class="card-title"><i class="fas fa-server"></i>&nbsp;&nbsp;$serverName</div>
  </div>
  <div class="card-body">
    <p><b>Environment:</b> $environment</p>
    <p><b>IP Address:</b> $actualIP</p>
    <p><b>Last Check:</b> $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')</p>
  </div>
</div>
"@
Set-NinjaProperty -Name "StatusReport" -Value $htmlReport -Type "WYSIWYG" -DocumentName $serverName
#endregion

Write-Output "Configuration updated successfully"
exit 0
```

## Best Practices

1. **Always specify type** - Use `-Type` parameter for proper conversion and friendly values
2. **Type for dropdowns** - Required to get/set friendly names instead of GUIDs
3. **Secure field access** - Only accessible during automation execution, not in terminal
4. **Unicode support** - Full Unicode including emojis supported in all text fields
5. **Documentation organization** - Use templates for structured multi-device data
6. **Character limits** - Text (200), MultiLine (10,000), Secure (200-10,000), WYSIWYG (200,000)
7. **Validation** - Email, IP Address, Phone, and URL fields validate format automatically
8. **Read-only fields** - Attachment, WYSIWYG (via CLI), Device/Organization selectors managed via web UI
9. **Field limits** - Maximum 20 WYSIWYG fields per form/template
10. **Help available** - Run `Get-Help Get-NinjaProperty -Full` or `Get-Help Set-NinjaProperty -Full` for detailed documentation
