BLUETOOTH PERSONAL LINK
Standalone beta 1.2.0-beta.6 | Target: Cyberpunk 2077 2.5

Plays a local sound when V completes an ordinary personal-link connection.
With multiple sounds installed, a shuffled cycle plays every usable recording
before another cycle begins and avoids immediate repeats.

The public package includes ONE real-device Bluetooth chime as its starter
sound, with a +10 dB level edit to make it easier to hear over game ambience.
It is not a spoken voice pack. Add recordings you have permission to
use to create a larger pool. See SOUND-PACKS.txt and THIRD-PARTY-NOTICES.txt.

REQUIREMENTS
Install compatible versions of these frameworks separately:
- Cyber Engine Tweaks
- Audioware and its dependencies, including redscript, Codeware, TweakXL and RED4ext
Follow each framework's installation instructions. None are bundled here.
https://wiki.redmodding.org/cyber-engine-tweaks
https://cyb3rpsych0s1s.github.io/audioware/

NightCoop, any collection, and other personal-link mods are not required.

INSTALL
Close the game. Install the ZIP with Vortex, or merge its bin and r6 folders
into the Cyberpunk 2077 folder containing bin, r6 and archive.
Start the game normally. New audio requires a full restart, not a CET reload.
Back up custom settings and sound lists before updating an existing install.

SETTINGS
Open the CET overlay to see the Bluetooth Personal Link settings window.
It provides enable/disable, volume, audio boost, cooldown, optional disconnect audio,
preview and reload controls. Use Save settings to keep changes across launches.
The mod's settings.json and clips.json can also be edited with the game closed.

Console commands:
GetMod("BluetoothPersonalLink").test()
GetMod("BluetoothPersonalLink").reloadSettings()
GetMod("BluetoothPersonalLink").setEnabled(false)
GetMod("BluetoothPersonalLink").setEnabled(true)
GetMod("BluetoothPersonalLink").status()
GetMod("BluetoothPersonalLink").diagnostic()

Allow at least five seconds between previews at the default cooldown.
Volume defaults to 0.8, Audio boost to 0 dB, and disconnect announcements to off.
If notifications are too quiet, raise Audio boost (dB) gradually, up to 24 dB.
Boost affects only this addon's next sound; it does not change the game's Master
Volume, normal dialogue, effects or other mods. Save settings to retain it.
The gainDb JSON value is clamped to 0-24 and missing values default to zero.
Audio requests normal playback speed during time dilation.

PREVIEWING
Press Test connection sound, then close CET and any game menus and return to
unpaused gameplay. A test requested with CET open, a menu open or the game
paused queues one preview instead of trying to play into paused audio. The
request expires after 30 real seconds and is cancelled by disabling the addon
or resetting the game session. It will not keep replaying automatically.
The menu check also applies when NightCoop leaves gameplay unpaused behind a
menu. The read-only diagnostic() command reports audio version, event durations,
playback settings and menu/pause state; it does not play or alter audio.

An already-active connection sound uses separate menu recovery in beta.4:
after Audioware pauses sounds when a menu opens, the addon requests resume for
its own tracked sound only. It also requests resume when a connection sound is
queued while that menu state is already active. It does not unpause the game,
change NightCoop's pause state or resume other sounds. If the DynamicSoundEvent
factory is unavailable, ordinary Audioware playback is used without this targeted
protection. This fallback does not guarantee compatibility with every older
framework version or missing hook. New manual preview requests still wait for
CET and game menus to close, as described above.

INSTALLED LOCATIONS
bin\x64\plugins\cyber_engine_tweaks\mods\BluetoothPersonalLink
r6\audioware\BluetoothPersonalLink
Optional imported sounds: r6\audioware\BluetoothPersonalLinkUserAudio

COMPATIBILITY AND LIMITATIONS
Only the local player's standard Device personal-link path is observed.
Cancelled connections and duplicate callbacks do not trigger extra lines.
The addon sends no network messages and has no multiplayer dependency.
Other players need their own local installation to hear their own sounds.
Scripted story scenes, vehicles and special props can use different systems
and are not guaranteed to trigger these hooks.

If no sound plays, check Audioware's logs, confirm both addon folders exist,
restart fully and try the preview command while a game save is loaded. Close
CET and game menus within 30 seconds so the queued preview can play. Check the
result beside the preview control and the CET log for playback diagnostics.
The dependency reminder at the bottom is permanent text, not a missing-framework
error. Manual previews wait for gameplay; ordinary fallback playback can also
be paused by menus. Beta.4's tracked sound and targeted menu recovery were verified
at one ordinary access point while its breach screen opened. Other connection
types and framework combinations still need testing.
Missing audio events are skipped; if the whole pool is unavailable the addon
reports the issue and stays silent.

UNINSTALL
Close the game and remove only the two main addon folders listed above.
Keep a backup of any user recordings before removing the optional user-audio
folder. Do not remove CET, Audioware or their parent folders.

DEVELOPMENT AND TESTING
Lua, UI and documentation were generated with OpenAI Codex.
The included chime is a real CC0 recording, not AI-generated audio.
Automated tests exercise actual Lua with mocked game, audio and UI interfaces.
The louder starter's beta.3 preview was verified in a game-loopback capture on
8 November 2026. Beta.4 was then tested using the normal Jack In interaction at
one Watson/Northside access point. The recording matched the chime across its
duration while the breach screen opened, with one announcement and one targeted
resume request. This verifies recorded output for that connection, not perceived
loudness at every listening setup. Wider connection coverage, story scenes,
vehicles and live multiplayer behavior remain unverified.
Beta.6 gain was verified at +20 dB with a separately supplied recording during a normal connection at the same access point. The complete phrase matched the recorded output and the tester confirmed a suitable volume.
This is a beta prepared for testing; no Nexus upload has been performed.
