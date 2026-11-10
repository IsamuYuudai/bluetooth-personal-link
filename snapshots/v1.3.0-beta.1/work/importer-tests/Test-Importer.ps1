#Requires -Version 5.1
param([string]$TestRoot=$PSScriptRoot)
$ErrorActionPreference='Stop'
Set-StrictMode -Version 2.0
$projectRoot=Split-Path (Split-Path $TestRoot -Parent) -Parent
$importer=Join-Path $projectRoot 'creator-kit\tools\Import-BPLAudio.ps1'
if (!(Test-Path -LiteralPath $importer)) { $importer=Join-Path $projectRoot 'tools\Import-BPLAudio.ps1' }
$importerCode=[ScriptBlock]::Create([IO.File]::ReadAllText($importer))
$fixtureRoot=Join-Path $TestRoot ('fixtures-'+[Guid]::NewGuid().ToString('N'))
$null=New-Item -ItemType Directory -Path $fixtureRoot
$encoding=New-Object Text.UTF8Encoding($false)
$checks=New-Object 'Collections.Generic.List[string]'
function Assert-True($Value,[string]$Message){if(!$Value){throw $Message}}
function Snapshot([string]$Root){
 return (@(Get-ChildItem -LiteralPath $Root -Recurse -Force | ForEach-Object {
  $relative=$_.FullName.Substring($Root.Length)
  if($_.PSIsContainer){'D '+$relative}else{'F '+$relative+' '+(Get-FileHash -LiteralPath $_.FullName).Hash}
 } | Sort-Object) -join "`n")
}
function New-Fixture([string]$Name){
 $game=Join-Path $fixtureRoot $Name
 $mod=Join-Path $game 'bin\x64\plugins\cyber_engine_tweaks\mods\BluetoothPersonalLink'
 $audio=Join-Path $game 'r6\audioware\BluetoothPersonalLink'
 $null=New-Item -ItemType Directory -Path $mod -Force
 $null=New-Item -ItemType Directory -Path $audio -Force
 [IO.File]::WriteAllText((Join-Path $mod 'init.lua'),'return {}',$encoding)
 [IO.File]::WriteAllText((Join-Path $mod 'settings.json'),'{"enabled":true,"volume":0.8}',$encoding)
 [IO.File]::WriteAllText((Join-Path $mod 'clips.json'),'{"connected":["bpl_starter_chime"],"disconnected":["bpl_disconnect_original"]}',$encoding)
 return $game
}
function New-Wave([string]$Path,[int]$Frequency){
 $stream=[IO.File]::Open($Path,[IO.FileMode]::Create,[IO.FileAccess]::Write)
 $writer=New-Object IO.BinaryWriter($stream)
 try{
  $writer.Write([Text.Encoding]::ASCII.GetBytes('RIFF'));$writer.Write([int]1636)
  $writer.Write([Text.Encoding]::ASCII.GetBytes('WAVEfmt '));$writer.Write([int]16)
  $writer.Write([int16]1);$writer.Write([int16]1);$writer.Write([int]8000)
  $writer.Write([int]16000);$writer.Write([int16]2);$writer.Write([int16]16)
  $writer.Write([Text.Encoding]::ASCII.GetBytes('data'));$writer.Write([int]1600)
  for($i=0;$i -lt 800;$i++){$writer.Write([int16](2000*[math]::Sin(2*[math]::PI*$Frequency*$i/8000)))}
 }finally{$writer.Dispose();$stream.Dispose()}
}
function Expect-Failure([scriptblock]$Action,[string]$Message){
 $failed=$false
 try{& $Action | Out-Null}catch{$failed=$true}
 Assert-True $failed $Message
}
$inputs=Join-Path $fixtureRoot 'audio-input'
$single=Join-Path $fixtureRoot 'single-audio'
$third=Join-Path $fixtureRoot 'third-audio'
foreach($directory in @($inputs,$single,$third)){$null=New-Item -ItemType Directory -Path $directory}
New-Wave (Join-Path $inputs 'A.wav') 440
Copy-Item -LiteralPath (Join-Path $inputs 'A.wav') -Destination (Join-Path $inputs 'A-duplicate.wav')
New-Wave (Join-Path $inputs 'B.wav') 550
Copy-Item -LiteralPath (Join-Path $inputs 'A.wav') -Destination (Join-Path $single 'A.wav')
New-Wave (Join-Path $third 'C.wav') 660
[IO.File]::WriteAllText((Join-Path $inputs 'not-audio.txt'),'not imported',$encoding)
$game=New-Fixture 'main-game'
$mod=Join-Path $game 'bin\x64\plugins\cyber_engine_tweaks\mods\BluetoothPersonalLink'
$userAudio=Join-Path $game 'r6\audioware\BluetoothPersonalLinkUserAudio'
$before=Snapshot $game
$plan=& $importerCode -GameFolder $game -AudioFolder $inputs -DryRun
Assert-True ($plan.DryRun -and $plan.UniqueInputRecordings -eq 2 -and $plan.PoolRecordings -eq 3) 'Dry run plan is incorrect.'
Assert-True ((Snapshot $game) -ceq $before) 'Dry run wrote files or directories.'
$checks.Add('Dry run validates and reports deduplicated results without creating files or directories')
$settingsHash=(Get-FileHash -LiteralPath (Join-Path $mod 'settings.json')).Hash
$result=& $importerCode -GameFolder $game -AudioFolder $inputs
$pools=Get-Content -LiteralPath (Join-Path $mod 'clips.json') -Raw|ConvertFrom-Json
Assert-True ($result.UniqueInputRecordings -eq 2 -and $result.NewAudioFiles -eq 2 -and $pools.connected.Count -eq 3) 'Append or deduplication failed.'
Assert-True ($pools.disconnected.Count -eq 1 -and $pools.disconnected[0] -eq 'bpl_disconnect_original') 'The other pool changed.'
Assert-True ((Get-FileHash -LiteralPath (Join-Path $mod 'settings.json')).Hash -eq $settingsHash) 'Settings changed.'
Assert-True (@(Get-ChildItem -LiteralPath $userAudio -File -Filter '*.wav').Count -eq 2) 'Wrong audio file count.'
Assert-True ($result.Backups.Count -eq 1 -and (Test-Path -LiteralPath $result.Backups[0])) 'Original clips.json backup missing.'
$backupPools=Get-Content -LiteralPath $result.Backups[0] -Raw|ConvertFrom-Json
Assert-True ($backupPools.connected.Count -eq 1 -and $backupPools.connected[0] -eq 'bpl_starter_chime') 'Backup is not the pre-import list.'
$checks.Add('Append imports unique content, retains the other pool/settings, and backs up the original list')
$before=Snapshot $game
$again=& $importerCode -GameFolder $game -AudioFolder $inputs
Assert-True (!$again.Changed -and $again.NewAudioFiles -eq 0 -and (Snapshot $game) -ceq $before) 'Identical second import was not idempotent.'
$checks.Add('Repeated identical import is idempotent and creates no extra files or backups')
$append=& $importerCode -GameFolder $game -AudioFolder $third
$manifest=Get-Content -LiteralPath (Join-Path $userAudio 'audios.yaml') -Raw
Assert-True ($append.NewAudioFiles -eq 1 -and ([regex]::Matches($manifest,'(?m)^  bpl_user_')).Count -eq 3) 'Append discarded prior manifest entries.'
Assert-True ($append.Backups.Count -eq 2) 'Existing manifest was not backed up.'
$checks.Add('Later imports preserve existing audio registrations and back up the prior manifest')
$replace=& $importerCode -GameFolder $game -AudioFolder $single -Mode Replace
$pools=Get-Content -LiteralPath (Join-Path $mod 'clips.json') -Raw|ConvertFrom-Json
$expectedA='bpl_user_'+(Get-FileHash -LiteralPath (Join-Path $single 'A.wav')).Hash.ToLowerInvariant().Substring(0,16)
Assert-True ($pools.connected.Count -eq 1 -and $pools.connected[0] -eq $expectedA) 'Replace did not replace the selected pool.'
Assert-True ($pools.disconnected[0] -eq 'bpl_disconnect_original' -and @(Get-ChildItem -LiteralPath $userAudio -File -Filter '*.wav').Count -eq 3) 'Replace deleted audio or changed the other pool.'
& $importerCode -GameFolder $game -AudioFolder $third -Kind Disconnected -Mode Replace|Out-Null
$pools=Get-Content -LiteralPath (Join-Path $mod 'clips.json') -Raw|ConvertFrom-Json
Assert-True ($pools.connected[0] -eq $expectedA -and $pools.disconnected.Count -eq 1 -and $pools.disconnected[0] -ne 'bpl_disconnect_original') 'Disconnected import modified the wrong pool.'
$checks.Add('Replace and Disconnected modes change only the selected pool and retain imported files')
$badInputs=Join-Path $fixtureRoot 'bad-audio'
$null=New-Item -ItemType Directory -Path $badInputs
[IO.File]::WriteAllText((Join-Path $badInputs 'wrong.wav'),'this is not a WAV',$encoding)
$before=Snapshot $game
Expect-Failure {& $importerCode -GameFolder $game -AudioFolder $badInputs} 'Invalid header was accepted.'
Assert-True ((Snapshot $game) -ceq $before) 'Invalid input changed target files.'
$checks.Add('Invalid media headers fail before changing the target')
$foreign=New-Fixture 'foreign-manifest'
$foreignAudio=Join-Path $foreign 'r6\audioware\BluetoothPersonalLinkUserAudio'
$null=New-Item -ItemType Directory -Path $foreignAudio
[IO.File]::WriteAllText((Join-Path $foreignAudio 'audios.yaml'),'version: 1.0.0'+"`n"+'sfx: {}',$encoding)
$before=Snapshot $foreign
Expect-Failure {& $importerCode -GameFolder $foreign -AudioFolder $single} 'Foreign manifest was overwritten.'
Assert-True ((Snapshot $foreign) -ceq $before) 'Foreign manifest rejection changed files.'
$checks.Add('Unmanaged manifests are preserved and rejected')
$collision=New-Fixture 'hash-collision'
$collisionAudio=Join-Path $collision 'r6\audioware\BluetoothPersonalLinkUserAudio'
$null=New-Item -ItemType Directory -Path $collisionAudio
[IO.File]::WriteAllText((Join-Path $collisionAudio 'BPL_IMPORTER_OWNED.txt'),'Bluetooth Personal Link local audio importer v1.2',$encoding)
$occupiedName='user_'+(Get-FileHash -LiteralPath (Join-Path $single 'A.wav')).Hash.ToLowerInvariant().Substring(0,16)+'.wav'
Copy-Item -LiteralPath (Join-Path $third 'C.wav') -Destination (Join-Path $collisionAudio $occupiedName)
$before=Snapshot $collision
Expect-Failure {& $importerCode -GameFolder $collision -AudioFolder $single} 'Hash/name collision was accepted.'
Assert-True ((Snapshot $collision) -ceq $before) 'Collision rejection changed files.'
$checks.Add('Conflicting imported filenames cannot overwrite existing content')
$full=New-Fixture 'full-pool'
$fullClips=Join-Path $full 'bin\x64\plugins\cyber_engine_tweaks\mods\BluetoothPersonalLink\clips.json'
[IO.File]::WriteAllText($fullClips,([ordered]@{connected=@(1..128|ForEach-Object{'valid_event_'+$_});disconnected=@('other')}|ConvertTo-Json -Depth 3),$encoding)
$before=Snapshot $full
Expect-Failure {& $importerCode -GameFolder $full -AudioFolder $single} 'Pool limit was not enforced.'
Assert-True ((Snapshot $full) -ceq $before) 'Pool-limit rejection changed files.'
$checks.Add('The 128-recording pool limit is enforced before writes')
$running=New-Fixture 'running-game'
[IO.File]::WriteAllText((Join-Path $running 'bin\x64\Cyberpunk2077.exe'),'fixture only; never executed',$encoding)
function Get-Process { [CmdletBinding()]param([string]$Name) [pscustomobject]@{Id=999;ProcessName=$Name} }
$before=Snapshot $running
Expect-Failure {& $importerCode -GameFolder $running -AudioFolder $single} 'Running-game protection failed.'
$null=& $importerCode -GameFolder $running -AudioFolder $single -DryRun
Assert-True ((Snapshot $running) -ceq $before) 'Running-game guard or dry run changed files.'
$checks.Add('Writes to a running game are blocked while DryRun remains read-only')
$tokens=$null;$parseErrors=$null
[Management.Automation.Language.Parser]::ParseFile($importer,[ref]$tokens,[ref]$parseErrors)|Out-Null
Assert-True (@($parseErrors).Count -eq 0) 'Importer syntax parsing failed.'
Assert-True (@(Get-ChildItem -LiteralPath $fixtureRoot -Recurse -File -Filter '*.bpltmp').Count -eq 0) 'Staged temporary files were left behind.'
$checks.Add('PowerShell syntax passes and atomic commit leaves no temporary files')
$report=[ordered]@{pass=$true;checkedUtc=[DateTime]::UtcNow.ToString('o');powershell=$PSVersionTable.PSVersion.ToString();scriptSHA256=(Get-FileHash -LiteralPath $importer).Hash;checks=$checks.ToArray();groups=$checks.Count;liveGameModified=$false;networkUsed=$false;gameExecuted=$false}
[IO.File]::WriteAllText((Join-Path $TestRoot 'TEST-RESULTS.json'),($report|ConvertTo-Json -Depth 5),$encoding)
$report|ConvertTo-Json -Depth 5
