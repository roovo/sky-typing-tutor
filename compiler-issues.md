Three cases where well-typed Sky code (accepted by `sky check` / type-checker) generates invalid Go that fails `go build`. All discovered in the same project.

---

## Issue 1: `.field` accessor in pipeline generates untyped `rt.Field` without type assertion

### Summary

Using the `.field` accessor syntax in a pipeline generates Go code that returns `any` where a concrete type (`int`) is expected. The compiler knows the return type from the annotation but doesn't emit a type assertion.

### Reproduction

Complete minimal app (`Main.sky` + `sky.toml`) that fails `sky build`:

**sky.toml:**

```toml
name    = "field-accessor-bug"
version = "0.1.0"
entry   = "Main.sky"

[source]
root = "."
```

**Main.sky:**

```elm
module Main exposing (main)

import Sky.Core.Prelude exposing (..)
import Std.Tui as Tui
import Std.Cmd as Cmd
import Std.Sub as Sub
import Std.Ui as Ui
import Std.Ui exposing (Element)


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


type alias Model =
    { value : Int }


type Msg
    = NoOp


init : () -> ( Model, Cmd Msg )
init _ =
    ( { value = terminalLineHeight (Session { terminalLineHeight = 36, wpmTarget = 40 }) }
    , Cmd.none
    )


update : Msg -> Model -> ( Model, Cmd Msg )
update _ model =
    ( model, Cmd.none )


view : Model -> Element Msg
view model =
    Ui.text ("Value: " ++ String.fromInt model.value)


main =
    Tui.app
        { init = init
        , update = update
        , view = view
        , subscriptions = \_ -> Sub.none
        , onKey = \_ -> NoOp
        }
```

The type-checker accepts this, but `go build` fails:

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

Complete minimal app that fails `sky build`:

**sky.toml:**

```toml
name    = "recursive-let-bug"
version = "0.1.0"
entry   = "Main.sky"

[source]
root = "."
```

**Main.sky:**

```elm
module Main exposing (main)

import Sky.Core.Prelude exposing (..)
import Std.Tui as Tui
import Std.Cmd as Cmd
import Std.Sub as Sub
import Std.Ui as Ui
import Std.Ui exposing (Element)


takeWhile : (a -> Bool) -> List a -> List a
takeWhile predicate list =
    let
        helper memo xs =
            case xs of

                [] ->
                    List.reverse memo

                x :: rest ->
                    if predicate x then
                        helper (x :: memo) rest

                    else
                        List.reverse memo
    in
        helper [] list


type alias Model =
    { items : List Int }


type Msg
    = NoOp


init : () -> ( Model, Cmd Msg )
init _ =
    ( { items = takeWhile (\n -> n < 5) [ 1, 2, 3, 4, 5, 6, 7 ] }
    , Cmd.none
    )


update : Msg -> Model -> ( Model, Cmd Msg )
update _ model =
    ( model, Cmd.none )


view : Model -> Element Msg
view model =
    Ui.text ("Items: " ++ String.fromInt (List.length model.items))


main =
    Tui.app
        { init = init
        , update = update
        , view = view
        , subscriptions = \_ -> Sub.none
        , onKey = \_ -> NoOp
        }
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

Complete minimal app that fails `sky build`:

**sky.toml:**

```toml
name    = "lambda-coercion-bug"
version = "0.1.0"
entry   = "Main.sky"

[source]
root = "."
```

**Main.sky:**

```elm
module Main exposing (main)

import Sky.Core.Prelude exposing (..)
import Std.Tui as Tui
import Std.Cmd as Cmd
import Std.Sub as Sub
import Std.Ui as Ui
import Std.Ui exposing (Element)


type Step
    = Typeable Char
    | EnterChar
    | EmptyLine
    | End


dropWhile : (a -> Bool) -> List a -> List a
dropWhile predicate list =
    case list of

        [] ->
            []

        x :: xs ->
            if predicate x then
                dropWhile predicate xs

            else
                list


dropWhileRight : (a -> Bool) -> List a -> List a
dropWhileRight p list =
    List.foldr
        (\x xs ->
            if p x && List.isEmpty xs then
                []

            else
                x :: xs)
        []
        list


toSteps : String -> List Step
toSteps string =
    string |> String.lines |> List.map (\_ -> [ Typeable 'a', EnterChar ])
        |> List.concat
        |> dropWhile (\s -> s == EmptyLine)
        |> dropWhileRight (\s -> s == EnterChar || s == EmptyLine)
        |> (\steps -> steps ++ [ End ])


