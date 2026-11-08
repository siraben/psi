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

`assets/tty-opus.png` is the QEMU framebuffer of a real NixOS Linux virtual console, not a desktop terminal made to resemble one. The guest uses kernel 6.18.38, a current standalone static psi build, and a real Opus 5.5 turn that executes `uname` and reads the demonstration source.

## Tiny Core Linux

`assets/tinycore-opus-5-5.png` is a fresh QEMU framebuffer capture of Tiny Core Linux 16.2, kernel 6.12.11, running the current static psi build. The visible Opus 5.5 turn executes shell tools and identifies the guest environment.

The VM reproduction harness comes from [PR #56](https://github.com/siraben/psi/pull/56), commit [`19a51395`](https://github.com/siraben/psi/commit/19a51395e9cae27bb91bb0f7b7f961d9b599e792). The PR's older screenshots were references only; the published screenshot was captured afresh with the requested model.

## Scope

Screenshots are evidence of these particular runs and configurations. They are not an operating-system compatibility test suite or a performance benchmark. No credentials or unrelated prior session transcripts are included in the media.
