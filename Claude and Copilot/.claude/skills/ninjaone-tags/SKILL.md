---
name: ninjaone-tags
description: Use when code uses Get-NinjaTag, Set-NinjaTag, Remove-NinjaTag, ninjarmm-cli tag-get/tag-set/tag-clear, or user asks about NinjaOne device tagging, tag-based automation, or tag management.
---

# NinjaOne Tags

NinjaOne tags classify devices (endpoints) beyond roles and custom fields. Tags enable device searches, automation assignment with conditions, and filtered queries.

## When to Use This Skill

- Assign tags based on detected server roles or installed software
- Implement conditional automation that executes only for tagged devices
- Remove deprecated tags and standardize tag naming conventions
- Report current device tags to custom fields for dashboard visibility
- Tag devices by environment (Production, Development, QA)
- Group devices for monitoring, reporting, or bulk operations

## Prerequisites

- **Tag Creation:** Tags must be created in NinjaOne web interface before use in scripts
- **Automation Context:** Tag operations only work from automation scripts running on the NinjaOne agent
- **Error Handling:** Scripts should wrap tag operations in try-catch blocks
- **Case Sensitivity:** Tag names are case-sensitive; use exact matches

## Related Skills

- [ninjaone-api](../ninjaone-api/SKILL.md) - Device/endpoint tags have no REST API (agent automation + CLI only); the REST `/v2/tag` endpoints are a separate feature (ITAM Asset Tags)
- [ninjaone-custom-fields](../ninjaone-custom-fields/SKILL.md) - Store tag reports in custom fields for dashboard visibility
- [ninjaone-environment-variables](../ninjaone-environment-variables/SKILL.md) - Use organization context for environment-based tagging
- [ninjaone-cli](../ninjaone-cli/SKILL.md) - Alternative CLI commands for tag operations (tag-get, tag-set, tag-clear)
- [ninjaone-script-variables](../ninjaone-script-variables/SKILL.md) - Configure tag names via script parameters for flexible automation

## PowerShell Module Cmdlets

### Get-NinjaTag

Retrieves all tags assigned to the current device.

**Syntax:**
```powershell
Get-NinjaTag
```

**Returns:** Array of strings containing tag names

**Example:**
```powershell
# Get all tags assigned to this device
$tags = Get-NinjaTag

# Display all tags
$tags

# Access specific tag by index
$tags[0]

# Check if specific tag exists
if ($tags -contains "Production") {
    Write-Output "Device is tagged as Production"
}

# Count tags
$tagCount = $tags.Count
Write-Output "Device has $tagCount tags"
```

### Set-NinjaTag

Assigns a tag to the current device.

**Syntax:**
```powershell
Set-NinjaTag [-Name] <String>
```

**Parameters:**
- `Name` (String, Mandatory) - The tag name to assign

**Returns:** None. Throws error if tag doesn't exist in the organization.

**Example:**
```powershell
# Assign a tag
Set-NinjaTag -Name "Production"

# Assign using positional parameter
Set-NinjaTag "Development"

# Assign multiple tags
@("Web Server", "North Region", "Priority 1") | ForEach-Object {
    Set-NinjaTag -Name $_
}

# Assign tag with validation
$tagName = "Production"
try {
    Set-NinjaTag -Name $tagName
    Write-Output "Successfully assigned tag: $tagName"
} catch {
    Write-Error "Failed to assign tag '$tagName': $_"
}
```

**Error Handling:**
- Throws error if tag name doesn't exist in the organization
- Create tags in NinjaOne web interface before using in scripts

### Remove-NinjaTag

Removes a tag from the current device.

**Syntax:**
```powershell
Remove-NinjaTag [-Name] <String>
```

**Parameters:**
- `Name` (String, Mandatory) - The tag name to remove

**Returns:** None. Throws error if tag doesn't exist in the organization.

**Example:**
```powershell
# Remove a tag
Remove-NinjaTag -Name "Development"

# Remove using positional parameter
Remove-NinjaTag "Test Environment"

# Remove multiple tags
@("Old Tag", "Deprecated") | ForEach-Object {
    try {
        Remove-NinjaTag -Name $_
        Write-Output "Removed tag: $_"
    } catch {
        Write-Warning "Could not remove tag '$_': $($_.Exception.Message)"
    }
}

# Conditional tag removal
$tags = Get-NinjaTag
if ($tags -contains "Temporary") {
    Remove-NinjaTag -Name "Temporary"
    Write-Output "Removed temporary tag"
}
```

## CLI Commands (ninjarmm-cli)

### tag-get

Lists all tags assigned to the device.

**Syntax:**
```bash
ninjarmm-cli tag-get
```

**Returns:** One tag per line

**Example:**
```powershell
# Execute from PowerShell
$output = & ninjarmm-cli tag-get
$tags = $output -split "`n" | Where-Object { $_ -ne '' }

# Process each tag
foreach ($tag in $tags) {
    Write-Output "Found tag: $tag"
}
```

### tag-set

Assigns a tag to the device.

**Syntax:**
```bash
ninjarmm-cli tag-set "Tag Name"
```

**Example:**
```powershell
# Assign a tag via CLI
& ninjarmm-cli tag-set "Production"

# With error handling
$tagName = "Web Server"
$result = & ninjarmm-cli tag-set $tagName 2>&1
if ($LASTEXITCODE -ne 0) {
    Write-Error "Failed to set tag: $result"
}
```

### tag-clear

Removes a tag from the device.

**Syntax:**
```bash
ninjarmm-cli tag-clear "Tag Name"
```

**Example:**
```powershell
# Remove a tag via CLI
& ninjarmm-cli tag-clear "Development"

