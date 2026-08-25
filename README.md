# NameplateSCT-Vanilla

NameplateSCT-Vanilla brings scrolling combat text to enemy nameplates on World of Warcraft 1.12.1.

It is a Vanilla-focused adaptation of [NameplateSCT](https://github.com/Justw8/NameplateSCT), implemented around the original 1.12 API and native Blizzard nameplates.

## Features

- Combat text anchored to enemy nameplates
- Native Vanilla nameplate discovery and lifecycle tracking
- Native outgoing combat parsing through `CHAT_MSG_*` events
- Localized parsing based on Blizzard combat strings
- White hits, abilities, spells, criticals, misses and avoidance outcomes
- Periodic damage / DoT parsing
- Spell-school colors and spell icons when available in the spellbook
- Target and off-target visual differentiation
- Safe handling of recycled or disappearing nameplate frames
- Optional diagnostic logging for development and testing

## Compatibility

- World of Warcraft 1.12.1
- Enemy nameplates must be enabled

The addon is designed to work with the native Vanilla API. Additional nameplate or combat-log extensions are not required.

## Installation

Copy the addon folder to:

```text
World of Warcraft/Interface/AddOns/NameplateSCT-Vanilla/
```

The folder should contain at least:

```text
NameplateSCT-Vanilla.toc
NameplateSCT-Vanilla.lua
```

Enable **NameplateSCT-Vanilla** from the AddOns menu, then enable enemy nameplates in game.

## Commands

```text
/np status
/np test
/np crit
/np testoff
```

`/nsct` is also registered as an alias for `/np`.

Additional development and diagnostic commands are documented in [TESTING.md](TESTING.md).

## Development documentation

- [CHANGELOG.md](CHANGELOG.md) — release history
- [ROADMAP.md](ROADMAP.md) — planned work and open research areas
- [TESTING.md](TESTING.md) — current validation matrix and diagnostic workflow

## Credits

NameplateSCT-Vanilla is based on and inspired by **NameplateSCT**, originally developed by **mpstark** and **Justwait**.

Original project: [Justw8/NameplateSCT](https://github.com/Justw8/NameplateSCT)

The Vanilla implementation has been substantially rewritten for WoW 1.12.1 while retaining the original addon's concept and parts of its visual behavior.

## License

The upstream NameplateSCT project is distributed under the MIT License. The original copyright and license notice are retained in [LICENSE](LICENSE).
