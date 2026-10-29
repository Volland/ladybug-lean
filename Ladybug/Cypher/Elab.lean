import Ladybug.Cypher.Syntax
import Ladybug.Schema.Command
import Ladybug.Cypher.Advanced
import Ladybug.Search

/-!
# `cypher%` elaboration

Each clause is translated into the builder call that expresses it, inside one
`do` block, which Lean then elaborates as ordinary builder code. The typing
rules and the resulting core AST are therefore exactly the builder's. Labels
and properties are resolved against the table registry first so that unknown
names are reported at the Cypher token that names them.
-/

namespace Ladybug.Cypher.Elab

open Lean Elab Term Meta
open Ladybug.Cypher.Syntax

inductive VarKind where
  | node (table : Registry.TableEntry)
  | rel (table : Registry.TableEntry)
  | expr
  deriving Inhabited

structure VarInfo where
  lean : Ident
  kind : VarKind
  optional : Bool := false
  deriving Inhabited

structure St where
  scope : Std.HashMap String VarInfo := {}
  elems : Array (TSyntax `doElem) := #[]
  next : Nat := 0

abbrev M := StateT St TermElabM

private def emit (e : TSyntax `doElem) : M Unit := modify fun s => { s with elems := s.elems.push e }

private def fresh (base : String) : M Ident := do
  let n ← modifyGet fun s => (s.next, { s with next := s.next + 1 })
  return mkIdent (← MonadQuotation.addMacroScope (Name.mkSimple s!"cy_{base}_{n}"))

private def bind (name : String) (info : VarInfo) : M Unit :=
  modify fun s => { s with scope := s.scope.insert name info }

private def lookup? (name : String) : M (Option VarInfo) := return (← get).scope.get? name

/-! ## Helpers -/

private def editDistance (a b : String) : Nat := Id.run do
  let a := a.toLower.toList.toArray
  let b := b.toLower.toList.toArray
  let mut prev := Array.range (b.size + 1)
  for i in [0:a.size] do
    let mut cur := #[i + 1]
    for j in [0:b.size] do
      let cost := if a[i]! == b[j]! then 0 else 1
      cur := cur.push (Nat.min (Nat.min (prev[j + 1]! + 1) (cur[j]! + 1)) (prev[j]! + cost))
    prev := cur
  return prev[b.size]!

private def suggestion (name : String) (candidates : Array String) : String :=
  let scored := candidates.map fun c => (editDistance name c, c)
  match scored.foldl (fun best x => if x.1 < best.1 then x else best) (1000, "") with
  | (d, c) => if d ≤ 2 && !c.isEmpty then s!"; did you mean '{c}'?" else ""

private def identStr (id : Syntax) : String := id.getId.toString (escape := false)

/-- Resolve a node or relationship label at its token. -/
private def table (lbl : Syntax) (wantRel : Bool) : M Registry.TableEntry := do
  let env ← getEnv
  let name := identStr lbl
  let kind := if wantRel then "relationship" else "node"
  match Registry.find? env name with
  | some e =>
    if e.isRel != wantRel then
      throwErrorAt lbl "'{name}' is a {if e.isRel then "relationship" else "node"} table, not a {kind} table"
    return e
  | none =>
    let candidates := (Registry.labels env).filter fun l => (Registry.find? env l).any (·.isRel == wantRel)
    throwErrorAt lbl "unknown {kind} label '{name}'{suggestion name candidates}"

private def tableIdent (e : Registry.TableEntry) : Ident := mkIdent e.declName

private def unsupported {α : Type} (stx : Syntax) (what : String) : M α :=
  throwErrorAt stx "cypher%: {what} is not supported; use the raw-text API (`queryRaw`) for it"

private def isKeyword (stx : Syntax) (kw : String) : Bool :=
  stx.isIdent && (identStr stx).toLower == kw

/-! ## Patterns -/

/-- Parts of `(var:Label {props})`. -/
private structure NodeParts where
  ref : Syntax
  var : Option String
  label : Option Syntax
  props : Syntax

private def nodeParts (n : Syntax) : NodeParts :=
  { ref := n, var := n[1].getOptional?.map identStr,
    label := if n[2].getNumArgs == 2 then some n[2][1] else none, props := n[3] }

private inductive Dir where | out | inc | both

