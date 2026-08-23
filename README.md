# NameplateSCT-Vanilla

A Vanilla 1.12.1 adaptation of [NameplateSCT](https://github.com/Justw8/NameplateSCT), rewritten for the original WoW client and SuperWoW.

The project keeps the core idea of displaying scrolling combat text on enemy nameplates, but most of the implementation is specific to the Vanilla 1.12 API and SuperWoW GUID/nameplate extensions.

> **Current status:** `0.4.1a` — development build.

## Requirements

- World of Warcraft 1.12.1 compatible client
- SuperWoW
- English combat-log strings are currently assumed by the parser

No Ace3, LibEasing, LibSharedMedia, Masque, or ShaguPlates dependency is required.

## Features currently implemented

- Damage numbers anchored to native enemy nameplates
- SuperWoW GUID-to-nameplate resolution
- Bidirectional GUID/nameplate tracking with recycled-frame cleanup
- Normal hit fountain animation
- Critical hit / miss vertical animation with POW sizing
- Physical and spell-school colors
- Spell icons resolved from the Vanilla spellbook when available
- Continued combat text motion when a killed unit's nameplate disappears
- Parsing for several player-owned outgoing damage, critical, reflect, and avoidance events
- Internal debug/error capture and diagnostic slash commands

## v0.4.1a

This patch focuses on nameplate tracking stability rather than new visual features.

- Added reverse `nameplate -> GUID` tracking.
- Removes the previous GUID association when a native nameplate frame is recycled for another unit.
- Removes stale mappings for nameplate frames no longer discovered under `WorldFrame`.
- Caches the resolved nameplate on each active combat-text object.
- Validates cached plates against the reverse GUID mapping before using them.
- Stops resolving a nameplate after a text has detached from a disappeared/killed unit.
- Keeps the existing fountain and critical movement unchanged.

See [`TESTING.md`](TESTING.md) for the current test matrix.

## Installation

Place the addon folder in your WoW installation:

```text
World of Warcraft/Interface/AddOns/NameplateSCT-Vanilla/
```

The folder should contain at least:

```text
NameplateSCT-Vanilla.toc
NameplateSCT-Vanilla.lua
```

Enable **NameplateSCT-Vanilla** from the AddOns menu and make sure SuperWoW is installed and active.

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

Useful starting checks:

1. Show an enemy nameplate and target that enemy.
2. Run `/np status`.
3. Run `/np test`.
4. Run `/np crit`.
5. Fight normally and then run `/np errors`.

## Development direction

The Vanilla version is intentionally not being forced into the architecture of the modern addon. Planned work includes:

- performance and spell-cache cleanup
- a normalized internal combat-event model
- explicit damage-source classification
- target vs. off-target scaling
- small-hit scaling
- spell filtering
- clutter protection / maximum active texts
- SavedVariables-backed configuration and slash commands
- broader WoW 1.12.1 / SuperWoW combat-log coverage based on captured real logs

The current fountain trajectory is intentional and is not scheduled for replacement.

## Credits

NameplateSCT-Vanilla is based on and inspired by **NameplateSCT**, originally developed by **mpstark** and **Justwait**.

Original project: [Justw8/NameplateSCT](https://github.com/Justw8/NameplateSCT)

Although the Vanilla implementation has been largely rewritten for WoW 1.12.1 and SuperWoW, it retains the original addon's concept and parts of its visual/animation behavior.

## License

The upstream NameplateSCT project is distributed under the MIT License. The original copyright and license notice are retained in [`LICENSE`](LICENSE).
