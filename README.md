# NameplateSCT-Vanilla

A Vanilla 1.12.1 adaptation of [NameplateSCT](https://github.com/Justw8/NameplateSCT), rewritten for the original WoW client.

The project keeps the core idea of displaying scrolling combat text on enemy nameplates while using a lightweight implementation designed around the Vanilla 1.12 API.

> **Current status:** `0.4.4-test` — development build.

## Requirements

- World of Warcraft 1.12.1 compatible client
- Enemy nameplates enabled for normal use

No Ace3, LibEasing, LibSharedMedia, Masque, replacement-nameplate addon, or enhanced GUID API is required for the native backend.

Enhanced GUID/nameplate APIs remain optional. When present, NameplateSCT-Vanilla uses them automatically for more exact unit resolution.

## Features currently implemented

- Native Vanilla nameplate discovery by scanning `WorldFrame`
- Native nameplate lifecycle tracking through `OnShow` / `OnHide`
- Native unit-name indexing from Blizzard nameplate FontStrings
- Target-nameplate resolution without requiring a GUID
- Unique visible-name fallback when the destination is unambiguous
- Optional exact GUID-to-nameplate resolution when compatible APIs are available
- Bidirectional GUID/nameplate tracking with recycled-frame cleanup
- Visibility-generation protection so active text cannot jump onto a recycled frame
- Native Vanilla outgoing-combat parsing through `CHAT_MSG_*` events
- Localized combat parsing based on Blizzard global combat strings instead of hard-coded English sentences
- Explicit normalized combat classification for autoattacks, abilities, spells, periodic damage, reflected damage, and miss outcomes
- Normalized `result` values for hit, crit, miss, dodge, parry, block, resist, absorb, immune, reflect, and evade
- Native parsing for MISS, DODGE, PARRY, BLOCK, RESIST, ABSORB, IMMUNE, REFLECT, and EVADE where the corresponding Vanilla global string exists
- Optional native damage-shield/reflected-damage parsing through `CHAT_MSG_SPELL_DAMAGESHIELDS_ON_SELF` when available
- RAW_COMBATLOG fallback when the native combat backend is unavailable
- Normal hit fountain animation
- Critical hit / miss vertical animation with POW sizing
- Physical and spell-school colors
- Spell icons resolved from the Vanilla spellbook when available
- Continued combat text motion when a unit's nameplate disappears
- Internal debug/error capture and diagnostic slash commands

## v0.4.4-test

This patch formalizes damage-source and outcome classification without changing visible animation behavior.

- Uses a consistent normalized event contract with `kind`, `source`, `damageType`, and `result`.
- Classifies outgoing damage as `autoattack`, `ability`, `spell`, `periodic`, or `reflected`.
- Keeps miss/avoidance events as `kind=miss` while preserving the attempted source type.
- Normalizes outcomes to `hit`, `crit`, `miss`, `dodge`, `parry`, `block`, `resist`, `absorb`, `immune`, `reflect`, or `evade`.
- Treats periodic damage as normal damage with `damageType=periodic` and `periodic=1`, rather than overloading `kind`.
- Adds optional native damage-shield parsing from `CHAT_MSG_SPELL_DAMAGESHIELDS_ON_SELF` / `DAMAGESHIELDSELFOTHER`.
- Normalizes the RAW_COMBATLOG fallback into the same internal event contract as the native backend.
- Expands diagnostics so `[PARSED]` and `[PARSE]` include `kind`, `type`, `result`, `periodic`, and `reflected`.
- Keeps the observed recent-resolution/killing-blow race under observation; no heuristic cache is added in this build.

The existing fountain and critical/miss movement remain unchanged.

## v0.4.3-test

This patch adds the native Vanilla outgoing-combat backend.

- Registers `CHAT_MSG_COMBAT_SELF_HITS` for white hits and white criticals.
- Registers `CHAT_MSG_COMBAT_SELF_MISSES` for melee miss/avoidance outcomes.
- Registers `CHAT_MSG_SPELL_SELF_DAMAGE` for abilities, spells, criticals, and spell miss outcomes.
- Registers `CHAT_MSG_SPELL_PERIODIC_CREATURE_DAMAGE` and `CHAT_MSG_SPELL_PERIODIC_HOSTILEPLAYER_DAMAGE` for player-owned DoTs.
- Compiles Blizzard's localized global combat strings into Lua search patterns at runtime.
- Converts parsed combat messages into a normalized internal event structure before display.
- Uses the existing GUID/target/name nameplate resolver rather than coupling combat parsing to a specific nameplate API.
- Uses native `CHAT_MSG_*` events as the preferred display backend when all required native events register successfully.
- Keeps `RAW_COMBATLOG` registered as a fallback and diagnostic source without duplicating displayed combat text.
- Logs unrecognized outgoing combat strings as `[UNMATCHED]` for targeted parser expansion.

The existing fountain and critical movement remain unchanged.

## v0.4.2a

This hotfix stabilized active-text tracking for native nameplate resolutions and improved diagnostics.

- Keeps `target-alpha`, `target-unique-name`, and `unique-name` texts attached to the native frame selected at display time even when an auxiliary GUID is available.
- Uses exact GUID re-resolution only when the original resolution mode was `guid`.
- Adds `/np clearlog` as an alias for `/np clear`.
- Expands `/np status` to report optional client capabilities independently.
- Updates addon metadata for the current maintainer.

## Compatibility model

Nameplate discovery and outgoing combat parsing now both have native Vanilla implementations:

```text
Native WorldFrame nameplates
        +
Native CHAT_MSG_* combat events
        |
        v
Normalized outgoing event
        |
        v
GUID / target / unique-name resolver
        |
        v
Nameplate combat text
```

When optional GUID information is available it improves destination resolution, but it is not required for the native combat parser.

If all required native `CHAT_MSG_*` events are available, they are the active display backend. `RAW_COMBATLOG`, when available, is retained as fallback/diagnostic input so both systems do not create duplicate floating text.

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
/np clearlog
/np auto
/np sizetest
/np fonttest
```

`/nsct` is also registered as an alias for `/np`.

For a clean combat-parser test:

1. Enable enemy nameplates.
2. Run `/np clear`.
3. Run `/np status` and confirm `native combat backend: active`.
4. Fight one visible enemy using white attacks and one or more abilities/spells.
5. If possible, cause a critical, miss/dodge/parry/resist, and a periodic damage tick.
6. Run `/np errors`.
7. Run `/np dump 50`.

Look for `[PARSED]` entries for supported messages and `[UNMATCHED]` entries for formats that still need coverage.

See [`TESTING.md`](TESTING.md) for the complete test matrix.

## Development direction

Planned work includes:

- hardening native combat parsing from real captured logs
- stronger destination resolution for ambiguous same-named enemies
- performance and spell-cache cleanup
- explicit damage-source classification refinements
- target vs. off-target scaling
- small-hit scaling
- spell filtering
- clutter protection / maximum active texts
- SavedVariables-backed configuration and slash commands
- later pet/guardian and partial absorb/block/resist research

The current fountain trajectory is intentional and is not scheduled for replacement.

## Credits

NameplateSCT-Vanilla is based on and inspired by **NameplateSCT**, originally developed by **mpstark** and **Justwait**.

Original project: [Justw8/NameplateSCT](https://github.com/Justw8/NameplateSCT)

Although the Vanilla implementation has been largely rewritten for WoW 1.12.1, it retains the original addon's concept and parts of its visual/animation behavior.

## License

The upstream NameplateSCT project is distributed under the MIT License. The original copyright and license notice are retained in [`LICENSE`](LICENSE).
