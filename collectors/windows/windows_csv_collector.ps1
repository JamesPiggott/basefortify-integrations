# Output
$OutPath = "$env:USERPROFILE\Desktop\basefortify_components.csv"

# --- Host / OS context ---
$csProduct = Get-CimInstance Win32_ComputerSystemProduct
$os        = Get-CimInstance Win32_OperatingSystem
$nodeName  = $env:COMPUTERNAME
$deviceId  = $csProduct.UUID
$arch      = $os.OSArchitecture
$osName    = $os.Caption
$osVersion = $os.Version
$osBuild   = $os.BuildNumber

$hf = Get-HotFix -ErrorAction SilentlyContinue | Sort-Object InstalledOn -Descending | Select-Object -First 1
$latestKbId   = if ($hf) { $hf.HotFixID } else { $null }
$latestKbDate = if ($hf) { $hf.InstalledOn } else { $null }

function Normalize([string]$s) {
  if ([string]::IsNullOrWhiteSpace($s)) { return $null }
  return (($s -replace '\s+', ' ').Trim()).ToLowerInvariant()
}

# --- Registry uninstall (don’t filter SystemComponent) ---
function Get-UninstallEntriesFromPath {
  param([string]$Path)
  if (-not (Test-Path $Path)) { return @() }
  $rows = @()
  foreach ($k in Get-ChildItem $Path -ErrorAction SilentlyContinue) {
    try {
      $p = Get-ItemProperty $k.PsPath -ErrorAction Stop
      if ($p.DisplayName) {
        $rows += [PSCustomObject]@{
          vendor         = $p.Publisher
          product        = $p.DisplayName
          version        = $p.DisplayVersion
          node           = $nodeName
          device_id      = $deviceId
          os_name        = $osName
          os_version     = $osVersion
          os_build       = $osBuild
          arch           = $arch
          latest_kb      = $latestKbId
          latest_kb_date = $latestKbDate
          source         = "Registry"
        }
      }
    } catch {}
  }
  return $rows
}

$regPaths = @(
  "HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall",
  "HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall",
  "HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall"
)
$regUninstall = @()
foreach ($p in $regPaths) { $regUninstall += Get-UninstallEntriesFromPath -Path $p }

# --- MSI InstallProperties (often has Publisher) ---
function Get-MSIInstallProps {
  $base = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Installer\UserData"
  if (-not (Test-Path $base)) { return @() }
  $rows = @()
  $paths = Get-ChildItem -Recurse -ErrorAction SilentlyContinue "$base\*\Products\*\InstallProperties"
  foreach ($ip in $paths) {
    try {
      $p = Get-ItemProperty $ip.PsPath -ErrorAction Stop
      if ($p.DisplayName -and $p.DisplayVersion) {
        $rows += [PSCustomObject]@{
          vendor         = $p.Publisher
          product        = $p.DisplayName
          version        = $p.DisplayVersion
          node           = $nodeName
          device_id      = $deviceId
          os_name        = $osName
          os_version     = $osVersion
          os_build       = $osBuild
          arch           = $arch
          latest_kb      = $latestKbId
          latest_kb_date = $latestKbDate
          source         = "MSI"
        }
      }
    } catch {}
  }
  return $rows
}
$msiProps = Get-MSIInstallProps

# --- Build a first-class OS component row ---
function Get-OsComponentRow {
  try {
    $cvKey = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion'
    $cv    = Get-ItemProperty -Path $cvKey -ErrorAction Stop

    # Use CIM caption as the authoritative name (it already says "Microsoft Windows 11 Pro")
    $caption        = "$($os.Caption)"               # e.g., "Microsoft Windows 11 Pro"
    $winProductName = ($caption -replace '^Microsoft\s+', '') # -> "Windows 11 Pro"

    $displayVersion = if ($cv.DisplayVersion) { "$($cv.DisplayVersion)" } else { $null }
    $ubr            = if ($cv.UBR -ne $null) { [string]$cv.UBR } else { $null }

    # Version string for BF: OSVersion + .UBR (precise build)
    $winVersion = if ($ubr) { "$($os.Version).$ubr" } else { "$($os.Version)" }

    # Extra context in source
    $src = if ($displayVersion) { "OS ($displayVersion)" } else { "OS" }

    # Safety correction: if some caption still says Windows 10 but build >= 22000, call it Windows 11
    if ($winProductName -match 'Windows 10' -and [int]$os.BuildNumber -ge 22000) {
      $winProductName = $winProductName -replace 'Windows 10','Windows 11'
    }

    return [PSCustomObject]@{
      vendor         = 'Microsoft'
      product        = $winProductName         # e.g., "Windows 11 Pro"
      version        = $winVersion             # e.g., "10.0.26100.6899"
      node           = $nodeName
      device_id      = $deviceId
      os_name        = $osName
      os_version     = $osVersion
      os_build       = $osBuild
      arch           = $arch
      latest_kb      = $latestKbId
      latest_kb_date = $latestKbDate
      source         = $src
    }
  } catch {
    # Fallback: CIM-only values
    return [PSCustomObject]@{
      vendor         = 'Microsoft'
      product        = ($os.Caption -replace '^Microsoft\s+', '')
      version        = "$($os.Version)"
      node           = $nodeName
      device_id      = $deviceId
      os_name        = $osName
      os_version     = $osVersion
      os_build       = $osBuild
      arch           = $arch
      latest_kb      = $latestKbId
      latest_kb_date = $latestKbDate
      source         = 'OS'
    }
  }
}

