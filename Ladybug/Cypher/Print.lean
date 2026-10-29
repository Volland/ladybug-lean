import Ladybug.Cypher.Core

/-!
# Printer

Renders the core AST as Cypher text plus a parameter map. Literal values become
parameters `p0, p1, …` in first-use order, identifiers that are not plain names
are backquoted, and the output is a pure function of the query value.
-/

namespace Ladybug.Cypher

open Core

/-- Quote an identifier with backticks unless it is `[A-Za-z_][A-Za-z0-9_]*`. -/
def quoteIdent (s : String) : String :=
  let plain := match s.toList with
    | c :: cs => (c.isAlpha || c == '_') && cs.all fun c => c.isAlphanum || c == '_'
    | [] => false
  if plain then s else "`" ++ s.replace "`" "``" ++ "`"

private abbrev PrintM := StateM (Array (String × Value))

private def addParam (v : Value) : PrintM String := do
  let ps ← get
  let name := s!"p{ps.size}"
  set (ps.push (name, v))
  return "$" ++ name

private def binOpText : BinOp → String
  | .eq => "=" | .neq => "<>" | .lt => "<" | .le => "<=" | .gt => ">" | .ge => ">="
  | .and => "AND" | .or => "OR" | .xor => "XOR"
  | .add => "+" | .sub => "-" | .mul => "*" | .div => "/" | .mod => "%"
  | .startsWith => "STARTS WITH" | .endsWith => "ENDS WITH" | .contains => "CONTAINS" | .in_ => "IN"

private partial def expr : Expr → PrintM String
  | .var n => return quoteIdent n
  | .prop e k => return (← expr e) ++ "." ++ quoteIdent k
  | .value v => addParam v
  | .null => return "NULL"
  | .list xs => return "[" ++ ", ".intercalate (← xs.mapM expr) ++ "]"
  | .binop op a b => return s!"({← expr a} {binOpText op} {← expr b})"
  | .unop .not a => return s!"(NOT {← expr a})"
  | .unop .neg a => return s!"(-{← expr a})"
  | .unop .isNull a => return s!"({← expr a} IS NULL)"
  | .unop .isNotNull a => return s!"({← expr a} IS NOT NULL)"
  | .call fn args distinct =>
    return fn ++ "(" ++ (if distinct then "DISTINCT " else "") ++ ", ".intercalate (← args.mapM expr) ++ ")"
  | .countStar => return "count(*)"

/-- Print a top-level expression without its outermost parentheses. -/
private def topExpr (e : Expr) : PrintM String := do
  let s ← expr e
  if s.startsWith "(" && s.endsWith ")" && balanced s then
    return ((s.drop 1).dropEnd 1).toString
  return s
where
  /-- The outer parentheses enclose the whole string. -/
  balanced (s : String) : Bool := Id.run do
    let cs := s.toList
    let mut depth : Int := 0
    for h : i in [0:cs.length] do
      let c := cs[i]
      if c == '(' then depth := depth + 1
      if c == ')' then
        depth := depth - 1
        if depth == 0 && i + 1 < cs.length then return false
    return true

private def props (ps : List (String × Expr)) : PrintM String := do
  if ps.isEmpty then return ""
  let fs ← ps.mapM fun (k, v) => return s!"{quoteIdent k}: {← expr v}"
  return " {" ++ ", ".intercalate fs ++ "}"

private def nodePat (n : NodePat) : PrintM String := do
  let label := n.label.map (":" ++ quoteIdent ·) |>.getD ""
  return s!"({quoteIdent n.var}{label}{← props n.props})"

private def relPat (r : RelPat) : PrintM String := do
  let var := r.var.map quoteIdent |>.getD ""
  let body := s!"[{var}:{quoteIdent r.label}{← props r.props}]"
  return match r.dir with
    | .out => s!"-{body}->"
    | .inc => s!"<-{body}-"
    | .both => s!"-{body}-"

private def pattern (p : Pattern) : PrintM String := do
  let mut s ← nodePat p.start
  for (r, n) in p.steps do
    s := s ++ (← relPat r) ++ (← nodePat n)
  return s

private def items (is : List Item) : PrintM String := do
  let parts ← is.mapM fun i => do
    let e ← topExpr i.expr
    return match i.alias with
      | some a => s!"{e} AS {quoteIdent a}"
      | none => e
  return ", ".intercalate parts

private def modifiers (m : Modifiers) : PrintM String := do
  let mut s := ""
  unless m.orderBy.isEmpty do
    let keys ← m.orderBy.mapM fun k => return (← topExpr k.expr) ++ (if k.desc then " DESC" else "")
    s := s ++ " ORDER BY " ++ ", ".intercalate keys
  if let some e := m.skip then s := s ++ s!" SKIP {← topExpr e}"
  if let some e := m.limit then s := s ++ s!" LIMIT {← topExpr e}"
  return s

private def clause : Clause → PrintM String
  | .match opt pats => return (if opt then "OPTIONAL MATCH " else "MATCH ") ++ ", ".intercalate (← pats.mapM pattern)
  | .where c => return s!"WHERE {← topExpr c}"
  | .with is d m => return s!"WITH {if d then "DISTINCT " else ""}{← items is}{← modifiers m}"
  | .return is d m => return s!"RETURN {if d then "DISTINCT " else ""}{← items is}{← modifiers m}"
  | .unwind e a => return s!"UNWIND {← topExpr e} AS {quoteIdent a}"
  | .create pats => return "CREATE " ++ ", ".intercalate (← pats.mapM pattern)
  | .merge p => return s!"MERGE {← pattern p}"
  | .set is => do
    let parts ← is.mapM fun i => return s!"{← expr i.target} = {← topExpr i.value}"
    return "SET " ++ ", ".intercalate parts
  | .delete detach ts => return (if detach then "DETACH DELETE " else "DELETE ") ++ ", ".intercalate (← ts.mapM expr)

-- @tg: implements:: [[openspec:cypher-query#Printing]]
/-- Cypher text and parameters for a query. A WHERE that does not follow a
MATCH or WITH is preceded by `WITH *`. -/
def print (q : Query) : String × Array (String × Value) :=
  let act : PrintM (List String) := do
    let mut out := #[]
    let mut prev : Option Clause := none
    for c in q.clauses do
      if let .where _ := c then
        unless prev.any Clause.acceptsWhere do out := out.push "WITH *"
      out := out.push (← clause c)
      prev := some c
    return out.toList
  let (parts, ps) := act.run #[]
  (" ".intercalate parts, ps)

end Ladybug.Cypher
