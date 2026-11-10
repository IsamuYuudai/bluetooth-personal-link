# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Isamu Yuudai
# Reads frozen source snapshots; writes only new files below this repository's outputs/.
[CmdletBinding()]
param(
    [ValidateSet('All','1.3.0-beta.1','1.2.0-beta.6')]
    [string]$Version = 'All',
    [ValidatePattern('^[A-Za-z0-9][A-Za-z0-9_-]{0,63}$')]
    [string]$BuildSubdirectory = 'reproduced',
    [switch]$ValidateOnly
)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2
$repo = [IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot))
$utf8 = [Text.UTF8Encoding]::new($false, $true)
Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem

function Assert([bool]$Condition, [string]$Message) {
    if (!$Condition) { throw $Message }
}
function Assert-Relative([string]$Relative) {
    Assert (![string]::IsNullOrWhiteSpace($Relative)) 'An empty manifest path is not allowed.'
    Assert (!$Relative.Contains('\') -and !$Relative.StartsWith('/') -and !$Relative.Contains(':')) ('Nonportable manifest path: ' + $Relative)
    foreach ($part in $Relative.Split('/')) {
        Assert ($part -notin @('', '.', '..') -and $part -notmatch '[. ]$|[<>"|?*\x00-\x1f]') ('Unsafe manifest path: ' + $Relative)
        Assert ($part -notmatch '^(?i:CON|PRN|AUX|NUL|COM[1-9]|LPT[1-9])(?:\.|$)') ('Reserved Windows name: ' + $Relative)
    }
}
function Local-Path([string]$Relative) {
    Assert-Relative $Relative
    $resolved = [IO.Path]::GetFullPath((Join-Path $repo $Relative.Replace('/', [IO.Path]::DirectorySeparatorChar)))
    Assert ($resolved.StartsWith($repo + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) 'A manifest path escaped the repository.'
    return $resolved
}
function Assert-NoLinks([string]$Path) {
    $cursor = $Path
    while ($cursor.Length -ge $repo.Length) {
        Assert (!((Get-Item -LiteralPath $cursor -Force).Attributes -band [IO.FileAttributes]::ReparsePoint)) 'Linked files or directories are not accepted.'
        if ($cursor -eq $repo) { break }
        $cursor = Split-Path -Parent $cursor
    }
}
function File-Hash([string]$Path) { return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash }
function Stream-Hash($Stream) {
    $algorithm = [Security.Cryptography.SHA256]::Create()
    try { return [BitConverter]::ToString($algorithm.ComputeHash($Stream)).Replace('-', '') }
    finally { $algorithm.Dispose() }
}
function Ordered-Entries($Entries) {
    $lookup = [Collections.Generic.Dictionary[string,object]]::new([StringComparer]::Ordinal)
    $names = [Collections.Generic.List[string]]::new()
    foreach ($entry in $Entries) { $lookup.Add([string]$entry.path, $entry); $names.Add([string]$entry.path) }
    $names.Sort([StringComparer]::Ordinal)
    foreach ($name in $names) { $lookup[$name] }
}
function Read-Manifest([string]$Path) {
    $manifest = [IO.File]::ReadAllText($Path, $utf8) | ConvertFrom-Json
    Assert ($manifest.schema -eq 1) 'Unsupported manifest schema.'
    Assert ($manifest.version -in @('1.3.0-beta.1', '1.2.0-beta.6')) 'Unsupported source version.'
    Assert ($manifest.kind -in @('main', 'creator')) 'Unsupported artifact type.'
    Assert ($manifest.sourceRoot -ceq ('snapshots/v' + $manifest.version)) 'Unexpected snapshot directory.'
    Assert ($manifest.originalArchive.sha256 -cmatch '^[A-F0-9]{64}$') 'Invalid historical archive hash.'
    Assert ($manifest.entryCount -eq @($manifest.entries).Count) 'Manifest entry count does not match its records.'
    Assert-Relative $manifest.outputFileName
    Assert (!$manifest.outputFileName.Contains('/') -and $manifest.outputFileName.EndsWith('-content-reproduction.zip')) 'Unexpected reproduction filename.'
    $seen = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($entry in $manifest.entries) {
        Assert-Relative $entry.path
        Assert-Relative $entry.sourcePath
        Assert ($seen.Add([string]$entry.path)) 'Duplicate or case-colliding archive path.'
        Assert ($entry.sha256 -cmatch '^[A-F0-9]{64}$' -and $entry.bytes -ge 0) 'Invalid file hash or size.'
        $source = Local-Path ($manifest.sourceRoot + '/' + $entry.sourcePath)
        Assert (Test-Path -LiteralPath $source -PathType Leaf) ('Missing source: ' + $entry.sourcePath)
        Assert-NoLinks $source
        Assert ((Get-Item -LiteralPath $source).Length -eq $entry.bytes -and (File-Hash $source) -ceq $entry.sha256) ('Source bytes differ: ' + $entry.sourcePath)
    }
    return $manifest
}
function Assert-Snapshot($CreatorManifest) {
    $root = Local-Path $CreatorManifest.sourceRoot
    $actual = @(Get-ChildItem -LiteralPath $root -Recurse -File -Force)
    Assert ($actual.Count -eq $CreatorManifest.entryCount) 'The frozen snapshot contains extra or missing files. Run historical tests only in an outputs/ working copy.'
    $expected = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    foreach ($record in $CreatorManifest.entries) {
        Assert ($record.path -ceq $record.sourcePath) 'A creator snapshot must use original entry paths.'
        [void]$expected.Add([string]$record.sourcePath)
    }
    foreach ($file in $actual) {
        Assert-NoLinks $file.FullName
        $relative = $file.FullName.Substring($root.Length + 1).Replace('\', '/')
        Assert ($expected.Contains($relative)) ('Unexpected frozen source: ' + $relative)
    }
}
function Verify-Archive([string]$Path, $Manifest) {
    $archive = [IO.Compression.ZipFile]::OpenRead($Path)
    try {
        Assert ($archive.Entries.Count -eq $Manifest.entryCount) 'Reproduced ZIP entry count differs.'
        foreach ($record in $Manifest.entries) {
            $entry = $archive.GetEntry([string]$record.path)
            Assert ($null -ne $entry -and $entry.Length -eq $record.bytes) ('Missing ZIP entry or incorrect size: ' + $record.path)
            $stream = $entry.Open()
            try { Assert ((Stream-Hash $stream) -ceq $record.sha256) ('ZIP entry hash differs: ' + $record.path) }
            finally { $stream.Dispose() }
        }
    } finally { $archive.Dispose() }
}
function Build-Archive($Manifest, [string]$Destination) {
    Assert (!(Test-Path -LiteralPath $Destination)) 'An output archive already exists. Choose a new BuildSubdirectory; nothing was overwritten.'
    $fixedTime = [DateTimeOffset]::new(2020, 1, 1, 0, 0, 0, [TimeSpan]::Zero)
    $outputStream = [IO.File]::Open($Destination, [IO.FileMode]::CreateNew, [IO.FileAccess]::ReadWrite, [IO.FileShare]::None)
    try {
        $archive = [IO.Compression.ZipArchive]::new($outputStream, [IO.Compression.ZipArchiveMode]::Create, $true, $utf8)
        try {
            foreach ($record in @(Ordered-Entries $Manifest.entries)) {
                # Stored entries avoid dependency on a particular compression encoder.
                $entry = $archive.CreateEntry([string]$record.path, [IO.Compression.CompressionLevel]::NoCompression)
                $entry.LastWriteTime = $fixedTime
                $entry.ExternalAttributes = 0
                $inputStream = [IO.File]::OpenRead((Local-Path ($Manifest.sourceRoot + '/' + $record.sourcePath)))
                $entryStream = $entry.Open()
                try { $inputStream.CopyTo($entryStream) }
                finally { $entryStream.Dispose(); $inputStream.Dispose() }
            }
        } finally { $archive.Dispose() }
    } finally { $outputStream.Dispose() }
    Verify-Archive $Destination $Manifest
    return [ordered]@{
        version = $Manifest.version; kind = $Manifest.kind
        file = $Manifest.outputFileName; sha256 = File-Hash $Destination
        bytes = (Get-Item -LiteralPath $Destination).Length; entryCount = $Manifest.entryCount
        allOriginalEntryBytesVerified = $true
        historicalOriginalZipSHA256 = $Manifest.originalArchive.sha256
        originalContainerHashExpected = $false
    }
}

$versions = if ($Version -eq 'All') { @('1.2.0-beta.6', '1.3.0-beta.1') } else { @($Version) }
$manifests = @()
foreach ($selectedVersion in $versions) {
    $creator = Read-Manifest (Local-Path ('manifests/' + $selectedVersion + '-creator.json'))
    Assert-Snapshot $creator
    $main = Read-Manifest (Local-Path ('manifests/' + $selectedVersion + '-main.json'))
    $manifests += $main, $creator
}
if ($ValidateOnly) {
    [pscustomobject]@{ validated = $true; sourceVersions = $versions; artifactManifests = $manifests.Count; writesPerformed = $false } | ConvertTo-Json -Depth 5
    return
}
$destinationRoot = Local-Path ('outputs/' + $BuildSubdirectory)
Assert (!(Test-Path -LiteralPath $destinationRoot)) 'This output directory already exists. Choose a new BuildSubdirectory; nothing was overwritten.'
# Check existing ancestors before creating anything, so an outputs/ junction
# cannot cause an initial write outside the intended repository tree.
$existingAncestor = Split-Path -Parent $destinationRoot
while (!(Test-Path -LiteralPath $existingAncestor)) { $existingAncestor = Split-Path -Parent $existingAncestor }
Assert (Test-Path -LiteralPath $existingAncestor -PathType Container) 'An output ancestor is not a directory.'
Assert-NoLinks $existingAncestor
[void][IO.Directory]::CreateDirectory($destinationRoot)
Assert-NoLinks $destinationRoot
$artifacts = @()
foreach ($manifest in $manifests) { $artifacts += Build-Archive $manifest (Join-Path $destinationRoot $manifest.outputFileName) }
$report = [ordered]@{
    schema = 1; format = 'Source-review content reproduction; stored ZIP entries, ordinal path order, fixed 2020-01-01 timestamps'
    originalZipIdentityClaimed = $false; snapshotBytesModified = $false
    localRuntime = $PSVersionTable.PSVersion.ToString(); artifacts = $artifacts
}
[IO.File]::WriteAllText((Join-Path $destinationRoot 'REPRODUCTION-RESULTS.json'), ($report | ConvertTo-Json -Depth 8) + "`n", $utf8)
$report | ConvertTo-Json -Depth 8