/-- Parts of one step: direction, `[var:Label*range {props}]`, end node. -/
private def stepParts (s : Syntax) : Dir × Syntax × Syntax :=
  let inner := s[0]
  let dir := match inner.getKind with
    | ``cypherIn => Dir.inc
    | ``cypherBoth => Dir.both
    | _ => Dir.out
  (dir, inner[1], inner[3])

private def dirFn : Dir → Name
  | .out => ``Ladybug.out | .inc => ``Ladybug.inc | .both => ``Ladybug.both

private def dirTerm : Dir → M Term
  | .out => `(Ladybug.Cypher.Core.Dir.out)
  | .inc => `(Ladybug.Cypher.Core.Dir.inc)
  | .both => `(Ladybug.Cypher.Core.Dir.both)

private def matchFn (optional : Bool) : Ident :=
  mkIdent (if optional then ``Ladybug.optMatch else ``Ladybug.match_)

/-- The bound node variable `(v)` with no label or properties, if `n` is one. -/
private def boundNode? (n : NodeParts) : M (Option VarInfo) := do
  let some v := n.var | return none
  let some info ← lookup? v | return none
  if n.label.isSome || !n.props.isNone then
    throwErrorAt n.ref "variable '{v}' is already bound; refer to it as ({v})"
  match info.kind with
  | .node _ => return some info
  | _ => throwErrorAt n.ref "'{v}' is not a node variable"

private def noProps (n : NodeParts) : M Unit := do
  unless n.props.isNone do
    throwErrorAt n.props "property maps in MATCH are not supported; filter with WHERE"

/-- The end node's table: its label, or the relationship's endpoint. -/
private def endTable (dst : NodeParts) (r : Registry.TableEntry) (dir : Dir) : M Registry.TableEntry := do
  match dst.label with
  | some l => table l false
  | none =>
    let inferred := match dir with | .inc => r.src | _ => r.dst
    let some name := inferred | throwErrorAt dst.ref "a new node needs a label"
    let some t := Registry.find? (← getEnv) name | throwErrorAt dst.ref "a new node needs a label"
    pure t

-- @tg: implements:: [[openspec:cypher-syntax#Advanced clauses in syntax]]
/-- `*min..max` with its mode, from a `cypherRange` node. -/
private def rangeOf (rng : Syntax) : M (Nat × Nat × Option Name) := do
  let all := !rng[1].isNone
  let shortest := !rng[2].isNone
  let lo := (rng[3].getOptional?.bind (·.isNatLit?)).getD 1
  let hi? := if rng[4].getNumArgs == 2 then rng[4][1].getOptional?.bind (·.isNatLit?) else none
  let some hi := hi? | throwErrorAt rng "a variable-length pattern needs an upper bound, e.g. *1..3"
  if all && !shortest then throwErrorAt rng "ALL must be followed by SHORTEST"
  let fn := if shortest then some (if all then ``Ladybug.allShortestPaths else ``Ladybug.shortestPath) else none
  if fn.isSome && lo != 1 then throwErrorAt rng "shortest paths start at length 1"
  return (lo, hi, fn)

private def matchPattern (optional : Bool) (pat : Syntax) : M Unit := withRef pat do
  let pathVar := if pat[0].getNumArgs == 2 then some (identStr pat[0][0]) else none
  let start := nodeParts pat[1]
  let steps := pat[2].getArgs
  let mut cur ← match ← boundNode? start with
    | some info => pure info
    | none => do
      noProps start
      let some lbl := start.label | throwErrorAt start.ref "a new node needs a label, e.g. (p:Person)"
      let t ← table lbl false
      let id ← fresh (start.var.getD "n")
      let f := matchFn optional
      let rhs ← `($f (Ladybug.node $(tableIdent t)))
      emit (← `(doElem| let $id ← $rhs:term))
      let info : VarInfo := { lean := id, kind := .node t, optional }
      if let some v := start.var then bind v info
      pure info
  let ranged := steps.any fun st => !(stepParts st).2.1[4].isNone
  if pathVar.isSome && !ranged then
    throwErrorAt pat "a path variable needs a variable-length relationship, e.g. p = (a)-[:R*1..3]->(b)"
  if ranged && steps.size != 1 then
    throwErrorAt pat "a variable-length relationship must be the only step of its pattern"
  for step in steps do
    let (dir, relStx, endStx) := stepParts step
    let relVar := relStx[1].getOptional?.map identStr
    let r ← table relStx[3] true
    unless relStx[5].isNone do throwErrorAt relStx[5] "property maps in MATCH are not supported; filter with WHERE"
    let dst := nodeParts endStx
    let src := cur.lean
    if !relStx[4].isNone then
      if optional then throwErrorAt relStx[4] "OPTIONAL MATCH of a variable-length pattern is not supported"
      let (lo, hi, fn?) ← rangeOf relStx[4][0]
      let pathId ← fresh (pathVar.getD "p")
      let (dstTerm, dstInfo?) ← match ← boundNode? dst with
        | some info => pure ((info.lean : Term), some info)
        | none => do
          noProps dst
          let t ← endTable dst r dir
          pure (← `(Ladybug.node $(tableIdent t)), none)
      let d ← dirTerm dir
      let rhs ← match fn? with
        | some fn => `($(mkIdent fn) $src $(tableIdent r) $dstTerm (max := $(quote hi)) (dir := $d))
        | none => `(Ladybug.matchPaths $src $(tableIdent r) $dstTerm (min := $(quote lo)) (max := $(quote hi)) (dir := $d))
      let dstId ← fresh (dst.var.getD "n")
      emit (← withRef step `(doElem| let ($pathId, $dstId) ← $rhs:term))
      for name in [pathVar, relVar].filterMap id do bind name { lean := pathId, kind := .expr }
      let info ← match dstInfo? with
        | some info => pure info
        | none => do
          let info : VarInfo := { lean := dstId, kind := .node (← endTable dst r dir) }
          if let some v := dst.var then bind v info
          pure info
      cur := info
    else
      let relId ← fresh (relVar.getD "r")
      let f := matchFn optional
      let d := mkIdent (dirFn dir)
      let next ← match ← boundNode? dst with
        | some info => do
          let p ← `($d $src $(tableIdent r) $(info.lean))
          let rhs ← `($f $p)
          emit (← withRef step `(doElem| let $relId ← $rhs:term))
          pure info
        | none => do
          noProps dst
          let t ← endTable dst r dir
          let id ← fresh (dst.var.getD "n")
          let p ← `($d $src $(tableIdent r) (Ladybug.node $(tableIdent t)))
          let rhs ← `($f $p)
          emit (← withRef step `(doElem| let ($relId, $id) ← $rhs:term))
          let info : VarInfo := { lean := id, kind := .node t, optional }
          if let some v := dst.var then bind v info
          pure info
      if let some v := relVar then bind v { lean := relId, kind := .rel r, optional }
      cur := next

/-! ## Expressions -/

/-- `var` or `var.prop` in an expression. -/
private def identTerm (stx : Syntax) : M Term := withRef stx do
  let parts := (identStr stx).splitOn "."
  match parts with
  | [w] =>
    if w.toLower == "true" then return ← `(Ladybug.lit true)
    if w.toLower == "false" then return ← `(Ladybug.lit false)
    let some v ← lookup? w | throwErrorAt stx "unknown variable '{w}'"
    match v.kind with
    | .expr => return v.lean
    | _ => `(Ladybug.ref $(v.lean))
  | [w, prop] =>
    let some v ← lookup? w | throwErrorAt stx "unknown variable '{w}'"
    let t ← match v.kind with
      | .node t | .rel t => pure t
      | .expr => throwErrorAt stx "'{w}' is not a node or relationship variable"
    unless t.columns.any (·.name == prop) do
      throwErrorAt stx "unknown property '{prop}' of table {t.label}{suggestion prop (t.columns.map (·.name))}"
    let companion := t.declName ++ (if v.optional then `OptVar else `Var) ++ Name.mkSimple prop
    `($(mkIdent companion) $(v.lean))
  | _ => throwErrorAt stx "unsupported name '{identStr stx}'"

private def binFn : SyntaxNodeKind → Option Name
  | ``orE => some ``Ladybug.Expr.or | ``xorE => some ``Ladybug.Expr.xor | ``andE => some ``Ladybug.Expr.and
  | ``eqE => some ``Ladybug.Expr.eq | ``neqE => some ``Ladybug.Expr.neq
  | ``ltE => some ``Ladybug.Expr.lt | ``leE => some ``Ladybug.Expr.le
  | ``gtE => some ``Ladybug.Expr.gt | ``geE => some ``Ladybug.Expr.ge
  | ``inE => some ``Ladybug.Expr.isIn | ``containsE => some ``Ladybug.Expr.contains
  | ``addE => some ``Ladybug.Expr.plus | ``subE => some ``Ladybug.Expr.sub
  | ``mulE => some ``Ladybug.Expr.mul | ``divE => some ``Ladybug.Expr.div | ``modE => some ``Ladybug.Expr.mod
  | _ => none

private def unaryFns : List (String × Name) :=
  [("sum", ``Ladybug.Expr.sum), ("avg", ``Ladybug.Expr.avg), ("min", ``Ladybug.Expr.min),
   ("max", ``Ladybug.Expr.max), ("collect", ``Ladybug.Expr.collect), ("lower", ``Ladybug.Expr.lower),
   ("upper", ``Ladybug.Expr.upper), ("trim", ``Ladybug.Expr.trim), ("size", ``Ladybug.Expr.size),
   ("abs", ``Ladybug.Expr.abs)]

/-- `$x` and `$(e)` arrive as antiquotations; their term is the parameter. -/
private def antiquotParam? (stx : Syntax) : Option Term :=
  if stx.isAntiquot then some ⟨stx.getAntiquotTerm⟩ else none

mutual

partial def expr (stx : Syntax) : M Term := withRef stx do
  if let some t := antiquotParam? stx then return ← `(Ladybug.lit $t)
  if stx.getKind == ``existsE || stx.getKind == ``countSubE then
    return ← subquery stx
  let k := stx.getKind
  if let some f := binFn k then
    let a ← expr stx[0]
    let b ← expr stx[stx.getNumArgs - 1]
    return ← `($(mkIdent f) $a $b)
  match k with
  | ``numLit => return ⟨stx[0]⟩
  | ``sciLit => return ⟨stx[0]⟩
  | ``strLit => `(Ladybug.lit $(⟨stx[0]⟩))
  | ``nullLit => `(Ladybug.null)
  | ``identExpr => identTerm stx[0]
  | ``paramLocal => `(Ladybug.lit $(⟨stx[1]⟩))
  | ``paramTerm => `(Ladybug.lit ($(⟨stx[2]⟩)))
  | ``listLit => do
    let xs ← stx[1].getSepArgs.mapM expr
    `(Ladybug.Expr.list [$xs,*])
  | ``paren => expr stx[1]
  | ``notE => `(Ladybug.Expr.not $(← expr stx[1]))
  | ``negE => `(Ladybug.Expr.neg $(← expr stx[1]))
  | ``isNullE => `(Ladybug.isNull $(← expr stx[0]))
  | ``isNotNullE => `(Ladybug.isNotNull $(← expr stx[0]))
  | ``startsE => `(Ladybug.Expr.startsWith $(← expr stx[0]) $(← expr stx[3]))
  | ``endsE => `(Ladybug.Expr.endsWith $(← expr stx[0]) $(← expr stx[3]))
  | ``callStar =>
    unless isKeyword stx[0] "count" do throwErrorAt stx[0] "only count(*) takes *"
    `(Ladybug.countStar)
  | ``call => do
    let fnName := identStr stx[0]
    let fn := fnName.toLower
    let distinct := !stx[2].isNone
    let args := stx[3].getSepArgs
    match fn, args with
    | "count", #[a] =>
      if distinct then `(Ladybug.Expr.countDistinct $(← expr a)) else `(Ladybug.Expr.count $(← expr a))
    | "coalesce", #[a, b] => `(Ladybug.coalesce $(← expr a) $(← expr b))
    | _, #[a] =>
      if distinct then unsupported stx[2] "DISTINCT here"
      match unaryFns.lookup fn with
      | some f => `($(mkIdent f) $(← expr a))
      | none => unsupported stx[0] s!"function {fnName}"
    | _, _ => unsupported stx[0] s!"function {fnName} with {args.size} arguments"
  | _ => unsupported stx "this expression"

/-- `EXISTS { MATCH … WHERE … }` / `COUNT { … }`: the body is translated in a
nested scope (its variables stay local) and run through `exists_`/`countSub`. -/
partial def subquery (stx : Syntax) : M Term := withRef stx do
  let saved ← get
  modify fun s => { s with elems := #[] }
  for p in stx[3].getSepArgs do matchPattern false p
  if stx[4].getNumArgs == 2 then emit (← `(doElem| Ladybug.where_ $(← expr stx[4][1])))
  let inner := (← get).elems.push (← `(doElem| pure ()))
  modify fun s => { saved with next := s.next }
  let items ← inner.mapM fun e => `(Lean.Parser.Term.doSeqItem| $e:doElem)
  let fn := mkIdent (if stx.getKind == ``existsE then ``Ladybug.exists_ else ``Ladybug.countSub)
  let id ← fresh "sub"
  let rhs ← `($fn (do $items*))
  emit (← `(doElem| let $id ← $rhs:term))
  return id

