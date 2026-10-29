import Ladybug.Mem.Graph
import Ladybug.Cypher.Core

/-!
# Evaluator

Evaluates the core Cypher AST over an in-memory `Graph`, following Ladybug's
behaviour where openCypher leaves a choice: NULLs sort as the largest value,
`x IN list` ignores NULL elements, integer `/` and `%` truncate toward zero,
division by zero and INT64 overflow are errors, `sum` of integers is an INT128,
and variable-length patterns use walk semantics (relationships may repeat).

A query is a fold over its clauses on an array of rows, each row an
environment from variable names to values. Node and relationship values in a
row are references: their properties are read from the graph when used, so a
later SET is visible.
-/

namespace Ladybug.Mem

open Cypher.Core

abbrev Env := List (String × Value)

/-- Fault injection for the differential suite's self-test. -/
structure Faults where
  /-- Comparisons with NULL return true instead of unknown. -/
  nullCompareTrue : Bool := false
  deriving Inhabited

structure EvalState where
  graph : Graph
  faults : Faults := {}
  /-- Writes are rejected inside a read-only transaction. -/
  readOnly : Bool := false

abbrev EvalM := StateT EvalState (Except Error)

private def fail {α : Type} (msg : String) : EvalM α := throw (.query msg)

private def graph : EvalM Graph := return (← get).graph
private def setGraph (g : Graph) : EvalM Unit := modify fun s => { s with graph := g }

private def checkWritable : EvalM Unit := do
  if (← get).readOnly then throw (.query "cannot write in a read-only transaction")

/-! ## Values -/

private def asInt? (v : Value) : Option Int := v.toInt?

private def asFloat? : Value → Option Float
  | .double d => some d
  | .float f => some f.toFloat
  | v => v.toInt?.map Float.ofInt

private def isFloat : Value → Bool
  | .double _ | .float _ => true
  | _ => false

private def isInt128 : Value → Bool
  | .int128 _ => true
  | _ => false

/-- Values for comparison: nodes and relationships by ID, numbers across kinds. -/
partial def cmp? (a b : Value) : Option Ordering :=
  match a, b with
  | .string x, .string y => some (compare x y)
  | .bool x, .bool y => some (compare x y)
  | .date x, .date y => some (compare x y)
  | .timestamp x, .timestamp y | .timestampTz x, .timestampTz y => some (compare x y)
  | .uuid x, .uuid y => some (compare x y)
  | .node i .., .node j .. | .rel i .., .rel j .. => some (compare i j)
  | .internalId i, .internalId j => some (compare i j)
  | .list xs, .list ys | .array xs, .array ys => listCmp xs.toList ys.toList
  | a, b =>
    if isFloat a || isFloat b then
      match asFloat? a, asFloat? b with
      | some x, some y => some (if x < y then .lt else if x > y then .gt else .eq)
      | _, _ => none
    else match asInt? a, asInt? b with
      | some x, some y => some (compare x y)
      | _, _ => none
where
  listCmp : List Value → List Value → Option Ordering
    | [], [] => some .eq
    | [], _ => some .lt
    | _, [] => some .gt
    | x :: xs, y :: ys => match cmp? x y with
      | some .eq => listCmp xs ys
      | o => o

