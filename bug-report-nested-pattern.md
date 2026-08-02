# Bug: Nested pattern match on user-defined ADT wrapping Maybe generates invalid Go

## Summary

When pattern matching on a user-defined ADT constructor that contains a `Maybe` value, using a nested pattern like `Loaded (Just x)` generates Go code that accesses `.Tag` and `.JustValue` directly on a field typed as `any`, causing a compile error.

## Sky version

v0.15 (latest as of 2026-08-02)

## Minimal reproduction

```elm
module Main exposing (main)

import Sky.Core.Prelude exposing (..)
import Std.Log exposing (println)


type Status a
    = Loading
    | Loaded a


type alias Model =
    { items : Status (Maybe (List String))
    }


process : Model -> String
process model =
    case model.items of

        Loaded (Just xs) ->
            "got items"

        Loaded Nothing ->
            "no items"

        Loading ->
            "loading"


main =
    let
        model = { items = Loaded (Just [ "a", "b" ]) }
        _ = println (process model)
    in
        ()
```

## Expected behaviour

The nested pattern `Loaded (Just xs)` should compile successfully, matching the `Loaded` constructor and destructuring the inner `Maybe` value.

CLAUDE.md states: "Nested patterns work: `Ok (Just x)` and `Ok Nothing` are fully supported in case expressions"

## Actual behaviour

`sky build` fails with:

```
sky run: go build failed:
# sky-app
./main.go:XXX: _v0.V0.Tag undefined (type any has no field or method Tag)
./main.go:XXX: _v0.V0.JustValue undefined (type any has no field or method JustValue)
```

The generated Go correctly type-asserts the outer ADT constructor (e.g. `_subj.(Status_Loaded_V)`) but then directly accesses `.Tag` and `.JustValue` on the `V0` field which is typed as `any` in the Go struct — missing the required type assertion to a Maybe struct.

## Workaround

Split the nested pattern into two separate case levels:

```elm
process : Model -> String
process model =
    case model.items of

        Loaded maybeXs ->
            case maybeXs of

                Just xs ->
                    "got items"

                Nothing ->
                    "no items"

        Loading ->
            "loading"
```

This generates correct Go with proper type assertions at each level.

## Notes

- The issue appears specific to **user-defined ADTs** wrapping `Maybe` (or possibly other ADTs). The documented `Ok (Just x)` pattern on `Result` may work due to special-cased codegen for built-in types.
- The type checker passes successfully (`Types OK`) — the error only surfaces during Go compilation of the generated code.
- Discovered in a real project with `type Status a = Loading | Loaded a | LoadFailed String | OpenFailed String a` where `a` was `Maybe (Zipper ExerciseDb)`.
