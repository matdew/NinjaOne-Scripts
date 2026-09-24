---
name: ninjaone-wysiwyg
description: HTML formatting, inline styling, Font Awesome 6 icons, Charts.css data visualization, and optional Bootstrap 5 grid for NinjaOne WYSIWYG custom fields. Use when creating visual reports, formatted documentation, status dashboards, data charts, or styled content in custom fields. Supports cards, tables, info cards, stat cards, buttons, tags, and responsive layouts with allowlist-based HTML/CSS security.
---

# NinjaOne WYSIWYG Fields

> ⚠️ **Critical:** HTML styling in WYSIWYG custom fields **must be applied via the API or CLI**. The NinjaOne console editor does not support inline styles, NinjaOne CSS classes, or any of the HTML patterns described in this skill. Always generate and write HTML content programmatically (e.g. via `Set-NinjaProperty` or the REST API).

NinjaOne WYSIWYG fields support HTML, inline styling, Font Awesome 6 icons, Charts.css for data visualization, and optional Bootstrap 5 grid layouts.

## When to Use This Skill

- Create visual status dashboards with cards and color-coded indicators
- Format automation reports with tables, headings, and styled content
- Display data visualizations using Charts.css (bar, line, pie, area charts)
- Build responsive layouts using Bootstrap 5 grid system
- Add Font Awesome icons for visual context and status indicators
- Generate HTML reports from automation scripts
- Create styled documentation with info cards and statistic displays

## Prerequisites

- **Character Limit:** Maximum 200,000 characters per field
- **Auto-Collapse:** Fields > 10,000 characters collapse automatically
- **Field Limit:** Maximum 20 WYSIWYG fields per form/template
- **Styling:** HTML and inline styles **must be applied via API or CLI** — the NinjaOne console editor does not support styled HTML
- **Allowlist-Based:** Only specific HTML elements and styles permitted
- **Editor:** WYSIWYG editor available in NinjaOne console for Knowledge Base (Docs) only — not for custom fields

## Related Skills

- [ninjaone-custom-fields](../ninjaone-custom-fields/SKILL.md) - Use Set-NinjaProperty with -Type "WYSIWYG" to store HTML content
- [ninjaone-cli](../ninjaone-cli/SKILL.md) - Pipe large HTML content using CLI for fields > 10,000 characters
- [ninjaone-tags](../ninjaone-tags/SKILL.md) - Report device tags in formatted WYSIWYG status cards
- [ninjaone-script-variables](../ninjaone-script-variables/SKILL.md) - Configure report styling via script parameters

## Allowed HTML Elements

```html
<a>, <blockquote>, <caption>, <code>, <col>, <div>
<h1> - <h6>, <i>, <li>, <ol>, <p>, <pre>
<span>, <table>, <tbody>, <td>, <tfoot>, <th>, <thead>, <tr>, <ul>
```

**Note:** Most elements support NinjaOne CSS classes except `<code>` and `<pre>`.

## Allowed Inline Styles

> Source: Official NinjaOne WYSIWYG documentation (ninja_wysiwyg.txt)

| Style | Allowed Values |
|---|---|
| `color` | RGB or hex (`rgb(240,30,50,.7)`, `#f015ca`) |
| `background-color` | RGB or hex |
| `display` | `block`, `inline`, `inline-block`, `flex`, `inline-flex` |
| `justify-content` | `center`, `start`, `end`, `flex`, `flex-start`, `flex-end`, `left`, `right`, `normal`, `space-between`, `space-around`, `space-evenly` |
| `align-items` | `center`, `start`, `end`, `flex`, `flex-start`, `flex-end`, `left`, `right`, `normal`, `stretch` |
| `text-align` | `start`, `end`, `left`, `center`, `right`, `justify`, `justify-all`, `match-parent` |
| `word-break` | `normal`, `break-all`, `keep-all`, `break-word` |
| `white-space` | `normal`, `no-wrap`, `pre`, `pre-wrap`, `pre-line`, `break-spaces` |
| `overflow-wrap` | `normal`, `break-word`, `pre`, `anywhere` |
| `box-sizing` | `border-box`, `content-box` |
| `font-size` | Any valid CSS unit (`100%`, `18px`, `2em`, etc.) |
| `font-family` | `serif`, `sans-serif`, `monospace`, `cursive`, `fantasy`, `system-ui`, `emoji` |
| `width` / `height` | Any valid CSS unit (`100%`, `400px`, `auto`, `2em`, etc.) |
| `margin` / `margin-top/right/bottom/left` | Any valid CSS unit |
| `padding` / `padding-top/right/bottom/left` | Any valid CSS unit |
| `border-width` | Any valid CSS unit |
| `border-style` | `none`, `solid`, `dashed`, `inset`, `outset` |
| `border-color` | RGB or hex |
| `border-top/right/bottom/left` | Any valid CSS unit |
| `border-radius` | Any valid CSS unit |
| `border-collapse` | `collapse`, `separate` |

