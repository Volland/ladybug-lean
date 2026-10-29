import Ladybug.Schema

/-!
# In-memory graph state

The whole database as a pure value: the applied schema, nodes, relationships
and search indexes. Nodes and relationships carry Ladybug-style internal IDs
(table index and offset), and their properties are kept in declared column order.
-/

namespace Ladybug.Mem

structure Node where
  id : InternalId
  label : String
  props : Array (String × Value)
  deriving Inhabited

structure Rel where
  id : InternalId
  src : InternalId
  dst : InternalId
  label : String
  props : Array (String × Value)
  deriving Inhabited

structure VecIndex where
  table : String
  name : String
  column : String
  metric : String
  deriving Inhabited

structure FtsIndex where
  table : String
  name : String
  columns : List String
  deriving Inhabited

-- @tg: implements:: [[openspec:memory-backend#Pure graph state]]
structure Graph where
  tables : Array TableDecl := #[]
  /-- Next offset per table, aligned with `tables`. -/
  counters : Array Nat := #[]
  nodes : Array Node := #[]
  rels : Array Rel := #[]
  vecIndexes : Array VecIndex := #[]
  ftsIndexes : Array FtsIndex := #[]
  deriving Inhabited

namespace Graph

def tableIndex? (g : Graph) (label : String) : Option Nat := g.tables.findIdx? (·.label == label)

def table? (g : Graph) (label : String) : Option TableDecl := g.tables.find? (·.label == label)

def node? (g : Graph) (id : InternalId) : Option Node := g.nodes.find? (·.id == id)

def rel? (g : Graph) (id : InternalId) : Option Rel := g.rels.find? (·.id == id)

/-- A fresh ID in the table at index `t`. -/
def freshId (g : Graph) (t : Nat) : InternalId × Graph :=
  let n := g.counters[t]?.getD 0
  (⟨UInt64.ofNat t, UInt64.ofNat n⟩, { g with counters := g.counters.set! t (n + 1) })

def addTable (g : Graph) (d : TableDecl) : Graph :=
  if (g.tableIndex? d.label).isSome then g
  else { g with tables := g.tables.push d, counters := g.counters.push 0 }

end Graph

def Node.value (n : Node) : Value := .node n.id n.label n.props
def Rel.value (r : Rel) : Value := .rel r.id r.src r.dst r.label r.props

/-! ## Text search -/

/-- Whether `cs[i]` is a vowel in Porter's sense: `y` after a consonant counts. -/
private def isVowel (cs : Array Char) : Nat → Bool
  | 0 => match (cs[0]? : Option Char) with
    | some c => "aeiou".contains c
    | none => false
  | j + 1 => match (cs[j + 1]? : Option Char) with
    | some 'y' => !isVowel cs j
    | some c => "aeiou".contains c
    | none => false

/-- Porter's measure: the number of vowel-consonant sequences in `cs[0:n]`. -/
private def measure (cs : Array Char) (n : Nat) : Nat := Id.run do
  let mut m := 0
  let mut prevVowel := false
  for i in [0:n] do
    let v := isVowel cs i
    if prevVowel && !v then m := m + 1
    prevVowel := v
  return m

private def hasVowel (cs : Array Char) (n : Nat) : Bool := (List.range n).any (isVowel cs)

private def endsDoubleCons (cs : Array Char) (n : Nat) : Bool :=
  n ≥ 2 && cs[n-1]! == cs[n-2]! && !isVowel cs (n - 1)

/-- Consonant-vowel-consonant ending, the last not w, x or y. -/
private def endsCVC (cs : Array Char) (n : Nat) : Bool :=
  n ≥ 3 && !isVowel cs (n - 1) && isVowel cs (n - 2) && !isVowel cs (n - 3) &&
    !"wxy".contains cs[n-1]!

/-- Replace suffix `s` by `r` when the stem before it has measure > `m`. -/
private def rule (w : String) (s r : String) (m : Nat) : Option String :=
  if w.endsWith s then
    let stem := (w.dropEnd s.length).toString
    let cs := stem.toList.toArray
    if measure cs cs.size > m then some (stem ++ r) else some w
  else none

private def step2 : List (String × String) :=
  [("ational", "ate"), ("tional", "tion"), ("enci", "ence"), ("anci", "ance"), ("izer", "ize"),
   ("abli", "able"), ("alli", "al"), ("entli", "ent"), ("eli", "e"), ("ousli", "ous"),
   ("ization", "ize"), ("ation", "ate"), ("ator", "ate"), ("alism", "al"), ("iveness", "ive"),
   ("fulness", "ful"), ("ousness", "ous"), ("aliti", "al"), ("iviti", "ive"), ("biliti", "ble")]

private def step3 : List (String × String) :=
  [("icate", "ic"), ("ative", ""), ("alize", "al"), ("iciti", "ic"), ("ical", "ic"), ("ful", ""), ("ness", "")]

private def step4 : List String :=
  ["al", "ance", "ence", "er", "ic", "able", "ible", "ant", "ement", "ment", "ent", "ion", "ou",
   "ism", "ate", "iti", "ous", "ive", "ize"]

/-- The Porter stemmer, which Ladybug's full-text index uses by default. -/
def porterStem (word : String) : String := Id.run do
  let mut w := word
  if w.length ≤ 2 then return w
  -- Step 1a
  if w.endsWith "sses" then w := (w.dropEnd 2).toString
  else if w.endsWith "ies" then w := (w.dropEnd 2).toString
  else if w.endsWith "ss" then pure ()
  else if w.endsWith "s" then w := (w.dropEnd 1).toString
  -- Step 1b
  let mut extra := false
  if w.endsWith "eed" then
    let stem := (w.dropEnd 3).toString.toList.toArray
    if measure stem stem.size > 0 then w := (w.dropEnd 1).toString
  else
    for suf in ["ed", "ing"] do
      if w.endsWith suf then
        let stem := (w.dropEnd suf.length).toString
        let cs := stem.toList.toArray
        if hasVowel cs cs.size then
          w := stem
          extra := true
        break
  if extra then
    let cs := w.toList.toArray
    if w.endsWith "at" || w.endsWith "bl" || w.endsWith "iz" then w := w ++ "e"
    else if endsDoubleCons cs cs.size && !"lsz".contains cs[cs.size-1]! then w := (w.dropEnd 1).toString
    else if measure cs cs.size == 1 && endsCVC cs cs.size then w := w ++ "e"
  -- Step 1c
  if w.endsWith "y" then
    let stem := (w.dropEnd 1).toString.toList.toArray
    if hasVowel stem stem.size then w := (w.dropEnd 1).toString ++ "i"
  -- Steps 2 and 3
  for table in [step2, step3] do
    for (s, r) in table do
      if let some w' := rule w s r 0 then
        w := w'
        break
  -- Step 4
  for s in step4 do
    if w.endsWith s then
      let stem := (w.dropEnd s.length).toString
      let cs := stem.toList.toArray
      if measure cs cs.size > 1 then
        if s == "ion" then
          if stem.endsWith "s" || stem.endsWith "t" then w := stem
        else w := stem
      break
  -- Step 5
  if w.endsWith "e" then
    let stem := (w.dropEnd 1).toString.toList.toArray
    let m := measure stem stem.size
    if m > 1 || (m == 1 && !endsCVC stem stem.size) then w := (w.dropEnd 1).toString
  let cs := w.toList.toArray
  if measure cs cs.size > 1 && endsDoubleCons cs cs.size && cs[cs.size-1]! == 'l' then
    w := (w.dropEnd 1).toString
  return w

/-- English stopwords removed from documents and queries. -/
def stopwords : List String :=
  ["a", "an", "and", "are", "as", "at", "be", "but", "by", "for", "if", "in", "into", "is", "it", "no",
   "not", "of", "on", "or", "such", "that", "the", "their", "then", "there", "these", "they", "this",
   "to", "was", "will", "with", "i", "me", "my", "we", "our", "you", "your", "he", "him", "his", "she",
   "her", "its", "them", "what", "which", "who", "whom", "am", "were", "been", "being", "have", "has",
   "had", "having", "do", "does", "did", "doing", "so", "than", "too", "very", "can", "just", "should",
   "now", "from", "up", "down", "out", "off", "over", "under", "again", "further", "once", "here",
   "when", "where", "why", "how", "all", "any", "both", "each", "few", "more", "most", "other", "some",
   "own", "same", "only", "about", "against", "between", "through", "during", "before", "after",
   "above", "below", "while", "because", "until", "nor"]

/-- Lower-case, split on non-alphanumerics, drop stopwords, stem. -/
def tokenize (text : String) : List String := Id.run do
  let mut words : Array String := #[]
  let mut cur := ""
  for c in text.toLower.toList do
    if c.isAlphanum then cur := cur.push c
    else
      unless cur.isEmpty do words := words.push cur
      cur := ""
  unless cur.isEmpty do words := words.push cur
  return words.toList.filter (!stopwords.contains ·) |>.map porterStem

/-- BM25 scores (k1 = 1.2, b = 0.75) of documents for a query; only documents
with a positive score are returned. -/
def bm25 (docs : Array (InternalId × List String)) (query : List String) : Array (InternalId × Float) :=
  let n := docs.size.toFloat
  let total := docs.foldl (fun acc (d : InternalId × List String) => acc + d.2.length) 0
  let avgdl := if docs.isEmpty then 1 else total.toFloat / n
  let terms := query.eraseDups
  let df (t : String) : Float := (docs.filter (·.2.contains t)).size.toFloat
  docs.filterMap fun (id, toks) =>
    let dl := toks.length.toFloat
    let score := terms.foldl (init := 0.0) fun acc t =>
      let tf := (toks.filter (· == t)).length.toFloat
      if tf == 0 then acc
      else
        let idf := Float.log (1 + (n - df t + 0.5) / (df t + 0.5))
        acc + idf * tf * 2.2 / (tf + 1.2 * (0.25 + 0.75 * dl / avgdl))
    if score > 0 then some (id, score) else none

end Ladybug.Mem
