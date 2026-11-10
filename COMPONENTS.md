# Source and component map

Copyright 2026 Isamu Yuudai. This new guide is licensed under CC BY 4.0; see LICENSE.md.

| Component | Location inside each historical snapshot | Purpose / licence |
| --- | --- | --- |
| CET addon | `package/bin/x64/plugins/cyber_engine_tweaks/mods/BluetoothPersonalLink/init.lua` | Complete readable runtime source; historical MIT. |
| Default settings/selections | Adjacent `settings.json`, `clips.json` | Public defaults, not a user's private selections; historical MIT. |
| Audio event manifest | `package/r6/audioware/BluetoothPersonalLink/audios.yaml` | Registers the included public starter; historical MIT configuration. |
| Importer | `tools/Import-BPLAudio.ps1` | Complete readable local audio-import tool; historical MIT. |
| Manager and launcher, 1.3 only | `tools/Manage-Audio.ps1`, `tools/Manage-Audio.cmd` and packaged copies | Optional readable local Forms tool and launcher; historical MIT. |
| Lua tests and native wrapper | `work/tests/` | Complete Lua harness and PowerShell embedded C# P/Invoke source. User supplies the Lua runtime; historical MIT. |
| Importer fixtures | `work/importer-tests/Test-Importer.ps1` | Generates isolated local fixtures; historical MIT. Generated fixture data is excluded. |
| Manager fixtures, 1.3 only | `work/Test-AudioManager.ps1` | Local dummy-game/async-import fixtures; historical MIT. Generated fixture data is excluded. |
| Historical guides/templates/evidence | Snapshot root, `templates/`, `evidence/` or historical `work/` reports | Preserved build-time documentation under its original MIT scope; no new test outcome implied. |
| Starter recording | `package/r6/audioware/BluetoothPersonalLink/starter_chime.mp3` | Historical edited CC0 recording by gecop. Separately credited below. |
| New reproduction tooling/metadata | Repository `tools/`, `manifests/`, `.gitattributes`, `.gitignore` | MIT by Isamu Yuudai; not a historical shipped file. |
| New explanatory guides | Explicit root Markdown list in LICENSE.md | CC BY 4.0 by Isamu Yuudai; not a replacement licence for historical guides. |

Cyber Engine Tweaks, Audioware, Native Settings/Unified Mod Settings and Cyberpunk 2077 are referenced integrations/dependencies. Their original authors retain their rights. No source copied from their development repositories, framework binary or game file is included in this collection. The historical addon and tools contain their API calls, not a bundled copy of those frameworks. A developer must separately obtain any runtime needed to execute tests or the game addon.

## Starter recording provenance

- Creator: **gecop**.
- Recording title: **marshall tufton bluetooth.wav**, published 17 November 2020.
- Source: [Freesound sound 545028](https://freesound.org/people/gecop/sounds/545028/).
- Original HQ preview URL recorded by the project: `https://cdn.freesound.org/previews/545/545028_3562198-hq.mp3`.
- Dedication: [CC0 1.0 Universal](https://creativecommons.org/publicdomain/zero/1.0/); full reference text in `LICENSES/CC0-1.0.txt`.
- Historical original-preview SHA-256: `B4A6F90C02E781383826CA85E95EE32134C324327E37D50A9E5F920F5AC3F190` (51,504 bytes). The original preview is not bundled a second time.
- Included edited-media SHA-256: `0469066EB42C3BA28CC3340F637A596F986A5F0D86ABFED8406CD8B59F8D676F` (51,309 bytes).
- Recorded transformation: +10 dB gain, FFmpeg/libmp3lame, 192 kbps MP3, 48 kHz stereo. The exact command and encoder build were not located; no bit-identical re-encoding recipe is claimed.

The historical notices describe a real speaker chime, with no AI speech added. Their recorded decoding/loudness evidence is preserved as historical evidence. The repository reproduction checks supplied bytes rather than rerunning an audio decoder or certifying universal playback. Additional user recordings retain their own rights; importing a recording does not authorise publishing it.

## Historical beta6 test labels

The beta6 harness contains the synthetic `ncc_bluetooth_personallink_connected` and `ncc_bluetooth_personallink_disconnected` fixture labels at three test-source lines. Their exact historically submitted bytes are preserved for source completeness. No recording, private bank, user's selected clip list or source filename is supplied by those strings. This preservation is limited to those historical fixtures and does not publish any private voice pack. The 1.3 harness instead uses neutral `bpl_test_*` labels.
