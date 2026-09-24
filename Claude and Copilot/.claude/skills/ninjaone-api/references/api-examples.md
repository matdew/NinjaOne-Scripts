# NinjaOne API Examples

## Advanced Pagination Pattern

```powershell
function Get-AllNinjaDevices {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$BaseUrl,

        [Parameter(Mandatory)]
        [hashtable]$Headers,

        [int]$PageSize = 100
    )

    $allResults = [System.Collections.Generic.List[object]]::new()
    $after = 0

    do {
        $url = "$BaseUrl/devices?pageSize=$PageSize&after=$after"

        try {
            # /devices returns a plain array with no 'next'; page by the last node id.
            $page = @(Invoke-RestMethod -Uri $url -Headers $Headers)
            if ($page.Count -gt 0) {
                $allResults.AddRange($page)
                $after = $page[-1].id
            }
        } catch {
            Write-Error "Failed to retrieve devices: $_"
            throw
        }
    } while ($page.Count -eq $PageSize)

    return $allResults.ToArray()
}
```

## Bulk Operations with Progress

```powershell
function Update-NinjaDeviceCustomFields {
    param(
        [Parameter(Mandatory)]
        [array]$DeviceIds,

        [Parameter(Mandatory)]
        [hashtable]$FieldUpdates,

        [Parameter(Mandatory)]
        [string]$BaseUrl,

        [Parameter(Mandatory)]
        [hashtable]$Headers
    )

    $total = $DeviceIds.Count
    $current = 0
    $results = @{
        Success = @()
        Failed = @()
    }

    foreach ($deviceId in $DeviceIds) {
        $current++
        Write-Progress -Activity "Updating Devices" `
            -Status "Processing $current of $total" `
            -PercentComplete (($current / $total) * 100)

        try {
            # Body is a flat object keyed by field name, e.g. @{ FieldName = "value" }
            Invoke-RestMethod `
                -Uri "$BaseUrl/device/$deviceId/custom-fields" `
                -Headers $Headers `
                -Method Patch `
                -Body ($FieldUpdates | ConvertTo-Json) `
                -ContentType "application/json"

            $results.Success += $deviceId
        } catch {
            $results.Failed += @{
                DeviceId = $deviceId
                Error = $_.Exception.Message
            }
        }

        Start-Sleep -Milliseconds 100  # Rate limiting
    }

    Write-Progress -Activity "Updating Devices" -Completed
    return $results
}
```

## Token Management

```powershell
class NinjaApiClient {
    [string]$BaseUrl
    [string]$ClientId
    [string]$ClientSecret
    [string]$AccessToken
    [datetime]$TokenExpiry

    NinjaApiClient([string]$instance, [string]$clientId, [string]$clientSecret) {
        $this.BaseUrl = "https://$instance.ninjarmm.com/api/v2"
        $this.ClientId = $clientId
        $this.ClientSecret = $clientSecret
    }

    [void]RefreshToken() {
        $tokenUrl = $this.BaseUrl -replace '/api/v2', '/ws/oauth/token'
        $body = @{
            grant_type = "client_credentials"
            client_id = $this.ClientId
            client_secret = $this.ClientSecret
            scope = "monitoring management control"
        }

        $response = Invoke-RestMethod -Uri $tokenUrl -Method Post -Body $body
        $this.AccessToken = $response.access_token
        $this.TokenExpiry = (Get-Date).AddSeconds($response.expires_in - 60)
    }

    [hashtable]GetHeaders() {
        if (-not $this.AccessToken -or (Get-Date) -ge $this.TokenExpiry) {
            $this.RefreshToken()
        }

        return @{
            Authorization = "Bearer $($this.AccessToken)"
            Accept = "application/json"
        }
    }