> **Note:** `grid` is NOT in the allowed `display` values. Use `flex` for layout instead.
> `white-space: no-wrap` uses a hyphen (NinjaOne's listed form); standard CSS is `nowrap`.

## NinjaOne CSS Classes

### Card Width

NinjaOne's rendering context acts as a Bootstrap container, so `row`/`col-*` classes work
directly inside WYSIWYG field content — no explicit `<div class="container">` wrapper is needed
or allowed.

For a **single full-width card**, wrap it in `row` → `col-12 d-flex`. The `d-flex` class is
required to make `flex-grow-1` work — without a flex parent, `flex-grow-1` is ignored:

```powershell
# Single full-width card
$html = @"
<div class="row"><div class="col-12 d-flex">
<div class="card flex-grow-1">
  <div class="card-title-box">
    <div class="card-title"><i class="fas fa-server"></i>&nbsp;&nbsp;Status</div>
  </div>
  <div class="card-body">
    Content here
  </div>
</div>
</div></div>
"@
```

For **multiple cards side by side**, use Bootstrap's grid inside the field (no container needed):

```powershell
# Multi-card grid layout
$html = @"
<div class="row g-3">
  <div class="col-xl-6 col-md-12 d-flex">
    <div class="card flex-grow-1">...</div>
  </div>
  <div class="col-xl-6 col-md-12 d-flex">
    <div class="card flex-grow-1">...</div>
  </div>
</div>
"@
```

The card column span (how wide the form column itself is) is configured in the NinjaOne
form/template editor and cannot be changed from script output.

### Cards

```powershell
# Standard card (use row/col-12 wrapper above for full-width)
$card = @"
<div class="card flex-grow-1">
  <div class="card-title-box">
    <div class="card-title"><i class="fas fa-server"></i>&nbsp;&nbsp;Server Status</div>
  </div>
  <div class="card-body">
    <p><b>Status:</b> Online</p>
  </div>
</div>
"@

# Card with action link
$cardWithLink = @"
<div class="card flex-grow-1">
  <div class="card-title-box">
    <div class="card-title">Title</div>
    <div class="card-link-box">
      <a href="https://example.com" target="_blank" class="card-link">
        <i class="fas fa-arrow-up-right-from-square"></i>
      </a>
    </div>
  </div>
  <div class="card-body">Content</div>
</div>
"@
```

### Tables with Status

```powershell
$table = @"
<table>
  <thead>
    <tr><th>Service</th><th>Status</th></tr>
  </thead>
  <tbody>
    <tr class="success"><td>Web Server</td><td>Running</td></tr>
    <tr class="danger"><td>Database</td><td>Stopped</td></tr>
    <tr class="warning"><td>Mail</td><td>Degraded</td></tr>
    <tr class="other"><td>Backup</td><td>Skipped</td></tr>
    <tr class="unknown"><td>Monitor</td><td>Unknown</td></tr>
  </tbody>
</table>
"@
```

### Info Cards

> **Important:** The `<i class="info-icon ...">` element is a **required structural part** of the
> `info-card` component. Omitting it leaves a visual gap in the layout. Always include the icon.

```powershell
# Informational (default — no modifier class)
$info = @"
<div class="info-card">
  <i class="info-icon fa-solid fa-circle-info"></i>
  <div class="info-text">
    <div class="info-title">Informational title</div>
    <div class="info-description">Description text here.</div>
  </div>
</div>
"@

# Success
$success = @"
<div class="info-card success">
  <i class="info-icon fa-solid fa-circle-check"></i>
  <div class="info-text">
    <div class="info-title">Success</div>
    <div class="info-description">Operation completed</div>
  </div>
</div>
"@

# Error
$errorCard = @"
<div class="info-card error">
  <i class="info-icon fa-solid fa-circle-exclamation"></i>
  <div class="info-text">
    <div class="info-title">Error</div>
    <div class="info-description">Service stopped</div>
  </div>
</div>
"@

# Warning
$warning = @"
<div class="info-card warning">
  <i class="info-icon fa-solid fa-triangle-exclamation"></i>
  <div class="info-text">
    <div class="info-title">Warning</div>
    <div class="info-description">Low disk space</div>
  </div>
</div>
"@
```

### Statistic Cards

```powershell
$statCard = @"
<div class="stat-card">
  <div class="stat-value">
    <span style="color: #008001;">25</span>
  </div>
  <div class="stat-desc">
    <span style="font-size: 18px;">Active Users</span>
  </div>
</div>
"@
```

### Buttons

```powershell
$buttons = @"
<a href="https://example.com" target="_blank" class="btn">Primary Button</a>
<a href="https://example.com" target="_blank" class="btn secondary">Secondary Button</a>
<a href="https://example.com" target="_blank" class="btn danger">Danger Button</a>
"@
```

### Tags

```powershell
$tags = @"
<div class="tag">Enabled</div>
<div class="tag disabled">Disabled</div>
<div class="tag expired">Expired</div>
"@
```

### Line Chart (Simple)

```powershell
$lineChart = @"
<div class="p-3 linechart">
  <div style="width: 33.33%; background-color: #55ACBF;"></div>
  <div style="width: 33.33%; background-color: #3633B7;"></div>
  <div style="width: 33.33%; background-color: #8063BF;"></div>
</div>
<ul class="unstyled p-3" style="display: flex; justify-content: space-between;">
  <li><span class="chart-key" style="background-color: #55ACBF;"></span><span>Licensed (20)</span></li>
  <li><span class="chart-key" style="background-color: #3633B7;"></span><span>Unlicensed (20)</span></li>
  <li><span class="chart-key" style="background-color: #8063BF;"></span><span>Guests (20)</span></li>
</ul>
"@
```

### NinjaOne Utility Classes

```powershell
# Flexbox utilities
".d-flex"           # Display flex
".flex-grow-1"      # Flex grow

# Spacing
".p-3"    # Padding 3

# Lists
".unstyled"  # Remove list styling
```

## Font Awesome 6 Icons

```powershell
# Common icons
$icons = @"
<i class="fas fa-server"></i> Server
<i class="fas fa-database"></i> Database
<i class="fas fa-shield-halved"></i> Security
<i class="fas fa-circle-check"></i> Success
<i class="fas fa-circle-xmark"></i> Error
<i class="fas fa-triangle-exclamation"></i> Warning
<i class="fas fa-circle-info"></i> Information
"@
```

## Charts.css Support

### Column Chart

```powershell
$columnChart = @"
<table class="charts-css column show-heading">
  <tbody>
    <tr><td style="--size: 0.4"><span class="data">40%</span></td></tr>
    <tr><td style="--size: 0.6"><span class="data">60%</span></td></tr>
    <tr><td style="--size: 0.75"><span class="data">75%</span></td></tr>
  </tbody>
</table>
"@
```

### Bar Chart

```powershell
$barChart = @"
<table class="charts-css bar show-heading">
  <tbody>
    <tr><td style="--size: 0.4"><span class="data">40%</span></td></tr>
    <tr><td style="--size: 0.6"><span class="data">60%</span></td></tr>
  </tbody>
</table>
"@
```

### Pie Chart

```powershell
$pieChart = @"
<div style="height:300px; width:300px;">
  <table class="charts-css pie show-heading">
    <tbody>
      <tr><th scope="row">Cat 1</th><td style="--start: 0; --end: 0.2;"><span class="data">20%</span></td></tr>
      <tr><th scope="row">Cat 2</th><td style="--start: 0.2; --end: 0.5;"><span class="data">30%</span></td></tr>
    </tbody>
  </table>
</div>
"@
```

### Line Chart

```powershell
$lineChart = @"
<table class="charts-css line multiple show-data-on-hover show-labels show-primary-axis show-10-secondary-axes show-heading">
  <tbody>
    <tr>
      <th scope="row">21-03</th>
      <td style="--start: 0.1; --end: 0.3;"><span class="data">30</span></td>
      <td style="--start: 0.6; --end: 0.4;"><span class="data">40</span></td>
      <td style="--start: 0.8; --end: 0.7;"><span class="data">70</span></td>
    </tr>
    <tr>
      <th scope="row">20-03</th>
      <td style="--start: 0.3; --end: 0.1;"><span class="data">10</span></td>
      <td style="--start: 0.4; --end: 0.6;"><span class="data">60</span></td>
      <td style="--start: 0.7; --end: 0.9;"><span class="data">90</span></td>
    </tr>
  </tbody>
</table>
<ul class="charts-css legend legend-inline legend-rectangle">
  <li>C:</li>
  <li>D:</li>
  <li>CPU</li>
  <li>Memory</li>
</ul>
"@
```

### Area Chart

```powershell
$areaChart = @"
<table class="charts-css area show-heading">
  <tbody>
    <tr>
      <th scope="row">21-03</th>
      <td style="--start: 0.1; --end: 0.3;"><span class="data">30</span></td>
      <td style="--start: 0.6; --end: 0.4;"><span class="data">40</span></td>
    </tr>
    <tr>
      <th scope="row">20-03</th>
      <td style="--start: 0.3; --end: 0.1;"><span class="data">10</span></td>
      <td style="--start: 0.4; --end: 0.6;"><span class="data">60</span></td>
    </tr>
  </tbody>
</table>
"@
```

### Chart Modifiers

```powershell
# Show data on hover
"charts-css column show-data-on-hover"

# Show all data
"charts-css column show-heading"

# Show axes
"charts-css line show-primary-axis show-10-secondary-axes"

# Show labels
"charts-css line show-labels"
```

## Advanced Layout: Bootstrap 5 Grid (Optional)

Bootstrap's grid system is available for complex responsive layouts when needed.

### Breakpoints

| Breakpoint | Size | Class Prefix |
|------------|------|--------------|
| Extra small (xs) | <576px | `.col-` |
| Small (sm) | ≥576px | `.col-sm-` |
| Medium (md) | ≥768px | `.col-md-` |
| Large (lg) | ≥992px | `.col-lg-` |
| Extra large (xl) | ≥1200px | `.col-xl-` |
| Extra extra large (xxl) | ≥1400px | `.col-xxl-` |

### Basic Grid Examples

```powershell
# Three equal columns
$html = @"
<div class="row">
  <div class="col">Column 1</div>
  <div class="col">Column 2</div>
  <div class="col">Column 3</div>
</div>
"@

# Responsive: stacked mobile, horizontal tablet+
$html = @"
<div class="row">
  <div class="col-sm-8">Main content</div>
  <div class="col-sm-4">Sidebar</div>
</div>
"@

# Mixed breakpoints
$html = @"
<div class="row">
  <div class="col-6 col-md-4">Responsive column</div>
  <div class="col-6 col-md-8">Another column</div>
</div>
"@
```

### Row Columns

Control the number of columns directly on the row:

```powershell
# Two columns per row
$html = @"
<div class="row row-cols-2">
  <div class="col">Column</div>
  <div class="col">Column</div>
  <div class="col">Column</div>
  <div class="col">Column</div>
</div>
"@

# Responsive columns: 1 on mobile, 2 on small, 4 on medium+
$html = @"
<div class="row row-cols-1 row-cols-sm-2 row-cols-md-4">
  <div class="col">Column</div>
  <div class="col">Column</div>
  <div class="col">Column</div>
  <div class="col">Column</div>
</div>
"@

# Auto-width columns
$html = @"
<div class="row row-cols-auto">
  <div class="col">Column</div>
  <div class="col">Column</div>
  <div class="col">Column</div>
</div>
"@
```

### Nesting

```powershell
$html = @"
<div class="row">
  <div class="col-sm-9">
    <div class="row">
      <div class="col-8 col-sm-6">Nested Level 2</div>
      <div class="col-4 col-sm-6">Nested Level 2</div>
    </div>
  </div>
</div>
"@
```

### Gutters

```powershell
# No gutters
$html = '<div class="row g-0"><div class="col">No spacing</div></div>'

# Custom gutters
$html = '<div class="row g-3"><div class="col">3 spacing</div></div>'

# Horizontal only
$html = '<div class="row gx-5"><div class="col">Horizontal spacing</div></div>'

# Vertical only
$html = '<div class="row gy-3"><div class="col">Vertical spacing</div></div>'
```

### Additional Grid Utilities

```powershell
# Alignment
".justify-content-between"  # Space between
".align-items-center"       # Center align
".justify-content-center"   # Center justify
".align-items-start"        # Top align

# Gaps
".g-3"    # Gap 3 (all sides)
".gx-5"   # Horizontal gap 5
".gy-3"   # Vertical gap 3
".g-0"    # No gap
```

## Using Piped Commands

For large HTML content, use piped commands:

```powershell
$html = @"
<div class="card">
  <div class="card-body">Large content here...</div>
</div>
"@

# Pipe to NinjaOne field
$html | Ninja-Property-Set-Piped "FieldName"
```

## Complete Report Example

```powershell
<#
.SYNOPSIS
    Generates system information report in WYSIWYG field.
#>

[CmdletBinding()]
param()

# Collect data
$os = Get-CimInstance Win32_OperatingSystem
$cpuUsage = (Get-Counter '\Processor(_Total)\% Processor Time').CounterSamples.CookedValue
$memoryPercent = [math]::Round((($os.TotalVisibleMemorySize - $os.FreePhysicalMemory) / $os.TotalVisibleMemorySize) * 100, 2)

# Build HTML using simple inline styling
$html = @"
<div style="display: flex; gap: 1rem; flex-wrap: wrap;">
  
  <!-- Overview Card -->
  <div class="card flex-grow-1" style="min-width: 300px;">
    <div class="card-title-box">
      <div class="card-title"><i class="fas fa-desktop"></i>&nbsp;&nbsp;System</div>
    </div>
    <div class="card-body">
      <p><b>Computer:</b> $($env:COMPUTERNAME)</p>
      <p><b>OS:</b> $($os.Caption)</p>
      <p><b>Uptime:</b> $([math]::Round((New-TimeSpan -Start $os.LastBootUpTime).TotalDays, 2)) days</p>
    </div>
  </div>
  
  <!-- Resource Usage -->
  <div class="card flex-grow-1" style="min-width: 300px;">
    <div class="card-title-box">
      <div class="card-title"><i class="fas fa-chart-line"></i>&nbsp;&nbsp;Resources</div>
    </div>
    <div class="card-body">
      <table class="charts-css bar show-heading">
        <tbody>
          <tr><th>CPU</th><td style="--size: $([math]::Round($cpuUsage / 100, 2));"><span class="data">$([math]::Round($cpuUsage, 1))%</span></td></tr>
          <tr><th>Memory</th><td style="--size: $([math]::Round($memoryPercent / 100, 2));"><span class="data">$($memoryPercent)%</span></td></tr>
        </tbody>
      </table>
    </div>
  </div>
  
</div>
"@

# Set WYSIWYG field
Set-NinjaProperty -Name "SystemReport" -Value $html -Type "WYSIWYG"
Write-Output "Report generated successfully"
exit 0
```

## Best Practices

1. **HTML/CSS First** - Use inline styles and flexbox for simple layouts
2. **NinjaOne Classes** - Leverage built-in card, table, and info card styles
3. **Card Width is a Form Setting** - WYSIWYG field column span is set in the NinjaOne form template editor. Use `flex-grow-1` on the card; use `row`/`col-*` (no container wrapper needed) for multi-card side-by-side layouts
4. **Meaningful Icons** - Font Awesome icons provide visual context; limit to card titles and key indicators to avoid visual clutter
5. **Status Indicators** - Color-coded rows and info cards for quick scanning
6. **Character Limits** - Stay under 200,000; optimize for 10,000
7. **Sanitize Input** - Escape HTML characters in user data
8. **Charts for Data** - Use Charts.css for visual data representation
9. **Piped Data** - Use for large content (via CLI)
10. **Test Rendering** - Verify in NinjaOne before production
11. **Semantic HTML** - Use appropriate heading levels and semantic elements
12. **Accessibility** - Include meaningful text for icons and links
13. **Grid When Needed** - Use Bootstrap grid for complex responsive requirements
