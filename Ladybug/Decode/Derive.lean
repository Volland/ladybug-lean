import Lean
import Ladybug.Decode

/-!
# Deriving handlers

`deriving FromValue, ToValue, FromRow` for structures. Fields are matched by
name: in struct and node values for `FromValue`, in column names for `FromRow`.
-/

namespace Ladybug.Derive

open Lean Elab Command Meta

private def structureFields (declName : Name) : CommandElabM (Array Name) := do
  let env ← getEnv
  unless isStructure env declName do
    throwError "cannot derive for {declName}: only structures are supported"
  let info ← getConstInfoInduct declName
  unless info.numParams == 0 do
    throwError "cannot derive for {declName}: structures with parameters are not supported"
  return getStructureFieldsFlattened env declName (includeSubobjectFields := false)

private def mkFromValue (declName : Name) : CommandElabM Unit := do
  let fields ← structureFields declName
  let ty := mkIdent declName
  let ids := fields.map mkIdent
  let vals : Array Term := ids
  let strs := fields.map fun f => quote f.toString
  let cmd ← `(command|
    instance : Ladybug.FromValue $ty where
      typeName := $(quote declName.toString)
      fromValue? v := do
        $[let $ids:ident ← Ladybug.decodeField v $strs]*
        pure { $[$ids:ident := $vals],* })
  elabCommand cmd

private def mkToValue (declName : Name) : CommandElabM Unit := do
  let fields ← structureFields declName
  let ty := mkIdent declName
  let x := mkIdent `x
  let projs ← fields.mapM fun f => `(Ladybug.toValue ($(mkIdent (declName ++ f)) $x))
  let strs := fields.map fun f => quote f.toString
  let cmd ← `(command|
    instance : Ladybug.ToValue $ty where
      toValue := fun $x => .struct #[$[($strs, $projs)],*])
  elabCommand cmd

private def mkFromRow (declName : Name) : CommandElabM Unit := do
  let fields ← structureFields declName
  let ty := mkIdent declName
  let ids := fields.map mkIdent
  let vals : Array Term := ids
  let strs := fields.map fun f => quote f.toString
  let cmd ← `(command|
    instance : Ladybug.FromRow $ty where
      decodeFrom r _ := do
        $[let $ids:ident ← r.decodeNamed $strs]*
        pure ({ $[$ids:ident := $vals],* }, r.values.size))
  elabCommand cmd

private def handler (mk : Name → CommandElabM Unit) (declNames : Array Name) : CommandElabM Bool := do
  for n in declNames do mk n
  return true

initialize
  registerDerivingHandler ``Ladybug.FromValue (handler mkFromValue)
  registerDerivingHandler ``Ladybug.ToValue (handler mkToValue)
  registerDerivingHandler ``Ladybug.FromRow (handler mkFromRow)

end Ladybug.Derive
