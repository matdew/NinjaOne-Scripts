# NinjaOne API Device Filters Reference

Complete reference for device filtering (`df` parameter) in NinjaOne API v2.

Authoritative sources:

- [Device Filters article](https://app.ninjarmm.com/apidocs-beta/core-resources/articles/devices/device-filters)
- [Device Filter syntax PDF](https://resources.ninjarmm.com/API/Ninja+RMM+Public+API+v2.0.5+Device+Filter+Syntax.pdf)

## Filter Syntax

`df` takes an **expression**, not a flat comma-separated list. Each term is
`key operator value`. Combine multiple terms with `AND` (aliases `and` / `&&`). The whole
value must be **URL-encoded**.

```
GET /devices?df=class=WINDOWS_SERVER AND offline
```

### Operators

| Operator | Aliases | Applies to |
|----------|---------|------------|
| `=` | `eq` | all keyed filters |
| `!=` | `neq`, `<>` | all keyed filters |
| `in (a,b,...)` | | integer/enum lists |
| `nin (a,b,...)` | `notin`, `!in` | integer/enum lists |
| `<` | `lt`, `before` | `created` |
| `>` | `gt`, `after` | `created` |

> There is **no `search` key**. To find devices by name (or logged-on user, IP address,
> etc.) use the dedicated `GET /v2/devices/search?q=<term>` endpoint - see
> [api-examples.md](./api-examples.md) (`Search-Devices`).

## Filter Keys

### org / organization (Organization ID)

**Type:** Integer

```powershell
# Devices in organization 123
$devices = Invoke-RestMethod -Uri "$baseUrl/devices?df=org=123" -Headers $headers

# Devices in organizations 1 or 2
$devices = Invoke-RestMethod -Uri "$baseUrl/devices?df=organization in (1,2)" -Headers $headers
```

### loc / location (Location ID)

**Type:** Integer

```powershell
$locationDevices = Invoke-RestMethod -Uri "$baseUrl/devices?df=loc=10" -Headers $headers
```

### role (Node Role ID)

**Type:** Integer

```powershell
$roleDevices = Invoke-RestMethod -Uri "$baseUrl/devices?df=role=5" -Headers $headers
```

### id (Device ID)

**Type:** Integer

```powershell
$devices = Invoke-RestMethod -Uri "$baseUrl/devices?df=id in (1,2)" -Headers $headers
```

### class (Device Class)

**Type:** Enum. Valid values:

`WINDOWS_SERVER`, `WINDOWS_WORKSTATION`, `LINUX_SERVER`, `LINUX_WORKSTATION`, `MAC`,
`MAC_SERVER`, `ANDROID`, `APPLE_IOS`, `APPLE_IPADOS`, `VMWARE_VM_HOST`, `VMWARE_VM_GUEST`,
`HYPERV_VMM_HOST`, `HYPERV_VMM_GUEST`, `CLOUD_MONITOR_TARGET`, `NMS_SWITCH`, `NMS_ROUTER`,
`NMS_FIREWALL`, `NMS_PRIVATE_NETWORK_GATEWAY`, `NMS_PRINTER`, `NMS_SCANNER`,
`NMS_DIAL_MANAGER`, `NMS_WAP`, `NMS_IPSLA`, `NMS_COMPUTER`, `NMS_VM_HOST`, `NMS_APPLIANCE`,
`NMS_OTHER`, `NMS_SERVER`, `NMS_PHONE`, `NMS_VIRTUAL_MACHINE`,
`NMS_NETWORK_MANAGEMENT_AGENT`, `UNMANAGED_DEVICE`, `MANAGED_DEVICE`.

```powershell
# All Windows servers
$servers = Invoke-RestMethod -Uri "$baseUrl/devices?df=class=WINDOWS_SERVER" -Headers $headers

# Windows or Mac servers
$servers = Invoke-RestMethod -Uri "$baseUrl/devices?df=class in (WINDOWS_SERVER,MAC_SERVER)" -Headers $headers
```

### status (Approval Status)

**Type:** Enum: `PENDING` | `APPROVED` (approved is the default). This is the approval
status - it is **not** online/offline (see below).

```powershell
# Devices awaiting approval
$pending = Invoke-RestMethod -Uri "$baseUrl/devices?df=status=PENDING" -Headers $headers
```

### online / offline (Connection State)

Bare keywords - there is no `status=ONLINE`/`OFFLINE`.

```powershell
$online  = Invoke-RestMethod -Uri "$baseUrl/devices?df=online" -Headers $headers
$offline = Invoke-RestMethod -Uri "$baseUrl/devices?df=offline" -Headers $headers
```

### created (Creation Date)

**Type:** Date. Accepted formats: `yyyyMMdd`, `yyyy-MM-dd`, or
`yyyy-MM-dd'T'HH:mm:ss.SSS'Z'`. Use it with the date operators (`before`/`lt`,
`after`/`gt`, `=`/`eq`).

```powershell
# Devices created before 4 July 2019
$devices = Invoke-RestMethod -Uri "$baseUrl/devices?df=created before 2019-07-04" -Headers $headers

# Devices created in the last 7 days
$since = (Get-Date).AddDays(-7).ToString('yyyy-MM-dd')
$recent = Invoke-RestMethod -Uri "$baseUrl/devices?df=created after $since" -Headers $headers
```

### group (Saved Search / Group Membership)

**Type:** Integer (the id of a predefined group / saved search).

```powershell
# Members of saved search 563
$devices = Invoke-RestMethod -Uri "$baseUrl/devices?df=group 563" -Headers $headers
```

## Combining Filters

Combine terms with `AND` (all conditions must match). URL-encode the full value.

```powershell
# Offline Windows servers in organization 123
$devices = Invoke-RestMethod -Uri "$baseUrl/devices?df=org=123 AND class=WINDOWS_SERVER AND offline" -Headers $headers

# Windows workstations created between two dates
$devices = Invoke-RestMethod -Uri "$baseUrl/devices?df=class=WINDOWS_WORKSTATION AND created after 2024-01-01 AND created before 2024-03-31" -Headers $headers

# Pending devices in a specific location
$devices = Invoke-RestMethod -Uri "$baseUrl/devices?df=loc=5 AND status=PENDING" -Headers $headers
```

## Filter Helper Functions

### Dynamic Filter Builder

```powershell
function New-DeviceFilter {
    [CmdletBinding()]
    param(
        [int]$OrgId,
        [ValidateSet('WINDOWS_SERVER','WINDOWS_WORKSTATION','LINUX_SERVER','LINUX_WORKSTATION','MAC','MAC_SERVER','ANDROID','APPLE_IOS','APPLE_IPADOS','VMWARE_VM_HOST','VMWARE_VM_GUEST','HYPERV_VMM_HOST','HYPERV_VMM_GUEST','CLOUD_MONITOR_TARGET')]
        [string]$Class,
        [ValidateSet('PENDING','APPROVED')]
        [string]$Status,
        [ValidateSet('online','offline')]
        [string]$Connection,
        [int]$RoleId,
        [int]$LocationId,
        [datetime]$CreatedAfter,
        [datetime]$CreatedBefore
    )

    $parts = @()

    if ($PSBoundParameters.ContainsKey('OrgId'))      { $parts += "org=$OrgId" }
    if ($PSBoundParameters.ContainsKey('Class'))      { $parts += "class=$Class" }
    if ($PSBoundParameters.ContainsKey('Status'))     { $parts += "status=$Status" }
    if ($PSBoundParameters.ContainsKey('Connection')) { $parts += $Connection }
    if ($PSBoundParameters.ContainsKey('RoleId'))     { $parts += "role=$RoleId" }
    if ($PSBoundParameters.ContainsKey('LocationId')) { $parts += "loc=$LocationId" }
    if ($PSBoundParameters.ContainsKey('CreatedAfter'))  { $parts += "created after $($CreatedAfter.ToString('yyyy-MM-dd'))" }
    if ($PSBoundParameters.ContainsKey('CreatedBefore')) { $parts += "created before $($CreatedBefore.ToString('yyyy-MM-dd'))" }

    return $parts -join ' AND '
}

# Usage
$filter  = New-DeviceFilter -OrgId 123 -Class WINDOWS_SERVER -Connection online
$encoded = [System.Web.HttpUtility]::UrlEncode($filter)
$devices = Invoke-RestMethod -Uri "$baseUrl/devices?df=$encoded" -Headers $headers
```

## Common Filter Patterns

### Organization-Scoped Operations

```powershell
# All devices in organization
$allOrgDevices = Invoke-RestMethod -Uri "$baseUrl/devices?df=org=$orgId" -Headers $headers

# Only servers in organization
$orgServers = Invoke-RestMethod -Uri "$baseUrl/devices?df=org=$orgId AND class=WINDOWS_SERVER" -Headers $headers

# Offline devices in organization
$orgOffline = Invoke-RestMethod -Uri "$baseUrl/devices?df=org=$orgId AND offline" -Headers $headers
```

### Time-Based Queries

```powershell
# Devices created today
$today = (Get-Date).ToString('yyyy-MM-dd')
$todayDevices = Invoke-RestMethod -Uri "$baseUrl/devices?df=created after $today" -Headers $headers

# Devices created in a date range
$range = "created after 2024-01-01 AND created before 2024-01-31"
$rangeDevices = Invoke-RestMethod -Uri "$baseUrl/devices?df=$range" -Headers $headers
```

### Device Type Filtering

```powershell
# Windows or Linux servers in one call (list membership)
$allServers = Invoke-RestMethod -Uri "$baseUrl/devices?df=class in (WINDOWS_SERVER,LINUX_SERVER)" -Headers $headers

# All workstation classes
$allWorkstations = Invoke-RestMethod -Uri "$baseUrl/devices?df=class in (WINDOWS_WORKSTATION,LINUX_WORKSTATION,MAC)" -Headers $headers
```

### Name Search (separate endpoint)

```powershell
# Name search is NOT a df filter - use GET /v2/devices/search
$encoded = [System.Web.HttpUtility]::UrlEncode('PROD')
$matches = (Invoke-RestMethod -Uri "$baseUrl/devices/search?q=$encoded" -Headers $headers).devices
```

## Filter Notes

1. **AND only** for combining terms in a single `df` expression. For OR across values of
   the same key, use `in (...)`; for OR across different keys, make separate calls and
   combine client-side.
2. **`in` / `nin`** provide list membership and negation for `org`, `location`, `role`,
   `id`, and `class`.
3. **`!=` / `<>`** provide "not equal" on a single value.
4. **Case-sensitive** enum values - use exact spellings (e.g. `WINDOWS_SERVER`).
5. **URL-encode** the whole `df` value; expressions contain spaces and parentheses.
6. **Name search** lives on `GET /v2/devices/search`, not in `df`.

## Best Practices

1. **Filter server-side** with `df` rather than pulling everything and filtering in script.
2. **Prefer `in (...)`** over multiple round-trips when matching several values of one key.
3. **Paginate** device lists with the `after` (last node id) cursor - see the main skill.
4. **Validate enum values** (`class`, `status`) before building the expression.
5. **Always URL-encode** the `df` value.

## Additional Resources

- [Main API Skill](../SKILL.md)
- [API Examples](./api-examples.md)
- [Device Filters article](https://app.ninjarmm.com/apidocs-beta/core-resources/articles/devices/device-filters)
