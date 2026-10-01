# check-pc-storage.ps1 — Finds what is eating your disk space and slowing your PC.
#
# SAFE: this script only LOOKS. It does not delete anything.
#
# HOW TO RUN (Windows):
#   1. Download this file to your PC.
#   2. Right-click the Start button -> "Terminal" (or "Windows PowerShell").
#   3. Type:  powershell -ExecutionPolicy Bypass -File "C:\path\to\check-pc-storage.ps1"
#      (drag the file into the window to paste its path automatically)
#   4. Copy everything it prints and paste it back to Claude.

# A "function" is a reusable chunk of code. This one takes a folder path and
# returns its total size in GB. We'll call it many times below.
function Get-FolderSizeGB($path) {
    # Test-Path checks the folder exists, so we don't crash on missing folders.
    if (-not (Test-Path $path)) { return 0 }
    # Get-ChildItem lists every file inside (-Recurse = including subfolders).
    # -ErrorAction SilentlyContinue skips files Windows won't let us read.
    # Measure-Object -Sum adds up all the file sizes (in bytes).
    $bytes = (Get-ChildItem $path -Recurse -File -Force -ErrorAction SilentlyContinue |
              Measure-Object -Property Length -Sum).Sum
    # Convert bytes -> gigabytes (1 GB = 1024^3 bytes) and round to 2 decimals.
    return [math]::Round(($bytes / 1GB), 2)
}

Write-Host "`n===== 1. DRIVE SPACE =====" -ForegroundColor Cyan
# Shows every drive, how big it is, and how much is free.
Get-PSDrive -PSProvider FileSystem | Where-Object { $_.Used -ne $null } | ForEach-Object {
    $total = ($_.Used + $_.Free) / 1GB
    $free  = $_.Free / 1GB
    $pct   = if ($total -gt 0) { [math]::Round(($free / $total) * 100, 1) } else { 0 }
    # Windows slows down when less than ~10-15% of the drive is free.
    $warn  = if ($pct -lt 15) { "  <-- LOW! This alone can make your PC slow." } else { "" }
    "{0}:  {1:N1} GB free of {2:N1} GB ({3}% free){4}" -f $_.Name, $free, $total, $pct, $warn
}

Write-Host "`n===== 2. USUAL SUSPECTS (sizes in GB) =====" -ForegroundColor Cyan
# $env:USERPROFILE is your user folder, e.g. C:\Users\Isaiah
# $env:TEMP is Windows' temporary-files folder.
# The @{ } below is a list of "name = path" pairs to check.
$suspects = [ordered]@{
    "Blender default render folder (C:\tmp)" = "C:\tmp"
    "Windows temp files"                     = $env:TEMP
    "Downloads"                              = "$env:USERPROFILE\Downloads"
    "Videos"                                 = "$env:USERPROFILE\Videos"
    "Pictures"                               = "$env:USERPROFILE\Pictures"
    "Documents"                              = "$env:USERPROFILE\Documents"
    "Desktop"                                = "$env:USERPROFILE\Desktop"
    "Blender settings/add-ons"               = "$env:APPDATA\Blender Foundation"
    "Windows Update cache"                   = "C:\Windows\SoftwareDistribution\Download"
    "Recycle Bin"                            = "C:\`$Recycle.Bin"
}
foreach ($name in $suspects.Keys) {
    "{0,-42} {1,8} GB" -f $name, (Get-FolderSizeGB $suspects[$name])
}

Write-Host "`n===== 3. BIGGEST FOLDERS IN YOUR USER FOLDER =====" -ForegroundColor Cyan
Write-Host "(this can take a minute...)"
# Check each top-level folder in C:\Users\<you>, then sort biggest first, show top 10.
Get-ChildItem $env:USERPROFILE -Directory -Force -ErrorAction SilentlyContinue | ForEach-Object {
    [PSCustomObject]@{ Folder = $_.Name; SizeGB = (Get-FolderSizeGB $_.FullName) }
} | Sort-Object SizeGB -Descending | Select-Object -First 10 | Format-Table -AutoSize

Write-Host "===== 4. BLENDER CLUTTER =====" -ForegroundColor Cyan
# Search your user folder for Blender backup files (.blend1, .blend2...) and bake caches.
$blendBackups = Get-ChildItem $env:USERPROFILE -Recurse -File -Force -Include *.blend1,*.blend2,*.blend3 -ErrorAction SilentlyContinue
$backupGB = [math]::Round((($blendBackups | Measure-Object Length -Sum).Sum / 1GB), 2)
"Blender .blend1/.blend2 backup files: {0} files, {1} GB" -f $blendBackups.Count, $backupGB

$caches = Get-ChildItem $env:USERPROFILE -Recurse -Directory -Force -ErrorAction SilentlyContinue |
          Where-Object { $_.Name -like "cache_*" -or $_.Name -like "blendcache_*" }
foreach ($c in $caches) { "Bake cache: {0}  ({1} GB)" -f $c.FullName, (Get-FolderSizeGB $c.FullName) }
if (-not $caches) { "No Blender bake cache folders found." }

Write-Host "`n===== 5. 15 BIGGEST SINGLE FILES =====" -ForegroundColor Cyan
Get-ChildItem $env:USERPROFILE -Recurse -File -Force -ErrorAction SilentlyContinue |
    Sort-Object Length -Descending | Select-Object -First 15 |
    ForEach-Object { "{0,8:N2} GB  {1}" -f ($_.Length / 1GB), $_.FullName }

Write-Host "`n===== 6. WHAT'S USING YOUR PC RIGHT NOW (slowness) =====" -ForegroundColor Cyan
# Total RAM vs. free RAM.
$os = Get-CimInstance Win32_OperatingSystem
"RAM: {0:N1} GB free of {1:N1} GB" -f ($os.FreePhysicalMemory / 1MB), ($os.TotalVisibleMemorySize / 1MB)
"`nTop 10 programs by memory use:"
Get-Process | Sort-Object WorkingSet64 -Descending | Select-Object -First 10 |
    ForEach-Object { "{0,8:N0} MB  {1}" -f ($_.WorkingSet64 / 1MB), $_.ProcessName }
"`nTop 10 programs by CPU time:"
Get-Process | Sort-Object CPU -Descending | Select-Object -First 10 |
    ForEach-Object { "{0,10:N0} sec  {1}" -f $_.CPU, $_.ProcessName }

Write-Host "`n===== 7. PROGRAMS THAT START WITH WINDOWS =====" -ForegroundColor Cyan
Get-CimInstance Win32_StartupCommand | Select-Object Name, Command | Format-Table -AutoSize -Wrap

Write-Host "DONE. Copy everything above and paste it to Claude." -ForegroundColor Green
