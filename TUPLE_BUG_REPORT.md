# Tuple codegen bugs

## Bug 1: Tuple destructuring in lambda parameters

Destructuring a tuple in a lambda parameter (e.g. as the accumulator in `List.foldr`) produces a Go codegen error:

```
./main.go:116:137: _t0.V0 undefined (type any has no field or method V0)
```

### Minimal reproduction

```elm
module TupleBug1Tests exposing (tests)

import Sky.Test as Test exposing (Test)


partition : (a -> Bool) -> List a -> ( List a, List a )
partition pred list =
    let
        step x ( trues, falses ) =
            if pred x then
                ( List.cons x trues, falses )

            else
                ( trues, List.cons x falses )
    in
        List.foldr step ( [], [] ) list


tests : List Test
tests =
    [ Test.test
          "tuple destructuring in lambda param"
          (\_ ->
              partition (\n -> n > 3) [ 1, 2, 3, 4, 5 ]
                  |> Test.equal ( [ 4, 5 ], [ 1, 2, 3 ] ))
    ]
```

### Workaround

Avoid destructuring — take the tuple as a single value and use `fst`/`snd`:

```elm
step x acc =
    if pred x then
        ( List.cons x (fst acc), snd acc )

    else
        ( fst acc, List.cons x (snd acc) )
```

---

## Bug 2: `fst` on polymorphic tuples inside `List.foldl` zeroes record fields

When a polymorphic function returns `List ( a, List a )` and `a` is a record
type, calling `fst` on those tuples **inside a `List.foldl` callback** produces
records with zeroed-out fields (e.g. a `Char` field becomes char code 0).

Note: calling `fst` on the same tuples inside `List.map` works correctly.
The bug is specific to `fst` used within a `foldl` accumulator function.

### Minimal reproduction

Requires a helper module exporting a polymorphic function returning tuples
(e.g. `gatherWith` below), and a consumer that uses `fst` inside `List.foldl`:

```elm
-- In a helper module (e.g. List/Extra.sky):

gatherWith : (a -> a -> Bool) -> List a -> List ( a, List a )
gatherWith testFn list =
    let
        helper scattered gathered =
            case scattered of

                [] ->
                    List.reverse gathered

                toGather :: population ->
                    let
                        partitioned = partition (testFn toGather) population
                        gathering = fst partitioned
                        remaining = snd partitioned
                    in
                        helper remaining (( toGather, gathering ) :: gathered)
    in
        helper list []
```

```elm
-- Test module:

module TupleBug2Tests exposing (tests)

import Sky.Test as Test exposing (Test)
import List.Extra as LE


type alias Item =
    { name : Char
    , value : Int
    }


groupByName : List Item -> List Item
groupByName items =
    let
        addValues item acc = { acc | value = acc.value + item.value }
        helper gathered acc =
            let
                head = fst gathered
                rest = snd gathered
            in
                List.foldl addValues head rest :: acc
    in
        items |> LE.gatherWith (\a b -> a.name == b.name)
            |> List.foldl helper []
            |> List.reverse


tests : List Test
tests =
    [ Test.test
          "fst inside foldl on gatherWith results preserves record fields"
          (\_ ->
              let
                  items =
                      [ Item 'a' 1
                      , Item 'b' 2
                      , Item 'a' 3
                      ]

                  grouped = groupByName items

                  names = List.map (\item -> Char.toCode item.name) grouped
              in
                  Test.equal [ 97, 98 ] names)
    ]
```

### Expected output

```
  ok    fst inside foldl on gatherWith results preserves record fields
```

### Actual output

```
  FAIL  fst inside foldl on gatherWith results preserves record fields
          expected [97 98] but got [0 98]
```

The first element ('a', which had duplicates grouped) gets its `name` field
zeroed to char code 0. The second element ('b', which had no duplicates) is
fine.

### Workaround

Avoid `fst`/`snd` on polymorphic tuples inside `foldl`. Rewrite using `Dict`
to accumulate grouped results directly.

---

## Environment

- Sky compiler version: (run `sky --version` to fill in)
- OS: macOS
