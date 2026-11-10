#Requires -Version 5.1
<#
.SYNOPSIS
Imports locally supplied audio into Bluetooth Personal Link.
.DESCRIPTION
No download or upload is performed. Use recordings you own or have permission
to use. Close the target game before importing. Restart it fully afterwards.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$GameFolder,
    [Parameter(Mandatory=$true)][string]$AudioFolder,
    [ValidateSet('Append','Replace')][string]$Mode = 'Append',
    [ValidateSet('Connected','Disconnected')][string]$Kind = 'Connected',
    [switch]$DryRun
)
Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'
$managedHeader = '# Managed by Bluetooth Personal Link Import-BPLAudio.ps1 v1.2'
$markerText = 'Bluetooth Personal Link local audio importer v1.2'
$encoding = New-Object Text.UTF8Encoding($false)

function Resolve-Directory([string]$Path) {
    $item = Get-Item -LiteralPath $Path -Force
    if (!$item.PSIsContainer -or $item.PSProvider.Name -ne 'FileSystem') { throw 'Expected an existing filesystem directory.' }
    $absolute = [IO.Path]::GetFullPath($item.FullName)
    $driveRoot = [IO.Path]::GetPathRoot($absolute)
    if ($absolute.Length -gt $driveRoot.Length) { $absolute = $absolute.TrimEnd([IO.Path]::DirectorySeparatorChar) }
    return $absolute
}
function Assert-InGameRoot([string]$Path) {
    $absolute = [IO.Path]::GetFullPath($Path)
    $prefix = $gameRoot
    if (!$prefix.EndsWith([string][IO.Path]::DirectorySeparatorChar)) { $prefix += [IO.Path]::DirectorySeparatorChar }
    if (!$absolute.StartsWith($prefix,[StringComparison]::OrdinalIgnoreCase)) { throw 'A target path is outside the selected game root.' }
    # Refuse linked target directories instead of following them to another root.
    $current = [IO.Path]::GetDirectoryName($absolute)
    while ($current -and $current.Length -ge $gameRoot.Length) {
        if (Test-Path -LiteralPath $current) {
            if ((Get-Item -LiteralPath $current -Force).Attributes -band [IO.FileAttributes]::ReparsePoint) { throw 'Linked target directories are not supported.' }
        }
        if ($current.Equals($gameRoot,[StringComparison]::OrdinalIgnoreCase)) { break }
        $current = [IO.Path]::GetDirectoryName($current)
    }
    if ((Test-Path -LiteralPath $absolute) -and ((Get-Item -LiteralPath $absolute -Force).Attributes -band [IO.FileAttributes]::ReparsePoint)) { throw 'Linked target files are not supported.' }
    return $absolute
}
function Read-Audio([IO.FileInfo]$File) {
    $extension = $File.Extension.ToLowerInvariant()
    if (@('.wav','.mp3','.ogg','.flac') -notcontains $extension) { throw 'Unsupported audio extension.' }
    if ($File.Length -le 0 -or $File.Length -gt 20MB) { throw ('Audio must be nonempty and no larger than 20 MiB: ' + $File.Name) }
    if ($File.Attributes -band [IO.FileAttributes]::ReparsePoint) { throw 'Linked audio files are not supported.' }
    $stream = [IO.File]::Open($File.FullName,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::Read)
    try {
        $header = New-Object byte[] 12
        $read = $stream.Read($header,0,$header.Length)
    } finally { $stream.Dispose() }
    $valid = $false
    if ($extension -eq '.wav') { $valid = $read -ge 12 -and [Text.Encoding]::ASCII.GetString($header,0,4) -eq 'RIFF' -and [Text.Encoding]::ASCII.GetString($header,8,4) -eq 'WAVE' }
    if ($extension -eq '.ogg') { $valid = $read -ge 4 -and [Text.Encoding]::ASCII.GetString($header,0,4) -eq 'OggS' }
    if ($extension -eq '.flac') { $valid = $read -ge 4 -and [Text.Encoding]::ASCII.GetString($header,0,4) -eq 'fLaC' }
    if ($extension -eq '.mp3') { $valid = $read -ge 4 -and (([Text.Encoding]::ASCII.GetString($header,0,3) -eq 'ID3') -or ($header[0] -eq 255 -and ($header[1] -band 224) -eq 224)) }
    if (!$valid) { throw ('The audio header does not match its extension: ' + $File.Name) }
    $hash = (Get-FileHash -LiteralPath $File.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
    return [pscustomobject]@{ Source=$File.FullName; Hash=$hash; ID=('bpl_user_'+$hash.Substring(0,16)); FileName=('user_'+$hash.Substring(0,16)+$extension) }
}
function Build-Manifest($Records) {
    $lines = New-Object 'Collections.Generic.List[string]'
    $lines.Add($managedHeader); $lines.Add('version: 1.0.0'); $lines.Add('sfx:')
    foreach ($record in @($Records | Sort-Object ID)) {
        $lines.Add('  '+$record.ID+':'); $lines.Add('    file: '+$record.FileName)
        $lines.Add('    usage: in-memory'); $lines.Add('    settings:'); $lines.Add('      volume: 1.0')
    }
    return (($lines -join "`n")+"`n")
}
function Set-AtomicText([string]$Path,[string]$Text) {
    $checkedPath = Assert-InGameRoot $Path
    $temporary = Assert-InGameRoot ($checkedPath + '.' + [Guid]::NewGuid().ToString('N') + '.bpltmp')
    try {
        [IO.File]::WriteAllText($temporary,$Text,$encoding)
        if (Test-Path -LiteralPath $checkedPath) { [IO.File]::Replace($temporary,$checkedPath,[NullString]::Value) }
        else { [IO.File]::Move($temporary,$checkedPath) }
    } finally {
        # This is only the exact temporary file generated above, never user audio.
        if (Test-Path -LiteralPath $temporary) { Remove-Item -LiteralPath $temporary }
    }
}

$gameRoot = Resolve-Directory $GameFolder
$inputRoot = Resolve-Directory $AudioFolder
$modRoot = Assert-InGameRoot (Join-Path $gameRoot 'bin\x64\plugins\cyber_engine_tweaks\mods\BluetoothPersonalLink')
$baseAudioRoot = Assert-InGameRoot (Join-Path $gameRoot 'r6\audioware\BluetoothPersonalLink')
$userAudioRoot = Assert-InGameRoot (Join-Path $gameRoot 'r6\audioware\BluetoothPersonalLinkUserAudio')
$clipsPath = Assert-InGameRoot (Join-Path $modRoot 'clips.json')
$manifestPath = Assert-InGameRoot (Join-Path $userAudioRoot 'audios.yaml')
$markerPath = Assert-InGameRoot (Join-Path $userAudioRoot 'BPL_IMPORTER_OWNED.txt')
if (!(Test-Path -LiteralPath (Join-Path $modRoot 'init.lua') -PathType Leaf) -or !(Test-Path -LiteralPath $clipsPath -PathType Leaf) -or !(Test-Path -LiteralPath $baseAudioRoot -PathType Container)) { throw 'Install Bluetooth Personal Link first, then select its game root (not bin/x64).' }
$clipsOriginal = [IO.File]::ReadAllText($clipsPath)
$pools = $clipsOriginal | ConvertFrom-Json
foreach ($poolName in @('connected','disconnected')) {
    if (!$pools.PSObject.Properties[$poolName] -or $pools.$poolName -isnot [Array]) { throw 'clips.json must contain connected and disconnected arrays.' }
    $seen = @{}
    foreach ($id in $pools.$poolName) {
        if ($id -isnot [string] -or $id.Length -gt 128 -or $id -notmatch '^[A-Za-z0-9_]+$' -or $seen.ContainsKey($id)) { throw 'The existing audio list contains an invalid or duplicate event ID.' }
        $seen[$id]=$true
    }
    if ($seen.Count -gt 128) { throw 'An audio pool exceeds 128 recordings.' }
}
$audioFiles = @(Get-ChildItem -LiteralPath $inputRoot -File | Where-Object { @('.wav','.mp3','.ogg','.flac') -contains $_.Extension.ToLowerInvariant() } | Sort-Object Name)
if ($audioFiles.Count -eq 0) { throw 'No supported audio files were found in the selected folder.' }
if ($audioFiles.Count -gt 128) { throw 'Select a folder with no more than 128 audio files.' }
$records = @{}
$manifestOriginal = $null
if (Test-Path -LiteralPath $userAudioRoot) {
    $contents = @(Get-ChildItem -LiteralPath $userAudioRoot -Force)
    $hasMarker = (Test-Path -LiteralPath $markerPath) -and ([IO.File]::ReadAllText($markerPath).Trim() -eq $markerText)
    if (Test-Path -LiteralPath $manifestPath) {
        $manifestOriginal = [IO.File]::ReadAllText($manifestPath)
        if (!$manifestOriginal.StartsWith($managedHeader + "`n") -and !$manifestOriginal.StartsWith($managedHeader + "`r`n")) { throw 'The user-audio manifest is not managed by this importer; no overwrite performed.' }
    } elseif ($contents.Count -gt 0 -and !$hasMarker) { throw 'The user-audio folder already contains unmanaged files; no overwrite performed.' }
    foreach ($file in @(Get-ChildItem -LiteralPath $userAudioRoot -File | Where-Object Name -Match '^user_[a-f0-9]{16}\.(wav|mp3|ogg|flac)$')) {
        $record = Read-Audio $file
        if ($record.FileName -cne $file.Name) { throw 'An existing imported filename does not match its content hash.' }
        if ($records.ContainsKey($record.ID)) { throw 'Duplicate imported content or a truncated-hash collision was found.' }
        $records[$record.ID]=$record
    }
    if ($null -ne $manifestOriginal) {
        $expected = Build-Manifest @($records.Values)
        if (($manifestOriginal -replace "`r`n","`n").TrimEnd() -cne $expected.TrimEnd()) { throw 'The managed manifest was edited externally; no overwrite performed.' }
    }
}
$newCopies = New-Object 'Collections.Generic.List[object]'
$incoming = New-Object 'Collections.Generic.List[string]'
$incomingSeen = @{}
foreach ($file in $audioFiles) {
    $record = Read-Audio $file
    if ($incomingSeen.ContainsKey($record.ID)) {
        if ($incomingSeen[$record.ID] -cne $record.Hash) { throw 'A truncated-hash collision exists in the input folder; no files changed.' }
        continue
    }
    $incomingSeen[$record.ID]=$record.Hash
    if ($records.ContainsKey($record.ID)) {
        if ($records[$record.ID].Hash -cne $record.Hash) { throw 'A truncated-hash collision was found; no files changed.' }
    } else {
        $destination = Assert-InGameRoot (Join-Path $userAudioRoot $record.FileName)
        if (Test-Path -LiteralPath $destination) { throw 'An unmanaged audio file occupies the intended destination.' }
        $records[$record.ID]=$record; $newCopies.Add($record)
    }
    $incoming.Add($record.ID)
}
$selectedPool = $Kind.ToLowerInvariant()
$before = @($pools.$selectedPool)
$final = New-Object 'Collections.Generic.List[string]'
if ($Mode -eq 'Append') { foreach ($id in $before) { $final.Add($id) } }
foreach ($id in $incoming) { if (!$final.Contains($id)) { $final.Add($id) } }
if ($final.Count -gt 128) { throw 'The resulting pool would exceed 128 recordings; no files changed.' }
$poolChanged = (($before -join "`0") -cne ($final -join "`0"))
$pools.PSObject.Properties[$selectedPool].Value = [object[]]$final.ToArray()
$clipsNew = ($pools | ConvertTo-Json -Depth 20) + "`n"
$manifestNew = Build-Manifest @($records.Values)
$manifestChanged = $null -eq $manifestOriginal -or (($manifestOriginal -replace "`r`n","`n").TrimEnd() -cne $manifestNew.TrimEnd())
$changed = $poolChanged -or $manifestChanged -or $newCopies.Count -gt 0
$result = [ordered]@{ DryRun=[bool]$DryRun; Changed=$changed; Kind=$Kind; Mode=$Mode; UniqueInputRecordings=$incoming.Count; NewAudioFiles=$newCopies.Count; PoolRecordings=$final.Count; GameRestartRequired=$changed; Backups=@() }
if ($DryRun -or !$changed) { [pscustomobject]$result; return }

$gameExe = Join-Path $gameRoot 'bin\x64\Cyberpunk2077.exe'
if ((Test-Path -LiteralPath $gameExe) -and @(Get-Process -Name Cyberpunk2077 -ErrorAction SilentlyContinue).Count -gt 0) { throw 'Close Cyberpunk 2077 before importing audio into its installation.' }
if ([IO.File]::ReadAllText($clipsPath) -cne $clipsOriginal) { throw 'The audio list changed during validation; no files changed.' }
if ($null -ne $manifestOriginal -and [IO.File]::ReadAllText($manifestPath) -cne $manifestOriginal) { throw 'The manifest changed during validation; no files changed.' }
$suffix = '.bpl-backup-' + [DateTime]::UtcNow.ToString('yyyyMMdd-HHmmss-fff') + '-' + [Guid]::NewGuid().ToString('N')
$backups = New-Object 'Collections.Generic.List[string]'
$clipsBackup = Assert-InGameRoot ($clipsPath+$suffix)
Copy-Item -LiteralPath $clipsPath -Destination $clipsBackup
$backups.Add($clipsBackup)
if ($null -ne $manifestOriginal) {
    $manifestBackup = Assert-InGameRoot ($manifestPath+$suffix)
    Copy-Item -LiteralPath $manifestPath -Destination $manifestBackup
    $backups.Add($manifestBackup)
}
if (!(Test-Path -LiteralPath $userAudioRoot)) { $null=New-Item -ItemType Directory -Path $userAudioRoot }
if (!(Test-Path -LiteralPath $markerPath)) { [IO.File]::WriteAllText($markerPath,$markerText+"`n",$encoding) }
foreach ($record in $newCopies) {
    $destination = Assert-InGameRoot (Join-Path $userAudioRoot $record.FileName)
    if (Test-Path -LiteralPath $destination) { throw 'An audio destination appeared during import; no overwrite performed.' }
    Copy-Item -LiteralPath $record.Source -Destination $destination
    if ((Get-FileHash -LiteralPath $destination -Algorithm SHA256).Hash.ToLowerInvariant() -cne $record.Hash) { throw 'An input audio file changed during copying; the audio list has not been changed.' }
}
if ($manifestChanged) { Set-AtomicText $manifestPath $manifestNew }
if ($poolChanged) { Set-AtomicText $clipsPath $clipsNew }
$result.Backups = $backups.ToArray()
[pscustomobject]$result
Write-Host 'Import complete. Fully restart Cyberpunk 2077 so Audioware loads the new recordings.'
