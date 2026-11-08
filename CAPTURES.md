# Website capture provenance

Captured on November 8, 2026. These are real psi executions, not illustrations or generated screenshots.

## Model and source

All published runs select `openrouter/anthropic/claude-opus-5.5` and receive actual responses from Claude Opus 5.5. `anthropic/claude-opus-5.5` is the identifier verified in OpenRouter's live model catalog; it corresponds to the requested `claude-opus-5-5`. No model names or response text were changed in the images.

The captured psi source is commit [`b960ff4`](https://github.com/siraben/psi/commit/b960ff4), archived from the working repository. Native Linux and portable static Linux builds were compiled from that source. Captures use fresh, small demonstration files.

## Terminal demo

- `assets/terminal-opus.png` is an actual Linux terminal display: psi reads `hello.py`, adds a default value to `greet`, and runs the script with Python. The successful output and real model footer are visible. Only the blank surrounding display area and terminal multiplexer status bar were cropped.
- `assets/psi-terminal.cast` is the original asciinema v2 terminal recording, at 112 columns × 32 rows, lasting 32.325 seconds. It includes the prompt being typed and the actual read/edit/run turn.
- `assets/psi-terminal.mp4` renders that same recorded output with asciinema-agg 1.9.0 and FFmpeg. Idle gaps are capped at two seconds for a 14.079-second video. The video is a rendering of the real terminal recording; the PNG is a capture of the real displayed terminal.

## Linux console

`assets/tty-opus.png` is the QEMU framebuffer of a real NixOS Linux virtual console, not a desktop terminal made to resemble one. The guest uses kernel 6.18.38 and a current standalone static psi build. A genuine Opus 5.5 turn inspects the actual `lsblk` and `findmnt` output and explains this live system's ISO, squashfs, tmpfs, and overlay layout. No hard disk is attached. The successful command-line turn is reopened in psi's interactive UI for the screenshot, with its real model footer. `assets/tty-partitions.cast` records the actual turn; `assets/tty-partitions.mp4` renders that recording.

## Tiny Core Linux

`assets/tinycore-opus-5-5.png` is a fresh QEMU framebuffer capture of Tiny Core Linux 16.2, kernel 6.12.11, running the current static psi build. The visible Opus 5.5 turn executes shell tools and identifies the guest environment.

The VM reproduction harness comes from [PR #56](https://github.com/siraben/psi/pull/56), commit [`19a51395`](https://github.com/siraben/psi/commit/19a51395e9cae27bb91bb0f7b7f961d9b599e792). The PR's older screenshots were references only; the published screenshot was captured afresh with the requested model.

## Haiku

`assets/haiku-opus.png` is a real 1280×800 QEMU framebuffer capture of Haiku R1/beta6, release kernel hrev59866+79. The native Sakura artwork window floats over the right side of Haiku Terminal and leaves psi's actual Opus 5.5 footer visible. This final demo was rerolled from scratch in a new empty workspace and a fresh live interactive psi session: no previous app source or conversation was reused, and the creating TUI was never restarted or resumed for the capture. Terminal uses UTF-8 and psi's `pi-light` palette.

In that live session, Opus 5.5 wrote the new 261-line `assets/haiku-sakura.cpp`, compiled it with Haiku GCC 13.3/C++17 and `-lbe`, corrected a C++ math-header lookup issue, and actually opened the app. It then inspected screenshots and refined its layout within that same creating session. The app uses `BApplication`, `BWindow`, and `BView` to draw ivory washi paper, an ink-style sakura tree, pink blossoms, red vertical Japanese poetry 春風に / 桜舞う, and a red cherry seal. Its only window title is `Sakura`; there is no secondary artwork-name label or signature. Japanese uses [Noto Serif CJK JP](https://github.com/notofonts/noto-cjk). The C++ file is the actual model-written source, not a reconstruction or image retouch.

`assets/haiku-sakura-window.mp4` is a nine-second excerpt of the actual final-version window opening during that same fresh interactive creation, captured continuously before it opened. Real QEMU framebuffer samples were taken four times per second, and the clip preserves measured monotonic intervals. It is not a staged relaunch by the capture operator, a resumed session, an invented animation, or time-compressed footage. The encoded clip is 9.04 seconds at 1280×800.

Psi itself was compiled inside the guest from the current source with strict C89 and `-Werror`, Lua 5.4.9, and Haiku SDK headers. The harness comes from [PR #51](https://github.com/siraben/psi/pull/51). The official beta6 image was SHA-256 verified: `bb7743474fd175aea511be1799764ba054465285bbdf54c4722ca61d1fb4f5c9`. Development headers were extracted into Haiku's non-packaged SDK location with explicit compiler/startfile paths; BSD/network libraries were linked through Makefile overrides. Psi's source was not patched for the capture.

The newer repository kernel hrev59866+92 panicked during early startup in this QEMU TCG configuration. The successful run uses the release +79 live environment and does not claim that the newer kernel worked.

## Windows

`assets/windows-opus.png` shows native Windows 11 Pro 10.0.26300.9818, Windows Terminal 1.24.12741.0 and `cmd.exe`, with no WSL. A clean-source Cosmopolitan APE build of psi was copied unchanged to Windows as `psi.exe` (6,409,016 bytes; SHA-256 `5fe02357f5f07c84fee9a0a3b218a8fb6e349e3f98cd55332952ad52d4ea7b0c`). Actual Opus 5.5 read `hello.cmd`, added a default name, and ran it successfully. That genuine successful session was reopened in the TUI for the screenshot, with its real model footer.

The screenshot was captured from the actual desktop over RDP. Only the RDP client's top toolbar was cropped to remove a private network address; terminal text and model labels were untouched. See [Windows provenance](assets/windows-provenance.txt). Temporary credentials and launchers were removed after capture.

## Scope

Screenshots are evidence of these particular runs and configurations. They are not an operating-system compatibility test suite or a performance benchmark. No credentials or unrelated prior session transcripts are included in the media.
