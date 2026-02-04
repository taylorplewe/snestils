# snestils
<img width="3091" height="1059" alt="out" src="https://github.com/user-attachments/assets/7665ef1d-545a-4d71-988d-44c436ddf54d" />

A CLI that encompasses a suite of utilities for working with Super Nintendo/Super Famicom ROM files. I really wanted to just have one tool I use for all the different things you have to do to a ROM to make it runnable on real hardware. Nick from MouseBiteLabs has written [some great instructions on how to do so](https://mousebitelabs.com/2017/09/14/how-to-make-a-snes-reproduction-cartridge/), but it requires the use of at least four different (somewhat jank/sketchy) tools from the internet to do all the different things.

A rather ambitious goal for this program is to attain feature parity with ucon64, just the SNES-specific features. And keep in mind, ucon64 only supports IPS, APS and PPF patch formats, and not BPS or UPS.

## Utilities
| Name | Description |
| - | - |
| `info` | Display all relevant information about a ROM such as the internal checksums, ROM size, version number and title |
| `fix-checksum` | Fix the internal ROM's checksum and complement |
| `split` | Split the ROM file into different size chunks, for writing to various (E)EPROMs |
| `patch` | Apply a patch file to a ROM |

### Supported patch file types
- IPS
- UPS
- BPS

---

### Thanks to
- [SNESdev Wiki](https://snes.nesdev.org), particularly the pages:
  - [ROM header](https://snes.nesdev.org/wiki/ROM_header)
  - [ROM file formats](https://snes.nesdev.org/wiki/ROM_file_formats)
- [mousebitelabs.com](mousebitelabs.com)
- ucon64; I have no idea where the official repo is but do a GitHub search and you'll see plenty of mirrors
- [termshot](https://github.com/homeport/termshot) for the terminal screenshot
