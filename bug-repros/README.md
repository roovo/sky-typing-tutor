# Bug Reproduction Apps

Minimal Sky.Tui apps demonstrating ADT serialisation corruption in the Tui runtime.

## Running

Each directory contains a standalone `Main.sky`. Run from the project root:

```bash
sky run bug-repros/adt-in-model/Main.sky
sky run bug-repros/maybe-in-model/Main.sky
sky run bug-repros/parameterised-adt-in-model/Main.sky
```

## Expected vs Actual

All three apps:
- Display a counter and a value on screen
- Increment the counter on any key press
- Should keep the ADT/Maybe value unchanged

| App | Expected | Actual |
|-----|----------|--------|
| adt-in-model | Stays "Mode: Listing" | Panic: Unreachable(case) |
| maybe-in-model | Stays "Value: Nothing" | Switches to "Value: Just ''" |
| parameterised-adt-in-model | Stays "Status: Loaded (2 items)" | Panic: Unreachable(case) |

## Root Cause

The Tui runtime's model serialisation (gob encode/decode) does not preserve ADT variant tags for values stored in record fields. After any update cycle, the ADT value is corrupted.

## Workaround

Use primitive types (String, Bool, Int, List) instead of ADTs in model fields.