end

/-! ## Values for CREATE and MERGE -/

/-- A Lean term for a literal property value. -/
private partial def litValue (stx : Syntax) : M Term := withRef stx do
  if let some t := antiquotParam? stx then return t
  match stx.getKind with
  | ``numLit | ``sciLit | ``strLit => return ⟨stx[0]⟩
  | ``nullLit => `(none)
  | ``paramLocal => return ⟨stx[1]⟩
  | ``paramTerm => return ⟨stx[2]⟩
  | ``identExpr =>
    let w := identStr stx[0]
    if w.toLower == "true" then `(true)
    else if w.toLower == "false" then `(false)
    else throwErrorAt stx "CREATE and MERGE take literal values or $parameters"
  | ``negE => do `(- $(← litValue stx[1]))
  | _ => throwErrorAt stx "CREATE and MERGE take literal values or $parameters"

/-- `T.mk v₁ … vₙ` from `{k: v, …}`; missing nullable properties are `none`. -/
private def structValue (t : Registry.TableEntry) (props : Syntax) (ref : Syntax) : M Term := withRef ref do
  let given : Array (String × Syntax) :=
    if props.isNone then #[] else props[0][1].getSepArgs.map fun p => (identStr p[0], p[2])
  for (k, v) in given do
    unless t.columns.any (·.name == k) do
      throwErrorAt v "unknown property '{k}' of table {t.label}{suggestion k (t.columns.map (·.name))}"
  let args ← t.columns.mapM fun c => do
    match given.find? (·.1 == c.name) with
    | some (_, v) =>
      let val ← litValue v
      if c.nullable && v.getKind != ``nullLit then `(some $val) else pure val
    | none =>
      if c.nullable then `(none) else throwErrorAt ref "missing property '{c.name}' of table {t.label}"
  `($(mkIdent (t.declName ++ `mk)) $args*)

