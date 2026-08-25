# Roadmap

This file tracks intended development direction and open research. Items may move as Vanilla client behavior is validated in real combat.

## Next

### Same-name multitarget DoT resolution

`0.5.0b-test` can remember the exact native nameplate associated with one DoT application even when other same-named enemies are visible. If the same spell is active on multiple visible enemies with the same name, Vanilla combat text does not identify which one produced a tick.

Research target:

- correlate an ambiguous periodic tick with native nameplate health changes;
- resolve only when one candidate can be identified reliably;
- continue suppressing the event when ambiguity remains.

### Small-hit scaling

Planned baseline for evaluation:

- rolling damage average around 30 seconds;
- small-hit threshold around 50% of the rolling average;
- small-hit scale around 0.66.

Values remain subject to in-game testing.

## Planned

- Spell filtering / blacklist controls
- Clutter protection and maximum active combat texts
- SavedVariables-backed user configuration
- Slash-command configuration
- Visual configuration, including icon positioning
- Performance and spell-cache cleanup

## Research / validation

- Pet and guardian outgoing damage through native Vanilla pet combat events
- Same-name multitarget resolution outside periodic damage
- Late-event / killing-blow destination resolution
- Partial block, absorb, resist, glancing, and related combat metadata
- Additional native combat-string coverage from real captured logs

## Known limitations under investigation

- Late combat events can arrive after a target/nameplate disappears and may have no safe destination.
- Two visible enemies with the same name and the same tracked DoT remain ambiguous in native-only mode.
- A DoT binding is intentionally discarded when its nameplate hides or is recycled; the addon does not currently reconstruct that binding when the same unit reappears.