$osRow = Get-OsComponentRow

# --- Build vendor index from Registry + MSI (by product name) ---
$vendorByName = @{}
foreach ($row in ($regUninstall + $msiProps)) {
  $k = Normalize $row.product
  if ($k -and $row.vendor -and -not $vendorByName.ContainsKey($k)) {
    $vendorByName[$k] = $row.vendor
  }
}

# --- Optional: winget enrichment (if available) ---
$wingetMapById = @{}
$wingetMapByName = @{}
try {
  $wingetCmd = Get-Command winget -ErrorAction Stop
  $json = & $wingetCmd.Source list --accept-source-agreements --accept-package-agreements --source winget --output json 2>$null
  if ($LASTEXITCODE -eq 0 -and $json) {
    $list = $json | ConvertFrom-Json
    foreach ($pkg in $list) {
      $pub = $pkg.Publisher
      if (-not [string]::IsNullOrWhiteSpace($pub)) {
        if ($pkg.Id)   { $wingetMapById[$pkg.Id] = $pub }
        if ($pkg.Name) { $wingetMapByName[(Normalize $pkg.Name)] = $pub }
      }
    }
  }
} catch {}

# --- PackageManager rows with vendor backfill ---
$pkgApps = @()
$gps = Get-Package -ErrorAction SilentlyContinue
foreach ($x in $gps) {
  $name    = $x.Name
  $version = if ($x.Version) { "$($x.Version)" } else { $null }
  $vendor  = $null

  # Native publisher if present
  if ($x.PSObject.Properties['Publisher'] -and -not [string]::IsNullOrWhiteSpace($x.Publisher)) {
    $vendor = $x.Publisher
  }

  # If winget, try Id + Name
  $prov = $x.PSObject.Properties['ProviderName'].Value
  if (-not $vendor -and $prov -and $prov -eq 'winget') {
    $wingetId = $x.PSObject.Properties['Id'].Value
    if ($wingetId -and $wingetMapById.ContainsKey($wingetId)) { $vendor = $wingetMapById[$wingetId] }
    if (-not $vendor -and $name) {
      $nk = Normalize $name
      if ($nk -and $wingetMapByName.ContainsKey($nk)) { $vendor = $wingetMapByName[$nk] }
    }
  }

  # Fall back to Registry/MSI by product name
  if (-not $vendor -and $name) {
    $nk = Normalize $name
    if ($nk -and $vendorByName.ContainsKey($nk)) { $vendor = $vendorByName[$nk] }
  }

  $pkgApps += [PSCustomObject]@{
    vendor         = $vendor
    product        = $name
    version        = $version
    node           = $nodeName
    device_id      = $deviceId
    os_name        = $osName
    os_version     = $osVersion
    os_build       = $osBuild
    arch           = $arch
    latest_kb      = $latestKbId
    latest_kb_date = $latestKbDate
    source         = if ($prov) { "PackageManager/$prov" } else { "PackageManager" }
  }
}

# --- Combine & pick best per product|version ---
function Get-RowScore($row) {
  $score = 0
  if (-not [string]::IsNullOrWhiteSpace($row.vendor)) { $score += 1 }
  if ($row.source -eq 'Registry' -or $row.source -eq 'MSI') { $score += 1 }
  return $score
}

$best = @{}
foreach ($r in (@($regUninstall) + @($msiProps) + @($pkgApps) + @($osRow))) {
  if ([string]::IsNullOrWhiteSpace($r.product) -or [string]::IsNullOrWhiteSpace($r.version)) { continue }
  $key = "$(Normalize $r.product)|$(Normalize $r.version)"
  if (-not $best.ContainsKey($key)) {
    $best[$key] = $r
  } else {
    $cur = $best[$key]
    if ( (Get-RowScore $r) -gt (Get-RowScore $cur) ) { $best[$key] = $r }
  }
}

$final = $best.Values | Sort-Object vendor, product
$final | Export-Csv -NoTypeInformation -Encoding UTF8 -Path $OutPath
Write-Host "Wrote $($final.Count) rows to: $OutPath"