private def createPattern (merge : Bool) (pat : Syntax) : M Unit := withRef pat do
  unless pat[0].isNone do throwErrorAt pat[0] "a path variable is only allowed in MATCH"
  let start := nodeParts pat[1]
  let steps := pat[2].getArgs
  if steps.isEmpty then
    let some lbl := start.label | throwErrorAt start.ref "CREATE needs a label, e.g. (p:Person \{…})"
    let t ← table lbl false
    let value ← structValue t start.props start.ref
    let id ← fresh (start.var.getD "n")
    let fn := mkIdent (if merge then ``Ladybug.merge else ``Ladybug.create)
    let rhs ← `($fn $value)
    emit (← `(doElem| let $id ← $rhs:term))
    if let some v := start.var then bind v { lean := id, kind := .node t }
  else
    if merge then throwErrorAt pat "MERGE of a relationship pattern is not supported"
    unless steps.size == 1 do throwErrorAt pat "CREATE takes one relationship at a time"
    let (dir, relStx, endStx) := stepParts steps[0]!
    let some a ← boundNode? start | throwErrorAt start.ref "CREATE of a relationship needs bound end nodes"
    let some b ← boundNode? (nodeParts endStx) | throwErrorAt endStx "CREATE of a relationship needs bound end nodes"
    let r ← table relStx[3] true
    unless relStx[4].isNone do throwErrorAt relStx[4] "CREATE takes a single relationship, not a range"
    let value ← structValue r relStx[5] relStx
    let id ← fresh ((relStx[1].getOptional?.map identStr).getD "r")
    let (x, y) ← match dir with
      | .out => pure (a, b)
      | .inc => pure (b, a)
      | .both => throwErrorAt steps[0]! "CREATE needs a direction"
    emit (← `(doElem| let $id ← Ladybug.createRel $(x.lean) $value $(y.lean)))
    if let some v := relStx[1].getOptional?.map identStr then bind v { lean := id, kind := .rel r }

/-! ## Projections -/

private def tuple (ts : Array Term) : M Term := do
  let some last := ts.back? | `(())
  ts.pop.foldrM (fun t acc => `(($t, $acc))) last

/-- A RETURN/WITH item: the term, and the variable it re-binds under WITH. -/
private def item (it : Syntax) : M (Term × Option (String × VarInfo)) := do
  let e := it[0]
  let alias := if it[1].getNumArgs == 2 then some (identStr it[1][1]) else none
  if e.getKind == ``identExpr && !(identStr e[0]).contains '.' then
    if let some v ← lookup? (identStr e[0]) then
      return (v.lean, some (alias.getD (identStr e[0]), v))
  return (← expr e, alias.map (·, { lean := default, kind := .expr }))

private def modifiers (mods : Syntax) : M Unit := do
  unless mods[0].isNone do
    for key in mods[0][2].getSepArgs do
      let e ← expr key[0]
      let desc := !key[1].isNone && key[1][0].getKind == ``kwDesc
      emit (← withRef key (if desc then `(doElem| Ladybug.orderByDesc $e) else `(doElem| Ladybug.orderBy $e)))
  let count (stx : Syntax) : M Term :=
    if let some t := antiquotParam? stx then pure t else match stx.getKind with
    | ``numLit => return ⟨stx[0]⟩
    | ``paramLocal => return ⟨stx[1]⟩
    | ``paramTerm => return ⟨stx[2]⟩
    | _ => throwErrorAt stx "SKIP and LIMIT take a number or a $parameter"
  unless mods[1].isNone do emit (← `(doElem| Ladybug.skip $(← count mods[1][1])))
  unless mods[2].isNone do emit (← `(doElem| Ladybug.limit $(← count mods[2][1])))

/-! ## Clauses -/

private def clause (c : Syntax) (isLast : Bool) : M Unit := withRef c do
  match c.getKind with
  | ``matchC => for p in c[1].getSepArgs do matchPattern false p
  | ``optMatchC => for p in c[2].getSepArgs do matchPattern true p
  | ``whereC => emit (← `(doElem| Ladybug.where_ $(← expr c[1])))
  | ``unwindC =>
    let e ← expr c[1]
    let id ← fresh (identStr c[3])
    emit (← `(doElem| let $id ← Ladybug.unwind $e))
    bind (identStr c[3]) { lean := id, kind := .expr }
  | ``createC => createPattern false c[1]
  | ``mergeC => createPattern true c[1]
  | ``setC =>
    for it in c[1].getSepArgs do
      emit (← withRef it `(doElem| Ladybug.set $(← identTerm it[0]) $(← expr it[2])))
  | ``deleteC | ``detachDeleteC =>
    let detach := c.getKind == ``detachDeleteC
    let ids := if detach then c[2] else c[1]
    for id in ids.getSepArgs do
      let some v ← lookup? (identStr id) | throwErrorAt id "unknown variable '{identStr id}'"
      emit (← withRef id (if detach then `(doElem| Ladybug.detachDelete $(v.lean))
                          else `(doElem| Ladybug.delete $(v.lean))))
  | ``withC =>
    if isLast then throwErrorAt c "a query cannot end with WITH"
    let items ← c[2].getSepArgs.mapM item
    modifiers c[3]
    let mut binds := #[]
    let mut newScope : Std.HashMap String VarInfo := {}
    for ((_, b), it) in items.zip c[2].getSepArgs do
      let some (name, info) := b | throwErrorAt it "a WITH expression needs an alias: WITH e AS x"
      let id ← fresh name
      binds := binds.push id
      newScope := newScope.insert name { info with lean := id }
    let distinct := !c[1].isNone
    let pat ← tuple (binds.map (⟨·.raw⟩))
    let value ← tuple (items.map (·.1))
    emit (← `(doElem| let $pat:term ← Ladybug.with_ $value (distinct := $(quote distinct))))
    modify fun s => { s with scope := newScope }
  | ``returnC =>
    unless isLast do throwErrorAt c "RETURN must be the last clause"
    let items ← c[2].getSepArgs.mapM item
    modifiers c[3]
    let distinct := !c[1].isNone
    emit (← `(doElem| Ladybug.return_ $(← tuple (items.map (·.1))) (distinct := $(quote distinct))))
  | ``callC =>
    let proc := (identStr c[1]).toLower
    let args := c[3].getSepArgs
    let (fn, outs) ← match proc with
      | "query_vector_index" => pure (``Ladybug.vectorSearch, ("node", "distance"))
      | "query_fts_index" => pure (``Ladybug.ftsSearch, ("node", "score"))
      | _ => unsupported c[1] s!"procedure {identStr c[1]}"
    let expected := if proc == "query_vector_index" then 4 else 3
    unless args.size == expected do throwErrorAt c "{identStr c[1]} takes {expected} arguments"
    let tableName ← match args[0]!.getKind with
      | ``strLit => pure (args[0]![0].isStrLit?.getD "")
      | _ => throwErrorAt args[0]! "the table must be a string literal naming a node table"
    let t ← match Registry.find? (← getEnv) tableName with
      | some t => if t.isRel then throwErrorAt args[0]! "'{tableName}' is not a node table" else pure t
      | none => throwErrorAt args[0]! "unknown node label '{tableName}'"
    let rest ← (args.extract 1 args.size).mapM litValue
    let rhs ← `($(mkIdent fn) $(tableIdent t) $rest*)
    let names := if c[5].getNumArgs == 2 then c[5][1].getSepArgs.map fun y =>
        (identStr y[0], if y[1].getNumArgs == 2 then identStr y[1][1] else identStr y[0]) else
      #[(outs.1, outs.1), (outs.2, outs.2)]
    let nodeName := (names.find? (·.1.toLower == outs.1)).map (·.2)
    let valName := (names.find? (·.1.toLower == outs.2)).map (·.2)
    let nodeId ← fresh (nodeName.getD "node")
    let valId ← fresh (valName.getD outs.2)
    emit (← `(doElem| let ($nodeId, $valId) ← $rhs:term))
    if let some n := nodeName then bind n { lean := nodeId, kind := .node t }
    if let some n := valName then bind n { lean := valId, kind := .expr }
  | _ => unsupported c "this clause"

