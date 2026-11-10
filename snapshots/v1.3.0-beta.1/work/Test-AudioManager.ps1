#Requires -Version 5.1
$ErrorActionPreference='Stop';Set-StrictMode -Version 2
$bluetooth=Split-Path -Parent $PSScriptRoot
$tools=Join-Path $bluetooth 'package\bin\x64\plugins\cyber_engine_tweaks\mods\BluetoothPersonalLink\docs\tools'
$root=Join-Path $PSScriptRoot ('audio-fixture-'+[Guid]::NewGuid().ToString('N')+'-'+[char]0x97F3)
$game=Join-Path $root 'Cyberpunk 2077';$mod=Join-Path $game 'bin\x64\plugins\cyber_engine_tweaks\mods\BluetoothPersonalLink'
$fakeTools=Join-Path $mod 'docs\tools';$inputAudio=Join-Path $mod 'audio-inbox\connected';$disconnected=Join-Path $mod 'audio-inbox\disconnected'
foreach($p in @($fakeTools,$inputAudio,$disconnected,(Join-Path $game 'r6\audioware\BluetoothPersonalLink'))){[void][IO.Directory]::CreateDirectory($p)}
[IO.File]::WriteAllText((Join-Path $game 'bin\x64\Cyberpunk2077.exe'),'fixture-only')
[IO.File]::WriteAllText((Join-Path $mod 'init.lua'),'-- fixture only')
[IO.File]::WriteAllText((Join-Path $mod 'clips.json'),'{"connected":["bpl_starter_chime"],"disconnected":[]}')
foreach($file in @('Manage-Audio.ps1','Manage-Audio.cmd','Import-BPLAudio.ps1')){Copy-Item -LiteralPath (Join-Path $tools $file) -Destination (Join-Path $fakeTools $file)}
function Wave([string]$Path,[int]$Tone){
 $bytes=New-Object byte[] 2044;$mem=[IO.MemoryStream]::new($bytes,$true);$writer=[IO.BinaryWriter]::new($mem)
 try{$writer.Write([Text.Encoding]::ASCII.GetBytes('RIFF'));$writer.Write([int]2036);$writer.Write([Text.Encoding]::ASCII.GetBytes('WAVEfmt '));$writer.Write([int]16);$writer.Write([int16]1);$writer.Write([int16]1);$writer.Write([int]8000);$writer.Write([int]16000);$writer.Write([int16]2);$writer.Write([int16]16);$writer.Write([Text.Encoding]::ASCII.GetBytes('data'));$writer.Write([int]2000);for($i=0;$i-lt1000;$i++){$writer.Write([int16](1000*[Math]::Sin($i*$Tone/8000.0*6.28318530718)))};$writer.Flush()}finally{$writer.Dispose();$mem.Dispose()};[IO.File]::WriteAllBytes($Path,$bytes)
}
Wave (Join-Path $inputAudio 'one.wav') 400;Wave (Join-Path $disconnected 'two.wav') 600
$results=[Collections.Generic.List[object]]::new()
function Assert([bool]$Condition,[string]$Message){if(!$Condition){throw $Message}}
function Pass([string]$Name){$results.Add([pscustomobject]@{Name=$Name;Passed=$true});Write-Host ('PASS '+$Name)}
function Fingerprint([string]$Base){$rows=@(Get-ChildItem -LiteralPath $Base -Recurse -Force|Sort-Object FullName|ForEach-Object {$r=$_.FullName.Substring($Base.Length);if($_.PSIsContainer){'D|'+$r}else{'F|'+$r+'|'+(Get-FileHash -LiteralPath $_.FullName).Hash}});$rows-join"`n"}
function ExpectThrow([scriptblock]$Action,[string]$Pattern){$caught=$false;try{&$Action}catch{if($_.Exception.Message-notmatch$Pattern){throw};$caught=$true};Assert $caught ('Expected refusal: '+$Pattern)}
$manager=Join-Path $fakeTools 'Manage-Audio.ps1';$importer=Join-Path $fakeTools 'Import-BPLAudio.ps1'
foreach($script in @($manager,$importer)){$errors=$null;[void][Management.Automation.Language.Parser]::ParseFile($script,[ref]$null,[ref]$errors);Assert (@($errors).Count-eq0) 'WinPS5.1 parser errors.'};Pass 'Actual WindowsPowerShell5.1 parses manager and unchanged importer'
$before=Fingerprint $game;$assembliesBefore=@([AppDomain]::CurrentDomain.GetAssemblies()|ForEach-Object {$_.GetName().Name})
$dry=&$manager -NoUI
Assert ($dry.Status-eq'ValidatedDryRun'-and$dry.Result.DryRun-and!$dry.GameFilesChanged) 'NoUI did not validate as read-only.'
Assert ($dry.GameFolder-eq$game) 'Ancestor game detection failed.';Assert ((Fingerprint $game)-ceq$before) 'NoUI changed fixture files or directories.'
$newForms=@([AppDomain]::CurrentDomain.GetAssemblies()|Where-Object {$_.GetName().Name-eq'System.Windows.Forms'-and$_.GetName().Name-notin$assembliesBefore});Assert (!$newForms.Count) 'NoUI loaded forms.';Pass 'NoUI auto-detects ancestor Unicode game path without forms or any target writes'
$dry=&$manager -NoUI -GameFolder $game -AudioFolder $disconnected -Kind Disconnected -Mode Replace
Assert ($dry.Result.Kind-eq'Disconnected'-and$dry.Result.Mode-eq'Replace'-and$dry.Result.PoolRecordings-eq1) 'NoUI kind/mode forwarding incorrect.';Assert ((Fingerprint $game)-ceq$before) 'Explicit NoUI changed target.';Pass 'NoUI forwards explicit selected pool and Replace mode without target writes'
$bad=Join-Path $root 'invalid';[void][IO.Directory]::CreateDirectory($bad);[IO.File]::WriteAllText((Join-Path $bad 'invalid.wav'),'not an audio recording')
ExpectThrow {&$manager -NoUI -GameFolder $game -AudioFolder $bad} 'header';Assert ((Fingerprint $game)-ceq$before) 'Invalid audio changed target.';Pass 'Invalid audio header is refused before any fixture writes'
# Extract only the manager function definitions, without evaluating its UI block.
$ast=[Management.Automation.Language.Parser]::ParseFile($manager,[ref]$null,[ref]$null)
foreach($fn in $ast.FindAll({param($node)$node-is[Management.Automation.Language.FunctionDefinitionAst]},$false)|Where-Object {$_.Name-notin@('Label','Button','Refresh-BplForm')}){Invoke-Expression $fn.Extent.Text}
$script:bplImporter=$importer
ExpectThrow {Assert-BplLocalPath '\\server\share\audio'} 'local drive';Pass 'Network paths are refused by manager validation'
$many=Join-Path $root 'too-many';[void][IO.Directory]::CreateDirectory($many);for($i=0;$i-lt129;$i++){[IO.File]::WriteAllBytes((Join-Path $many ($i.ToString()+'.wav')),[IO.File]::ReadAllBytes((Join-Path $inputAudio 'one.wav')))}
ExpectThrow {Get-BplInputSummary $many} '128';Pass 'Manager input cap refuses129recordings'
$linked=Join-Path $root 'linked-input';$null=New-Item -ItemType Junction -Path $linked -Target $inputAudio
ExpectThrow {Get-BplInputSummary $linked} 'Linked';Pass 'Manager refuses reparse input folder'
function global:Get-Process{param([string]$Name)if($Name-eq'Cyberpunk2077'){[pscustomobject]@{ProcessName='Cyberpunk2077'}}}
ExpectThrow {Get-BplImportArguments $game $inputAudio Connected Append} 'Close Cyberpunk';Assert ((Fingerprint $game)-ceq$before) 'Running-game refusal changed target.';Pass 'Manager refuses Import while target game process is present'
Remove-Item Function:\Get-Process
# Exercise the same AddCommand/AddParameters/BeginInvoke/EndInvoke mechanism used
# by the GUI, in an isolated test runspace. Process lookup alone is test-mocked;
# all importer paths are this fixture and no UI is created.
function ImportViaRunspace([string]$Pool,[string]$SelectedMode,[string]$Folder){
 $state=[Management.Automation.Runspaces.InitialSessionState]::CreateDefault()
 $mock=[Management.Automation.Runspaces.SessionStateFunctionEntry]::new('Get-Process','param([string]$Name) if($Name -eq ''Cyberpunk2077''){return}; Microsoft.PowerShell.Management\Get-Process @PSBoundParameters')
 $state.Commands.Add($mock);$runspace=[RunspaceFactory]::CreateRunspace($state);$runspace.Open();$worker=[Management.Automation.PowerShell]::Create();$worker.Runspace=$runspace
 try{$null=$worker.AddCommand($importer).AddParameters(@{GameFolder=$game;AudioFolder=$Folder;Kind=$Pool;Mode=$SelectedMode});$async=$worker.BeginInvoke();$output=$worker.EndInvoke($async);if($worker.Streams.Error.Count){throw $worker.Streams.Error[0]};$result=@($output|Where-Object {$_.PSObject.Properties['PoolRecordings']}|Select-Object -Last 1);Assert ($result.Count-eq1) 'Runspace importer returned no result.';return $result[0]}finally{$worker.Dispose();$runspace.Dispose()}
}
$imported=ImportViaRunspace Connected Append $inputAudio
Assert ($imported.NewAudioFiles-eq1-and$imported.PoolRecordings-eq2-and$imported.GameRestartRequired) 'Append import result incorrect.'
$clips=Get-Content -LiteralPath (Join-Path $mod 'clips.json') -Raw -Encoding UTF8|ConvertFrom-Json
Assert ($clips.connected.Count-eq2-and$clips.disconnected.Count-eq0) 'Append changed unrelated pool.';Assert ($imported.Backups.Count-eq1-and(Test-Path -LiteralPath $imported.Backups[0])) 'Pre-import clips backup missing.';Pass 'GUI-equivalent async runspace imports recording and creates backup/manifest in fakegame'
$again=ImportViaRunspace Connected Append $inputAudio;Assert (!$again.Changed-and$again.NewAudioFiles-eq0-and!$again.GameRestartRequired) 'Duplicate content not idempotent.';Pass 'Repeated append is content-addressed and idempotent'
$switched=ImportViaRunspace Disconnected Replace $disconnected;$clips=Get-Content -LiteralPath (Join-Path $mod 'clips.json') -Raw -Encoding UTF8|ConvertFrom-Json
Assert ($clips.connected.Count-eq2-and$clips.disconnected.Count-eq1-and$switched.PoolRecordings-eq1) 'Disconnected Replace changed wrong pool.';Pass 'Replace changes only selected connection pool and preserves other pool'
$manifest=Join-Path $game 'r6\audioware\BluetoothPersonalLinkUserAudio\audios.yaml';Add-Content -LiteralPath $manifest -Value '# external edit' -Encoding UTF8;$unchanged=Fingerprint $game
ExpectThrow {&$manager -NoUI -GameFolder $game -AudioFolder $inputAudio} 'edited externally';Assert ((Fingerprint $game)-ceq$unchanged) 'External manifest refusal changed target.';Pass 'Externally edited managed manifest is refused without additional writes'
$report=[ordered]@{Schema=1;CreatedUtc=[DateTime]::UtcNow.ToString('o');Runtime=$PSVersionTable.PSVersion.ToString();GroupsPassed=$results.Count;Results=$results.ToArray();ManagerSHA256=(Get-FileHash -LiteralPath (Join-Path $tools 'Manage-Audio.ps1')).Hash;ImporterSHA256=(Get-FileHash -LiteralPath (Join-Path $tools 'Import-BPLAudio.ps1')).Hash;CmdSHA256=(Get-FileHash -LiteralPath (Join-Path $tools 'Manage-Audio.cmd')).Hash;FixtureRoot=$root;NoUIOrLiveGameChanges=$true;Limits='Actual WinPS5.1 parser, NoUI read-only and async importer mechanics tested against isolated dummy game/WAV fixtures only. No form was instantiated or displayed. No actual gameplay, Audioware decoding or audible playback was tested. Mutation fixtures mock only process lookup; shipped Import has no bypass and running-game guard tested separately.'}
[IO.File]::WriteAllText((Join-Path $PSScriptRoot 'AUDIO-MANAGER-FIXTURE-RESULTS.json'),($report|ConvertTo-Json -Depth 8)+"`n",[Text.UTF8Encoding]::new($false));[pscustomobject]$report|Select-Object Runtime,GroupsPassed,ManagerSHA256,ImporterSHA256|ConvertTo-Json
