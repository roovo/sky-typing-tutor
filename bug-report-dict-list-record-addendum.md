# Addendum to Dict List Record bug

## Further finding: unannotated version also corrupts records

The original report noted that removing the type annotation made the Dict non-empty. However, further testing reveals the unannotated version also has a bug: **String and List fields within the stored records are zeroed**.

### Reproduction

```elm
type alias Item =
    { name : String
    , value : Int
    }

-- No annotation
buildDict items =
    List.foldl (\item acc -> Dict.insert item.value [ item ] acc) Dict.empty items
```

Calling `buildDict [ Item "a" 10 ] |> Dict.get 10` returns:

- **Expected:** `Just [ { name = "a", value = 10 } ]`
- **Actual:** `Just [ { name = "", value = 10 } ]`

### What's preserved vs what's lost

| Field type | Preserved? |
|---|---|
| Int | ✓ |
| String | ✗ (becomes `""`) |
| List a | ✗ (becomes `[]`) |

### Summary of the two layers of this bug

1. **With annotation** (`Dict Int (List Record)`) → Dict is completely empty
2. **Without annotation** → Dict has correct keys and structure, but String and List fields inside the stored records are zeroed

### Workaround

Use `Dict Int Record` (single record value, not wrapped in a List) and merge records before inserting. Single-record Dict values preserve all field types correctly.