-- @tg: implements:: [[openspec:cypher-syntax#Same AST as the builder]]
-- @tg: implements:: [[openspec:cypher-syntax#Schema-checked elaboration]]
-- @tg: implements:: [[openspec:cypher-syntax#Located errors]]
-- @tg: implements:: [[openspec:cypher-syntax#Lean values as parameters]]
/-- One query part (no UNION inside) as a `query`/`stmt` term. -/
private def part (clauses : Array Syntax) : TermElabM Term := do
  let returns := clauses.back?.any (·.getKind == ``returnC)
  let (_, st) ← (clauses.size.fold (init := pure ()) fun i _ acc => do
      acc
      clause clauses[i]! (i + 1 == clauses.size)).run {}
  let elems := st.elems
  let unit ← `(doElem| pure ())
  let elems := if returns then elems else elems.push unit
  let items ← elems.mapM fun e => `(Lean.Parser.Term.doSeqItem| $e:doElem)
  if returns then `(Ladybug.query (do $items*)) else `(Ladybug.stmt (do $items*))

@[term_elab Ladybug.Cypher.Syntax.cypherTerm] def elabCypher : TermElab := fun stx expectedType? => do
  let clauses := #[stx[1]] ++ stx[2].getArgs
  -- Split at UNION markers; every part is its own scope.
  let mut parts : Array (Array Syntax) := #[#[]]
  let mut unions : Array (Syntax × Bool) := #[]
  for c in clauses do
    if c.getKind == ``unionC then
      unions := unions.push (c, !c[1].isNone)
      parts := parts.push #[]
    else
      parts := parts.modify (parts.size - 1) (·.push c)
  for (c, _) in unions do
    if parts.any (·.isEmpty) then throwErrorAt c "UNION needs a query on both sides"
  let mut body ← part parts[0]!
  for h : i in [0:unions.size] do
    let (c, all) := unions[i]
    let rhs ← part parts[i + 1]!
    let fn := mkIdent (if all then ``Ladybug.Query.unionAll else ``Ladybug.Query.union)
    body ← withRef c `($fn $body $rhs)
  withMacroExpansion stx body <| elabTerm body expectedType?

end Ladybug.Cypher.Elab
