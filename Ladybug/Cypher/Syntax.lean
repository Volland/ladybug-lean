import Lean
import Ladybug.Cypher.Keyword

/-!
# `cypher%` syntax

The grammar of Cypher text embedded in Lean. Keywords are accepted in upper
case, lower case and capitalized form (`MATCH`, `match`, `Match`); they are
matched as identifiers, so they never become reserved Lean tokens. Strings are
Lean string literals (`"Ann"`), since `'…'` is Lean's character syntax.

Every clause after the first must start at or to the right of the first
clause's column, so the query ends where the indentation does.
-/

namespace Ladybug.Cypher.Syntax

open Ladybug.Cypher.Keyword

/-! ## Keywords -/

syntax kwMatch := &"MATCH" <|> &"match" <|> &"Match"
syntax kwOptional := &"OPTIONAL" <|> &"optional" <|> &"Optional"
syntax kwWhere := &"WHERE" <|> &"where" <|> &"Where"
syntax kwWith := &"WITH" <|> &"with" <|> &"With"
syntax kwReturn := &"RETURN" <|> &"return" <|> &"Return"
syntax kwDistinct := &"DISTINCT" <|> &"distinct" <|> &"Distinct"
syntax kwAs := &"AS" <|> &"as" <|> &"As"
syntax kwOrder := &"ORDER" <|> &"order" <|> &"Order"
syntax kwBy := &"BY" <|> &"by" <|> &"By"
syntax kwAsc := &"ASC" <|> &"asc" <|> &"Asc"
syntax kwDesc := &"DESC" <|> &"desc" <|> &"Desc"
syntax kwSkip := &"SKIP" <|> &"skip" <|> &"Skip"
syntax kwLimit := &"LIMIT" <|> &"limit" <|> &"Limit"
syntax kwUnwind := &"UNWIND" <|> &"unwind" <|> &"Unwind"
syntax kwCreate := &"CREATE" <|> &"create" <|> &"Create"
syntax kwMerge := &"MERGE" <|> &"merge" <|> &"Merge"
syntax kwSet := &"SET" <|> &"set" <|> &"Set"
syntax kwDelete := &"DELETE" <|> &"delete" <|> &"Delete"
syntax kwDetach := &"DETACH" <|> &"detach" <|> &"Detach"
syntax kwNot := &"NOT" <|> &"not" <|> &"Not"
syntax kwNull := &"NULL" <|> &"null" <|> &"Null"

/-! ## Expressions -/

/-- `both`: an identifier is tried as a keyword (`NULL`, `NOT`) first, then as a name. -/
declare_syntax_cat cypherExpr (behavior := both)

syntax (name := numLit) num : cypherExpr
syntax (name := sciLit) scientific : cypherExpr
syntax (name := strLit) str : cypherExpr
/-- A variable, `var.property`, `true`, `false`. -/
syntax (name := identExpr) ident : cypherExpr
syntax (name := nullLit) kwNull : cypherExpr
/-- `$x`: the Lean local `x` as a parameter. -/
syntax (name := paramLocal) "$" ident : cypherExpr
/-- `$(e)`: the Lean term `e` as a parameter. -/
syntax (name := paramTerm) "$" "(" term ")" : cypherExpr
syntax (name := listLit) "[" cypherExpr,* "]" : cypherExpr
syntax (name := paren) "(" cypherExpr ")" : cypherExpr
/-- `count(*)`. -/
syntax:max (name := callStar) ident noWs "(" "*" ")" : cypherExpr
/-- A function call, optionally `fn(DISTINCT x)`. -/
syntax:max (name := call) ident noWs "(" (kwDistinct)? cypherExpr,* ")" : cypherExpr

