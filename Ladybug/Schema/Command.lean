import Lean
import Ladybug.Cypher.Builder
import Ladybug.Decode.Derive
import Ladybug.Schema.Registry

/-!
# Table declarations

```lean
structure Person where
  id : Int64
  name : String
  age : Option Int64

node_table Person                      -- label "Person", key `id`
node_table Company (key := name) (label := "Org")
rel_table WorksAt (from := Person) (to := Company)
```

Each command checks that every field has a column type, then generates
`FromValue`/`ToValue` instances, the table instance, and the companion
structures `T.Var` (one `Expr` per field) and `T.OptVar` (every field nullable)
used by the query builder. `deriving NodeTable` declares a node table with the
default label and key; `deriving CypherType` makes a structure usable as a
nested STRUCT column.
-/

namespace Ladybug.Command

open Lean Elab Command Term Meta

structure FieldInfo where
  name : Name
  type : Lean.Expr
  typeStx : Term
  /-- The field's type with NULL allowed: itself if already an `Option`. -/
  optTypeStx : Term
  isOption : Bool

private def delabFull (e : Lean.Expr) : MetaM Term :=
  withOptions (fun o => o.setBool `pp.fullNames true |>.setBool `pp.universes false) do
    PrettyPrinter.delab e

/-- The fields of a parameterless structure without parents, with their types,
checking that every type has a `CypherType` instance. -/
def structFields (cmd : String) (declName : Name) : TermElabM (Array FieldInfo) := do
  let env ← getEnv
  unless isStructure env declName do
    throwError "{cmd}: {declName} is not a structure"
  let info ← getConstInfoInduct declName
  unless info.numParams == 0 do
    throwError "{cmd}: structures with parameters are not supported ({declName})"
  unless (getStructureParentInfo env declName).isEmpty do
    throwError "{cmd}: structures that extend others are not supported ({declName})"
  let fields := getStructureFields env declName
  fields.mapM fun f => do
    let projTy ← inferType (mkConst (declName ++ f))
    let τ := projTy.bindingBody!
    if τ.hasLooseBVars then
      throwError "{cmd} {declName}: field '{f}' has a dependent type, which is not a column type"
    let inst ← mkAppM ``Ladybug.CypherType #[τ]
    if (← synthInstance? inst).isNone then
      throwError "{cmd} {declName}: field '{f}' has type {τ}, which is not a column type \
        (no Ladybug.CypherType instance)"
    let isOption := τ.isAppOf ``Option
    let typeStx ← delabFull τ
    let optTypeStx ← if isOption then pure typeStx else `(Option $typeStx)
    return { name := f, type := τ, typeStx, optTypeStx, isOption }

private def vId : Ident := mkIdent `v

/-- `⟨v, ⟨.prop (.var v) "f₁"⟩, …⟩` for a companion structure. -/
private def companionValue (fields : Array FieldInfo) : CommandElabM Term := do
  let vals ← fields.mapM fun fi =>
    `(⟨Ladybug.Cypher.Core.Expr.prop (Ladybug.Cypher.Core.Expr.var $vId) $(quote fi.name.toString)⟩)
  `(⟨$vId, $vals,*⟩)

/-- Generate decoders, the companion structures and `HasVar`. -/
private def companions (declName : Name) (fields : Array FieldInfo) : CommandElabM (Ident × Ident) := do
  let S := mkIdent declName
  elabCommand (← `(deriving instance Ladybug.FromValue, Ladybug.ToValue for $S))
  -- `_root_` keeps the current namespace from being prepended to the full name.
  let varId := mkIdent (declName ++ `Var)
  let optId := mkIdent (declName ++ `OptVar)
  let varDecl := mkIdent (`_root_ ++ declName ++ `Var)
  let optDecl := mkIdent (`_root_ ++ declName ++ `OptVar)
  let ids := fields.map (mkIdent ·.name)
  let tys ← fields.mapM fun fi => `(Ladybug.Expr $(fi.typeStx))
  let optTys ← fields.mapM fun fi => `(Ladybug.Expr $(fi.optTypeStx))
  elabCommand (← `(
    /-- Query variable of this table: each field is a typed property expression. -/
    structure $varDecl:ident where
      cypherVar : String
      $[$ids:ident : $tys]*))
  elabCommand (← `(
    /-- OPTIONAL MATCH variable of this table: every property is nullable. -/
    structure $optDecl:ident where
      cypherVar : String
      $[$ids:ident : $optTys]*))
  let value ← companionValue fields
  elabCommand (← `(instance : Ladybug.HasVar $S $varId $optId where
    mkVar := fun $vId => $value
    mkOpt := fun $vId => $value))
  return (varId, optId)

private def registryColumns (fields : Array FieldInfo) : Array Registry.ColumnEntry :=
  fields.map fun fi => { name := fi.name.toString, nullable := fi.isOption }

