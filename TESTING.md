# NameplateSCT-Vanilla Testing

## Current build

`0.4.2a`

Primary goal: verify native Vanilla nameplate discovery and confirm that native target/name resolutions remain attached for their full animation even when the client exposes an auxiliary GUID.

## Native Vanilla baseline — highest priority

Run this test in a WoW 1.12.1 environment where `UnitNameplate`, `UnitGUID`, and `RAW_COMBATLOG` are not available if possible.

1. Enable enemy nameplates.
2. Target a visible enemy.
3. Run `/np status`.
4. Confirm `native scanner: active` and that `visible` / `named` are greater than zero.
5. Note the independent capability report for `UnitExists GUID`, `UnitGUID API`, `UnitNameplate API`, and `RAW_COMBATLOG`.
6. Run `/np test`.
7. Run `/np crit`.
8. Run `/np errors`.
9. Run `/np clear` (or `/np clearlog`) and confirm the saved diagnostic log/error lists reset.

Expected:

- Both synthetic texts appear on the current target's native nameplate without requiring exact GUID-to-nameplate resolution.
- Neither test logs `plate disappeared` immediately after `DISPLAY` while the target plate is still visible.
- The normal fountain and critical vertical/POW animations are unchanged.
- No Lua errors occur because `RAW_COMBATLOG` is unavailable.

## Native nameplate lifecycle

1. Stand where one enemy nameplate is visible.
2. Run `/np status`.
3. Move far enough away that the plate disappears.
4. Move back until it appears again.
5. Repeat several times and with several nearby units.
6. Run `/np dump 50`.

Expected:

- `PLATESHOW` and `PLATEHIDE` entries appear for registered frames.
- Hidden plates are removed from the visible name index.
- A reshown/recycled frame is treated as a new visibility generation.
- Existing floating text does not jump to the newly shown unit.

## Same-name safety

1. Find two or more visible enemies with the same name.
2. Target one of them.
3. Run `/np test` several times while switching between them.
4. Deselect the target if practical and inspect `/np status`.

Expected:

- Target resolution uses the target plate when Vanilla's target alpha state identifies it uniquely.
- A unique visible name can be resolved when only one matching plate exists.
- Multiple ambiguous same-named plates are not guessed by the generic name resolver.

## Enhanced GUID regression

If the client exposes compatible GUID/nameplate APIs:

1. Target a visible enemy.
2. Run `/np status` and confirm GUID resolution is available.
3. Run `/np test` and `/np crit`.
4. Fight several enemies and force native frames to recycle.
5. Kill one unit and immediately engage another.

Expected:

- Exact GUID resolution continues to work.
- Forward/reverse GUID mappings remain consistent.
- No combat text migrates to a recycled frame belonging to another GUID.

## Killing-blow / disappearing-plate regression

1. Create combat text on a low-health target.
2. Cause its nameplate to disappear while the text is still active.

Expected:

- Existing text continues from its last valid WorldFrame position.
- Once detached, it does not reattach to a later visibility generation of the same frame.

## Current automatic combat-parser boundary

The automatic parser in `0.4.2a` still consumes `RAW_COMBATLOG` only when that event exists.

Expected on a stock Vanilla environment:

- Native nameplate discovery and `/np test` / `/np crit` work.
- Absence of `RAW_COMBATLOG` produces no Lua registration error.
- Real outgoing combat text without that event is not yet expected; native `CHAT_MSG_*` parsing is the next development step.

## Diagnostics

```text
/np status
/np plates
/np dump 50
/np errors
```

If resolution fails, capture:

- `/np status`
- `/np dump 50`
- target name
- number of visible mobs with that same name
- whether the client exposes an enhanced GUID/nameplate API

## Version history relevant to current testing

### 0.4.2a

- Fix native-resolution texts detaching immediately when an auxiliary GUID exists.
- Preserve sticky frame/generation tracking for `target-alpha`, `target-unique-name`, and `unique-name`.
- Add `/np clearlog` alias.
- Report optional client capabilities independently in `/np status`.
- Update addon author metadata to Ryogin.

### 0.4.2-test

- Native `WorldFrame` nameplate scanner.
- `Nameplate-Border` frame detection.
- `OnShow` / `OnHide` lifecycle hooks.
- Visible nameplate index by native unit name.
- Target and unique-name resolution without GUIDs.
- Strict optional GUID validation.
- Visibility-generation protection for recycled native frames.
- Safe optional registration of `RAW_COMBATLOG`.

### 0.4.1a

- Bidirectional GUID/nameplate cache.
- Recycled native-frame cleanup.
- Cached active-text plate references.
- Detached text no longer attempts further nameplate resolution.