type alias Model =
    { steps : List Step }


type Msg
    = NoOp


init : () -> ( Model, Cmd Msg )
init _ =
    ( { steps = toSteps "hello\nworld" }
    , Cmd.none
    )


update : Msg -> Model -> ( Model, Cmd Msg )
update _ model =
    ( model, Cmd.none )


view : Model -> Element Msg
view model =
    Ui.text ("Steps: " ++ String.fromInt (List.length model.steps))


main =
    Tui.app
        { init = init
        , update = update
        , view = view
        , subscriptions = \_ -> Sub.none
        , onKey = \_ -> NoOp
        }
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

Complete minimal app that fails `sky build`. Three files in one directory:

**sky.toml:**

```toml
name    = "same-name-type-alias-bug"
version = "0.1.0"
entry   = "Main.sky"

[source]
root = "."
```

**Page/A.sky:**

```elm
module Page.A exposing (Model, init, view)

import Sky.Core.Prelude exposing (..)
import Std.Cmd as Cmd
import Std.Ui as Ui
import Std.Ui exposing (Element)


type alias Model =
    { name : String
    , age : Int
    }


init : Model
init =
    { name = "Alice", age = 30 }


view : Model -> Element msg
view model =
    Ui.text ("A: " ++ model.name ++ " age " ++ String.fromInt model.age)
```

**Page/B.sky:**

```elm
module Page.B exposing (Model, init, view)

import Sky.Core.Prelude exposing (..)
import Std.Cmd as Cmd
import Std.Ui as Ui
import Std.Ui exposing (Element)


type alias Model =
    { title : String
    , count : Int
    }


init : Model
init =
    { title = "Hello", count = 42 }


view : Model -> Element msg
view model =
    Ui.text ("B: " ++ model.title ++ " count " ++ String.fromInt model.count)
```

**Main.sky:**

```elm
module Main exposing (main)

import Page.A as PageA
import Page.B as PageB
import Sky.Core.Prelude exposing (..)
import Std.Tui as Tui
import Std.Cmd as Cmd
import Std.Sub as Sub
import Std.Ui as Ui
import Std.Ui exposing (Element)


type AppModel
    = OnPageA PageA.Model
    | OnPageB PageB.Model


type Msg
    = NoOp


init : () -> ( AppModel, Cmd Msg )
init _ =
    ( OnPageA PageA.init, Cmd.none )


update : Msg -> AppModel -> ( AppModel, Cmd Msg )
update _ model =
    ( model, Cmd.none )


view : AppModel -> Element Msg
view model =
    case model of

        OnPageA subModel ->
            PageA.view subModel

        OnPageB subModel ->
            PageB.view subModel


main =
    Tui.app
        { init = init
        , update = update
        , view = view
        , subscriptions = \_ -> Sub.none
        , onKey = \_ -> NoOp
        }
```

### Errors

```
[init] record is missing field(s): count, title
[view] record is missing field(s): name
[view] record is missing field(s): age
```

All errors are in `Page/A.sky` — the compiler thinks `Page.A.Model` should have `Page.B.Model`'s fields (`count`, `title`). It has merged the two distinct types into one because they share the unqualified name `Model`.

### Expected behaviour

Qualified type references (`PageA.Model` and `PageB.Model`) should resolve to entirely separate types. Two modules exposing a type alias with the same name is idiomatic in Elm/ML-family languages and should not cause unification.

### Workaround

Give the type aliases distinct names across modules:

```elm
-- Page/A.sky
type alias PageAModel =
    { name : String
    , age : Int
    }

-- Page/B.sky
type alias PageBModel =
    { title : String
    , count : Int
    }
```

Then reference as `PageA.PageAModel` and `PageB.PageBModel` in `Main.sky`.

---

## Issue 5: Custom parameterised ADT in model record field corrupted after Tui runtime serialisation round-trip

### Summary

A parameterised ADT (`Status a`) wrapping database query results, stored in a sub-page model field and nested inside a parent `AppModel` ADT variant, is corrupted after the Tui runtime's serialisation round-trip. The initial `view` renders correctly, but after any key press triggers `update` — even if the model is returned unchanged — the ADT field no longer matches any variant in a `case` expression, causing a runtime panic.

