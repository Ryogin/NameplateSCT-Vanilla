# NameplateSCT Vanilla Testing

## Current build

`0.4.1-test`

Primary goal: verify that recycled native nameplate frames cannot leave stale GUID mappings and that active combat text remains attached to the correct unit without resolving the plate every frame.

## Baseline checks

1. Log in with SuperWoW active.
2. Enable enemy nameplates.
3. Target a visible enemy.
4. Run `/np status`.
5. Confirm that SuperWoW is detected and the target has a GUID.
6. Run `/np test`.
7. Run `/np crit`.
8. Run `/np errors`.

Expected:

- Synthetic normal text appears on the target plate.
- Synthetic critical text uses the existing vertical/POW animation.
- No Lua errors are reported.

## 0.4.1 recycled-nameplate test

This is the main regression test for the patch.

1. Find several nearby enemies that can show nameplates.
2. Fight or move between them so nameplates repeatedly appear and disappear.
3. Kill one unit and immediately engage another nearby unit.
4. Repeat with several mobs of the same name if possible.
5. Periodically run `/np status`.
6. Run `/np dump 50` after a suspicious transition.

Expected:

- Damage from the new unit never inherits combat text belonging to the previous unit that used the same native nameplate frame.
- `GUID mappings` and `reverse mappings` in `/np status` should normally stay consistent.
- Debug output may contain `PLATEGUID recycled plate ...` entries when frames are reused.

## Killing-blow / disappearing-plate test

1. Damage a low-health enemy with its nameplate visible.
2. Kill it with a hit that creates combat text.
3. Watch the text after the nameplate disappears.

Expected:

- Existing floating text continues its motion from the last known plate position.
- It does not jump to a newly recycled nameplate.
- Once detached, it should remain detached until it expires.

## Multiple active texts

1. Attack quickly enough to have several damage numbers active simultaneously.
2. Switch targets while old text is still visible.
3. Move between multiple visible nameplates.

Expected:

- Each active text follows the plate associated with its own GUID.
- Target switching does not move already-active text to the new target.
- No obvious animation change from `0.4.0-test`.

## Real combat-log coverage smoke test

Test as many as are available to your character:

- white melee hit
- white melee crit
- physical ability hit
- physical ability crit
- spell hit
- spell crit
- dodge
- parry
- block
- immune
- absorb
- reflected damage / Thorns-style event

Expected:

- Supported player-owned outgoing events appear on the correct nameplate.
- Unsupported lines may be ignored, but should not produce Lua errors.

## Diagnostics

```text
/np status
/np plates
/np dump 50
/np errors
```

If combat text appears over the wrong unit, capture:

- `/np status` output
- `/np dump 50` output
- the relevant `RAW_COMBATLOG` line if visible in the debug log
- what happened immediately before the issue (kill, target switch, plate disappeared, new mob entered range, etc.)

## Version history relevant to current testing

### 0.4.1-test

- Bidirectional GUID/nameplate cache.
- Recycled native-frame cleanup.
- Stale-frame cleanup after full WorldFrame scans.
- Active text caches its resolved nameplate.
- Cached plates are trusted only while their reverse GUID mapping still matches.
- Detached text no longer attempts further nameplate resolution.

### 0.4.0-test

- Continued floating text after killing-blow plate loss.
- Maul/physical ability avoidance and related parser work.
- Judgement spell-icon alias behavior.

### 0.3.9

- Physical ability lines without an explicit school, including critical variants.

### 0.3.8

- `CHAT_MSG_SPELL_DAMAGESHIELDS_ON_SELF` / reflected school-damage support.
