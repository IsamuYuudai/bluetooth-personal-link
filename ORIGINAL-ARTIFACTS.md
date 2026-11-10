# Historical archive identities

Copyright 2026 Isamu Yuudai. This new guide is licensed under CC BY 4.0; see LICENSE.md.

These identities describe the preserved original local archives associated with the Nexus submissions. Original ZIP containers are not nested inside this source repository. Their creator-kit contents were extracted without rewriting the files; the corresponding main-package content is preserved within each kit's `package/` directory.

| Version / kind | Nexus file ID | Original archive | Bytes | Entries |
| --- | --- | --- | ---: | ---: |
| 1.3.0-beta.1 main | 175773 | `Bluetooth-Personal-Link-v1.3.0-beta.1.zip` | 76,212 | 16 |
| 1.3.0-beta.1 creator | 175774 | `Bluetooth-Personal-Link-Creator-Kit-v1.3.0-beta.1.zip` | 126,413 | 40 |
| 1.2.0-beta.6 main | 175587 | `Bluetooth-Personal-Link-v1.2.0-beta.6.zip` | 64,542 | 10 |
| 1.2.0-beta.6 creator | 175588 | `Bluetooth-Personal-Link-Creator-Kit-v1.2.0-beta.6.zip` | 98,801 | 26 |

Original archive SHA-256 values:

```text
175773  E74CBC2DFA5BF1FF1B67B2969DFF2CB55D3091F1C55804828A51274CF82E0FEA
175774  1F2861D830ED10DDAC2443DAC1FC7545C9E3209DB975436BA09CD46813D80369
175587  5A6F0CD43433CB1C7B37348D1667FD0580DA1397B6417D84EA0ADD594558A9DE
175588  F86EB6EB01A3DBBE7AC2BABB39A1EA4AF8E68CB00151EBF9F4DD798E7F7CB6D9
```

The manifest for each artifact records these values and every entry's original path, size and SHA-256. A `sourcePath` points to the preserved file inside the matching snapshot. The 1.3 main/creator identity and Nexus-ID association are recorded in the original local upload/fix records. This source preparation did not independently download the quarantined files from Nexus or establish the server's current status. Remote files should be matched to these hashes before treating them as the same artifacts.

No EXE, DLL, native plugin, dependency binary or nested distribution archive appears among any of the four original file lists. The only non-text asset is the CC0 MP3 copied into each relevant `package/`. CMD/PowerShell scripts are readable executable source, and the historical optional test wrapper's C# source is embedded in the PowerShell runner. There is no missing compiled application project for these submissions.

## What a reproduction establishes

The new builder reproduces each original archive's **entry names and uncompressed file bytes**. It verifies every output entry against the historical per-file manifest. Its output names end in `-content-reproduction.zip`, keeping them distinct from the submitted archives.

The old packaging script rewrote dated evidence and used mutable file timestamps and environment-specific ZIP compression. Its raw preparatory script also depended on local development paths and older working folders. Those scripts are not bundled here because they are not a portable public build route and were not shipped source components. Their omission does not remove runtime/utility source from the historical snapshots.

The new builder uses preserved, already-generated historical documents as inputs rather than regenerating their dates. Fixed new ZIP metadata and no compression make repeated output reproducible on the tested local runtime. This does **not** reconstruct the original ZIP's timestamps, compressed streams, ordering or container SHA-256. Original container identity and verified entry identity are separate fields in the output report.

The already-submitted MP3 bytes are also preserved rather than re-encoded. Known recording provenance and transformation details are in COMPONENTS.md; the exact original encoder command/build was not recovered.

## Historical evidence limits

Embedded candidate status, publication flags, scan statements and test timestamps are preserved exactly as they appeared at build time. Do not edit them to present a later state. Local records of scans/uploads outside the snapshots remain distinct evidence, and this repository does not claim Nexus acceptance or a fresh antivirus scan.

Historical beta6 reports describe 45 mocked Lua groups and 11 importer groups. Historical 1.3 reports describe 52 mocked Lua, 11 importer and 12 manager groups. Gameplay, actual visible-window interaction, audible output and live co-op require separate tests. See VERIFICATION.md for the checks actually performed while preparing this source collection.