syntax:20 (name := orE) cypherExpr:20 kwOrP cypherExpr:21 : cypherExpr
syntax:22 (name := xorE) cypherExpr:22 kwXorP cypherExpr:23 : cypherExpr
syntax:24 (name := andE) cypherExpr:24 kwAndP cypherExpr:25 : cypherExpr
syntax:26 (name := notE) kwNot cypherExpr:26 : cypherExpr
syntax:30 (name := eqE) cypherExpr:31 " = " cypherExpr:31 : cypherExpr
syntax:30 (name := neqE) cypherExpr:31 " <> " cypherExpr:31 : cypherExpr
syntax:30 (name := ltE) cypherExpr:31 " < " cypherExpr:31 : cypherExpr
syntax:30 (name := leE) cypherExpr:31 " <= " cypherExpr:31 : cypherExpr
syntax:30 (name := gtE) cypherExpr:31 " > " cypherExpr:31 : cypherExpr
syntax:30 (name := geE) cypherExpr:31 " >= " cypherExpr:31 : cypherExpr
syntax:30 (name := isNullE) cypherExpr:31 kwIsP kwNull : cypherExpr
syntax:30 (name := isNotNullE) cypherExpr:31 kwIsP kwNot kwNull : cypherExpr
syntax:30 (name := startsE) cypherExpr:31 kwStartsP kwWith cypherExpr:31 : cypherExpr
syntax:30 (name := endsE) cypherExpr:31 kwEndsP kwWith cypherExpr:31 : cypherExpr
syntax:30 (name := containsE) cypherExpr:31 kwContainsP cypherExpr:31 : cypherExpr
syntax:30 (name := inE) cypherExpr:31 kwInP cypherExpr:31 : cypherExpr
syntax:40 (name := addE) cypherExpr:40 " + " cypherExpr:41 : cypherExpr
syntax:40 (name := subE) cypherExpr:40 " - " cypherExpr:41 : cypherExpr
syntax:50 (name := mulE) cypherExpr:50 " * " cypherExpr:51 : cypherExpr
syntax:50 (name := divE) cypherExpr:50 " / " cypherExpr:51 : cypherExpr
syntax:50 (name := modE) cypherExpr:50 " % " cypherExpr:51 : cypherExpr
syntax:60 (name := negE) "-" cypherExpr:60 : cypherExpr

/-! ## Patterns -/

syntax cypherProp := ident ": " cypherExpr
syntax cypherProps := "{" cypherProp,* "}"
/-- `(var:Label {props})`; every part is optional. -/
syntax cypherNode := "(" (ident)? (":" ident)? (cypherProps)? ")"
/-- `[var:Label {props}]`. -/
syntax cypherRel := "[" (ident)? ":" ident (cypherProps)? "]"
syntax cypherOut := "-" cypherRel "->" cypherNode
syntax cypherIn := "<-" cypherRel "-" cypherNode
syntax cypherBoth := "-" cypherRel "-" cypherNode
syntax cypherStep := atomic(cypherOut) <|> cypherIn <|> cypherBoth
syntax cypherPattern := cypherNode (cypherStep)*

/-! ## Clauses -/

syntax cypherItem := cypherExpr (ppSpace kwAs ident)?
syntax cypherSortKey := cypherExpr (kwAsc <|> kwDesc)?
syntax cypherMods := (kwOrder kwBy cypherSortKey,+)? (kwSkip cypherExpr)? (kwLimit cypherExpr)?
syntax cypherSetItem := ident " = " cypherExpr

/-- `symbol`: a leading identifier such as `MATCH` selects the clause keyword. -/
declare_syntax_cat cypherClause (behavior := symbol)

syntax (name := optMatchC) kwOptional kwMatch cypherPattern,+ : cypherClause
syntax (name := matchC) kwMatch cypherPattern,+ : cypherClause
syntax (name := whereC) kwWhere cypherExpr : cypherClause
syntax (name := withC) kwWith (kwDistinct)? cypherItem,+ cypherMods : cypherClause
syntax (name := returnC) kwReturn (kwDistinct)? cypherItem,+ cypherMods : cypherClause
syntax (name := unwindC) kwUnwind cypherExpr kwAs ident : cypherClause
syntax (name := createC) kwCreate cypherPattern : cypherClause
syntax (name := mergeC) kwMerge cypherPattern : cypherClause
syntax (name := setC) kwSet cypherSetItem,+ : cypherClause
syntax (name := detachDeleteC) kwDetach kwDelete ident,+ : cypherClause
syntax (name := deleteC) kwDelete ident,+ : cypherClause

-- @tg: implements:: [[openspec:cypher-syntax#Embedded Cypher]]
/-- Typed Cypher text: a `Query α` when it ends in RETURN, otherwise a `Statement`. -/
syntax (name := cypherTerm) "cypher% " withPosition(cypherClause (colGe cypherClause)*) : term

end Ladybug.Cypher.Syntax
