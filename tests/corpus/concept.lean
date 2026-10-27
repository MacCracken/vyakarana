/-!
# concept.lean — Lean 4 stand-in corpus (ADR 0006)

Definitions, structures, inductive types, pattern matching, tactics,
`do` notation, and every literal form the grammar reads.
-/

import Std
open Nat

namespace Concept

/-- A point in the plane. -/
structure Point where
  x : Float
  y : Float
  deriving Repr

inductive Shape where
  | circle (r : Float)
  | rect (w h : Float)

def area : Shape → Float
  | .circle r => 3.14159 * r * r
  | .rect w h => w * h

def double (n : Nat) : Nat := n + n

theorem double_eq (n : Nat) : double n = 2 * n := by
  unfold double
  omega

-- A line comment, and the ASCII spellings: fun, ->, <-, <=.
def compose (f : β -> γ) (g : α -> β) : α -> γ := fun x => f (g x)

def sumTo (n : Nat) : Nat := Id.run do
  let mut acc := 0
  for i in [0:n+1] do
    acc := acc + i
  return acc

def greet (name : String) : String := s!"hello, {name}!"
def path : String := r"C:\dir\file"
def quoted : String := r#"say "hi""#
def tab : Char := '\t'
def nums : List Nat := [42, 0x2A, 0b101010, 0o52]
def ratio : Float := 1.5e-3
def «weird name» : Nat := 7
def h' : Nat := double 3

instance : ToString Point where
  toString p := s!"({p.x}, {p.y})"

-- Quotations, array literals, and a proof after a bracket.
macro "twice" t:term : term => `($t + $t)
def names : List Lean.Name := [`Nat.add, ``Nat.succ]
def arr : Array Nat := #[1, 2, 3]
def first (xs : Array Nat) (h : 0 < xs.size) : Nat := xs[0]'h

#eval sumTo 10
#check @area

end Concept
