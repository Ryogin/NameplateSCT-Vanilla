# NameplateSCT-Vanilla Testing

## Current build

`0.4.3-test`

Primary goal: validate the native Vanilla outgoing-combat parser against real 1.12.1 combat messages while preserving the already validated native nameplate backend.

## Clean-session preparation

Before each focused capture:

```text
/np clear
/np status
```

Expected:

- `native combat backend: active (5/5 events)` on a normal Vanilla 1.12.1 client.
- `display backend: native CHAT_MSG` when the native backend is complete.
- `RAW_COMBATLOG` may also report as registered, but it must not create duplicate floating text while the native backend is active.

## Native combat parser — highest priority

Use one visible target at a time where practical. After each group of tests, run `/np dump 50` and `/np errors`.

### White melee hit

1. Autoattack an enemy until a normal white hit occurs.

Expected:

- One floating damage number.
- `[NATIVELOG]` for `CHAT_MSG_COMBAT_SELF_HITS`.
- `[PARSED] ... type=autoattack` with the target name and amount.
- A single `[DISPLAY]` entry for that hit.

### White melee critical

1. Continue autoattacking until a white critical occurs if practical.

Expected:

- Critical vertical/POW animation remains unchanged.
- `[PARSED] ... type=autoattack ... crit=1`.

### Physical ability

Use a physical ability that appears in the combat log as an ability hit (for example an applicable melee class ability).

Expected:

- `[PARSED] ... type=ability`.
- Spell/ability name captured.
- Physical color.
- Spell icon shown when the spellbook cache can resolve it.

### Spell damage

Use a direct spell with an explicit damage school.

Expected:

- `[PARSED] ... type=spell`.
- `school` normalized to `Holy`, `Fire`, `Nature`, `Frost`, `Shadow`, or `Arcane` when the client exposes the corresponding Blizzard school global.
- Appropriate school color.
- Critical spell hits retain POW behavior.

### Periodic damage

Apply a player-owned DoT and allow it to tick.

Expected:

- Event comes from `CHAT_MSG_SPELL_PERIODIC_CREATURE_DAMAGE` or `CHAT_MSG_SPELL_PERIODIC_HOSTILEPLAYER_DAMAGE`.
- `[PARSED] ... periodic=1`.
- DoT spell name and damage school captured when present.
- Periodic events do not blindly prefer a same-named current target when the destination is ambiguous.

## Miss / avoidance matrix

Capture as many as practical:

```text
MISS
DODGE
PARRY
BLOCK
RESIST
ABSORB
IMMUNE
REFLECT
EVADE
```

Expected:

- The matching outcome appears as miss-style combat text.
- `[PARSED]` includes `text=<OUTCOME>`.
- No Lua errors occur when a corresponding Blizzard global string is absent; unsupported formats should become `[UNMATCHED]` rather than breaking execution.

## Unmatched-message capture

Any outgoing message that produces:

```text
[UNMATCHED] <event> || <combat message>
```

is useful test data.

When reporting one, provide:

- `/np status`
- `/np dump 50`
- the class and ability involved
- whether the target was the current target
- whether more than one visible enemy had the same name

Do not paraphrase the combat message; the exact captured string is what is needed to extend the parser safely.

## Duplicate-output regression

Run this when `/np status` reports both native combat events and `RAW_COMBATLOG`.

1. Clear the log.
2. Perform 5-10 simple attacks against one target.
3. Count visible combat numbers relative to actual hits.

Expected:

- One NameplateSCT number per outgoing event, not two.
- Native `[PARSED]` / `[DISPLAY]` drives visible SCT.
- RAW may be present for diagnostics/fallback but does not independently display the same hit while native mode is active.

## Native nameplate regression

Repeat the validated `0.4.2a` checks:

1. `/np test`
2. `/np crit`
3. Move out of nameplate range and back in.
4. Switch between same-named mobs.

Expected:

- No immediate `plate disappeared` after synthetic display while the plate remains visible.
- Text never jumps to a recycled frame.
- Ambiguous generic same-name resolution is not guessed.

## Optional GUID regression

If the client provides auxiliary GUIDs:

- target GUID may be attached to a parsed native event when the combat-message target name equals the current target name;
- exact GUID resolution remains preferred when a reliable GUID-to-nameplate mapping exists;
- native target/name resolution remains valid even when an auxiliary target GUID is available but cannot be mapped directly to a plate.

## Diagnostics

```text
/np status
/np plates
/np dump 50
/np errors
/np clear
/np clearlog
```

Important log tags in `0.4.3-test`:

```text
[NATIVELOG]  raw native CHAT_MSG_* payload
[PARSED]     normalized outgoing event
[UNMATCHED]  native combat string not yet recognized
[DISPLAY]    resolved nameplate and rendered text
[RAW]        optional RAW_COMBATLOG diagnostic/fallback input
```

## Version history relevant to current testing

### 0.4.3-test

- Native outgoing `CHAT_MSG_*` combat backend.
- Blizzard global-string pattern compiler for localized parsing.
- Normalized autoattack / ability / spell / periodic / miss data.
- Native backend preferred over RAW display to prevent duplicate SCT.
- `[UNMATCHED]` logging for parser expansion.

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
