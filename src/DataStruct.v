(* Copyright (c) 2008, Adam Chlipala
 * 
 * This work is licensed under a
 * Creative Commons Attribution-Noncommercial-No Derivative Works 3.0
 * Unported License.
 * The license text is available at:
 *   http://creativecommons.org/licenses/by-nc-nd/3.0/
 *)

(* begin hide *)
Require Import List.

Require Import Tactics.

Set Implicit Arguments.
(* end hide *)


(** %\chapter{Dependent Data Structures}% *)

(** Our red-black tree example from the last chapter illustrated how dependent types enable static enforcement of data structure invariants.  To find interesting uses of dependent data structures, however, we need not look to the favorite examples of data structures and algorithms textbooks.  More basic examples like length-indexed and heterogeneous lists come up again and again as the building blocks of dependent programs.  There is a surprisingly large design space for this class of data structure, and we will spend this chapter exploring it. *)


(** * More Length-Indexed Lists *)

(** We begin with a deeper look at the length-indexed lists that began the last chapter. *)

Section ilist.
  Variable A : Set.

  Inductive ilist : nat -> Set :=
  | Nil : ilist O
  | Cons : forall n, A -> ilist n -> ilist (S n).

  (** We might like to have a certified function for selecting an element of an [ilist] by position.  We could do this using subset types and explicit manipulation of proofs, but dependent types let us do it more directly.  It is helpful to define a type family [index], where [index n] is isomorphic to [{m : nat | m < n}].  Such a type family is also often called [Fin] or similar, standing for "finite." *)

  Inductive index : nat -> Set :=
  | First : forall n, index (S n)
  | Next : forall n, index n -> index (S n).

  (** [index] essentially makes a more richly-typed copy of the natural numbers.  Every element is a [First] iterated through applying [Next] a number of times that indicates which number is being selected.

     Now it is easy to pick a [Prop]-free type for a selection function.  As usual, our first implementation attempt will not convince the type checker, and we will attack the deficiencies one at a time.

     [[
  Fixpoint get n (ls : ilist n) {struct ls} : index n -> A :=
    match ls in ilist n return index n -> A with
      | Nil => fun idx => ?
      | Cons _ x ls' => fun idx =>
        match idx with
          | First _ => x
          | Next _ idx' => get ls' idx'
        end
    end.

    We apply the usual wisdom of delaying arguments in [Fixpoint]s so that they may be included in [return] clauses.  This still leaves us with a quandary in each of the [match] cases.  First, we need to figure out how to take advantage of the contradiction in the [Nil] case.  Every [index] has a type of the form [S n], which cannot unify with the [O] value that we learn for [n] in the [Nil] case.  The solution we adopt is another case of [match]-within-[return].

    [[
  Fixpoint get n (ls : ilist n) {struct ls} : index n -> A :=
    match ls in ilist n return index n -> A with
      | Nil => fun idx =>
        match idx in index n' return (match n' with
                                        | O => A
                                        | S _ => unit
                                      end) with
          | First _ => tt
          | Next _ _ => tt
        end
      | Cons _ x ls' => fun idx =>
        match idx with
          | First _ => x
          | Next _ idx' => get ls' idx'
        end
    end.

    Now the first [match] case type-checks, and we see that the problem with the [Cons] case is that the pattern-bound variable [idx'] does not have an apparent type compatible with [ls'].  We need to use [match] annotations to make the relationship explicit.  Unfortunately, the usual trick of postponing argument binding will not help us here.  We need to match on both [ls] and [idx]; one or the other must be matched first.  To get around this, we apply a trick that we will call "the convoy pattern," introducing a new function and applying it immediately, to satisfy the type checker.

    [[
  Fixpoint get n (ls : ilist n) {struct ls} : index n -> A :=
    match ls in ilist n return index n -> A with
      | Nil => fun idx =>
        match idx in index n' return (match n' with
                                        | O => A
                                        | S _ => unit
                                      end) with
          | First _ => tt
          | Next _ _ => tt
        end
      | Cons _ x ls' => fun idx =>
        match idx in index n' return ilist (pred n') -> A with
          | First _ => fun _ => x
          | Next _ idx' => fun ls' => get ls' idx'
        end ls'
    end.

    There is just one problem left with this implementation.  Though we know that the local [ls'] in the [Next] case is equal to the original [ls'], the type-checker is not satisfied that the recursive call to [get] does not introduce non-termination.  We solve the problem by convoy-binding the partial application of [get] to [ls'], rather than [ls'] by itself. *)

  Fixpoint get n (ls : ilist n) {struct ls} : index n -> A :=
    match ls in ilist n return index n -> A with
      | Nil => fun idx =>
        match idx in index n' return (match n' with
                                        | O => A
                                        | S _ => unit
                                      end) with
          | First _ => tt
          | Next _ _ => tt
        end
      | Cons _ x ls' => fun idx =>
        match idx in index n' return (index (pred n') -> A) -> A with
          | First _ => fun _ => x
          | Next _ idx' => fun get_ls' => get_ls' idx'
        end (get ls')
    end.
End ilist.

Implicit Arguments Nil [A].
Implicit Arguments First [n].

(** A few examples show how to make use of these definitions. *)

Check Cons 0 (Cons 1 (Cons 2 Nil)).
(** [[

Cons 0 (Cons 1 (Cons 2 Nil))
     : ilist nat 3
]] *)
Eval simpl in get (Cons 0 (Cons 1 (Cons 2 Nil))) First.
(** [[

     = 0
     : nat
]] *)
Eval simpl in get (Cons 0 (Cons 1 (Cons 2 Nil))) (Next First).
(** [[

     = 1
     : nat
]] *)
Eval simpl in get (Cons 0 (Cons 1 (Cons 2 Nil))) (Next (Next First)).
(** [[

     = 2
     : nat
]] *)

(** Our [get] function is also quite easy to reason about.  We show how with a short example about an analogue to the list [map] function. *)

Section ilist_map.
  Variables A B : Set.
  Variable f : A -> B.

  Fixpoint imap n (ls : ilist A n) {struct ls} : ilist B n :=
    match ls in ilist _ n return ilist B n with
      | Nil => Nil
      | Cons _ x ls' => Cons (f x) (imap ls')
    end.

  (** It is easy to prove that [get] "distributes over" [imap] calls.  The only tricky bit is remembering to use the [dep_destruct] tactic in place of plain [destruct] when faced with a baffling tactic error message. *)

  Theorem get_imap : forall n (idx : index n) (ls : ilist A n),
    get (imap ls) idx = f (get ls idx).
    induction ls; dep_destruct idx; crush.
  Qed.