**Update (2026-07-24):** `Maybe` values and simple custom ADTs now survive the round-trip correctly (fixed in a recent compiler update). The bug still affects parameterised ADTs (`Status a`) but only in the full application — we could not reproduce it in a minimal standalone repro despite matching the model shape, nested TEA architecture, database queries, and cross-module types. The trigger appears to require a specific combination of factors present in the full app.

### Conditions that trigger the bug (in the real app)

- Sub-page model with a `Status (List ExerciseDb)` field
- Data populated via `Task.run (Db.query ...)`
- Model nested inside a parent `AppModel` ADT variant
- Multiple other fields in the model (String, Maybe String, List, Session)
- Nested TEA dispatch with `toMsg` pattern

### Conditions that do NOT trigger the bug (tested in isolation)

- Parameterised ADT in a flat (non-nested) model ✓
- Parameterised ADT in a nested model without DB query ✓
- Parameterised ADT in a nested model with DB query but matching field shapes ✓
- `Maybe` values in any configuration ✓ (fixed)
- Simple custom ADTs in any configuration ✓ (fixed)

### Reproduction

The bug reproduces consistently in the full `sky-typing-tutor` app on the `buggy_branch` branch. Run `sky run` and press any key on the exercises page to trigger the panic.

```elm
type Status a
    = Loading
    | Loaded a
    | Failed String

type alias ExercisesModel =
    { newExercisePath : String
    , exercises : Status (List ExerciseDb)
    , isAdding : Maybe String
    , session : Session
    }
```

With `init` populating via:

```elm
exercises =
    case Task.run (Db.query Database.db "SELECT ..." []) of
        Ok rows -> Loaded (List.map rowToExercise rows)
        Err e -> Failed (Error.toString e)
```

The initial render works. After any key press, the next `view` call panics:

```
Sky panic: CompilerBug (ref a932bb1e) — Unreachable code path
panicMsg=sky.Unreachable(case): sky: codegen reached an arm the exhaustiveness checker said was impossible
```

Removing the `Status` ADT and using plain fields (`exercises : List ExerciseDb` + `exerciseError : String`) resolves the issue. Removing the database query (hardcoding the data) also resolves the issue.

### Expected behaviour

Parameterised ADTs stored in model record fields should survive the Tui runtime's gob encode/decode round-trip without corruption.

### Workaround

Replace the parameterised ADT with primitive types in model fields:

- Instead of `Status (List a)` → use `List a` + `String` (error message, empty = no error)

Additionally, when doing record updates, explicitly include ALL fields that have non-zero values — not just the fields being changed. The codegen narrows the return type to only the fields mentioned in the update expression (see "Record update codegen" section below).

### Record update codegen issue

The codegen emits an anonymous struct containing only the fields mentioned in the record update as the tuple return type. For example:

```elm
( { model | newExercisePath = model.newExercisePath ++ keyEvent.value }, Cmd.none )
```

Generates a return type of:
```go
rt.T2[struct{ NewExercisePath any }, any]
```

Instead of:
```go
rt.T2[Page_Exercises_ExercisesModel_R, any]
```

The actual record update logic is correct (`_u := v_1; _u.NewExercisePath = ...; return _u` copies all fields), but the result is then coerced via `rt.Coerce` into the narrower anonymous struct — which drops all other fields (`exercises`, `exerciseError`, `isAdding`, `session`).

This means every record update in a tuple return must explicitly re-set all fields that aren't their Go zero value, otherwise they are silently lost.

**Note:** This could not be reproduced in a minimal standalone app — the generated Go in isolation correctly uses the full record type. The narrowed anonymous struct only appears in the full application. The trigger appears to depend on project size or module interaction. The behaviour can be observed in the `handleNewExerciseKeypresses` function in `src/Page/Exercises.sky` on the working branch by removing `isAdding = True` from the record update.

---

## Issue 6: Cross-module record type alias not recognised when extracted from ADT variant pattern match

### Summary

When a record type alias from another module is used as the payload of an ADT variant, extracting it via pattern matching results in a "type mismatch: SubModel vs record" error. The compiler sees the extracted value as a bare `record` instead of the named type alias, so passing it to functions that expect the named type fails.

This is a regression — the previous compiler version accepted this pattern (with distinct type alias names as a workaround for Issue 4).

### Reproduction

Complete minimal app that fails `sky build`. Three files in one directory:

