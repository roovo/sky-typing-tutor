# Compiler Codegen Issues

Three cases where well-typed Sky code (accepted by `sky check` / type-checker) generates invalid Go that fails `go build`. All discovered in the same project.

---

## Issue 1: `.field` accessor in pipeline generates untyped `rt.Field` without type assertion

### Summary

Using the `.field` accessor syntax in a pipeline generates Go code that returns `any` where a concrete type (`int`) is expected. The compiler knows the return type from the annotation but doesn't emit a type assertion.

### Reproduction

```elm
type Session
    = Session Config

type alias Config =
    { terminalLineHeight : Int
    , wpmTarget : Int
    }

config : Session -> Config
config (Session c) =
    c

terminalLineHeight : Session -> Int
terminalLineHeight session =
    session |> config |> .terminalLineHeight
```

### Generated Go (broken)

```go
func Session_terminalLineHeight(v_0 Session_Session) int {
    return func(_r any) any { return rt.Field(_r, "TerminalLineHeight") }(Session_config(v_0))
}
```

### Go error

```
cannot use func(_r any) any {…}(Session_config(v_0)) (value of interface type any) as int value in return statement: need type assertion
```

### Expected behaviour

The compiler should emit a type assertion on the `rt.Field` result, e.g. `rt.Field(_r, "TerminalLineHeight").(int)`, or use a typed accessor.

### Workaround

Use a let-binding with direct field access instead of the `.field` accessor in a pipeline:

```elm
terminalLineHeight : Session -> Int
terminalLineHeight session =
    let
        c = config session
    in
        c.terminalLineHeight
```

---

## Issue 2: Recursive let-binding generates undefined variable reference

### Summary

A recursive function defined inside a `let...in` block generates a Go closure variable that is referenced before it is assigned, causing an "undefined" compile error.

### Reproduction

```elm
takeWhile : (a -> Bool) -> List a -> List a
takeWhile predicate list =
    let
        takeWhileMemo memo list =
            case list of
                [] ->
                    List.reverse memo

                x :: xs ->
                    if predicate x then
                        takeWhileMemo (x :: memo) xs
                    else
                        List.reverse memo
    in
        takeWhileMemo [] list
```

### Go error

```
undefined: takeWhileMemo_2
```

### Generated Go (broken)

The closure is assigned to `takeWhileMemo_2` in a single statement, but the body of the closure references `takeWhileMemo_2` — which isn't yet in scope at that point in Go.

### Expected behaviour

The compiler should either:
- Emit a two-step `var takeWhileMemo_2 func(...) ...` declaration followed by the assignment (allowing the closure to capture the variable), or
- Auto-lift the recursive local function to a top-level Go function.

### Workaround

Extract the recursive let-binding into a top-level helper function:

```elm
takeWhile : (a -> Bool) -> List a -> List a
takeWhile predicate list =
    takeWhileHelper predicate [] list


takeWhileHelper : (a -> Bool) -> List a -> List a -> List a
takeWhileHelper predicate memo list =
    case list of
        [] ->
            List.reverse memo

        x :: xs ->
            if predicate x then
                takeWhileHelper predicate (x :: memo) xs
            else
                List.reverse memo
```

---

## Issue 3: `[]any` vs `[]T` type coercion failure across anonymous lambda boundary in pipeline

### Summary

When polymorphic list functions (`dropWhile`, `dropWhileRight`) feed into an anonymous lambda at the end of a pipeline, the generated Go code passes `[]any` where `[]T` is expected. The compiler loses the concrete element type at the lambda boundary.

### Reproduction

```elm
import List.Extra as LE
import Step exposing (Step(..))

toSteps : String -> List Step
toSteps string =
    string |> String.trimEnd |> String.lines |> List.map parseLine
        |> List.concat
        |> LE.dropWhile (\s -> s == EmptyLine)
        |> LE.dropWhileRight (\s -> s == EnterChar || s == EmptyLine)
        |> (\steps -> steps ++ [ Step.initEnd ])
```

### Go error

```
cannot use List_Extra_dropWhileRight(...) (value of type []any) as []Step_Step value in argument to func(v_3 []Step_Step) []Step_Step {…}
```

### Expected behaviour

The compiler should insert a coercion (`rt.AsListT[Step_Step](...)`) at the boundary where the `[]any` result of `dropWhileRight` flows into the typed lambda parameter.

### Workaround

Use intermediate let-bindings instead of feeding directly into an anonymous lambda:

```elm
toSteps : String -> List Step
toSteps string =
    let
        allSteps =
            string |> String.trimEnd |> String.lines |> List.map parseLine
                |> List.concat

        trimmedSteps =
            allSteps
                |> LE.dropWhile (\s -> s == EmptyLine)
                |> LE.dropWhileRight (\s -> s == EnterChar || s == EmptyLine)
    in
        trimmedSteps ++ [ Step.initEnd ]
```

---

## Issue 4: Identically-named type aliases in different modules are conflated by the type-checker

### Summary

When two modules each expose a `type alias` with the same name (`Model`), the type-checker conflates them even though they are referenced via distinct qualified paths (`PageExercise.Model` vs `PageExercises.Model`). The compiler unifies the two record types, causing spurious "missing field" errors in the module whose fields don't match the other's shape.

### Reproduction

```elm
-- src/Page/Exercise.sky
module Page.Exercise exposing (Model, Msg(..), init, view, update)

type alias Model =
    { elapsedTime : Int
    , exercise : Exercise
    , saveStatus : String
    , session : Session
    }
```

```elm
-- src/Page/Exercises.sky
module Page.Exercises exposing (Model, Msg(..), Status(..), init, update, view)

type alias Model =
    { exercises : Status
    , session : Session
    }
```

```elm
-- src/Main.sky
import Page.Exercise as PageExercise
import Page.Exercises as PageExercises

type AppModel
    = Exercise PageExercise.Model
    | Exercises PageExercises.Model
```

### Errors

```
[init] record is missing field(s): exercises
[update] record is missing field(s): exercise
[update] record is missing field(s): saveStatus
[update] record is missing field(s): elapsedTime
...
```

All errors are in `src/Page/Exercise.sky` — the compiler thinks `Page.Exercise.Model` should have `Page.Exercises.Model`'s fields (specifically `exercises`), and vice versa. It has merged the two distinct types into one because they share the unqualified name `Model`.

### Expected behaviour

Qualified type references (`PageExercise.Model` and `PageExercises.Model`) should resolve to entirely separate types. Two modules exposing a type alias with the same name is idiomatic in Elm/ML-family languages and should not cause unification.

### Workaround

Give the type aliases distinct names across modules:

```elm
-- src/Page/Exercises.sky
type alias ExercisesModel =
    { exercises : Status
    , session : Session
    }
```

Then reference as `PageExercises.ExercisesModel` in `Main.sky`.

---

## Environment

- Compiler: Sky (Rust-based, new compiler)
- OS: macOS
- Date: 2026-07-24