End ilist_map.


(** * Heterogeneous Lists *)

(** Programmers who move to statically-typed functional languages from "scripting languages" often complain about the requirement that every element of a list have the same type.  With fancy type systems, we can partially lift this requirement.  We can index a list type with a "type-level" list that explains what type each element of the list should have.  This has been done in a variety of ways in Haskell using type classes, and it we can do it much more cleanly and directly in Coq. *)

Section hlist.
  Variable A : Type.
  Variable B : A -> Type.

  (** We parameterize our heterogeneous lists by a type [A] and an [A]-indexed type [B]. *)

  Inductive hlist : list A -> Type :=
  | MNil : hlist nil
  | MCons : forall (x : A) (ls : list A), B x -> hlist ls -> hlist (x :: ls).

  (** We can implement a variant of the last section's [get] function for [hlist]s.  To get the dependent typing to work out, we will need to index our element selectors by the types of data that they point to. *)

  Variable elm : A.

  Inductive member : list A -> Type :=
  | MFirst : forall ls, member (elm :: ls)
  | MNext : forall x ls, member ls -> member (x :: ls).

  (** Because the element [elm] that we are "searching for" in a list does not change across the constructors of [member], we simplify our definitions by making [elm] a local variable.  In the definition of [member], we say that [elm] is found in any list that begins with [elm], and, if removing the first element of a list leaves [elm] present, then [elm] is present in the original list, too.  The form looks much like a predicate for list membership, but we purposely define [member] in [Type] so that we may decompose its values to guide computations.

     We can use [member] to adapt our definition of [get] to [hlists].  The same basic [match] tricks apply.  In the [MCons] case, we form a two-element convoy, passing both the data element [x] and the recursor for the sublist [mls'] to the result of the inner [match].  We did not need to do that in [get]'s definition because the types of list elements were not dependent there. *)

  Fixpoint hget ls (mls : hlist ls) {struct mls} : member ls -> B elm :=
    match mls in hlist ls return member ls -> B elm with
      | MNil => fun mem =>
        match mem in member ls' return (match ls' with
                                          | nil => B elm
                                          | _ :: _ => unit
                                        end) with
          | MFirst _ => tt
          | MNext _ _ _ => tt
        end
      | MCons _ _ x mls' => fun mem =>
        match mem in member ls' return (match ls' with
                                          | nil => Empty_set
                                          | x' :: ls'' =>
                                            B x' -> (member ls'' -> B elm) -> B elm
                                        end) with
          | MFirst _ => fun x _ => x
          | MNext _ _ mem' => fun _ get_mls' => get_mls' mem'
        end x (hget mls')
    end.
End hlist.

Implicit Arguments MNil [A B].
Implicit Arguments MCons [A B x ls].

Implicit Arguments MFirst [A elm ls].
Implicit Arguments MNext [A elm x ls].

(** By putting the parameters [A] and [B] in [Type], we allow some very higher-order uses.  For instance, one use of [hlist] is for the simple heterogeneous lists that we referred to earlier. *)

Definition someTypes : list Set := nat :: bool :: nil.

Example someValues : hlist (fun T : Set => T) someTypes :=
  MCons 5 (MCons true MNil).

Eval simpl in hget someValues MFirst.
(** [[

     = 5
     : (fun T : Set => T) nat
]] *)
Eval simpl in hget someValues (MNext MFirst).
(** [[

     = true
     : (fun T : Set => T) bool
]] *)

(** We can also build indexed lists of pairs in this way. *)

Example somePairs : hlist (fun T : Set => T * T)%type someTypes :=
  MCons (1, 2) (MCons (true, false) MNil).

(** ** A Lambda Calculus Interpreter *)

(** Heterogeneous lists are very useful in implementing interpreters for functional programming languages.  Using the types and operations we have already defined, it is trivial to write an interpreter for simply-typed lambda calculus.  Our interpreter can alternatively be thought of as a denotational semantics.

   We start with an algebraic datatype for types. *)

Inductive type : Set :=
| Unit : type
| Arrow : type -> type -> type.

(** Now we can define a type family for expressions.  An [exp ts t] will stand for an expression that has type [t] and whose free variables have types in the list [ts].  We effectively use the de Bruijn variable representation, which we will discuss in more detail in later chapters.  Variables are represented as [member] values; that is, a variable is more or less a constructive proof that a particular type is found in the type environment. *)

Inductive exp : list type -> type -> Set :=
| Const : forall ts, exp ts Unit

| Var : forall ts t, member t ts -> exp ts t
| App : forall ts dom ran, exp ts (Arrow dom ran) -> exp ts dom -> exp ts ran
| Abs : forall ts dom ran, exp (dom :: ts) ran -> exp ts (Arrow dom ran).

Implicit Arguments Const [ts].

(** We write a simple recursive function to translate [type]s into [Set]s. *)

Fixpoint typeDenote (t : type) : Set :=
  match t with
    | Unit => unit
    | Arrow t1 t2 => typeDenote t1 -> typeDenote t2
  end.

(** Now it is straightforward to write an expression interpreter.  The type of the function, [expDenote], tells us that we translate expressions into functions from properly-typed environments to final values.  An environment for a free variable list [ts] is simply a [hlist typeDenote ts].  That is, for each free variable, the heterogeneous list that is the environment must have a value of the variable's associated type.  We use [hget] to implement the [Var] case, and we use [MCons] to extend the environment in the [Abs] case. *)

Fixpoint expDenote ts t (e : exp ts t) {struct e} : hlist typeDenote ts -> typeDenote t :=
  match e in exp ts t return hlist typeDenote ts -> typeDenote t with
    | Const _ => fun _ => tt

    | Var _ _ mem => fun s => hget s mem
    | App _ _ _ e1 e2 => fun s => (expDenote e1 s) (expDenote e2 s)
    | Abs _ _ _ e' => fun s => fun x => expDenote e' (MCons x s)
  end.

(** Like for previous examples, our interpreter is easy to run with [simpl]. *)

Eval simpl in expDenote Const MNil.
(** [[

    = tt
     : typeDenote Unit
]] *)
Eval simpl in expDenote (Abs (dom := Unit) (Var MFirst)) MNil.
(** [[

     = fun x : unit => x
     : typeDenote (Arrow Unit Unit)
]] *)
Eval simpl in expDenote (Abs (dom := Unit)
  (Abs (dom := Unit) (Var (MNext MFirst)))) MNil.
(** [[

     = fun x _ : unit => x
     : typeDenote (Arrow Unit (Arrow Unit Unit))
]] *)
Eval simpl in expDenote (Abs (dom := Unit) (Abs (dom := Unit) (Var MFirst))) MNil.
(** [[

     = fun _ x0 : unit => x0
     : typeDenote (Arrow Unit (Arrow Unit Unit))
]] *)
Eval simpl in expDenote (App (Abs (Var MFirst)) Const) MNil.
(** [[

     = tt
     : typeDenote Unit
]] *)

(** We are starting to develop the tools behind dependent typing's amazing advantage over alternative approaches in several important areas.  Here, we have implemented complete syntax, typing rules, and evaluation semantics for simply-typed lambda calculus without even needing to define a syntactic substitution operation.  We did it all without a single line of proof, and our implementation is manifestly executable.  In a later chapter, we will meet other, more common approaches to language formalization.  Such approaches often state and prove explicit theorems about type safety of languages.  In the above example, we got type safety, termination, and other meta-theorems for free, by reduction to CIC, which we know has those properties. *)


