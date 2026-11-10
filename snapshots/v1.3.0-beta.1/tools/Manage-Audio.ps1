#Requires -Version 5.1
<# Local optional audio manager. No downloads, uploads, resident helpers or game hooks.
   NoUI is a READ-ONLY importer DryRun for installation checks and fixture tests. #>
[CmdletBinding()]
param([switch]$NoUI,[string]$GameFolder,[string]$AudioFolder,[ValidateSet('Connected','Disconnected')][string]$Kind='Connected',[ValidateSet('Append','Replace')][string]$Mode='Append')
Set-StrictMode -Version 2.0
$ErrorActionPreference='Stop'
$script:bplImporter=Join-Path $PSScriptRoot 'Import-BPLAudio.ps1'
function Assert-BplLocalPath([string]$Path,[switch]$MayNotExist){
 $full=[IO.Path]::GetFullPath($Path)
 if($full-notmatch'^[A-Za-z]:\\'-or$full.StartsWith('\\')){throw 'Select a local drive folder; network/device paths are not supported.'}
 $cursor=$full
 while($cursor){if(Test-Path -LiteralPath $cursor){if((Get-Item -LiteralPath $cursor -Force).Attributes-band[IO.FileAttributes]::ReparsePoint){throw 'Linked folders/files are not supported. Select the actual local folder.'}};$parent=Split-Path -Parent $cursor;if($parent-eq$cursor){break};$cursor=$parent}
 if(!$MayNotExist-and!(Test-Path -LiteralPath $full)){throw 'The selected local path does not exist.'}
 return $full
}
function Test-BplGameFolder([string]$Folder){
 try{$root=(Assert-BplLocalPath $Folder).TrimEnd('\','/');return (Test-Path -LiteralPath (Join-Path $root 'bin\x64\Cyberpunk2077.exe') -PathType Leaf)-and(Test-Path -LiteralPath (Join-Path $root 'bin\x64\plugins\cyber_engine_tweaks\mods\BluetoothPersonalLink\init.lua') -PathType Leaf)-and(Test-Path -LiteralPath (Join-Path $root 'bin\x64\plugins\cyber_engine_tweaks\mods\BluetoothPersonalLink\clips.json') -PathType Leaf)}catch{return $false}
}
function Find-BplGameFolder([string]$StartFolder){
 $cursor=[IO.Path]::GetFullPath($StartFolder)
 for($i=0;$cursor-and$i-lt40;$i++){if(Test-BplGameFolder $cursor){return $cursor.TrimEnd('\','/')};$parent=Split-Path -Parent $cursor;if($parent-eq$cursor){break};$cursor=$parent}
 return $null
}
function Get-BplInbox([string]$Root,[string]$SelectedKind){
 if(!(Test-BplGameFolder $Root)){throw 'Select the Cyberpunk game folder containing Bluetooth Personal Link.'}
 Assert-BplLocalPath (Join-Path $Root ('bin\x64\plugins\cyber_engine_tweaks\mods\BluetoothPersonalLink\audio-inbox\'+$SelectedKind.ToLowerInvariant())) -MayNotExist
}
function Get-BplInputSummary([string]$Folder){
 $inputRoot=Assert-BplLocalPath $Folder
 if(!(Test-Path -LiteralPath $inputRoot -PathType Container)){throw 'Select an audio input folder.'}
 $files=@(Get-ChildItem -LiteralPath $inputRoot -File|Where-Object {$_.Extension.ToLowerInvariant()-in@('.wav','.mp3','.ogg','.flac')})
 if(!$files.Count){throw 'No WAV, MP3, OGG or FLAC files were found. Put recordings in the inbox or choose another folder.'}
 if($files.Count-gt128){throw 'Select no more than128 supported audio files.'}
 foreach($file in $files){$null=Assert-BplLocalPath $file.FullName;if($file.Length-le0-or$file.Length-gt20971520){throw ('Each audio file must be nonempty and at most20MiB: '+$file.Name)}}
 return [pscustomobject]@{Folder=$inputRoot;Count=$files.Count;Bytes=($files|Measure-Object Length -Sum).Sum}
}
function Get-BplImportArguments([string]$Root,[string]$InputFolder,[string]$SelectedKind,[string]$SelectedMode,[switch]$DryRun){
 if($SelectedKind-notin@('Connected','Disconnected')-or$SelectedMode-notin@('Append','Replace')){throw 'Unsupported connection type or import mode.'}
 if(!(Test-BplGameFolder $Root)){throw 'Bluetooth Personal Link was not found in the selected game folder.'}
 $null=Assert-BplLocalPath $script:bplImporter
 $summary=Get-BplInputSummary $InputFolder
 if(!$DryRun-and@(Get-Process -Name Cyberpunk2077 -ErrorAction SilentlyContinue).Count){throw 'Close Cyberpunk2077 completely before importing new audio. Stable Audioware loads new recordings during a full game launch.'}
 $arguments=@{GameFolder=[IO.Path]::GetFullPath($Root);AudioFolder=$summary.Folder;Kind=$SelectedKind;Mode=$SelectedMode}
 if($DryRun){$arguments.DryRun=$true}
 return $arguments
}
if(!$GameFolder){$GameFolder=Find-BplGameFolder $PSScriptRoot}
if($NoUI){
 if(!$GameFolder){throw 'No game was found above this tool. Supply -GameFolder for a read-only check.'}
 if(!$AudioFolder){$AudioFolder=Get-BplInbox $GameFolder $Kind}
 $arguments=Get-BplImportArguments $GameFolder $AudioFolder $Kind $Mode -DryRun
 $result=& $script:bplImporter @arguments
 [pscustomobject]@{Status='ValidatedDryRun';NoUI=$true;GameFilesChanged=$false;GameFolder=$arguments.GameFolder;AudioFolder=$arguments.AudioFolder;Result=$result}
 return
}
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[Windows.Forms.Application]::EnableVisualStyles()
$script:bplBusy=$false;$script:bplWorker=$null;$script:bplAsync=$null;$script:bplUsingInbox=!$AudioFolder
$form=New-Object Windows.Forms.Form
$form.Text='Bluetooth Personal Link | Local Audio';$form.ClientSize=New-Object Drawing.Size(700,565);$form.StartPosition='CenterScreen';$form.MinimumSize=New-Object Drawing.Size(716,604);$form.BackColor=[Drawing.Color]::FromArgb(17,24,34);$form.ForeColor=[Drawing.Color]::White;$form.Font=New-Object Drawing.Font('Segoe UI',10)
function Label([string]$Text,[int]$X,[int]$Y,[int]$Width,[int]$Height=26){$xLabel=New-Object Windows.Forms.Label;$xLabel.Text=$Text;$xLabel.SetBounds($X,$Y,$Width,$Height);$form.Controls.Add($xLabel);return $xLabel}
function Button([string]$Text,[int]$X,[int]$Y,[int]$Width){$xButton=New-Object Windows.Forms.Button;$xButton.Text=$Text;$xButton.SetBounds($X,$Y,$Width,33);$xButton.BackColor=[Drawing.Color]::FromArgb(54,211,216);$xButton.ForeColor=[Drawing.Color]::Black;$xButton.FlatStyle='Flat';$form.Controls.Add($xButton);return $xButton}
$title=Label 'BLUETOOTH PERSONAL LINK' 22 16 650 34;$title.Font=New-Object Drawing.Font('Segoe UI',18,[Drawing.FontStyle]::Bold);$title.ForeColor=[Drawing.Color]::FromArgb(54,211,216)
$null=Label 'Import your own local recordings. Fully restart Cyberpunk after importing.' 23 55 650 34
$null=Label 'Game folder' 23 101 130
$gameBox=New-Object Windows.Forms.TextBox;$gameBox.SetBounds(23,130,535,27);$gameBox.ReadOnly=$true;if($GameFolder){$gameBox.Text=$GameFolder};$form.Controls.Add($gameBox)
$gameBrowse=Button 'Browse...' 571 127 104
$null=Label 'Connection type' 23 177 150
$kindBox=New-Object Windows.Forms.ComboBox;$kindBox.SetBounds(23,205,230,28);$kindBox.DropDownStyle='DropDownList';$null=$kindBox.Items.AddRange(@('Connected','Disconnected'));$kindBox.SelectedItem=$Kind;$form.Controls.Add($kindBox)
$null=Label 'Import mode' 280 177 150
$modeBox=New-Object Windows.Forms.ComboBox;$modeBox.SetBounds(280,205,230,28);$modeBox.DropDownStyle='DropDownList';$null=$modeBox.Items.AddRange(@('Append','Replace'));$modeBox.SelectedItem=$Mode;$form.Controls.Add($modeBox)
$null=Label 'Append keeps existing entries. Replace changes only the selected connection type.' 23 245 655 35
$null=Label 'Audio input folder (WAV, MP3, OGG or FLAC; at most20MiB each)' 23 285 650
$audioBox=New-Object Windows.Forms.TextBox;$audioBox.SetBounds(23,315,535,27);$audioBox.ReadOnly=$true;if($AudioFolder){$audioBox.Text=$AudioFolder};$form.Controls.Add($audioBox)
$audioBrowse=Button 'Browse...' 571 312 104
$openInbox=Button 'Open inbox' 23 357 144
$importButton=Button 'Import recordings' 456 357 219
$progress=New-Object Windows.Forms.ProgressBar;$progress.SetBounds(23,408,652,15);$progress.Style='Blocks';$form.Controls.Add($progress)
$status=Label '' 23 434 650 100;$status.ForeColor=[Drawing.Color]::FromArgb(233,225,143)
$controls=@($gameBrowse,$audioBrowse,$kindBox,$modeBox,$openInbox,$importButton)
function Refresh-BplForm {
 if($script:bplBusy){return}
 try{
  if(!(Test-BplGameFolder $gameBox.Text)){throw 'Choose the Cyberpunk game folder where Bluetooth Personal Link is installed.'}
  if($script:bplUsingInbox){$audioBox.Text=Get-BplInbox $gameBox.Text ([string]$kindBox.SelectedItem)}
  $summary=Get-BplInputSummary $audioBox.Text;$status.Text=('{0} supported files, {1:N1}MiB. Use recordings you own or have permission to use.'-f$summary.Count,($summary.Bytes/1MB));$importButton.Enabled=$true
  if(@(Get-Process -Name Cyberpunk2077 -ErrorAction SilentlyContinue).Count){$status.Text+=' Close Cyberpunk before importing.'}
 }catch{$status.Text=$_.Exception.Message;$importButton.Enabled=$false}
}
$gameBrowse.Add_Click({$dialog=New-Object Windows.Forms.FolderBrowserDialog;try{$dialog.Description='Select the Cyberpunk2077 game root (containing bin and r6).';$dialog.ShowNewFolderButton=$false;if($gameBox.Text){$dialog.SelectedPath=$gameBox.Text};if($dialog.ShowDialog($form)-eq'OK'){$gameBox.Text=$dialog.SelectedPath;$script:bplUsingInbox=$true;Refresh-BplForm}}finally{$dialog.Dispose()}})
$audioBrowse.Add_Click({$dialog=New-Object Windows.Forms.FolderBrowserDialog;try{$dialog.Description='Choose the local folder containing your recordings.';$dialog.ShowNewFolderButton=$true;if($audioBox.Text-and(Test-Path -LiteralPath $audioBox.Text -PathType Container)){$dialog.SelectedPath=$audioBox.Text};if($dialog.ShowDialog($form)-eq'OK'){$audioBox.Text=$dialog.SelectedPath;$script:bplUsingInbox=$false;Refresh-BplForm}}finally{$dialog.Dispose()}})
$kindBox.Add_SelectedIndexChanged({Refresh-BplForm})
$openInbox.Add_Click({try{$inbox=Get-BplInbox $gameBox.Text ([string]$kindBox.SelectedItem);$null=New-Item -ItemType Directory -Path $inbox -Force;$null=Assert-BplLocalPath $inbox;$script:bplUsingInbox=$true;$audioBox.Text=$inbox;Start-Process -FilePath (Join-Path $env:WINDIR 'explorer.exe') -ArgumentList @('"'+$inbox+'"') -WindowStyle Normal;Refresh-BplForm}catch{$status.Text=$_.Exception.Message}})
$importButton.Add_Click({
 try{
  $arguments=Get-BplImportArguments $gameBox.Text $audioBox.Text ([string]$kindBox.SelectedItem) ([string]$modeBox.SelectedItem)
  $script:bplBusy=$true;foreach($control in $controls){$control.Enabled=$false};$progress.Style='Marquee';$progress.MarqueeAnimationSpeed=25;$status.Text='Validating and importing local recordings. Keep this window open...'
  $script:bplWorker=[Management.Automation.PowerShell]::Create();$null=$script:bplWorker.AddCommand($script:bplImporter).AddParameters($arguments);$script:bplAsync=$script:bplWorker.BeginInvoke()
 }catch{$status.Text=$_.Exception.Message;if($script:bplWorker){$script:bplWorker.Dispose()};$script:bplWorker=$null;$script:bplAsync=$null;$script:bplBusy=$false;foreach($control in $controls){$control.Enabled=$true};$progress.Style='Blocks'}
})
$timer=New-Object Windows.Forms.Timer;$timer.Interval=250
$timer.Add_Tick({
 if(!$script:bplBusy-or!$script:bplAsync-or!$script:bplAsync.IsCompleted){return}
 try{
  $output=$script:bplWorker.EndInvoke($script:bplAsync)
  if($script:bplWorker.Streams.Error.Count){throw $script:bplWorker.Streams.Error[0].ToString()}
  $result=@($output|Where-Object {$_.PSObject.Properties['PoolRecordings']}|Select-Object -Last 1)
  if($result.Count-ne1){throw 'The importer returned no verified result. Check the input files and existing audio list before retrying.'}
  $status.Text=('Import complete: {0} new files; {1} recordings in this connection pool. '-f$result[0].NewAudioFiles,$result[0].PoolRecordings)
  if($result[0].GameRestartRequired){$status.Text+='Fully close and restart Cyberpunk2077. Audioware must load the new audio during launch.'}else{$status.Text+='No audio changes were necessary.'}
 }catch{$detail=$_.Exception.Message;if($script:bplWorker-and$script:bplWorker.Streams.Error.Count){$detail=$script:bplWorker.Streams.Error[0].ToString()};$status.Text='Import stopped: '+$detail+' Keep any importer backups. No game restart was attempted.'}
 finally{if($script:bplWorker){$script:bplWorker.Dispose()};$script:bplWorker=$null;$script:bplAsync=$null;$script:bplBusy=$false;$progress.Style='Blocks';foreach($control in $controls){$control.Enabled=$true}}
})
$form.Add_FormClosing({param($sender,$eventArgs)if($script:bplBusy){$eventArgs.Cancel=$true;$status.Text='Import is still running. Wait for its verified result before closing this window.'}})
$form.Add_Shown({Refresh-BplForm;$timer.Start()})
try{[void]$form.ShowDialog()}finally{$timer.Stop();$timer.Dispose();if($script:bplWorker){$script:bplWorker.Dispose()};$form.Dispose()}
