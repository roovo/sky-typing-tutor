# Bug: Type annotation `Dict k (List Record)` causes function to return empty Dict

## Summary

When a function has a type annotation with `Dict k (List Record)` as its return type, the function always returns an empty Dict at runtime. Removing the annotation (letting the type be inferred) produces the correct result. The type checker passes in both cases.

## Minimal reproduction

```elm
module DictListRecordBugTests exposing (tests)

import Sky.Test as Test exposing (Test)


type alias Item =
    { name : String
    , value : Int
    }


-- This produces an empty Dict (BUG)
buildDictAnnotated : List Item -> Dict Int (List Item)
buildDictAnnotated items =
    List.foldl (\item acc -> Dict.insert item.value [ item ] acc) Dict.empty items


-- This works correctly (no annotation)
buildDictUnannotated items =
    List.foldl (\item acc -> Dict.insert item.value [ item ] acc) Dict.empty items


tests : List Test
tests =
    [ Test.test
          "FAILS: annotated function returning Dict Int (List Record) produces empty Dict"
          (\_ ->
              buildDictAnnotated [ Item "a" 10 ]
                  |> Dict.isEmpty
                  |> Test.equal False)
    , Test.test
          "PASSES: same function without annotation works"
          (\_ ->
              buildDictUnannotated [ Item "a" 10 ]
                  |> Dict.isEmpty
                  |> Test.equal False)
    ]
```

## Expected behaviour

Both functions should return `Dict.fromList [ ( 10, [ Item "a" 10 ] ) ]` — a non-empty Dict.

## Actual behaviour

- `buildDictAnnotated` returns an empty Dict (`Dict.isEmpty` is `True`)
- `buildDictUnannotated` returns the correct non-empty Dict

## Notes

- The bug triggers specifically when the Dict value type is `List Record` in the annotation.
- `Dict Int Record` (single record, not a list) works correctly with annotations.
- The function bodies are identical — the only difference is the presence of the type annotation.
- The type checker accepts both forms without error.
- The issue manifests regardless of how the Dict is built (`List.foldl`, `Dict.fromList`, named helper function).

## Workaround

Remove the type annotation from functions that return `Dict k (List Record)`. The compiler will infer the correct type and the codegen will work.

## Environment

- Sky compiler version: (run `sky --version` to fill in)
- OS: macOS