    [object]InvokeApi([string]$endpoint, [string]$method = "Get", [object]$body = $null) {
        $uri = "$($this.BaseUrl)$endpoint"
        $headers = $this.GetHeaders()

        $params = @{
            Uri = $uri
            Headers = $headers
            Method = $method
        }

        if ($body) {
            $params.Body = ($body | ConvertTo-Json -Depth 10)
            $params.ContentType = "application/json"
        }

        return Invoke-RestMethod @params
    }
}
```

## Device Filtering Examples

### Get Offline Devices by Organization

```powershell
function Get-OfflineDevicesByOrg {
    param(
        [Parameter(Mandatory)]
        [string]$BaseUrl,

        [Parameter(Mandatory)]
        [hashtable]$Headers,

        [Parameter(Mandatory)]
        [int]$OrgId
    )

    $offline = Invoke-RestMethod -Uri "$BaseUrl/devices?df=org=$OrgId AND offline" -Headers $Headers

    return $offline | Select-Object `
        @{N='DeviceId';E={$_.id}},
        @{N='Name';E={$_.displayName}},
        @{N='LastSeen';E={[DateTimeOffset]::FromUnixTimeSeconds($_.lastContact).LocalDateTime}},
        @{N='Class';E={$_.nodeClass}}
}
```

### Filter Devices by Multiple Criteria

```powershell
function Find-CriticalServers {
    param(
        [string]$BaseUrl,
        [hashtable]$Headers,
        [int]$OrgId,
        [int]$LocationId
    )

    # Get online Windows servers in specific org and location
    $filter = "org=$OrgId AND location=$LocationId AND class=WINDOWS_SERVER AND online"
    $servers = Invoke-RestMethod -Uri "$BaseUrl/devices?df=$filter" -Headers $Headers

    # Further filter client-side for servers with role "Production"
    return $servers | Where-Object {
        $_.nodeRole.name -like "*Production*"
    }
}
```

### Get Recently Added Devices

```powershell
function Get-RecentDevices {
    param(
        [string]$BaseUrl,
        [hashtable]$Headers,
        [int]$Days = 7
    )

    # 'created' takes a date (yyyy-MM-dd or ISO 8601), not a Unix timestamp
    $cutoffDate = (Get-Date).AddDays(-$Days).ToString('yyyy-MM-dd')

    $recent = Invoke-RestMethod -Uri "$BaseUrl/devices?df=created after $cutoffDate" -Headers $Headers

    return $recent | Select-Object `
        displayName,
        nodeClass,
        @{N='CreatedDate';E={[DateTimeOffset]::FromUnixTimeSeconds($_.createTime).LocalDateTime}},
        @{N='Organization';E={$_.references.organization.name}}
}
```

### Search Devices by Name

```powershell
function Search-Devices {
    param(
        [Parameter(Mandatory)]
        [string]$BaseUrl,

        [Parameter(Mandatory)]
        [hashtable]$Headers,

        [Parameter(Mandatory)]
        [string]$SearchTerm,

        [int]$Limit = 100
    )

    # Name search is a dedicated endpoint (GET /v2/devices/search), NOT a df filter.
    # It takes q (name, logged-on user, IP, etc.) + optional limit and returns { query, devices }.
    $encoded = [System.Web.HttpUtility]::UrlEncode($SearchTerm)
    $result = Invoke-RestMethod -Uri "$BaseUrl/devices/search?q=$encoded&limit=$Limit" -Headers $Headers

    return $result.devices
}
```

### Filter Report - Device Distribution

```powershell
function Get-DeviceDistributionReport {
    param(
        [string]$BaseUrl,
        [hashtable]$Headers,
        [int]$OrgId
    )

    $classes = @(
        'WINDOWS_WORKSTATION',
        'WINDOWS_SERVER',
        'MAC',
        'LINUX_SERVER',
        'LINUX_WORKSTATION',
        'CLOUD_MONITOR_TARGET'
    )

    $report = foreach ($class in $classes) {
        $devices = Invoke-RestMethod -Uri "$BaseUrl/devices?df=org=$OrgId AND class=$class" -Headers $Headers

        [PSCustomObject]@{
            DeviceClass = $class
            Total = @($devices).Count
            Online = @($devices | Where-Object { $_.online }).Count
            Offline = @($devices | Where-Object { -not $_.online }).Count
        }
    }

    return $report
}
```

### Monitor New Device Approvals

```powershell
function Get-PendingApprovals {
    param(
        [string]$BaseUrl,
        [hashtable]$Headers,
        [int]$OrgId
    )

    $filter = "status=PENDING"
    if ($OrgId) {
        $filter += " AND org=$OrgId"
    }

    $pending = Invoke-RestMethod -Uri "$BaseUrl/devices?df=$filter" -Headers $Headers

    return $pending | Select-Object `
        @{N='DeviceId';E={$_.id}},
        @{N='Name';E={$_.displayName}},
        @{N='Class';E={$_.nodeClass}},
        @{N='Organization';E={$_.references.organization.name}},
        @{N='Location';E={$_.references.location.name}},
        @{N='FirstSeen';E={[DateTimeOffset]::FromUnixTimeSeconds($_.createTime).LocalDateTime}}
}

# Auto-approve devices matching criteria
function Approve-DevicesByFilter {
    param(
        [string]$BaseUrl,
        [hashtable]$Headers,
        [int]$OrgId,
        [string]$NamePattern
    )

    $pending = Get-PendingApprovals -BaseUrl $BaseUrl -Headers $Headers -OrgId $OrgId
    $toApprove = $pending | Where-Object { $_.Name -like $NamePattern }

    if ($toApprove) {
        $deviceIds = $toApprove | ForEach-Object { $_.DeviceId }
        $body = @{ devices = $deviceIds } | ConvertTo-Json

        Invoke-RestMethod `
            -Uri "$BaseUrl/devices/approval/APPROVE" `
            -Headers $Headers `
            -Method Post `
            -Body $body `
            -ContentType "application/json"

        Write-Host "Approved $($deviceIds.Count) devices"
    }
}
```
