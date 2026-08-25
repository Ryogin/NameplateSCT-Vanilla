# NameplateSCT-Vanilla

A Vanilla 1.12.1 adaptation of [NameplateSCT](https://github.com/Justw8/NameplateSCT), rewritten for the original WoW client.

The project keeps the core idea of displaying scrolling combat text on enemy nameplates while using a lightweight implementation designed around the Vanilla 1.12 API.

> **Current status:** `0.5.0a-test` — development build.

## Requirements

- World of Warcraft 1.12.1 compatible client
- Enemy nameplates enabled for normal use

No Ace3, LibEasing, LibSharedMedia, Masque, replacement-nameplate addon, or enhanced GUID API is required for the native backend.

Enhanced GUID/nameplate APIs remain optional but are ignored by default. `0.5.0a-test` starts in native-only mode; `/np native off` is an explicit comparison/debug opt-in to enhanced identity APIs.

## Features currently implemented

- Native Vanilla nameplate discovery by scanning `WorldFrame`
- Native nameplate lifecycle tracking through `OnShow` / `OnHide`
- Native unit-name indexing from Blizzard nameplate FontStrings
- Target-nameplate resolution without requiring a GUID
- Unique visible-name fallback when the destination is unambiguous
- Native-only mode enabled by default, with enhanced GUID/nameplate identity paths intentionally disabled
- Optional exact GUID-to-nameplate resolution only when native-only mode is explicitly turned off
- Bidirectional GUID/nameplate tracking with recycled-frame cleanup when enhanced identity is enabled
- Visibility-generation protection so active text cannot jump onto a recycled frame
- Native Vanilla outgoing-combat parsing through `CHAT_MSG_*` events
- Localized combat parsing based on Blizzard global combat strings instead of hard-coded English sentences
- Explicit normalized combat classification for autoattacks, abilities, spells, periodic damage, reflected damage, and miss outcomes
- Target/off-target visual focus: current-target text remains full size/opacity on HIGH strata; off-target text uses 75% scale, 72% base alpha, and MEDIUM strata
- Normalized `result` values for hit, crit, miss, dodge, parry, block, resist, absorb, immune, reflect, and evade
- Native parsing for MISS, DODGE, PARRY, BLOCK, RESIST, ABSORB, IMMUNE, REFLECT, and EVADE where the corresponding Vanilla global string exists
- Optional native damage-shield/reflected-damage parsing through `CHAT_MSG_SPELL_DAMAGESHIELDS_ON_SELF` when available
- Native `CHAT_MSG_*` remains the display backend in native-only mode; RAW_COMBATLOG is ignored there
- RAW_COMBATLOG fallback remains available only when native-only mode is explicitly disabled
- Normal hit fountain animation
- Critical hit / miss vertical animation with POW sizing
- Physical and spell-school colors
- Spell icons resolved from the Vanilla spellbook when available
- Continued combat text motion when a unit's nameplate disappears
- Internal debug/error capture and diagnostic slash commands

## v0.5.0a-test

This hotfix adds a forced native-compatibility mode on top of the `0.5.0-test` target/off-target visual differentiation. Native-only operation is enabled by default so an enhanced client cannot silently change addon behavior.

- `NameplateSCTVanillaDB.forceNative` defaults to `1` and persists across reloads/restarts.
- `/np native on` ignores `UnitGUID`, GUID-returning `UnitExists`, `UnitNameplate`, enhanced plate GUIDs, and `RAW_COMBATLOG` for addon logic.
- `/np native off` explicitly re-enables enhanced identity/fallback paths for comparison or debugging.
- Switching modes clears and rebuilds nameplate identity state so stale GUID mappings cannot survive the transition.
- `/np status` reports native-only state and marks enhanced capabilities as ignored when appropriate.
- Current-target combat text uses scale `1.00`, base alpha `1.00`, and `HIGH` frame strata.
- Off-target combat text uses scale `0.75`, base alpha `0.72`, and `MEDIUM` frame strata.
- Target identity is determined from the resolved nameplate/GUID rather than name alone, so another same-named enemy is not promoted to target styling.
- The focus state is captured when the text is created and remains stable for that text's lifetime.
- Existing fade timing is preserved; off-target alpha is multiplied by the normal fade curve.
- `/np testoff` (alias `/np offtest`) sends synthetic text to a visible non-target plate for isolated testing.
- No recent-resolution cache is included yet; late/killing-blow races remain a known deferred issue.

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
/np testoff
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
- continued target/off-target and multitarget testing
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

### Native-only compatibility mode

`0.5.0a-test` defaults to native-only operation even when an enhanced 1.12 client exposes GUID/nameplate APIs or `RAW_COMBATLOG`. In this mode the addon intentionally ignores `UnitGUID`, GUID-returning `UnitExists`, `UnitNameplate`, enhanced plate GUIDs, and `RAW_COMBATLOG` for addon logic. Use `/np native off` only for explicit comparison/debugging; `/np native on` restores the default. The setting persists in `NameplateSCTVanillaDB.forceNative`.
