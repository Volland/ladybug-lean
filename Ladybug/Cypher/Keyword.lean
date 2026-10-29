import Lean

/-!
# Keywords that start trailing rules

Lean indexes the trailing parsers of an identifier token only under `ident`, so
a rule like `a AND b` is found only if its keyword's first tokens include
`ident`. `nonReservedSymbol sym (includeIdent := true)` has exactly that, and,
being a standard combinator, gets a formatter and parenthesizer for free.
Like the other keywords, these accept upper, lower and capitalized case.
-/

namespace Ladybug.Cypher.Keyword

open Lean Parser

/-- `sym` in upper, lower or capitalized case, as a keyword that may start a trailing rule. -/
def ciKw (sym : String) : Parser :=
  let cap := (sym.take 1).toString.toUpper ++ (sym.drop 1).toString
  nonReservedSymbol sym.toUpper true <|> nonReservedSymbol sym true <|> nonReservedSymbol cap true

@[run_parser_attribute_hooks] def kwOrP : Parser := ciKw "or"
@[run_parser_attribute_hooks] def kwXorP : Parser := ciKw "xor"
@[run_parser_attribute_hooks] def kwAndP : Parser := ciKw "and"
@[run_parser_attribute_hooks] def kwIsP : Parser := ciKw "is"
@[run_parser_attribute_hooks] def kwStartsP : Parser := ciKw "starts"
@[run_parser_attribute_hooks] def kwEndsP : Parser := ciKw "ends"
@[run_parser_attribute_hooks] def kwContainsP : Parser := ciKw "contains"
@[run_parser_attribute_hooks] def kwInP : Parser := ciKw "in"

end Ladybug.Cypher.Keyword
