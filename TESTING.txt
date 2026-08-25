# NameplateSCT-Vanilla Testing

## Current build

`0.5.0a-test`

Primary goal: validate target/off-target visual differentiation on top of the working native nameplate and combat backends, without changing fountain or POW trajectories.

## Clean-session preparation

Before each focused capture:

```text
/np clear
/np status
```

Expected:

- `native combat backend: active (5/5 required; 0/1 or 1/1 optional)` on a compatible Vanilla 1.12.1 client.
- `display backend: native CHAT_MSG` when the native backend is complete.
- `RAW_COMBATLOG` may also report as registered, but it must not create duplicate floating text while the native backend is active.

## Target / off-target focus — highest priority

### Current target

1. Target one enemy with its nameplate visible.
2. Use `/np test`, `/np crit`, or deal normal damage.

Expected:

- `[DISPLAY] ... focus=target scale=1 baseAlpha=1 strata=HIGH`.
- Target text retains the existing full-size appearance and animation paths.
- Critical POW remains visually unchanged apart from the explicit focus metadata.

### Synthetic off-target

1. Show at least two enemy nameplates.
2. Keep one enemy targeted.
3. Run `/np testoff`.

Expected:

- The synthetic `OFF 123` appears over a different visible nameplate.
- `[DISPLAY] ... focus=offtarget scale=0.75 baseAlpha=0.72 strata=MEDIUM`.
- The off-target text is visibly smaller and less opaque than target text.
- The fountain trajectory itself is unchanged.

### Real off-target damage

Warlock DoTs are particularly useful:

1. Apply a DoT to one enemy.
2. Switch target to a different enemy while the first nameplate remains visible.
3. Allow the first DoT to tick.

Expected:

- The periodic event resolves to the original enemy when resolution is unambiguous.
- Its `[DISPLAY]` entry reports `focus=offtarget`.
- If multiple same-named visible enemies make the destination ambiguous, the addon should suppress the display rather than guess.

### Same-name safety

With two or more visible enemies sharing the same name:

- Only the actually resolved target frame should receive `focus=target`.
- A name match alone must never promote a different frame to target styling.

## Native combat parser — highest priority

Use one visible target at a time where practical. After each group of tests, run `/np dump 50` and `/np errors`.

### White melee hit

1. Autoattack an enemy until a normal white hit occurs.

Expected:

- One floating damage number.
- `[NATIVELOG]` for `CHAT_MSG_COMBAT_SELF_HITS`.
- `[PARSED] ... kind=damage type=autoattack result=hit` with the target name and amount.
- A single `[DISPLAY]` entry for that hit.

### White melee critical

1. Continue autoattacking until a white critical occurs if practical.

Expected:

- Critical vertical/POW animation remains unchanged.
- `[PARSED] ... kind=damage type=autoattack result=crit ... crit=1`.

### Physical ability

Use a physical ability that appears in the combat log as an ability hit (for example an applicable melee class ability).

Expected:

- `[PARSED] ... kind=damage type=ability result=hit` (or `result=crit`).
- Spell/ability name captured.
- Physical color.
- Spell icon shown when the spellbook cache can resolve it.

### Spell damage

Use a direct spell with an explicit damage school.

Expected:

- `[PARSED] ... kind=damage type=spell result=hit` (or `result=crit`).
- `school` normalized to `Holy`, `Fire`, `Nature`, `Frost`, `Shadow`, or `Arcane` when the client exposes the corresponding Blizzard school global.
- Appropriate school color.
- Critical spell hits retain POW behavior.

### Periodic damage

Apply a player-owned DoT and allow it to tick.

Expected:

- Event comes from `CHAT_MSG_SPELL_PERIODIC_CREATURE_DAMAGE` or `CHAT_MSG_SPELL_PERIODIC_HOSTILEPLAYER_DAMAGE`.
- `[PARSED] ... kind=damage type=periodic result=hit ... periodic=1`.
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
- `[PARSED]` includes `kind=miss`, `result=<lowercase outcome>`, and `text=<OUTCOME>`.
- Physical avoidance from spell/ability messages should classify as `type=ability` for DODGE/PARRY/BLOCK/EVADE; spell-like outcomes should classify as `type=spell` for MISS/RESIST/ABSORB/IMMUNE/REFLECT where Vanilla cannot prove a more specific source.
- No Lua errors occur when a corresponding Blizzard global string is absent; unsupported formats should become `[UNMATCHED]` rather than breaking execution.


## Damage shield / reflected damage

If the class/build can produce outgoing damage from an active damage shield or reactive aura, capture it.

Expected when the client exposes the optional event/global string:

- `CHAT_MSG_SPELL_DAMAGESHIELDS_ON_SELF` appears in `[NATIVELOG]`.
- `[PARSED] ... kind=damage type=reflected result=hit ... reflected=1`.
- The damage school is preserved when `DAMAGESHIELDSELFOTHER` supplies it.
- Missing support for this optional event must not disable the five-event native combat backend.

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

Important log tags in `0.5.0a-test`:

```text
[NATIVELOG]  raw native CHAT_MSG_* payload
[PARSED]     normalized outgoing event
[UNMATCHED]  native combat string not yet recognized
[DISPLAY]    resolved nameplate and rendered text
[RAW]        optional RAW_COMBATLOG diagnostic/fallback input
```

## Version history relevant to current testing

### 0.5.0a-test

- Native-only mode defaults to ON and persists through `NameplateSCTVanillaDB.forceNative`.
- `/np native on|off` toggles whether enhanced identity APIs / RAW fallback may participate.
- Mode transitions reset nameplate identity state to prevent stale GUID mappings.
- `/np status` reports enhanced capabilities as ignored while native-only mode is ON.
- Target styling: `1.00` scale, `1.00` base alpha, `HIGH` strata.
- Off-target styling: `0.75` scale, `0.72` base alpha, `MEDIUM` strata.
- Resolved-frame/GUID-based focus classification instead of name-only classification.
- Stable per-text focus state across the animation lifetime.
- `/np testoff` / `/np offtest` synthetic off-target test.
- Existing fountain, vertical POW, and fade timing preserved.
- Recent-resolution cache remains deferred.

### 0.4.4-test

- Explicit normalized `kind`, `damageType`, and `result` fields.
- `autoattack` / `ability` / `spell` / `periodic` / `reflected` source classification.
- Consistent native and RAW fallback event contracts.
- Optional native damage-shield/reflected-damage event support.
- Expanded classification diagnostics.
- No recent-resolution cache yet; late/killing-blow destination races remain observational test data.

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

## Native-only mode on enhanced clients

1. Run `/np clear`, then `/np native on` and `/np status`.
2. Even if the client exposes enhanced APIs, status should report them as `(ignored)`, target GUID should be `nil`, and GUID mappings should remain `0`.
3. `/np test` should resolve through `target-alpha` or `target-unique-name`, not `guid`.
4. `/np testoff` should still produce `focus=offtarget scale=0.75 baseAlpha=0.72 strata=MEDIUM`.
5. Fight normally and confirm logs use `[NATIVELOG]` / `[PARSED]` without `[RAW]` entries while native-only mode is ON.
6. `/np native off` is only a comparison/debug option; turn `/np native on` back on for stock-Vanilla compatibility testing.
