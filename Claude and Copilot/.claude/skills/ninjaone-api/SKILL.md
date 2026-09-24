---
name: ninjaone-api
description: Using the NinjaOne REST API v2 for automation, integration, and data retrieval via HTTP requests. Use when scripts need to interact with NinjaOne programmatically, manage devices/organizations/tickets, perform bulk operations, manage ITAM asset tags, retrieve monitoring data, synchronize with external systems (PSA, ITSM), or build custom dashboards. Covers OAuth2 authentication, pagination, filtering (device filters like df, class, org, status), rate limiting, and error handling patterns.
---

# NinjaOne REST API v2

The NinjaOne Public API v2 provides programmatic access to manage devices, organizations, tickets, custom fields, ITAM asset tags, and monitoring data via HTTP requests.

**Base URL:** `https://{instance}.ninjarmm.com/api/v2`

**API Documentation:** `https://{instance}.ninjarmm.com/apidocs-v2`

**Regional instances:** `{instance}` is the same subdomain you sign in to. Valid values are
`app` (US), `us2` (US2), `eu` (EU), `ca` (Canada), `oc` (Oceania) and `jp` (Japan) - e.g.
`https://eu.ninjarmm.com/api/v2`. The API base URL, token URL and apidocs all live on that
same host, so use whichever one your organization signs in to.

## When to Use This Skill

- Automating device management and monitoring
- Integrating NinjaOne with external systems (PSA, ITSM, etc.)
- Building custom dashboards and reports
- Bulk operations on organizations, locations, or devices
- Creating and managing tickets programmatically
- Reading/writing custom field data via API
- Synchronizing data between NinjaOne and other platforms

## Prerequisites

1. **API Credentials:**
   - Client ID (and Client Secret for machine-to-machine apps) - OAuth2
   - Obtained from NinjaOne Administration > Apps > API Clients
   - Scopes: `monitoring`, `management`, `control`

2. **Required Tools:**
   - HTTP client library (e.g., `Invoke-RestMethod`, `curl`, `requests`)
   - JSON parsing capabilities
   - Secure credential storage mechanism

3. **Choose the correct Client App type for your use case:**

   | App type | Grant flow | Has secret? | Use for |
   |----------|-----------|-------------|---------|
   | **API Services (machine-to-machine)** | `client_credentials` | Yes | Unattended scripts, scheduled scripts, RMM/NinjaOne script custom fields |
   | **Native (iOS, Android, macOS, Windows, etc.)** | `authorization_code` + PKCE | No | Interactive CLI/desktop tools using a loopback redirect (`http://localhost:PORT/`) |
   | **Web (PHP, Java, .NET Core, etc.)** | `authorization_code` | Yes (confidential) | Server-side web apps with a hosted https redirect |
   | **Single Page (Angular, React, Vue, etc.)** | `authorization_code` + PKCE | No | Browser-hosted SPAs with an https-hosted redirect page |

   Using the wrong app type for the flow you're implementing is the most common cause of
   OAuth failures - see Troubleshooting below.

## Authentication

### OAuth2 Access Token

```powershell
# Get OAuth2 token
$tokenUrl = "https://{instance}.ninjarmm.com/ws/oauth/token"
$body = @{
    grant_type    = "client_credentials"
    client_id     = $env:NINJA_CLIENT_ID
    client_secret = $env:NINJA_CLIENT_SECRET
    scope         = "monitoring management control"
}

$tokenResponse = Invoke-RestMethod -Uri $tokenUrl -Method Post -Body $body -ContentType "application/x-www-form-urlencoded"
$accessToken = $tokenResponse.access_token

# Use token in API requests
$headers = @{
    Authorization = "Bearer $accessToken"
    Accept        = "application/json"
}
```

### Token Lifecycle

- Access tokens expire after a configured period (typically 1 hour)
- Store tokens securely (never hardcode in scripts)
- Implement token refresh logic for long-running operations
- Use environment variables or secure vaults for credentials

### OAuth2 Authorization Code + PKCE (Interactive User Sign-In)

Use this flow for scripts/tools that need to act **as a signed-in user** (rather than
a service account), or when the target app must be a public client with no secret
(desktop/CLI tools, native apps). This is a different Client App registration than the
`client_credentials` (API Services) flow above - see the app-type table in Prerequisites.