**sky.toml:**
```toml
name    = "cross-module-adt-type-mismatch"
version = "0.1.0"
entry   = "Main.sky"

[source]
root = "."
```

**Page/Sub.sky:**
```elm
module Page.Sub exposing (SubModel, Msg(..), init, update, view)

import Sky.Core.Prelude exposing (..)
import Std.Cmd as Cmd
import Std.Ui as Ui
import Std.Ui exposing (Element)


type alias KeyEvent =
    { kind : String
    , value : String
    }


type alias SubModel =
    { counter : Int
    , label : String
    }


type Msg
    = KeyTyped KeyEvent


init : (Msg -> parentMsg) -> ( SubModel, Cmd parentMsg )
init toMsg =
    ( { counter = 0, label = "hello" }, Cmd.none )


update : (Msg -> parentMsg) -> Msg -> SubModel -> ( SubModel, Cmd parentMsg )
update toMsg msg model =
    case msg of

        KeyTyped _ ->
            ( { model | counter = model.counter + 1 }, Cmd.none )


view : (Msg -> parentMsg) -> SubModel -> Element parentMsg
view toMsg model =
    Ui.column
        [ Ui.padding 8, Ui.spacing 4 ]
        [ Ui.text ("Counter: " ++ String.fromInt model.counter)
        , Ui.text ("Label: " ++ model.label)
        ]
```

**Main.sky:**
```elm
module Main exposing (main)

import Page.Sub as PageSub
import Sky.Core.Prelude exposing (..)
import Std.Cmd as Cmd
import Std.Sub as Sub
import Std.Tui as Tui
import Std.Ui as Ui
import Std.Ui exposing (Element)


type alias KeyEvent =
    { kind : String
    , value : String
    }


type AppModel
    = Active PageSub.SubModel


type Msg
    = GotSubMsg PageSub.Msg
    | KeyPressed KeyEvent
    | Quit
    | NoOp


init : () -> ( AppModel, Cmd Msg )
init _ =
    let
        ( subModel, cmd ) = PageSub.init GotSubMsg
    in
        ( Active subModel, cmd )


update : Msg -> AppModel -> ( AppModel, Cmd Msg )
update msg model =
    case ( msg, model ) of

        ( GotSubMsg subMsg, Active subModel ) ->
            let
                ( newSubModel, cmd ) =
                    PageSub.update GotSubMsg subMsg subModel
            in
                ( Active newSubModel, cmd )

        ( GotSubMsg _, _ ) ->
            ( model, Cmd.none )

        ( KeyPressed keyEvent, Active subModel ) ->
            let
                ( newSubModel, cmd ) =
                    PageSub.update
                        GotSubMsg
                        (PageSub.KeyTyped keyEvent)
                        subModel
            in
                ( Active newSubModel, cmd )

        ( KeyPressed _, _ ) ->
            ( model, Cmd.none )

        ( Quit, _ ) ->
            ( model, Cmd.perform (System.exit 0) (\_ -> NoOp) )

        ( NoOp, _ ) ->
            ( model, Cmd.none )


view : AppModel -> Element Msg
view model =
    case model of

        Active subModel ->
            PageSub.view GotSubMsg subModel


subscriptions : AppModel -> Sub Msg
subscriptions _ =
    Sub.none


onKey : KeyEvent -> Msg
onKey keyEvent =
    if keyEvent.kind == "char" && keyEvent.value == "q" then
        Quit

    else if keyEvent.kind == "escape" then
        Quit

    else
        KeyPressed keyEvent


main =
    Tui.app
        { init = init
        , update = update
        , view = view
        , subscriptions = subscriptions
        , onKey = onKey
        }
```

### Errors

```
[init] type mismatch: SubModel vs record
[update] type mismatch: record vs SubModel
[view] type mismatch: record vs SubModel
```

The compiler treats the value extracted from `Active subModel` as a bare `record` instead of `PageSub.SubModel`, so it can't be passed to `PageSub.update` or `PageSub.view` which expect `SubModel`.

### Expected behaviour

A cross-module record type alias used as an ADT variant payload should be recognised as that type when extracted via pattern matching. This is the standard nested TEA pattern.

### Workaround

None known at this time. The previous compiler version accepted this pattern.

---

## Environment

- Compiler: Sky (Rust-based, new compiler)
- OS: macOS
- Date: 2026-07-24
