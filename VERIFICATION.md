# Source-review preparation checks

Copyright 2026 Isamu Yuudai. This new guide is licensed under CC BY 4.0; see LICENSE.md.

Checks performed on 10 November 2026 while preparing this repository:

- Extracted the exact original creator-kit entry bytes: 40 files for 1.3 and 26 for beta6. Every snapshot file was checked against the corresponding original archive entry hash. All 16/10 matching main-package entries also match the preserved `package/` files.
- Validated all four manifests and both complete snapshot inventories with the new builder. Extra/missing files, byte changes, unsafe paths, case collisions and linked source paths are rejected.
- Built all four content reproductions twice under PowerShell **7.6.9**. All 92 output entries across each complete run matched their original uncompressed hashes. Each new ZIP had the same SHA-256 on both runs.
- Checked the new builder with the Windows PowerShell **5.1.26100.9711** parser: zero syntax errors. A full file-launched build under that runtime was blocked by the machine's existing execution policy; no policy setting was changed. Full new-builder runtime verification is therefore limited to PowerShell 7.6.9.
- In a separate disposable copy, deliberately changed source bytes and added an extra snapshot file; both were rejected. An output-directory junction was rejected before any child directory was created in its target. The immutable repository snapshots remained unchanged.
- Checked the public candidate file inventory and strict UTF-8 text for personal machine paths, email addresses, common token/private-key patterns, null bytes, private handoff/receipt names, unexpected media, executable binaries and nested distribution archives. None was found. The two preserved MP3 copies both match the cleared historical edited-media hash. The explicitly documented beta6 synthetic fixture-label exception is retained.
- A separate read-only review checked source completeness, build instructions, licence scopes and historical-versus-current claims. Its output-ancestor guard finding was corrected before completion.

Reproduced ZIP identities on the tested runtime (these are **new container hashes**, not the original submitted archive hashes):

| Reproduction | Entries | Bytes | SHA-256 |
| --- | ---: | ---: | --- |
| 1.2.0-beta.6 main | 10 | 91,903 | `F107BB11769FF044C00EA39BA56CC58BB73C909F61B630459FF4397DDE15EEA6` |
| 1.2.0-beta.6 creator | 26 | 188,599 | `F182C6109D624F108FDF78A6B06DFC64940DBE79DC81420990D31BD143C53BA0` |
| 1.3.0-beta.1 main | 16 | 124,888 | `62A09F20DCD528F9CC37CA1343FD1633B22DEC2520B2FA84ACAEB41AC9B88174` |
| 1.3.0-beta.1 creator | 40 | 263,401 | `7710D02E7D0D3B74845704B36FC05CECAB897635DC9908CD12DC055C6772D5EE` |

The build reports under ignored `outputs/` record these hashes alongside the original container hashes and explicitly mark original-container identity as not expected. The fixed metadata/stored-entry format was inspected as part of review. Cross-runtime identical ZIP encoding is not claimed.

These checks establish source integrity and the stated local reproduction behavior. They are not a comprehensive security certification. The historical addon/utility fixture suites were not rerun as part of this source preparation. No game, Vortex, actual import into a live installation, audible capture, visible-window test, co-op test, antivirus scan, VirusTotal submission or Nexus server-side verification was performed. No original release artifact was changed, and no account, email or publication action was taken.