/-- Equality used by `=`, grouping and DISTINCT (NULL handled by callers). -/
partial def valueEq (a b : Value) : Bool :=
  match a, b with
  | .struct xs, .struct ys => xs.size == ys.size && (xs.zip ys).all fun ((k, x), (k', y)) => k == k' && valueEq x y
  | .map xs, .map ys => xs.size == ys.size && (xs.zip ys).all fun ((k, x), (k', y)) => valueEq k k' && valueEq x y
  | .null, .null => true
  | .list xs, .list ys | .array xs, .array ys => xs.size == ys.size && (xs.zip ys).all fun (x, y) => valueEq x y
  | a, b => match cmp? a b with
    | some o => o == .eq
    | none => a == b

/-- Total order for ORDER BY: NULL is the largest value. -/
def sortCmp (a b : Value) : Ordering :=
  match a, b with
  | .null, .null => .eq
  | .null, _ => .gt
  | _, .null => .lt
  | a, b => (cmp? a b).getD (compare a.kind b.kind)

private def int64Min : Int := -9223372036854775808
private def int64Max : Int := 9223372036854775807

private def intResult (a b : Value) (r : Int) (op : String) : EvalM Value := do
  if isInt128 a || isInt128 b then return .int128 r
  unless int64Min ≤ r ∧ r ≤ int64Max do
    throw (.query s!"Overflow exception: Value {a} {op} {b} is not within INT64 range.")
  return .int64 (Int64.ofInt r)

private def arith (op : BinOp) (a b : Value) : EvalM Value := do
  match a, b with
  | .null, _ | _, .null => return .null
  | .string x, .string y => if op == .add then return .string (x ++ y) else fail "invalid string arithmetic"
  | .list x, .list y => if op == .add then return .list (x ++ y) else fail "invalid list arithmetic"
  | _, _ =>
    if isFloat a || isFloat b then
      let some x := asFloat? a | fail s!"cannot apply arithmetic to {a.kind}"
      let some y := asFloat? b | fail s!"cannot apply arithmetic to {b.kind}"
      return .double <| match op with
        | .add => x + y | .sub => x - y | .mul => x * y | .div => x / y
        | _ => x - y * (x / y).floor
    let some x := asInt? a | fail s!"cannot apply arithmetic to {a.kind}"
    let some y := asInt? b | fail s!"cannot apply arithmetic to {b.kind}"
    match op with
    | .add => intResult a b (x + y) "+"
    | .sub => intResult a b (x - y) "-"
    | .mul => intResult a b (x * y) "*"
    | .div => if y == 0 then throw (.query "Runtime exception: Divide by zero.") else intResult a b (x.tdiv y) "/"
    | _ => if y == 0 then throw (.query "Runtime exception: Modulo by zero.") else intResult a b (x.tmod y) "%"

private def truth : Option Bool → Value
  | some b => .bool b
  | none => .null

private def asBool? : Value → Option (Option Bool)
  | .bool b => some (some b)
  | .null => some none
  | _ => none

/-- A binary operator applied to evaluated operands. -/
def applyBin (faults : Faults) (op : BinOp) (a b : Value) : EvalM Value := do
  let nullCmp : Value := if faults.nullCompareTrue then .bool true else .null
  match op with
  | .and | .or | .xor =>
    let some x := asBool? a | fail "boolean operator needs booleans"
    let some y := asBool? b | fail "boolean operator needs booleans"
    return truth <| match op, x, y with
      | .and, some false, _ | .and, _, some false => some false
      | .and, some true, some true => some true
      | .or, some true, _ | .or, _, some true => some true
      | .or, some false, some false => some false
      | .xor, some p, some q => some (p != q)
      | _, _, _ => none
  | .eq | .neq | .lt | .le | .gt | .ge =>
    if a matches .null || b matches .null then return nullCmp
    match op with
    | .eq => return .bool (valueEq a b)
    | .neq => return .bool (!valueEq a b)
    | _ =>
      let some o := cmp? a b | return .null
      return .bool <| match op with
        | .lt => o == .lt | .le => o != .gt | .gt => o == .gt | _ => o != .lt
  | .startsWith | .endsWith | .contains =>
    match a, b with
    | .string x, .string y => return .bool <| match op with
      | .startsWith => x.startsWith y | .endsWith => x.endsWith y | _ => (x.splitOn y).length > 1
    | .null, _ | _, .null => return .null
    | _, _ => fail "string predicate needs strings"
  | .in_ =>
    match a, b with
    | .null, _ | _, .null => return .null
    | x, .list ys | x, .array ys => return .bool (ys.any fun y => !(y matches .null) && valueEq x y)
    | _, _ => fail "IN needs a list"
  | _ => arith op a b

def isTrueV : Value → Bool
  | .bool true => true
  | _ => false

/-! ## Graph access -/

/-- The current value of a node or relationship reference; other values unchanged. -/
partial def current (g : Graph) : Value → Value
  | .node id l p => (g.node? id).map Node.value |>.getD (.node id l p)
  | .rel id s d l p => (g.rel? id).map Rel.value |>.getD (.rel id s d l p)
  | .list xs => .list (xs.map (current g))
  | .path ns rs => .path (ns.map (current g)) (rs.map (current g))
  | v => v

private def lookupVar (env : Env) (n : String) : EvalM Value := do
  match env.lookup n with
  | some v => return v
  | none => fail s!"Binder exception: Variable {n} is not in scope."

/-! ## Expressions and patterns -/

private def aggNames : List String := ["count", "sum", "avg", "min", "max", "collect"]

/-- Whether an expression contains an aggregate call. -/
partial def hasAgg : Expr → Bool
  | .countStar => true
  | .call fn args _ => aggNames.contains fn.toLower || args.any hasAgg
  | .binop _ a b => hasAgg a || hasAgg b
  | .unop _ a | .prop a _ => hasAgg a
  | .list xs => xs.any hasAgg
  | _ => false

private def nodeMatches (env : Env) (np : NodePat) (n : Node) (evalE : Env → Expr → EvalM Value) :
    EvalM Bool := do
  if let some l := np.label then
    if n.label != l then return false
  for (k, e) in np.props do
    let v ← evalE env e
    let actual := (n.props.find? (·.1 == k)).map (·.2) |>.getD .null
    if v matches .null || !valueEq actual v then return false
  return true

mutual

partial def evalExpr (env : Env) : Expr → EvalM Value
  | .var n => do return current (← graph) (← lookupVar env n)
  | .prop e k => do
    match current (← graph) (← evalExpr env e) with
    | .null => return .null
    | v@(.node ..) | v@(.rel ..) | v@(.struct ..) => return (v.field? k).getD .null
    | v => fail s!"cannot read property {k} of a {v.kind}"
  | .value v => return v
  | .null => return .null
  | .name s => return .string s
  | .list xs => return .list (← xs.toArray.mapM (evalExpr env))
  | .binop op a b => do
    -- AND/OR short-circuit only for definite results, as 3VL requires both sides otherwise.
    let x ← evalExpr env a
    let y ← evalExpr env b
    applyBin (← get).faults op x y
  | .unop .not a => do
    match ← evalExpr env a with
    | .bool b => return .bool !b
    | .null => return .null
    | v => fail s!"NOT needs a boolean, got {v.kind}"
  | .unop .neg a => do
    match ← evalExpr env a with
    | .null => return .null
    | v => arith .sub (.int64 0) v
  | .unop .isNull a => do return .bool ((← evalExpr env a) matches .null)
  | .unop .isNotNull a => do return .bool !((← evalExpr env a) matches .null)
  | .call fn args _ => do
    let vs ← args.toArray.mapM (evalExpr env)
    scalarFn fn.toLower vs
  | .countStar => fail "count(*) outside a projection"
  | .exists pats cond => do return .bool ((← subRows env pats cond).size > 0)
  | .countSub pats cond => do return .int64 (Int64.ofNat (← subRows env pats cond).size)

partial def scalarFn (fn : String) (vs : Array Value) : EvalM Value := do
  match fn, vs.toList with
  | "coalesce", xs => return (xs.find? (!· matches .null)).getD .null
  | _, [.null] => return .null
  | "lower", [.string s] => return .string s.toLower
  | "upper", [.string s] => return .string s.toUpper
  | "trim", [.string s] => return .string s.trimAscii.toString
  | "size", [.string s] => return .int64 (Int64.ofNat s.length)
  | "size", [.list xs] => return .int64 (Int64.ofNat xs.size)
  | "abs", [v] =>
    match v with
    | .double d => return .double d.abs
    | v => match v.toInt? with
      | some i => intResult v v i.natAbs "abs"
      | none => fail "abs needs a number"
  | "length", [.path _ rs] => return .int64 (Int64.ofNat rs.size)
  | "nodes", [.path ns _] => return .list ns
  | "rels", [.path _ rs] => return .list rs
  | f, _ => fail s!"Catalog exception: function {f} is not supported by the in-memory backend"

/-- Rows of a subquery's patterns, filtered by its condition. -/
partial def subRows (env : Env) (pats : List Pattern) (cond : Option Expr) : EvalM (Array Env) := do
  let mut rows := #[env]
  for p in pats do
    rows ← rows.flatMapM (matchPattern · p)
  match cond with
  | none => return rows
  | some c => rows.filterM fun r => do return isTrueV (← evalExpr r c)

/-- Every extension of `env` that binds the pattern; relationships are distinct within it. -/
partial def matchPattern (env : Env) (p : Pattern) : EvalM (Array Env) := do
  let g ← graph
  let starts ← matchNode env p.start
  starts.flatMapM fun (env', id) => steps env' id p.steps []
where
  steps (env : Env) (cur : InternalId) : List (RelPat × NodePat) → List InternalId → EvalM (Array Env)
    | [], _ => return #[env]
    | (rp, np) :: rest, used => do
      let g ← graph
      let mut out := #[]
      for r in g.rels do
        if r.label != rp.label || used.contains r.id then continue
        let nexts : List InternalId := match rp.dir with
          | .out => if r.src == cur then [r.dst] else []
          | .inc => if r.dst == cur then [r.src] else []
          -- An undirected self-loop matches once in each direction, as in Ladybug.
          | .both => (if r.src == cur then [r.dst] else []) ++ (if r.dst == cur then [r.src] else [])
        for next in nexts do
          let env1 ← match rp.var with
            | some v => match env.lookup v with
              | some (.rel id ..) => if id == r.id then pure (some env) else pure none
              | some _ => pure none
              | none => pure (some ((v, r.value) :: env))
            | none => pure (some env)
          let some env1 := env1 | continue
          let some n := g.node? next | continue
          let env2 ← bindNode env1 np n
          let some env2 := env2 | continue
          out := out ++ (← steps env2 next rest (r.id :: used))
      return out

/-- The nodes a node pattern can bind in `env`, with the extended environment. -/
partial def matchNode (env : Env) (np : NodePat) : EvalM (Array (Env × InternalId)) := do
  let g ← graph
  match env.lookup np.var with
  | some (.node id ..) =>
    let some n := g.node? id | return #[]
    if ← nodeMatches env np n evalExpr then return #[(env, id)] else return #[]
  | some .null => return #[]
  | some v => fail s!"variable {np.var} is a {v.kind}, not a node"
  | none =>
    if let some l := np.label then
      unless (g.table? l).isSome do fail s!"Binder exception: Table {l} does not exist."
    g.nodes.filterMapM fun n => do
      if ← nodeMatches env np n evalExpr then return some ((np.var, n.value) :: env, n.id) else return none

partial def bindNode (env : Env) (np : NodePat) (n : Node) : EvalM (Option Env) := do
  let g ← graph
  match env.lookup np.var with
  | some (.node id ..) => return if id == n.id then some env else none
  | some _ => return none
  | none => if ← nodeMatches env np n evalExpr then return some ((np.var, n.value) :: env) else return none

end

/-! ## Variable-length paths -/

/-- Walks of `lo` to `hi` relationships from `src` (relationships may repeat). -/
private partial def walks (g : Graph) (rp : RelPat) (src : InternalId) (lo hi : Nat) :
    Array (Array InternalId × Array Rel) :=
  let rec go (cur : InternalId) (nodes : Array InternalId) (rels : Array Rel) (depth : Nat) :
      Array (Array InternalId × Array Rel) :=
    let here := if depth ≥ lo then #[(nodes, rels)] else #[]
    if depth == hi then here
    else
      let nexts := g.rels.flatMap fun r =>
        if r.label != rp.label then #[]
        else match rp.dir with
          | .out => if r.src == cur then #[(r, r.dst)] else #[]
          | .inc => if r.dst == cur then #[(r, r.src)] else #[]
          | .both => (if r.src == cur then #[(r, r.dst)] else #[]) ++ (if r.dst == cur then #[(r, r.src)] else #[])
      here ++ nexts.flatMap fun (r, n) => go n (nodes.push n) (rels.push r) (depth + 1)
  go src #[src] #[] 0

private def pathValue (g : Graph) (nodes : Array InternalId) (rels : Array Rel) : Value :=
  .path (nodes.filterMap fun id => (g.node? id).map Node.value) (rels.map Rel.value)

private def matchPathClause (env : Env) (pv : String) (src : NodePat) (rp : RelPat) (lo hi : Nat)
    (mode : PathMode) (dst : NodePat) : EvalM (Array Env) := do
  let starts ← matchNode env src
  let g ← graph
  let mut out := #[]
  for (env1, sid) in starts do
    let all := walks g rp sid (max lo 1) hi
    -- Keep walks whose end binds `dst`.
    let mut ends : Array (Env × Array InternalId × Array Rel) := #[]
    for (ns, rs) in all do
      let some n := g.node? ns.back! | continue
      if let some env2 ← bindNode env1 dst n then ends := ends.push (env2, ns, rs)
    let chosen : Array (Env × Array InternalId × Array Rel) := match mode with
      | .all => ends
      | .shortest | .allShortest => Id.run do
        -- Per end node, the walks of minimal length (one of them for SHORTEST).
        let mut byEnd : Array (InternalId × Array (Env × Array InternalId × Array Rel)) := #[]
        -- Ladybug's shortest paths never lead back to their start node.
        for e in ends.filter (·.2.1.back! != sid) do
          let k := e.2.1.back!
          match byEnd.findIdx? (·.1 == k) with
          | some i => byEnd := byEnd.modify i fun (k, es) => (k, es.push e)
          | none => byEnd := byEnd.push (k, #[e])
        let mut out := #[]
        for (_, es) in byEnd do
          let best := es.foldl (fun m (e : Env × Array InternalId × Array Rel) => min m e.2.2.size) 1000000
          let shortest := es.filter (·.2.2.size == best)
          out := out ++ (if mode == .shortest then shortest.extract 0 1 else shortest)
        return out
    for (env2, ns, rs) in chosen do
      out := out.push ((pv, pathValue g ns rs) :: env2)
  return out

/-! ## Projection -/

/-- Evaluate an expression over a group of rows: aggregates over the group,
anything else on its first row. -/
private partial def evalAgg (group : Array Env) (e : Expr) : EvalM Value := do
  if !hasAgg e then
    return ← evalExpr (group[0]?.getD []) e
  match e with
  | .countStar => return .int64 (Int64.ofNat group.size)
  | .call fn [arg] distinct =>
    if aggNames.contains fn.toLower then
      let vs ← group.mapM (evalExpr · arg)
      let vs := vs.filter (!· matches .null)
      let vs := if distinct then vs.foldl (fun acc v => if acc.any (valueEq v) then acc else acc.push v) #[] else vs
      match fn.toLower with
      | "count" => return .int64 (Int64.ofNat vs.size)
      | "collect" => return .list vs
      | "sum" =>
        if vs.isEmpty then return .null
        if vs.any isFloat then return .double (vs.foldl (fun s v => s + (asFloat? v).getD 0) 0)
        return .int128 (vs.foldl (fun s v => s + (asInt? v).getD 0) 0)
      | "avg" =>
        if vs.isEmpty then return .null
        return .double ((vs.foldl (fun s v => s + (asFloat? v).getD 0) 0) / vs.size.toFloat)
      | "min" => return (vs.foldl (fun m v => if m matches .null || sortCmp v m == .lt then v else m) .null)
      | _ => return (vs.foldl (fun m v => if m matches .null || sortCmp v m == .gt then v else m) .null)
    else scalarFn fn.toLower #[← evalAgg group arg]
  | .call fn args _ => scalarFn fn.toLower (← args.toArray.mapM (evalAgg group))
  | .binop op a b => applyBin (← get).faults op (← evalAgg group a) (← evalAgg group b)
  | .unop op a => evalExpr [("__x", ← evalAgg group a)] (.unop op (.var "__x"))
  | .prop a k => evalExpr [("__x", ← evalAgg group a)] (.prop (.var "__x") k)
  | .list xs => return .list (← xs.toArray.mapM (evalAgg group))
  | e => evalExpr (group[0]?.getD []) e

private def itemName (it : Item) (i : Nat) : String :=
  match it.alias, it.expr with
  | some a, _ => a
  | none, .var n => n
  | none, _ => s!"_{i}"

/-- Project rows to items: one output row per input row, or per group when an
item aggregates. Each output row keeps its group for ORDER BY. -/
private def project (rows : Array Env) (items : List Item) (distinct : Bool) :
    EvalM (Array (Array Value × Array Env)) := do
  let its := items.toArray
  let out ← if its.any (hasAgg ·.expr) then do
      let keys := its.filter (!hasAgg ·.expr)
      let mut groups : Array (Array Value × Array Env) := #[]
      for r in rows do
        let k ← keys.mapM (evalExpr r ·.expr)
        match groups.findIdx? fun (k', _) => k'.size == k.size && (k'.zip k).all fun (a, b) => valueEq a b with
        | some i => groups := groups.modify i fun (k', rs) => (k', rs.push r)
        | none => groups := groups.push (k, #[r])
      if groups.isEmpty && keys.isEmpty then groups := #[(#[], #[])]
      groups.mapM fun (_, rs) => do return (← its.mapM (evalAgg rs ·.expr), rs)
    else rows.mapM fun r => do return (← its.mapM (evalExpr r ·.expr), #[r])
  if !distinct then return out
  return out.foldl (init := #[]) fun acc (vs, g) =>
    if acc.any fun (vs', _) => vs'.size == vs.size && (vs'.zip vs).all fun (a, b) => valueEq a b then acc
    else acc.push (vs, g)

private def asCount (v : Value) : EvalM Nat := do
  match v.toInt? with
  | some i => if i ≥ 0 then return i.toNat else fail "SKIP and LIMIT must not be negative"
  | none => fail "SKIP and LIMIT take integers"

/-- ORDER BY, SKIP and LIMIT; sort keys see the projected names and the group's rows. -/
private def applyMods (rows : Array (Array Value × Array Env)) (names : Array String) (m : Modifiers) :
    EvalM (Array (Array Value × Array Env)) := do
  let mut rows := rows
  unless m.orderBy.isEmpty do
    let keyed ← rows.mapM fun (vs, g) => do
      let withNames := g.map fun r => (names.toList.zip vs.toList) ++ r
      let ks ← m.orderBy.toArray.mapM fun k => evalAgg (if withNames.isEmpty then #[names.toList.zip vs.toList] else withNames) k.expr
      return (ks, (vs, g))
    let descs := m.orderBy.toArray.map (·.desc)
    let lt (a b : Array Value × (Array Value × Array Env)) : Bool := Id.run do
      for h : i in [0:a.1.size] do
        let o := sortCmp a.1[i] (b.1[i]?.getD .null)
        let o := if descs[i]?.getD false then o.swap else o
        if o != .eq then return o == .lt
      return false
    rows := (keyed.toList.mergeSort lt).toArray.map (·.2)
  if let some s := m.skip then rows := rows.extract (← asCount (← evalExpr [] s)) rows.size
  if let some l := m.limit then rows := rows.extract 0 (← asCount (← evalExpr [] l))
  return rows

/-! ## Writes -/

private def tableOf (g : Graph) (label : String) : EvalM (Nat × TableDecl) := do
  match g.tableIndex? label, g.table? label with
  | some i, some d => return (i, d)
  | _, _ => fail s!"Binder exception: Table {label} does not exist."

private def createNode (env : Env) (np : NodePat) : EvalM (Env × InternalId) := do
  checkWritable
  let g ← graph
  let some l := np.label | fail "CREATE needs a label"
  let (ti, d) ← tableOf g l
  let .node _ key cols := d | fail s!"{l} is not a node table"
  let given ← np.props.mapM fun (k, e) => do return (k, ← evalExpr env e)
  let props := cols.map fun c => (c.name, (given.lookup c.name).getD .null)
  let keyVal := (props.find? (·.1 == key)).map (·.2) |>.getD .null
  if keyVal matches .null then throw (.query s!"Runtime exception: Found NULL, which violates the non-null constraint of the primary key column.")
  if g.nodes.any fun n => n.label == l && ((n.props.find? (·.1 == key)).map (·.2)).any (valueEq keyVal) then
    throw (.constraint s!"Runtime exception: Found duplicated primary key value {keyVal}, which violates the uniqueness constraint of the primary key column.")
  let (id, g) := g.freshId ti
  setGraph { g with nodes := g.nodes.push ⟨id, l, props⟩ }
  return ((np.var, Value.node id l props) :: env, id)

private def nodeRef (env : Env) (np : NodePat) : EvalM (Env × InternalId) := do
  match env.lookup np.var with
  | some (.node id ..) => return (env, id)
  | some _ => fail s!"{np.var} is not a node"
  | none => createNode env np

private def createRel (env : Env) (rp : RelPat) (a b : InternalId) : EvalM Env := do
  checkWritable
  let g ← graph
  let (ti, d) ← tableOf g rp.label
  let .rel _ srcL dstL cols := d | fail s!"{rp.label} is not a relationship table"
  let (s, t) := if rp.dir == .inc then (b, a) else (a, b)
  let some sn := g.node? s | fail "missing source node"
  let some tn := g.node? t | fail "missing destination node"
  unless sn.label == srcL && tn.label == dstL do
    fail s!"Binder exception: {rp.label} connects {srcL} to {dstL}, not {sn.label} to {tn.label}"
  let given ← rp.props.mapM fun (k, e) => do return (k, ← evalExpr env e)
  let props := cols.map fun c => (c.name, (given.lookup c.name).getD .null)
  let (id, g) := g.freshId ti
  let r : Rel := ⟨id, s, t, rp.label, props⟩
  setGraph { g with rels := g.rels.push r }
  return match rp.var with
    | some v => (v, r.value) :: env
    | none => env

private def createPattern (env : Env) (p : Pattern) : EvalM Env := do
  let (env, startId) ← nodeRef env p.start
  let mut env := env
  let mut cur := startId
  for (rp, np) in p.steps do
    let (env', next) ← nodeRef env np
    env ← createRel env' rp cur next
    cur := next
  return env

private def setProp (env : Env) (it : SetItem) : EvalM Unit := do
  checkWritable
  let .prop target k := it.target | fail "SET needs a property"
  let v ← evalExpr env it.value
  match ← evalExpr env target with
  | .node id .. =>
    let g ← graph
    setGraph { g with nodes := g.nodes.map fun n =>
      if n.id == id then { n with props := n.props.map fun (k', x) => if k' == k then (k', v) else (k', x) } else n }
  | .rel id .. =>
    let g ← graph
    setGraph { g with rels := g.rels.map fun r =>
      if r.id == id then { r with props := r.props.map fun (k', x) => if k' == k then (k', v) else (k', x) } else r }
  | .null => pure ()
  | x => fail s!"cannot SET a property of a {x.kind}"

private def deleteValue (detach : Bool) (v : Value) : EvalM Unit := do
  checkWritable
  let g ← graph
  match v with
  | .node id .. =>
    let attached := g.rels.filter fun r => r.src == id || r.dst == id
    if !attached.isEmpty && !detach then
      throw (.constraint "Runtime exception: Node has connected edges, which cannot be deleted. Please delete the edges first or try DETACH DELETE.")
    setGraph { g with nodes := g.nodes.filter (·.id != id), rels := g.rels.filter fun r => r.src != id && r.dst != id }
  | .rel id .. => setGraph { g with rels := g.rels.filter (·.id != id) }
  | .null => pure ()
  | x => fail s!"cannot DELETE a {x.kind}"

/-! ## Procedures -/

private def floatsOf : Value → Option (Array Float)
  | .list xs | .array xs => xs.mapM asFloat?
  | _ => none

private def distance (metric : String) (a b : Array Float) : Float :=
  let pairs := a.zip b
  let dot := pairs.foldl (fun s (p : Float × Float) => s + p.1 * p.2) 0
  let norm (v : Array Float) := (v.foldl (fun s (x : Float) => s + x * x) 0).sqrt
  let sq := pairs.foldl (fun s (p : Float × Float) => s + (p.1 - p.2) * (p.1 - p.2)) 0
  match metric with
  | "l2" => sq.sqrt
  | "l2sq" => sq
  | "dotproduct" => -dot
  | _ => 1 - dot / (norm a * norm b)

private def nameArg : Expr → EvalM String
  | .name s => return s
  | .value (.string s) => return s
  | _ => fail "procedure arguments must be names"

private def callProc (env : Env) (proc : String) (args : List Expr) (named : List (String × Expr))
    (yields : List (String × String)) : EvalM (Array Env) := do
  let g ← graph
  let bindYields (out : List (String × Value)) : Env :=
    yields.foldl (fun e (o, a) => match out.lookup o with | some v => (a, v) :: e | none => e) env
  match proc, args with
  | "CREATE_VECTOR_INDEX", [t, i, c] =>
    checkWritable
    let metric ← match named.lookup "metric" with
      | some e => nameArg e
      | none => pure "cosine"
    setGraph { g with vecIndexes := g.vecIndexes.push ⟨← nameArg t, ← nameArg i, ← nameArg c, metric⟩ }
    return #[env]
  | "DROP_VECTOR_INDEX", [t, i] =>
    let (t, i) := (← nameArg t, ← nameArg i)
    setGraph { g with vecIndexes := g.vecIndexes.filter fun x => !(x.table == t && x.name == i) }
    return #[env]
  | "QUERY_VECTOR_INDEX", [t, i, q, k] =>
    let (t, i) := (← nameArg t, ← nameArg i)
    let some idx := g.vecIndexes.find? fun x => x.table == t && x.name == i
      | fail s!"Binder exception: vector index {i} on {t} does not exist"
    let some qv := floatsOf (← evalExpr env q) | fail "the query vector must be a list of numbers"
    let k ← asCount (← evalExpr env k)
    let scored := g.nodes.filterMap fun n =>
      if n.label != t then none
      else (n.props.find? (·.1 == idx.column)).bind (floatsOf ·.2) |>.map fun v => (n, distance idx.metric qv v)
    let best := (scored.toList.mergeSort fun a b => a.2 ≤ b.2).take k
    return best.toArray.map fun (n, d) => bindYields [("node", n.value), ("distance", .double d)]
  | "CREATE_FTS_INDEX", [t, i, .list cols] =>
    checkWritable
    setGraph { g with ftsIndexes := g.ftsIndexes.push ⟨← nameArg t, ← nameArg i, ← cols.mapM nameArg⟩ }
    return #[env]
  | "DROP_FTS_INDEX", [t, i] =>
    let (t, i) := (← nameArg t, ← nameArg i)
    setGraph { g with ftsIndexes := g.ftsIndexes.filter fun x => !(x.table == t && x.name == i) }
    return #[env]
  | "QUERY_FTS_INDEX", [t, i, q] =>
    let (t, i) := (← nameArg t, ← nameArg i)
    let some idx := g.ftsIndexes.find? fun x => x.table == t && x.name == i
      | fail s!"Binder exception: full-text index {i} on {t} does not exist"
    let .string qs ← evalExpr env q | fail "the text query must be a string"
    let docs := g.nodes.filterMap fun n =>
      if n.label != t then none
      else
        let text := " ".intercalate (idx.columns.filterMap fun c =>
          match (n.props.find? (fun (kv : String × Value) => kv.1 == c)).map (·.2) with
          | some (Value.string s) => some s
          | _ => none)
        some (n.id, tokenize text)
    let scores := bm25 docs (tokenize qs)
    return scores.filterMap fun (id, sc) =>
      (g.node? id).map fun n => bindYields [("node", n.value), ("score", .double sc)]
  | p, _ => fail s!"Catalog exception: procedure {p} is not supported by the in-memory backend"

/-! ## Clauses -/

structure Result where
  columns : Array String
  rows : Array (Array Value)
  deriving Inhabited

private def runPart (clauses : Array Clause) : EvalM Result := do
  let mut rows : Array Env := #[[]]
  let mut result : Option Result := none
  let mut i := 0
  while h : i < clauses.size do
    let c := clauses[i]
    match c with
    | .match false pats =>
      for p in pats do rows ← rows.flatMapM (matchPattern · p)
    | .match true pats =>
      -- A WHERE right after OPTIONAL MATCH filters inside the optional part.
      let cond := match clauses[i + 1]? with
        | some (.where e) => some e
        | _ => none
      if cond.isSome then i := i + 1
      let newVars := pats.flatMap fun p => p.start.var :: p.steps.flatMap fun (r, n) => r.var.toList ++ [n.var]
      rows ← rows.flatMapM fun r => do
        let found ← subRows r pats cond
        if found.isEmpty then
          return #[newVars.foldl (fun e v => if (e.lookup v).isSome then e else (v, .null) :: e) r]
        return found
    | .where e => rows ← rows.filterM fun r => do return isTrueV (← evalExpr r e)
    | .matchPath _ pv src rp lo hi mode dst =>
      rows ← rows.flatMapM fun r => matchPathClause r pv src rp lo hi mode dst
    | .unwind e v =>
      rows ← rows.flatMapM fun r => do
        match ← evalExpr r e with
        | .list xs | .array xs => return xs.map fun x => (v, x) :: r
        | .null => return #[]
        | x => return #[(v, x) :: r]
    | .with items distinct mods =>
      let names := (items.toArray.mapIdx fun i it => itemName it i)
      let projected ← applyMods (← project rows items distinct) names mods
      rows := projected.map fun (vs, _) => names.toList.zip vs.toList
    | .return items distinct mods =>
      let names := (items.toArray.mapIdx fun i it => itemName it i)
      let projected ← applyMods (← project rows items distinct) names mods
      let g ← graph
      result := some ⟨names, projected.map fun (vs, _) => vs.map (current g)⟩
    | .create pats =>
      rows ← rows.mapM fun r => pats.foldlM createPattern r
    | .merge p =>
      rows ← rows.flatMapM fun r => do
        let found ← matchPattern r p
        if found.isEmpty then return #[← createPattern r p] else return found
    | .set its => for r in rows do for it in its do setProp r it
    | .delete detach ts => for r in rows do for t in ts do deleteValue detach (← evalExpr r t)
    | .call proc args named yields => rows ← rows.flatMapM fun r => callProc r proc args named yields
    | .union _ => pure ()
    i := i + 1
  return result.getD ⟨#[], #[]⟩

-- @tg: implements:: [[openspec:memory-backend#Full AST evaluation]]
/-- Evaluate a query: each UNION part separately, then concatenate, removing
duplicate rows unless every union is `UNION ALL`. -/
def evalQuery (q : Query) : EvalM Result := do
  let mut parts : Array (Array Clause) := #[#[]]
  let mut dedupe := false
  for c in q.clauses do
    match c with
    | .union all =>
      parts := parts.push #[]
      if !all then dedupe := true
    | c => parts := parts.modify (parts.size - 1) (·.push c)
  let results ← parts.mapM runPart
  let cols := results[0]?.map (·.columns) |>.getD #[]
  let rows := results.flatMap (·.rows)
  let rows := if !dedupe then rows else rows.foldl (init := #[]) fun acc r =>
    if acc.any fun r' => r'.size == r.size && (r'.zip r).all fun (a, b) => valueEq a b then acc else acc.push r
  return ⟨cols, rows⟩

end Ladybug.Mem