private def columnsTerm (fields : Array FieldInfo) : CommandElabM Term := do
  let cols ← fields.mapM fun fi => `(Ladybug.Column.of $(quote fi.name.toString) $(fi.typeStx))
  `(#[$cols,*])

-- @tg: implements:: [[openspec:graph-schema#Node table declaration]]
def declareNodeTable (declName : Name) (key? : Option Name) (label? : Option String) : CommandElabM Unit := do
  let fields ← liftTermElabM (structFields "node_table" declName)
  let key := key?.getD `id
  let some keyField := fields.find? (·.name == key)
    | if key?.isNone then
        throwError "node_table {declName}: a key is required; add a field `id` or write \
          `node_table {declName} (key := <field>)`"
      else throwError "node_table {declName}: key field '{key}' does not exist"
  if keyField.isOption then
    throwError "node_table {declName}: key field '{key}' must not be an Option"
  let label := label?.getD (declName.getString!)
  let S := mkIdent declName
  let (varId, optId) ← companions declName fields
  elabCommand (← `(instance : Ladybug.NodeTable $S where
    label := $(quote label)
    key := $(quote key.toString)
    columns := $(← columnsTerm fields)))
  elabCommand (← `(instance : Ladybug.NodeVarOf $varId $S := ⟨(·.cypherVar)⟩))
  elabCommand (← `(instance : Ladybug.OptNodeVarOf $optId $S := ⟨(·.cypherVar)⟩))
  elabCommand (← `(instance : Ladybug.NodeKey $S $(keyField.typeStx) := ⟨$(mkIdent (declName ++ key))⟩))
  let entry : Registry.TableEntry :=
    { label := label, declName := declName, isRel := false, columns := registryColumns fields }
  liftCoreM <| Registry.register entry

-- @tg: implements:: [[openspec:graph-schema#Relationship table declaration]]
def declareRelTable (declName src dst : Name) (label? : Option String) : CommandElabM Unit := do
  let fields ← liftTermElabM (structFields "rel_table" declName)
  for endpoint in [src, dst] do
    let ok ← liftTermElabM do
      let inst ← mkAppM ``Ladybug.NodeTable #[mkConst endpoint]
      return (← synthInstance? inst).isSome
    unless ok do throwError "rel_table {declName}: {endpoint} is not a node table; declare it with node_table first"
  let label := label?.getD (declName.getString!)
  let R := mkIdent declName
  let (varId, optId) ← companions declName fields
  elabCommand (← `(instance : Ladybug.RelTable $R $(mkIdent src) $(mkIdent dst) where
    label := $(quote label)
    columns := $(← columnsTerm fields)))
  elabCommand (← `(instance : Ladybug.RelVarOf $varId $R := ⟨(·.cypherVar)⟩))
  elabCommand (← `(instance : Ladybug.OptRelVarOf $optId $R := ⟨(·.cypherVar)⟩))
  let labelOf (n : Name) : CommandElabM String := do
    let some e := (Registry.tableExt.getState (← getEnv)).toList.find? (·.2.declName == n)
      | return n.getString!
    return e.1
  let srcLabel ← labelOf src
  let dstLabel ← labelOf dst
  let entry : Registry.TableEntry :=
    { label := label, declName := declName, isRel := true, columns := registryColumns fields,
      src := some srcLabel, dst := some dstLabel }
  liftCoreM <| Registry.register entry

syntax tableKeyOpt := "(" &"key" " := " ident ")"
syntax tableLabelOpt := "(" &"label" " := " str ")"
syntax tableOpt := atomic(tableKeyOpt) <|> tableLabelOpt

/-- `node_table T`, optionally with `(key := field)` and `(label := "L")` in any order. -/
syntax (name := nodeTableCmd) "node_table " ident (ppSpace tableOpt)* : command

syntax (name := relTableCmd) "rel_table " ident ppSpace "(" "from" " := " ident ")"
  ppSpace "(" &"to" " := " ident ")" (ppSpace "(" &"label" " := " str ")")? : command

private def resolveStruct (id : Ident) : CommandElabM Name :=
  liftCoreM <| realizeGlobalConstNoOverloadWithInfo id

@[command_elab nodeTableCmd] def elabNodeTable : CommandElab
  | `(node_table $s $opts*) => do
    let mut key := none
    let mut label := none
    for o in opts do
      match o with
      | `(tableOpt| (key := $k)) => key := some k.getId
      | `(tableOpt| (label := $l)) => label := some l.getString
      | _ => throwUnsupportedSyntax
    declareNodeTable (← resolveStruct s) key label
  | _ => throwUnsupportedSyntax

@[command_elab relTableCmd] def elabRelTable : CommandElab
  | `(rel_table $r (from := $a) (to := $b) $[(label := $l)]?) => do
    declareRelTable (← resolveStruct r) (← resolveStruct a) (← resolveStruct b) (l.map (·.getString))
  | _ => throwUnsupportedSyntax

/-- `deriving CypherType`: a structure stored as a STRUCT column. -/
private def deriveCypherType (declName : Name) : CommandElabM Unit := do
  let fields ← liftTermElabM (structFields "deriving CypherType" declName)
  let S := mkIdent declName
  elabCommand (← `(deriving instance Ladybug.FromValue, Ladybug.ToValue for $S))
  let entries ← fields.mapM fun fi =>
    `(($(quote fi.name.toString), Ladybug.CypherType.colType $(fi.typeStx)))
  elabCommand (← `(instance : Ladybug.CypherType $S := ⟨.struct [$entries,*], false⟩))

initialize
  registerDerivingHandler ``Ladybug.NodeTable fun names => do
    for n in names do declareNodeTable n none none
    return true
  registerDerivingHandler ``Ladybug.CypherType fun names => do
    for n in names do deriveCypherType n
    return true

end Ladybug.Command
