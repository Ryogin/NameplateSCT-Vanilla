# Changelog

All notable development changes to NameplateSCT-Vanilla are recorded here.

## 0.5.0b-test

### Added

- Native DoT target bindings learned from harmful aura-application combat messages.
- Periodic tick resolution through the learned spell + target-name + native-nameplate binding.
- `[DOTBIND]`, `[DOTRESOLVE]`, `[DOTAMBIGUOUS]`, and `[DOTDROP]` diagnostics.
- DoT binding counts in `/np status`.
- Dedicated `CHANGELOG.md` and `ROADMAP.md` documentation.

### Changed

- Harmful aura applications such as `X is afflicted by Immolate` are consumed as resolver metadata instead of being reported as unmatched damage.
- DoT bindings are invalidated when their native nameplate hides or is recycled.
- Ambiguous same-name/same-spell DoT ticks are suppressed rather than assigned to an arbitrary nameplate.
- README and testing documentation were reorganized by purpose.

## 0.5.0a-test

### Added

- Native-only compatibility mode, enabled by default.
- `/np native on|off` for explicit compatibility testing.
- Capability reporting that distinguishes available APIs from APIs intentionally ignored by native-only mode.

### Changed

- Enhanced GUID/nameplate identity and RAW combat-log paths are excluded from addon logic while native-only mode is enabled.

## 0.5.0-test

### Added

- Target/off-target visual focus.
- Target text: scale `1.00`, base alpha `1.00`, `HIGH` strata.
- Off-target text: scale `0.75`, base alpha `0.72`, `MEDIUM` strata.
- `/np testoff` synthetic off-target test.

## 0.4.4-test

### Added

- Explicit normalized `kind`, `damageType`, and `result` combat fields.
- Damage classification for autoattacks, abilities, spells, periodic damage, and reflected damage.
- Optional native damage-shield parsing.

### Changed

- Native and RAW combat backends now produce the same normalized event contract.

## 0.4.3-test

### Added

- Native Vanilla outgoing-combat backend using `CHAT_MSG_*` events.
- Runtime compilation of Blizzard localized combat strings.
- Native parsing for white hits, abilities, spells, periodic damage, criticals, and avoidance results.
- `[UNMATCHED]` diagnostics for unsupported combat strings.

## 0.4.2a

### Fixed

- Native-resolved combat text no longer detaches immediately when an auxiliary GUID is present.

### Added

- `/np clearlog` alias.
- Expanded capability reporting in `/np status`.

## 0.4.2-test

### Added

- Native `WorldFrame` nameplate scanner.
- Blizzard nameplate detection through `Nameplate-Border`.
- Nameplate `OnShow` / `OnHide` lifecycle tracking.
- Name-based target and unique-name resolution without requiring GUIDs.
- Visibility-generation protection for recycled frames.

## 0.4.1a

### Changed

- Standardized public project, addon folder, TOC, and Lua filename naming as `NameplateSCT-Vanilla`.
