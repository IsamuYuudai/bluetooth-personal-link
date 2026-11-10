BLUETOOTH PERSONAL LINK 1.3.0 BETA

Plays a local connection notification after V's personal cable reports a completed
connection. The public download includes one cleared starter chime. You can import
your own recordings with the optional audio setup tool.

Install with Vortex
Install Cyber Engine Tweaks, RED4ext, redscript and the official Audioware release
with its requirements first. On the Nexus Files page choose Mod manager download
for this mod. In Vortex install, enable and Deploy Mods. Fully restart Cyberpunk.
No separate installer is required for the included starter sound.

Controls
If Native Settings is installed, open Mods > Bluetooth Personal Link. Unified Mod
Settings can display the same tab. These integrations are optional. Without them,
open the CET overlay and use the Bluetooth Personal Link panel.

Test connection sound queues a preview while menus/CET are open; close them to hear
it. The notification also plays after a supported local Jack In completes. The
mod observes the connection without replacing device interaction or quest logic.
Volume and boost affect only these notifications. Start with a low boost.

Add your own sounds
See SOUND-PACKS.txt or the in-game CET guide. Drop recordings into the audio-inbox
folders, close the game and run docs\tools\Manage-Audio.cmd. It opens the inbox,
imports your selected folder and generates the bank/list. Restart Cyberpunk.
Reload sound selections can select existing loaded events during gameplay; new
bank files need a full restart with the stable version of Audioware.

Uninstall
Disable or Remove this mod in Vortex, then Deploy Mods. Close the game first.
Keep any user inbox recordings and importer backups you want to retain. Imported
user banks are separate; SOUND-PACKS.txt explains removing those safely.

Scope and validation
The notifications are local to each PC. This mod does not synchronize sounds,
change multiplayer time, contact a server, collect telemetry or alter game saves.
Code, UI, tools and documentation were predominantly generated with OpenAI Codex under human direction. The included chime is a real CC0 recording, not AI speech. Existing beta6
connection playback was tested at a physical access point; this beta adds menu
and import UX and currently has 52 isolated behavioral test groups passing.
Live regression testing of this candidate is pending. It is not a claim of
universal device, quest or multiplayer compatibility.

Upgrade note
Before replacing a previous version, back up your own clips.json, settings.json,
audio-inbox recordings and separate imported user bank. A normal Vortex update
can restore this package's public defaults. Keep those backups and restore or
re-import your personal selections after the update with the game closed.

Optional tool validation: 12 isolated Windows PowerShell 5.1 groups pass. These
test file/manifest handling and asynchronous import mechanics; no new audible
playback or visible-window interaction is claimed for this candidate.
