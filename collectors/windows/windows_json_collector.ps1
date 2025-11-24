# BaseFortify – JSON Export (PowerShell)
# Outputs to: %USERPROFILE%\Desktop\basefortify_components.json

$OutPath = Join-Path $env:USERPROFILE 'Desktop\basefortify_components.json'

# --- Host / OS context ---
$csProduct = Get-CimInstance Win32_ComputerSystemProduct -ErrorAction SilentlyContinue
$os        = Get-CimInstance Win32_OperatingSystem -ErrorAction SilentlyContinue

$nodeName  = $env:COMPUTERNAME
$deviceId  = if ($csProduct) { $csProduct.UUID } else { $null }
$arch      = if ($os) { $os.OSArchitecture } else { $env:PROCESSOR_ARCHITECTURE }
$osName    = if ($os) { $os.Caption } else { $null }
$osVersion = if ($os) { $os.Version } else { $null }
$osBuild   = if ($os) { $os.BuildNumber } else { $null }

$hf = Get-HotFix -ErrorAction SilentlyContinue | Sort-Object InstalledOn -Descending | Select-Object -First 1
$latestKbId   = if ($hf) { $hf.HotFixID } else { $null }
$latestKbDate = if ($hf) { $hf.InstalledOn } else { $null }

function Normalize([string]$s) {
  if ([string]::IsNullOrWhiteSpace($s)) { return $null }
  return (($s -replace '\s+', ' ').Trim()).ToLowerInvariant()
}

# --- OS component row ---
function Get-OsComponentRow {
  try {
    $caption     = "$($os.Caption)"
    $productName = ($caption -replace '^Microsoft\s+', '') # e.g. Windows 11 Pro
    $cpeVersion  = if ($os.Version -match '^\d+\.\d+\.\d+') { $Matches[0] } else { $os.Version }
    if ($productName -match 'Windows 10' -and [int]$os.BuildNumber -ge 22000) {
      $productName = $productName -replace 'Windows 10','Windows 11'
    }
    return [PSCustomObject]@{
      vendor         = 'Microsoft'
      product        = $productName
      version        = $cpeVersion
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
  } catch {
    return $null
  }
}

# --- Installed programs (registry + MSI) ---
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
          source         = 'Registry'
        }
      }
    } catch {}
  }
  return $rows
}

$regPaths = @(
  'HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall',
  'HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall',
  'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall'
)
$regUninstall = @()
foreach ($p in $regPaths) { $regUninstall += Get-UninstallEntriesFromPath -Path $p }

function Get-MSIInstallProps {
  $base = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Installer\UserData'
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
          source         = 'MSI'
        }
      }
    } catch {}
  }
  return $rows
}
$msiProps = Get-MSIInstallProps

# --- Combine and add OS row ---
$rows = @()
$rows += Get-OsComponentRow
$rows += $regUninstall
$rows += $msiProps

# --- Filter and export to JSON ---
$valid = $rows | Where-Object { $_.product -and $_.version } | Sort-Object vendor, product
$valid | ConvertTo-Json -Depth 4 | Out-File -FilePath $OutPath -Encoding UTF8
Write-Host "Wrote $($valid.Count) entries to: $OutPath"