**Prerequisites specific to this flow:**

- Client App registered in NinjaOne as **Native (iOS, Android, macOS, Windows, etc.)**.
  Using **API Services (machine-to-machine)** here will not work - hitting the authorize
  endpoint with a machine-to-machine `client_id` returns a generic 404, not a helpful
  OAuth error (see Troubleshooting).
- A loopback redirect URI registered on the app, e.g. `http://localhost:8888/`.
  **It must match character-for-character** (including presence/absence of a trailing
  slash) what your script sends as `redirect_uri` - NinjaOne does exact string matching,
  not path-normalized matching.
- Scopes granted on the app must be a superset of what you request (e.g. `monitoring`,
  `management`, optionally `offline_access` if you also want a refresh token).

**Flow:**

1. Generate a PKCE `code_verifier` / `code_challenge` (S256) and a random `state`.
2. Start a local `HttpListener` on the redirect URI's host:port to catch the callback.
3. Open the system browser to `/ws/oauth/authorize` with `response_type=code`.
4. User signs in/consents in the browser; NinjaOne redirects to your loopback URI with
   `?code=...&state=...`.
5. Exchange the `code` (+ `code_verifier`) for tokens at `/ws/oauth/token`.

```powershell
function New-PkceVerifier {
    $bytes = New-Object byte[] 64
    [Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($bytes)
    ([Convert]::ToBase64String($bytes).TrimEnd('=') -replace '\+','-' -replace '/','_')
}

function Get-PkceChallenge {
    param([string]$Verifier)
    $sha = [Security.Cryptography.SHA256]::Create()
    $hash = $sha.ComputeHash([Text.Encoding]::ASCII.GetBytes($Verifier))
    ([Convert]::ToBase64String($hash).TrimEnd('=') -replace '\+','-' -replace '/','_')
}

$baseUrl     = 'https://app.ninjarmm.com'
$clientId    = '<native-app-client-id>'
$redirectUri = 'http://localhost:8888/'   # must exactly match the app's registered redirect URI
$scope       = 'monitoring management'

$verifier  = New-PkceVerifier
$challenge = Get-PkceChallenge -Verifier $verifier
$state     = [Guid]::NewGuid().ToString('N')

$listener = [System.Net.HttpListener]::new()
$redirect = [Uri]$redirectUri
$listener.Prefixes.Add("$($redirect.Scheme)://$($redirect.Host):$($redirect.Port)/")
$listener.Start()

$authorizeUri = '{0}/ws/oauth/authorize?response_type=code&client_id={1}&redirect_uri={2}&scope={3}&state={4}&code_challenge={5}&code_challenge_method=S256' -f `
    $baseUrl, [Uri]::EscapeDataString($clientId), [Uri]::EscapeDataString($redirectUri),
    [Uri]::EscapeDataString($scope), [Uri]::EscapeDataString($state), [Uri]::EscapeDataString($challenge)
Start-Process $authorizeUri

$context = $listener.GetContext()
$code = $context.Request.QueryString['code']
$returnedState = $context.Request.QueryString['state']
# ... write a simple HTML response, close $context.Response, verify $returnedState -eq $state ...
$listener.Stop(); $listener.Close()

$tokenResponse = Invoke-RestMethod -Method Post -Uri "$baseUrl/ws/oauth/token" `
    -Headers @{ accept = 'application/json'; 'Content-Type' = 'application/x-www-form-urlencoded' } `
    -Body @{
        grant_type    = 'authorization_code'
        client_id     = $clientId
        redirect_uri  = $redirectUri
        code          = $code
        code_verifier = $verifier
        scope         = $scope
    }
