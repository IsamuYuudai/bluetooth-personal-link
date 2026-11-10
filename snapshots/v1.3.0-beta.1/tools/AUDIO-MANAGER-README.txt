BLUETOOTH PERSONAL LINK - OPTIONAL LOCAL AUDIO MANAGER

1. Completely close Cyberpunk 2077.
2. Double-click Manage-Audio.cmd in this folder. When installed under the mod's
   docs/tools directory, it finds the game by walking its parent folders.
   Otherwise use Browse beside Game folder to select the game's root folder.
3. Choose Connected or Disconnected. Open inbox opens that type's local audio
   folder; put your own recordings there, or Browse to an existing folder.
4. Choose Append to keep the current pool, or Replace to replace only the
   selected type's pool. The other type is preserved. Supported formats are
   WAV, MP3, OGG and FLAC; maximum128 input files,20MiB per file.
5. Click Import recordings. Keep the window open until the result appears.
6. Fully restart Cyberpunk so stable Audioware loads the newly added bank.
   Reloading CET mods or saved settings does not load new Audioware files.

The manager runs the readable Import-BPLAudio.ps1 beside it. It creates a
separate managed user-audio bank and updates clips.json, making backups of
the existing audio list and managed manifest before changes. Imported files
are named by content hash; importing the same recording again does not add
duplicate audio. Replace does not delete the older recordings from disk.
Keep importer backups if an import is interrupted or reports an error.

Only use recordings you own or have permission to use. Nothing is downloaded,
uploaded, recorded from your microphone or installed as a resident helper.
The tool refuses new imports while Cyberpunk is running. It does not change
Windows security settings or start/restart the game.

Optional read-only validation, with no form or file changes:
  powershell.exe -NoProfile -File .\Manage-Audio.ps1 -NoUI
You can supply -GameFolder and -AudioFolder when testing another location.
NoUI validates inputs through the importer's DryRun and is not a playback test.

Tests for this build cover Windows PowerShell5.1 parsing, ancestor detection,
Unicode paths, read-only validation, invalid audio/path limits, running-game
refusal, isolated asynchronous import, idempotence, selected-pool replacement
and externally edited manifest refusal. No audible in-game playback or visible
window interaction is claimed by those tests.
