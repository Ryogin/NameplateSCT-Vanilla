# NameplateSCT-Vanilla Testing

## Current build

`0.5.0b-test`

Primary goal: validate native DoT target tracking in native-only mode while continuing regression testing of combat parsing and target/off-target display.

## Clean session

Before a focused capture:

```text
/np clear
/np native on
/np status
```

Expected:

- native-only mode is `ON`;
- native combat backend is active;
- target GUID is `nil` in native-only mode;
- enhanced identity APIs, if present in the client, are reported as ignored;
- combat display is driven by native `CHAT_MSG_*` events.

## Native DoT target tracking — highest priority

### One DoT target

1. Keep one enemy nameplate visible.
2. Apply a DoT such as Immolate or Corruption.
3. Allow several ticks.

Expected:

```text
[NATIVELOG] ... is afflicted by <spell>
[DOTBIND] spell=<spell> name=<target> ... bindings=1
[PARSED] ... type=periodic ...
[DOTRESOLVE] ... result=bound
[DISPLAY] mode=dot-binding ...
```

The aura-application line should not be logged as `[UNMATCHED]`.

### Different-name multitarget DoTs

1. Apply the same DoT to enemy A.
2. Switch target and apply it to enemy B with a different name.
3. Keep both nameplates visible.
4. Allow both DoTs to tick.

Expected:

- both applications create independent `[DOTBIND]` entries;
- ticks for both enemies resolve through `mode=dot-binding` while their learned plates remain valid;
- the current target uses target styling;
- the other enemy uses off-target styling.

### One dotted enemy among same-named enemies

1. Show two or more enemies with the same name.
2. Apply the DoT to only one of them while it is targeted.
3. Change target if desired, keeping the dotted plate visible.

Expected:

- the application binds the exact target plate through target resolution;
- later ticks use that binding even though generic `unique-name` resolution would be ambiguous;
- damage appears only on the learned plate.

### Same spell on two same-named enemies

1. Apply the same DoT to two visible enemies with the same name.
2. Allow ticks to occur.

Expected for `0.5.0b-test`:

```text
[DOTAMBIGUOUS] ... bindings=2 action=suppress
```

No tick should be assigned to either plate by guessing. Health-change correlation is not implemented in this build.

### Binding invalidation

Move a dotted unit out of nameplate range or otherwise cause its native plate to hide.

Expected:

```text
[DOTDROP] ... reason=plate-hide
```

A recycled frame must never inherit the previous unit's DoT binding.

## Target / off-target regression

### Current target

```text
/np test
/np crit
```

Expected:

```text
focus=target scale=1 baseAlpha=1 strata=HIGH
```

### Synthetic off-target

Show at least two enemy nameplates, keep one targeted, then run:

```text
/np testoff
```

Expected:

```text
focus=offtarget scale=0.75 baseAlpha=0.72 strata=MEDIUM
```

## Native combat regression

Continue validating when practical:

- white hit and white critical;
- physical ability hit/critical;
- spell hit/critical;
- periodic damage;
- `MISS`, `DODGE`, `PARRY`, `BLOCK`, `RESIST`, `ABSORB`, `IMMUNE`, `REFLECT`, `EVADE`;
- optional damage-shield/reflected damage.

Supported events should produce `[PARSED]` followed by one appropriate `[DISPLAY]`. Unsupported outgoing strings should be logged as `[UNMATCHED]` without causing a Lua error.

## Same-name safety

With multiple visible enemies sharing a name:

- a name match alone must not identify an arbitrary target frame;
- generic ambiguous resolution must be suppressed;
- a valid DoT binding may identify one exact plate;
- two valid bindings for the same spell + name remain ambiguous in this build.

## Late / killing-blow events

Continue recording cases where a parsed hit arrives as the target or nameplate disappears.

Current expected behavior:

- if a safe destination still exists, display it;
- otherwise log `unresolved destination` rather than assign it to another unit.

The recent-resolution cache remains deferred while more examples are collected.

## Diagnostics

```text
/np status
/np native on
/np native off
/np plates
/np dump [1-50]
/np errors
/np clear
/np clearlog
/np auto
/np sizetest
/np fonttest
```

Important log tags:

```text
[NATIVELOG]     native CHAT_MSG_* payload
[PARSED]        normalized outgoing combat event
[DOTBIND]       harmful aura associated with an exact native nameplate
[DOTRESOLVE]    periodic event resolved through a learned binding or fallback
[DOTAMBIGUOUS]  multiple valid same-spell/same-name bindings; event suppressed
[DOTDROP]       binding removed because its plate became invalid
[UNMATCHED]     unsupported native combat string
[DISPLAY]       resolved nameplate and rendered combat text
[RAW]           enhanced RAW_COMBATLOG input; ignored in native-only mode
```

When reporting an unresolved or unmatched case, include `/np status`, `/np dump 50`, the class/ability involved, and whether multiple visible enemies had the same name.