$accessToken = $tokenResponse.access_token
```

The snippet above is intentionally minimal (happy path). For production use also add: a
`state` check before exchanging the code, a timeout/cancellation on
`$listener.GetContext()`, an HTML page written back to the browser tab, and the non-`ws`
`/oauth/*` path fallback described below. See the NinjaOne authorization docs (Authorization
Code Flow with PKCE) for the full protocol.

**Known gotchas (confirmed against a live tenant, 2026-07-31):**

- **Wrong app type ⇒ misleading 404, not an OAuth error.** If `client_id` belongs to an
  **API Services (machine-to-machine)** app, calling `/ws/oauth/authorize` returns:
  ```json
  { "resultCode": "FAILURE", "errorMessage": "HTTP 404 Not Found", "incidentId": "WEB_MGMT_SERVICE-..." }
  ```
  This looks like a routing/redirect problem but actually means the app doesn't support
  the interactive flow at all. Fix: create/use a **Native** type Client App.
- **Redirect URI trailing-slash mismatch ⇒ also renders as the same 404.** After signing
  in, NinjaOne internally redirects to `/ws/oauth/error?error=unauthorized_client&error_description=Invalid+redirect_uri`
  - but that error page itself 404s with the same `WEB_MGMT_SERVICE` JSON body (a bug in
  NinjaOne's own error page, not your script). **Check the URL's query string**, not just
  the JSON body, to see the real `error`/`error_description`. Fix: make the `redirect_uri`
  your script sends match the registered value character-for-character (don't force-add
  or strip a trailing slash - preserve exactly what's registered).
- **Some tenants must use `/oauth/authorize` and `/oauth/token`** (no `ws` prefix) instead
  of `/ws/oauth/authorize` / `/ws/oauth/token`. If authorize 404s even with a correct
  Native app + exact redirect_uri match, try the non-`ws` path as a fallback.

## Common API Patterns

### Pagination

Device list endpoints (`/devices`, `/devices-detailed`) return a plain JSON array with no
`next` property. Page by passing the **last device id** from the previous page as the
`after` cursor, and stop when a page returns fewer than `pageSize` items:

```powershell
# Get all devices with pagination
$baseUrl  = "https://{instance}.ninjarmm.com/api/v2"
$pageSize = 100
$allDevices = [System.Collections.Generic.List[object]]::new()
$after = 0

do {
    $url  = "$baseUrl/devices?pageSize=$pageSize&after=$after"
    $page = @(Invoke-RestMethod -Uri $url -Headers $headers)
    if ($page.Count -gt 0) {
        $allDevices.AddRange($page)
        $after = $page[-1].id   # last node id = cursor for the next page
    }
} while ($page.Count -eq $pageSize)
```

> The cursor-style `/v2/queries/*` report endpoints are different: they accept `cursor` +
> `pageSize` and return an object shaped like `{ cursor, results }`. Page those by reading
> `$response.cursor` until it is empty.

### Filtering

Use the `df` (device filter) query parameter to filter device lists. Combine multiple
terms with `AND` (see Device Filters below for the full grammar):

```powershell
# Filter devices by organization
$devices = Invoke-RestMethod -Uri "$baseUrl/devices?df=org=$orgId" -Headers $headers

# Filter by creation date
$devices = Invoke-RestMethod -Uri "$baseUrl/devices?df=created after 2024-01-01" -Headers $headers

# Multiple filters (AND logic)
$devices = Invoke-RestMethod -Uri "$baseUrl/devices?df=org=$orgId AND class=WINDOWS_WORKSTATION" -Headers $headers
```

### Device Filters (df Parameter)

The `df` (device filter) query parameter accepts an **expression**, not a flat
comma-separated list. Each term is `key operator value`; combine terms with `AND`
(aliases `and` / `&&`). The whole value must be URL-encoded. See the authoritative
[Device Filter reference](./references/device-filters.md).

**Operators:** `=`/`eq`, `!=`/`neq`/`<>`, `in (a,b,...)`, `nin`/`notin`/`!in (a,b,...)`,
`<`/`lt`/`before`, `>`/`gt`/`after`.

### Available Filter Keys

| Filter Key | Type | Notes / Example |
|------------|------|-----------------|
| `org` (alias `organization`) | Integer | `df=org=123` ; `df=organization in (1,2)` |
| `loc` (alias `location`) | Integer | `df=loc=10` |
| `role` | Integer | `df=role=5` |
| `id` | Integer | `df=id in (1,2)` |
| `class` | Enum | `df=class=WINDOWS_SERVER` ; `df=class in (WINDOWS_SERVER,MAC_SERVER)` |
| `status` | Enum: `PENDING` \| `APPROVED` | `df=status=APPROVED` (approved is the default) |
| `online` / `offline` | Bare keyword | `df=online` - online/offline is **not** a `status` value |
| `created` | Date (`yyyyMMdd`, `yyyy-MM-dd`, or ISO 8601) | `df=created after 2024-01-01` |
| `group` | Integer | `df=group 563` - members of a saved search/group |

> There is **no `search` key**. To find devices by name, use the dedicated
> `GET /v2/devices/search` ("Find devices") endpoint instead of a `df` filter.

### Device Classes

`WINDOWS_SERVER`, `WINDOWS_WORKSTATION`, `LINUX_SERVER`, `LINUX_WORKSTATION`, `MAC`,
`MAC_SERVER`, `ANDROID`, `APPLE_IOS`, `APPLE_IPADOS`, `VMWARE_VM_HOST`, `VMWARE_VM_GUEST`,
`HYPERV_VMM_HOST`, `HYPERV_VMM_GUEST`, `CLOUD_MONITOR_TARGET`, `NMS_SWITCH`, `NMS_ROUTER`,
`NMS_FIREWALL`, `NMS_PRIVATE_NETWORK_GATEWAY`, `NMS_PRINTER`, `NMS_SCANNER`,
`NMS_DIAL_MANAGER`, `NMS_WAP`, `NMS_IPSLA`, `NMS_COMPUTER`, `NMS_VM_HOST`, `NMS_APPLIANCE`,
`NMS_OTHER`, `NMS_SERVER`, `NMS_PHONE`, `NMS_VIRTUAL_MACHINE`,
`NMS_NETWORK_MANAGEMENT_AGENT`, `UNMANAGED_DEVICE`, `MANAGED_DEVICE`.

### Filter Examples

```powershell
# Filter by organization
$devices = Invoke-RestMethod -Uri "$baseUrl/devices?df=org=123" -Headers $headers

# Filter by device class
$servers = Invoke-RestMethod -Uri "$baseUrl/devices?df=class=WINDOWS_SERVER" -Headers $headers

# Offline devices (online/offline are bare keywords, not status values)
$offline = Invoke-RestMethod -Uri "$baseUrl/devices?df=offline" -Headers $headers

# Multiple terms are combined with AND
$offlineServers = Invoke-RestMethod -Uri "$baseUrl/devices?df=class=WINDOWS_SERVER AND offline" -Headers $headers

# Membership in a list
$serverClasses = Invoke-RestMethod -Uri "$baseUrl/devices?df=class in (WINDOWS_SERVER,MAC_SERVER)" -Headers $headers

# Devices created in a date range
$created = Invoke-RestMethod -Uri "$baseUrl/devices?df=created after 2024-01-01 AND created before 2024-03-31" -Headers $headers

# Pending (awaiting approval) devices
$pending = Invoke-RestMethod -Uri "$baseUrl/devices?df=status=PENDING" -Headers $headers
```

### URL Encoding Considerations

`df` expressions contain spaces and parentheses, so URL-encode the value:

```powershell
Add-Type -AssemblyName System.Web
$filter = 'class=WINDOWS_SERVER AND offline'
$url = "$baseUrl/devices?df=" + [System.Web.HttpUtility]::UrlEncode($filter)
$devices = Invoke-RestMethod -Uri $url -Headers $headers
```

### Error Handling

```powershell
try {
    $response = Invoke-RestMethod -Uri $url -Headers $headers -Method Get
} catch {
    $statusCode = $_.Exception.Response.StatusCode.value__
    $errorBody = $_.ErrorDetails.Message | ConvertFrom-Json
    
    switch ($statusCode) {
        400 { Write-Error "Bad Request: $($errorBody.message)" }
        401 { Write-Error "Unauthorized: Token may be expired" }
        403 { Write-Error "Forbidden: Insufficient permissions" }
        404 { Write-Error "Not Found: Resource does not exist" }
        429 { Write-Error "Rate Limited: Retry after $($_.Exception.Response.Headers['Retry-After']) seconds" }
        500 { Write-Error "Server Error: $($errorBody.message)" }
        default { Write-Error "HTTP $($statusCode): $($errorBody.message)" }
    }
    throw
}
```

## Core Endpoints

### Organizations

```powershell
# List all organizations
$orgs = Invoke-RestMethod -Uri "$baseUrl/organizations" -Headers $headers

# Get organization details
$org = Invoke-RestMethod -Uri "$baseUrl/organization/$orgId" -Headers $headers

# Create organization
$newOrg = @{
    name = "New Organization"
    description = "Created via API"
    nodeApprovalMode = "AUTOMATIC"
}
$created = Invoke-RestMethod -Uri "$baseUrl/organizations" -Headers $headers -Method Post -Body ($newOrg | ConvertTo-Json) -ContentType "application/json"

# Update organization
$update = @{
    name = "Updated Name"
    description = "Updated description"
}
$updated = Invoke-RestMethod -Uri "$baseUrl/organization/$orgId" -Headers $headers -Method Patch -Body ($update | ConvertTo-Json) -ContentType "application/json"
```

### Devices

```powershell
# List all devices
$devices = Invoke-RestMethod -Uri "$baseUrl/devices" -Headers $headers

# Get device details
$device = Invoke-RestMethod -Uri "$baseUrl/device/$deviceId" -Headers $headers

# Update device
$update = @{
    displayName = "Updated Device Name"
    nodeRoleId = 123
}
$updated = Invoke-RestMethod -Uri "$baseUrl/device/$deviceId" -Headers $headers -Method Patch -Body ($update | ConvertTo-Json) -ContentType "application/json"

# Approve pending device
$approve = @{
    devices = @($deviceId)
}
Invoke-RestMethod -Uri "$baseUrl/devices/approval/APPROVE" -Headers $headers -Method Post -Body ($approve | ConvertTo-Json) -ContentType "application/json"
```

### Custom Fields

```powershell
# Get device custom fields
$fields = Invoke-RestMethod -Uri "$baseUrl/device/$deviceId/custom-fields" -Headers $headers

# Update custom field values - body is a flat object keyed by field name
$update = @{
    FieldName  = "New Value"
    OtherField = 42
}
Invoke-RestMethod -Uri "$baseUrl/device/$deviceId/custom-fields" -Headers $headers -Method Patch -Body ($update | ConvertTo-Json) -ContentType "application/json"

# Get organization custom fields
$orgFields = Invoke-RestMethod -Uri "$baseUrl/organization/$orgId/custom-fields" -Headers $headers
```

### Tags

> **Device/endpoint tags** (the tags set from the console and read in automation with
> `Get-NinjaTag` / `Set-NinjaTag`) have **no public REST API** - they can only be read and
> written from automation scripts running on the agent, or via `ninjarmm-cli tag-get` /
> `tag-set` / `tag-clear`. See the [ninjaone-tags](../ninjaone-tags/SKILL.md) skill.
>
> The `/v2/tag` endpoints are a **separate** feature - **ITAM Asset Tags** (asset-inventory
> labels), not endpoint tags. Don't use them to manage device tags.

### Queries (Reports)

```powershell
# Device health report
$health = Invoke-RestMethod -Uri "$baseUrl/queries/device-health" -Headers $headers

# Custom fields report
$fieldsReport = Invoke-RestMethod -Uri "$baseUrl/queries/custom-fields?fields=FieldName1,FieldName2" -Headers $headers

# Software inventory
$software = Invoke-RestMethod -Uri "$baseUrl/queries/software?df=org=$orgId" -Headers $headers

# OS patches report
$patches = Invoke-RestMethod -Uri "$baseUrl/queries/os-patches?status=PENDING" -Headers $headers
```

### Scripting

```powershell
# Get available scripts for device
$options = Invoke-RestMethod -Uri "$baseUrl/device/$deviceId/scripting/options" -Headers $headers

# Run script on device.
# Library scripts use type = "SCRIPT" with the script id; type = "ACTION" is for built-in
# actions and pairs with a uid (not id).
$runScript = @{
    type = "SCRIPT"
    id = 123
    parameters = "param1=value1"
    runAs = "SYSTEM"
}
Invoke-RestMethod -Uri "$baseUrl/device/$deviceId/script/run" -Headers $headers -Method Post -Body ($runScript | ConvertTo-Json) -ContentType "application/json"
```

### Ticketing

```powershell
# Create ticket
$newTicket = @{
    clientId = $orgId
    ticketFormId = 1
    subject = "API Created Ticket"
    description = @{
        public = $true
        htmlBody = "<p>Ticket description</p>"
    }
    status = "1000"         # status ID (string), not a name - see note below
    priority = "MEDIUM"
    requesterUid = $userUid
}
$ticket = Invoke-RestMethod -Uri "$baseUrl/ticketing/ticket" -Headers $headers -Method Post -Body ($newTicket | ConvertTo-Json) -ContentType "application/json"

# Get ticket
$ticket = Invoke-RestMethod -Uri "$baseUrl/ticketing/ticket/$ticketId" -Headers $headers

# Update ticket
$update = @{
    version = $ticket.version
    clientId = $ticket.clientId
    ticketFormId = $ticket.ticketFormId
    subject = "Updated Subject"
    status = "3000"         # status ID (string) - look IDs up via GET /v2/ticketing/statuses
    requesterUid = $ticket.requesterUid
}
Invoke-RestMethod -Uri "$baseUrl/ticketing/ticket/$ticketId" -Headers $headers -Method Put -Body ($update | ConvertTo-Json) -ContentType "application/json"
```

> **Ticket fields:**
> - `status` is a **status ID string** (for example the default `"1000"`), not a name like
>   `OPEN`. List valid IDs with `GET /v2/ticketing/statuses`.
> - `priority`: `NONE` | `LOW` | `MEDIUM` | `HIGH`.
> - `severity`: `NONE` | `MINOR` | `MODERATE` | `MAJOR` | `CRITICAL`.
> - Required on create: `clientId`, `ticketFormId`, `subject`, `status`.

## Best Practices

### Rate Limiting

- Implement exponential backoff for 429 responses
- Respect `Retry-After` header values
- Batch operations where possible
- Cache frequently accessed data

```powershell
function Invoke-NinjaApiWithRetry {
    param(
        [string]$Uri,
        [hashtable]$Headers,
        [string]$Method = "Get",
        [object]$Body,
        [int]$MaxRetries = 3
    )
    
    $attempt = 0
    do {
        try {
            $params = @{
                Uri = $Uri
                Headers = $Headers
                Method = $Method
            }
            if ($Body) {
                $params.Body = ($Body | ConvertTo-Json -Depth 10)
                $params.ContentType = "application/json"
            }
            
            return Invoke-RestMethod @params
        } catch {
            $attempt++
            $statusCode = $_.Exception.Response.StatusCode.value__
            
            if ($statusCode -eq 429 -and $attempt -lt $MaxRetries) {
                $retryAfter = $_.Exception.Response.Headers['Retry-After']
                if ($retryAfter) {
                    $waitSeconds = [int]$retryAfter
                } else {
                    $waitSeconds = [math]::Pow(2, $attempt)
                }
                Write-Warning "Rate limited. Waiting $waitSeconds seconds..."
                Start-Sleep -Seconds $waitSeconds
            } else {
                throw
            }
        }
    } while ($attempt -lt $MaxRetries)
}
```

### Secure Credential Management

```powershell
# Use environment variables
$clientId = $env:NINJA_CLIENT_ID
$clientSecret = $env:NINJA_CLIENT_SECRET

# Or use Azure Key Vault / AWS Secrets Manager
# Or use PowerShell SecretManagement module
$secret = Get-Secret -Name "NinjaClientSecret" -Vault "MyVault"
```

### Data Validation

```powershell
# Validate response structure
function Assert-NinjaApiResponse {
    param($Response, [string]$ExpectedProperty)
    
    if (-not $Response) {
        throw "Empty response from API"
    }
    
    if ($ExpectedProperty -and -not $Response.PSObject.Properties[$ExpectedProperty]) {
        throw "Expected property '$ExpectedProperty' not found in response"
    }
}

$device = Invoke-RestMethod -Uri "$baseUrl/device/$deviceId" -Headers $headers
Assert-NinjaApiResponse -Response $device -ExpectedProperty "id"
```

## Common Use Cases

### Bulk Device Updates

```powershell
# Update custom field for all devices in organization
$devices = Invoke-RestMethod -Uri "$baseUrl/organization/$orgId/devices" -Headers $headers

foreach ($device in $devices) {
    # Body is a flat object keyed by field name
    $update = @{
        LastAuditDate = (Get-Date).ToString("yyyy-MM-dd")
    }
    
    try {
        Invoke-RestMethod -Uri "$baseUrl/device/$($device.id)/custom-fields" `
            -Headers $headers `
            -Method Patch `
            -Body ($update | ConvertTo-Json) `
            -ContentType "application/json"
        
        Write-Verbose "Updated device: $($device.displayName)"
    } catch {
        Write-Warning "Failed to update device $($device.id): $_"
    }
}
```

### Synchronize with External System

```powershell
# Export device inventory to CSV
$devices = Invoke-RestMethod -Uri "$baseUrl/devices-detailed" -Headers $headers

$inventory = $devices | Select-Object `
    @{N='DeviceID';E={$_.id}},
    @{N='Name';E={$_.displayName}},
    @{N='Organization';E={$_.references.organization.name}},
    @{N='Location';E={$_.references.location.name}},
    @{N='OS';E={$_.system.operatingSystem.name}},
    @{N='LastContact';E={[DateTimeOffset]::FromUnixTimeSeconds($_.lastContact).LocalDateTime}}

$inventory | Export-Csv -Path "ninja_inventory.csv" -NoTypeInformation
```

### Automated Ticket Creation from Alerts

```powershell
# Monitor for critical alerts and create tickets.
# GET /v2/alerts only accepts sourceType, df, lang and tz - filter severity client-side.
$alerts = Invoke-RestMethod -Uri "$baseUrl/alerts" -Headers $headers |
    Where-Object { $_.severity -eq 'CRITICAL' }

foreach ($alert in $alerts) {
    # Check if ticket already exists for this alert
    $existingTicket = $alert.psaTicketId
    
    if (-not $existingTicket) {
        $ticket = @{
            clientId = $alert.device.organizationId
            ticketFormId = 1
            subject = "Critical Alert: $($alert.subject)"
            description = @{
                public = $true
                htmlBody = "<p>$($alert.message)</p><p>Device: $($alert.device.displayName)</p>"
            }
            status = "1000"   # status ID string; see GET /v2/ticketing/statuses
            priority = "HIGH"
            severity = "CRITICAL"
            nodeId = $alert.deviceId
        }
        
        Invoke-RestMethod -Uri "$baseUrl/ticketing/ticket" `
            -Headers $headers `
            -Method Post `
            -Body ($ticket | ConvertTo-Json) `
            -ContentType "application/json"
    }
}
```

## Troubleshooting

| Issue | Solution |
|-------|----------|
| 401 Unauthorized | Check token expiration, regenerate access token |
| 403 Forbidden | Verify API client has required scopes (monitoring, management, control) |
| 404 Not Found | Confirm resource ID is correct and exists |
| 429 Rate Limited | Implement retry logic with exponential backoff |
| 500 Server Error | Check API status page, retry with exponential backoff |
| Empty Response | Verify filters and pagination parameters |
| Parsing Error | Ensure `-ContentType "application/json"` is set for POST/PATCH/PUT |
| `/ws/oauth/authorize` returns `WEB_MGMT_SERVICE` 404 JSON | `client_id` is likely a Client Credentials (machine-to-machine) app; use a **Native** app for the interactive PKCE flow instead |
| Same `WEB_MGMT_SERVICE` 404 JSON after browser redirects to `/ws/oauth/error?error=unauthorized_client&error_description=Invalid+redirect_uri` | The `redirect_uri` your script sent doesn't character-for-character match the app's registered redirect URI (trailing slash is a common culprit) - fix the mismatch, don't force-normalize it |
| Authorize still 404s with correct app type + exact redirect_uri | Try dropping the `ws` prefix: use `/oauth/authorize` and `/oauth/token` instead of `/ws/oauth/authorize` / `/ws/oauth/token` |

## References

- [NinjaOne API Documentation](https://app.ninjarmm.com/apidocs-v2/core-resources)
- OpenAPI Specification: live per-instance at `https://{instance}.ninjarmm.com/apidocs/NinjaRMM-API-v2.yaml`
  (or `.json`); a copy is also in this repo under `reference_material/NinjaRMM-API-v2.yaml`
- [Device Filter Reference](./references/device-filters.md)
- [Advanced Examples](./references/api-examples.md)
- Related Skills:
  - [ninjaone-custom-fields](../ninjaone-custom-fields/SKILL.md) - Use API endpoints for bulk custom field operations across devices
  - [ninjaone-tags](../ninjaone-tags/SKILL.md) - Device/endpoint tags (agent automation + CLI only; no REST API)
  - [ninjaone-environment-variables](../ninjaone-environment-variables/SKILL.md) - Use NINJA_AGENT_NODE_ID for device API calls
  - [ninjaone-script-variables](../ninjaone-script-variables/SKILL.md) - Pass API credentials securely via script variables
