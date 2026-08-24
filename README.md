# NameplateSCT-Vanilla

A Vanilla 1.12.1 adaptation of [NameplateSCT](https://github.com/Justw8/NameplateSCT), rewritten for the original WoW client.

The project keeps the core idea of displaying scrolling combat text on enemy nameplates while using a lightweight implementation designed around the Vanilla 1.12 API.

> **Current status:** `0.4.2-test` — development build.

## Requirements

- World of Warcraft 1.12.1 compatible client
- Enemy nameplates enabled for normal use
- English combat-log strings are currently assumed by the implemented combat parser

No Ace3, LibEasing, LibSharedMedia, Masque, or replacement-nameplate addon is required.

Enhanced GUID/nameplate APIs are optional. When present, NameplateSCT-Vanilla uses them automatically for exact unit resolution; native nameplate discovery itself does not require them.

## Features currently implemented

- Native Vanilla nameplate discovery by scanning `WorldFrame`
- Native nameplate lifecycle tracking through `OnShow` / `OnHide`
- Native unit-name indexing from Blizzard nameplate FontStrings
- Target-nameplate resolution without requiring a GUID
- Unique visible-name fallback when the destination is unambiguous
- Optional exact GUID-to-nameplate resolution when compatible enhanced APIs are available
- Bidirectional GUID/nameplate tracking with recycled-frame cleanup
- Visibility-generation protection so active text cannot jump onto a recycled frame
- Normal hit fountain animation
- Critical hit / miss vertical animation with POW sizing
- Physical and spell-school colors
- Spell icons resolved from the Vanilla spellbook when available
- Continued combat text motion when a unit's nameplate disappears
- Internal debug/error capture and diagnostic slash commands

## v0.4.2-test

This patch introduces the native Vanilla nameplate backend.

- Detects Blizzard nameplate frames from the native `Nameplate-Border` texture.
- Accepts both native `Frame` and `Button` nameplate frame types.
- Scans only newly added `WorldFrame` children during normal operation.
- Hooks discovered nameplates once and tracks their `OnShow` / `OnHide` lifecycle.
- Reads and indexes the native name FontString for GUID-less resolution.
- Resolves the current target by exact GUID when available, otherwise by Vanilla target/nameplate state.
- Resolves a non-target name only when exactly one visible plate has that name.
- Refuses to guess when multiple same-named plates are ambiguous.
- Strictly validates enhanced GUID values as `0x...` before accepting them.
- Keeps the existing fountain and critical animations unchanged.

### Current compatibility boundary

`0.4.2-test` removes the GUID requirement from **nameplate discovery and target test rendering**. The existing automatic combat parser still consumes `RAW_COMBATLOG` when a client exposes that event.

A native `CHAT_MSG_*` combat-event backend is planned for the next development step so automatic combat text can also operate without `RAW_COMBATLOG`.

## Installation

Place the addon folder in:

```text
World of Warcraft/Interface/AddOns/NameplateSCT-Vanilla/
```

The folder should contain at least:

```text
NameplateSCT-Vanilla.toc
NameplateSCT-Vanilla.lua
```

Enable **NameplateSCT-Vanilla** from the AddOns menu and enable enemy nameplates in game.

## Commands

```text
/np status
/np test
/np crit
/np plates
/np dump [1-50]
/np errors
/np clear
/np auto
/np sizetest
/np fonttest
```

`/nsct` is also registered as an alias for `/np`.

For the native backend, the most useful first test is:

1. Use a standard Vanilla 1.12.1 client environment with no enhanced GUID/nameplate API available.
2. Enable enemy nameplates.
3. Target a visible enemy.
4. Run `/np status` and confirm the native scanner sees visible/named plates.
5. Run `/np test` and `/np crit`.
6. Move out of nameplate range and back in, then repeat.

See [`TESTING.md`](TESTING.md) for the complete test matrix.

## Development direction

Planned work includes:

- native `CHAT_MSG_*` outgoing-combat parsing
- a normalized internal combat-event model
- stronger destination resolution for ambiguous same-named enemies
- performance and spell-cache cleanup
- explicit damage-source classification
- target vs. off-target scaling
- small-hit scaling
- spell filtering
- clutter protection / maximum active texts
- SavedVariables-backed configuration and slash commands

The current fountain trajectory is intentional and is not scheduled for replacement.

## Credits

NameplateSCT-Vanilla is based on and inspired by **NameplateSCT**, originally developed by **mpstark** and **Justwait**.

Original project: [Justw8/NameplateSCT](https://github.com/Justw8/NameplateSCT)

Although the Vanilla implementation has been largely rewritten for WoW 1.12.1, it retains the original addon's concept and parts of its visual/animation behavior.

## License

The upstream NameplateSCT project is distributed under the MIT License. The original copyright and license notice are retained in [`LICENSE`](LICENSE).
