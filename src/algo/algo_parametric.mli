open Clause
open Formule
open Algo_base

exception Conflit of (clause*etat)

type dpll_answer = 
  | No_bet of bool vartable * (literal list -> (literal list*(unit -> dpll_answer)))
  | Bet_done of literal list * (unit -> dpll_answer) * (literal list -> (literal list*(unit -> dpll_answer)))
  | Conflit_dpll of literal list * (unit -> dpll_answer)


module type Algo_parametric =
sig
  val run : Heuristic.t -> bool -> bool -> bool -> int -> literal list list -> (literal list*(unit -> dpll_answer))
end

module Bind : functor(Base : Algo_base) -> Algo_parametric