# With validation
$tagName = "Old Configuration"
$result = & ninjarmm-cli tag-clear $tagName 2>&1
if ($LASTEXITCODE -eq 0) {
    Write-Output "Successfully removed tag: $tagName"
} else {
    Write-Warning "Could not remove tag: $result"
}
```

## Practical Examples

### Conditional Automation Based on Tags

```powershell
<#
.SYNOPSIS
    Performs maintenance only on devices tagged for maintenance window.
#>

[CmdletBinding()]
param()

$tags = Get-NinjaTag

if ($tags -contains "Maintenance Approved") {
    Write-Output "Device is approved for maintenance, proceeding..."

    # Perform maintenance operations

    # Remove maintenance tag after completion
    Remove-NinjaTag -Name "Maintenance Approved"

    # Add completion tag
    Set-NinjaTag -Name "Maintenance Completed"

    Write-Output "Maintenance completed successfully"
    exit 0
} else {
    Write-Output "Device not approved for maintenance, skipping..."
    exit 0
}
```

### Environment-Based Tagging

```powershell
<#
.SYNOPSIS
    Automatically tags devices based on their role or configuration.
#>

[CmdletBinding()]
param()

try {
    # Detect server role
    $windowsFeatures = Get-WindowsFeature | Where-Object { $_.Installed }

    # Tag as web server
    if ($windowsFeatures.Name -contains "Web-Server") {
        Set-NinjaTag -Name "Web Server"
        Write-Output "Tagged as Web Server"
    }

    # Tag as database server
    if (Get-Service -Name 'MSSQLSERVER' -ErrorAction SilentlyContinue) {
        Set-NinjaTag -Name "Database Server"
        Write-Output "Tagged as Database Server"
    }

    # Tag by organization
    $orgName = $env:NINJA_ORGANIZATION_NAME
    if ($orgName -like "*Production*") {
        Set-NinjaTag -Name "Production"
        Write-Output "Tagged as Production based on organization"
    }

    exit 0
} catch {
    Write-Error "Tagging failed: $_"
    exit 1
}
```

### Tag Cleanup and Standardization

```powershell
<#
.SYNOPSIS
    Removes deprecated tags and standardizes tag naming.
#>

[CmdletBinding()]
param()

$deprecatedTags = @("Old System", "Legacy", "To Be Removed")
$tagMapping = @{
    "Prod" = "Production"
    "Dev" = "Development"
    "QA" = "Quality Assurance"
}

try {
    $currentTags = Get-NinjaTag

    # Remove deprecated tags
    foreach ($tag in $currentTags) {
        if ($tag -in $deprecatedTags) {
            Remove-NinjaTag -Name $tag
            Write-Output "Removed deprecated tag: $tag"
        }
    }

    # Standardize tag names
    foreach ($tag in $currentTags) {
        if ($tagMapping.ContainsKey($tag)) {
            $newTag = $tagMapping[$tag]
            Remove-NinjaTag -Name $tag
            Set-NinjaTag -Name $newTag
            Write-Output "Replaced '$tag' with '$newTag'"
        }
    }

    exit 0
} catch {
    Write-Error "Tag cleanup failed: $_"
    exit 1
}
```

### Reporting Tags to Custom Field

```powershell
<#
.SYNOPSIS
    Reports current device tags to a multi-line custom field for visibility.
#>

[CmdletBinding()]
param()

try {
    $tags = Get-NinjaTag

    if ($tags.Count -eq 0) {
        $tagReport = "No tags assigned"
    } else {
        $tagReport = $tags -join ", "
    }

    # Store in custom field for dashboard visibility
    Set-NinjaProperty -Name "deviceTags" -Value $tagReport -Type "MultiLine"

    Write-Output "Tag report: $tagReport"
    exit 0
} catch {
    Write-Error "Tag reporting failed: $_"
    exit 1
}
```

## Best Practices

1. **Tag existence** - Create tags in NinjaOne web interface before using them in scripts
2. **Error handling** - Always wrap tag operations in try-catch blocks
3. **Validation** - Use `Get-NinjaTag` to check current tags before adding/removing
4. **Automation context** - Tag operations only work within automation scripts, not manual CLI
5. **Case sensitivity** - Tag names are case-sensitive; use exact matches
6. **PowerShell preference** - Prefer PowerShell cmdlets over CLI for better error handling and type safety
7. **Idempotency** - Check if tag exists before adding to avoid errors
8. **Documentation** - Document tag naming conventions and purposes in script headers
9. **Cleanup** - Remove temporary tags after automation completes
10. **Monitoring** - Use tags to group devices for monitoring and reporting

## Important Notes

- **Script-only access:** Tag operations only work from automation scripts running on the NinjaOne agent
- **Tag management:** Tags must be created in the NinjaOne web interface before use
- **No tag creation:** PowerShell cmdlets and CLI cannot create new tag definitions
- **Unicode support:** Both PowerShell module and CLI support full Unicode including emojis in tag names
- **Synchronization:** Tag changes are immediate but may take a moment to reflect in the NinjaOne dashboard

## API Access

For tag operations via REST API, refer to the **ninjaone-api** skill. The API supports:
- Creating and deleting tag definitions
- Listing tags assigned to devices
- Assigning and removing tags from devices
- Merging tags

API operations are performed through NinjaOne Public API v2 endpoints.
