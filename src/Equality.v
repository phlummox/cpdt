(* Copyright (c) 2008-2011, Adam Chlipala
 * 
 * This work is licensed under a
 * Creative Commons Attribution-Noncommercial-No Derivative Works 3.0
 * Unported License.
 * The license text is available at:
 *   http://creativecommons.org/licenses/by-nc-nd/3.0/
 *)

(* begin hide *)
Require Import Eqdep JMeq List.

Require Import CpdtTactics.

Set Implicit Arguments.
(* end hide *)


(** %\chapter{Reasoning About Equality Proofs}% *)

(** In traditional mathematics, the concept of equality is usually taken as a given.  On the other hand, in type theory, equality is a very contentious subject.  There are at least three different notions of equality that are important, and researchers are actively investigating new definitions of what it means for two terms to be equal.  Even once we fix a notion of equality, there are inevitably tricky issues that arise in proving properties of programs that manipulate equality proofs explicitly.  In this chapter, I will focus on design patterns for circumventing these tricky issues, and I will introduce the different notions of equality as they are germane. *)


(** * The Definitional Equality *)

(** We have seen many examples so far where proof goals follow %``%#"#by computation.#"#%''%  That is, we apply computational reduction rules to reduce the goal to a normal form, at which point it follows trivially.  Exactly when this works and when it does not depends on the details of Coq's %\index{definitional equality}\textit{%#<i>#definitional equality#</i>#%}%.  This is an untyped binary relation appearing in the formal metatheory of CIC.  CIC contains a typing rule allowing the conclusion $E : T$ from the premise $E : T'$ and a proof that $T$ and $T'$ are definitionally equal.

   The %\index{tactics!cbv}%[cbv] tactic will help us illustrate the rules of Coq's definitional equality.  We redefine the natural number predecessor function in a somewhat convoluted way and construct a manual proof that it returns [0] when applied to [1]. *)

Definition pred' (x : nat) :=
  match x with
    | O => O
    | S n' => let y := n' in y
  end.

Theorem reduce_me : pred' 1 = 0.

(* begin thide *)
  (** CIC follows the traditions of lambda calculus in associating reduction rules with Greek letters.  Coq can certainly be said to support the familiar alpha reduction rule, which allows capture-avoiding renaming of bound variables, but we never need to apply alpha explicitly, since Coq uses a de Bruijn representation%~\cite{DeBruijn}% that encodes terms canonically.

     The %\index{delta reduction}%delta rule is for unfolding global definitions.  We can use it here to unfold the definition of [pred'].  We do this with the [cbv] tactic, which takes a list of reduction rules and makes as many call-by-value reduction steps as possible, using only those rules.  There is an analogous tactic %\index{tactics!lazy}%[lazy] for call-by-need reduction. *)

  cbv delta.
  (** %\vspace{-.15in}%[[
  ============================
   (fun x : nat => match x with
                   | 0 => 0
                   | S n' => let y := n' in y
                   end) 1 = 0
      ]]

      At this point, we want to apply the famous %\index{beta reduction}%beta reduction of lambda calculus, to simplify the application of a known function abstraction. *)

  cbv beta.
  (** %\vspace{-.15in}%[[
  ============================
   match 1 with
   | 0 => 0
   | S n' => let y := n' in y
   end = 0
   ]]

   Next on the list is the %\index{iota reduction}%iota reduction, which simplifies a single [match] term by determining which pattern matches. *)

  cbv iota.
  (** %\vspace{-.15in}%[[
  ============================
   (fun n' : nat => let y := n' in y) 0 = 0
      ]]

   Now we need another beta reduction. *)

  cbv beta.
  (** %\vspace{-.15in}%[[
  ============================
   (let y := 0 in y) = 0
      ]]
   
      The final reduction rule is %\index{zeta reduction}%zeta, which replaces a [let] expression by its body with the appropriate term substituted. *)

  cbv zeta.
  (** %\vspace{-.15in}%[[
  ============================
   0 = 0
   ]]
   *)

  reflexivity.
Qed.
(* end thide *)

(** The [beta] reduction rule applies to recursive functions as well, and its behavior may be surprising in some instances.  For instance, we can run some simple tests using the reduction strategy [compute], which applies all applicable rules of the definitional equality. *)

Definition id (n : nat) := n.

Eval compute in fun x => id x.
(** %\vspace{-.15in}%[[
     = fun x : nat => x
]]
*)

Fixpoint id' (n : nat) := n.

Eval compute in fun x => id' x.
(** %\vspace{-.15in}%[[
     = fun x : nat => (fix id' (n : nat) : nat := n) x
]]

By running [compute], we ask Coq to run reduction steps until no more apply, so why do we see an application of a known function, where clearly no beta reduction has been performed?  The answer has to do with ensuring termination of all Gallina programs.  One candidate rule would say that we apply recursive definitions wherever possible.  However, this would clearly lead to nonterminating reduction sequences, since the function may appear fully applied within its own definition, and we would naively %``%#"#simplify#"#%''% such applications immediately.  Instead, Coq only applies the beta rule for a recursive function when %\emph{%#<i>#the top-level structure of the recursive argument is known#</i>#%}%.  For [id'] above, we have only one argument [n], so clearly it is the recursive argument, and the top-level structure of [n] is known when the function is applied to [O] or to some [S e] term.  The variable [x] is neither, so reduction is blocked.

What are recursive arguments in general?  Every recursive function is compiled by Coq to a %\index{Gallina terms!fix}%[fix] expression, for anonymous definition of recursive functions.  Further, every [fix] with multiple arguments has one designated as the recursive argument via a [struct] annotation.  The recursive argument is the one that must decrease across recursive calls, to appease Coq's termination checker.  Coq will generally infer which argument is recursive, though we may also specify it manually, if we want to tweak reduction behavior.  For instance, consider this definition of a function to add two lists of [nat]s elementwise: *)

Fixpoint addLists (ls1 ls2 : list nat) : list nat :=
  match ls1, ls2 with
    | n1 :: ls1' , n2 :: ls2' => n1 + n2 :: addLists ls1' ls2'
    | _, _ => nil
  end.

(** By default, Coq chooses [ls1] as the recursive argument.  We can see that [ls2] would have been another valid choice.  The choice has a critical effect on reduction behavior, as these two examples illustrate: *)

Eval compute in fun ls => addLists nil ls.
(** %\vspace{-.15in}%[[
     = fun _ : list nat => nil
]]
*)

Eval compute in fun ls => addLists ls nil.
(** %\vspace{-.15in}%[[
     = fun ls : list nat =>
       (fix addLists (ls1 ls2 : list nat) : list nat :=
          match ls1 with
          | nil => nil
          | n1 :: ls1' =>
              match ls2 with
              | nil => nil
              | n2 :: ls2' =>
                  (fix plus (n m : nat) : nat :=
                     match n with
                     | 0 => m
                     | S p => S (plus p m)
                     end) n1 n2 :: addLists ls1' ls2'
              end
          end) ls nil
]]

The outer application of the [fix] expression for [addList] was only simplified in the first case, because in the second case the recursive argument is [ls], whose top-level structure is not known.

The opposite behavior pertains to a version of [addList] with [ls2] marked as recursive. *)

Fixpoint addLists' (ls1 ls2 : list nat) {struct ls2} : list nat :=
  match ls1, ls2 with
    | n1 :: ls1' , n2 :: ls2' => n1 + n2 :: addLists' ls1' ls2'
    | _, _ => nil
  end.

Eval compute in fun ls => addLists' ls nil.
(** %\vspace{-.15in}%[[
     = fun ls : list nat => match ls with
                            | nil => nil
                            | _ :: _ => nil
                            end
]]

We see that all use of recursive functions has been eliminated, though the term has not quite simplified to [nil].  We could get it to do so by switching the order of the [match] discriminees in the definition of [addLists'].

Recall that co-recursive definitions have a dual rule: a co-recursive call only simplifies when it is the discriminee of a [match].  This condition is built into the beta rule for %\index{Gallina terms!cofix}%[cofix], the anonymous form of [CoFixpoint].

%\medskip%

   The standard [eq] relation is critically dependent on the definitional equality.  The relation [eq] is often called a %\index{propositional equality}\textit{%#<i>#propositional equality#</i>#%}%, because it reifies definitional equality as a proposition that may or may not hold.  Standard axiomatizations of an equality predicate in first-order logic define equality in terms of properties it has, like reflexivity, symmetry, and transitivity.  In contrast, for [eq] in Coq, those properties are implicit in the properties of the definitional equality, which are built into CIC's metatheory and the implementation of Gallina.  We could add new rules to the definitional equality, and [eq] would keep its definition and methods of use.

   This all may make it sound like the choice of [eq]'s definition is unimportant.  To the contrary, in this chapter, we will see examples where alternate definitions may simplify proofs.  Before that point, I will introduce proof methods for goals that use proofs of the standard propositional equality %``%#"#as data.#"#%''% *)


(** * Heterogeneous Lists Revisited *)

(** One of our example dependent data structures from the last chapter was heterogeneous lists and their associated %``%#"#cursor#"#%''% type.  The recursive version poses some special challenges related to equality proofs, since it uses such proofs in its definition of [member] types. *)

Section fhlist.
  Variable A : Type.
  Variable B : A -> Type.

  Fixpoint fhlist (ls : list A) : Type :=
    match ls with
      | nil => unit
      | x :: ls' => B x * fhlist ls'
    end%type.

  Variable elm : A.

  Fixpoint fmember (ls : list A) : Type :=
    match ls with
      | nil => Empty_set
      | x :: ls' => (x = elm) + fmember ls'
    end%type.

  Fixpoint fhget (ls : list A) : fhlist ls -> fmember ls -> B elm :=
    match ls return fhlist ls -> fmember ls -> B elm with
      | nil => fun _ idx => match idx with end
      | _ :: ls' => fun mls idx =>
        match idx with
          | inl pf => match pf with
                        | refl_equal => fst mls
                      end
          | inr idx' => fhget ls' (snd mls) idx'
        end
    end.
End fhlist.

Implicit Arguments fhget [A B elm ls].

(** We can define a [map]-like function for [fhlist]s. *)

Section fhlist_map.
  Variables A : Type.
  Variables B C : A -> Type.
  Variable f : forall x, B x -> C x.

  Fixpoint fhmap (ls : list A) : fhlist B ls -> fhlist C ls :=
    match ls return fhlist B ls -> fhlist C ls with
      | nil => fun _ => tt
      | _ :: _ => fun hls => (f (fst hls), fhmap _ (snd hls))
    end.

  Implicit Arguments fhmap [ls].

  (** For the inductive versions of the [ilist] definitions, we proved a lemma about the interaction of [get] and [imap].  It was a strategic choice not to attempt such a proof for the definitions that we just gave, because that sets us on a collision course with the problems that are the subject of this chapter. *)

  Variable elm : A.

  Theorem get_imap : forall ls (mem : fmember elm ls) (hls : fhlist B ls),
    fhget (fhmap hls) mem = f (fhget hls mem).
(* begin hide *)
    induction ls; crush; case a0; reflexivity.
(* end hide *)
    (** %\vspace{-.2in}%[[
    induction ls; crush.
    ]]

    %\vspace{-.15in}%In Coq 8.2, one subgoal remains at this point.  Coq 8.3 has added some tactic improvements that enable [crush] to complete all of both inductive cases.  To introduce the basics of reasoning about equality, it will be useful to review what was necessary in Coq 8.2.

       Part of our single remaining subgoal is:
       [[
  a0 : a = elm
  ============================
   match a0 in (_ = a2) return (C a2) with
   | refl_equal => f a1
   end = f match a0 in (_ = a2) return (B a2) with
           | refl_equal => a1
           end
       ]]

   This seems like a trivial enough obligation.  The equality proof [a0] must be [refl_equal], since that is the only constructor of [eq].  Therefore, both the [match]es reduce to the point where the conclusion follows by reflexivity.
    [[
    destruct a0.
]]

<<
User error: Cannot solve a second-order unification problem
>>

    This is one of Coq's standard error messages for informing us that its heuristics for attempting an instance of an undecidable problem about dependent typing have failed.  We might try to nudge things in the right direction by stating the lemma that we believe makes the conclusion trivial.
    [[
    assert (a0 = refl_equal _).
]]

<<
The term "refl_equal ?98" has type "?98 = ?98"
 while it is expected to have type "a = elm"
>>

    In retrospect, the problem is not so hard to see.  Reflexivity proofs only show [x = x] for particular values of [x], whereas here we are thinking in terms of a proof of [a = elm], where the two sides of the equality are not equal syntactically.  Thus, the essential lemma we need does not even type-check!

    Is it time to throw in the towel?  Luckily, the answer is %``%#"#no.#"#%''%  In this chapter, we will see several useful patterns for proving obligations like this.

    For this particular example, the solution is surprisingly straightforward.  [destruct] has a simpler sibling [case] which should behave identically for any inductive type with one constructor of no arguments.
    [[
    case a0.

  ============================
   f a1 = f a1
   ]]

    It seems that [destruct] was trying to be too smart for its own good.
    [[
    reflexivity.
    ]]
    %\vspace{-.2in}% *)
  Qed.
(* end thide *)

  (** It will be helpful to examine the proof terms generated by this sort of strategy.  A simpler example illustrates what is going on. *)

  Lemma lemma1 : forall x (pf : x = elm), O = match pf with refl_equal => O end.
(* begin thide *)
    simple destruct pf; reflexivity.
  Qed.
(* end thide *)

  (** The tactic %\index{tactics!simple destruct}%[simple destruct pf] is a convenient form for applying [case].  It runs [intro] to bring into scope all quantified variables up to its argument. *)

  Print lemma1.
  (** %\vspace{-.15in}% [[
lemma1 = 
fun (x : A) (pf : x = elm) =>
match pf as e in (_ = y) return (0 = match e with
                                     | refl_equal => 0
                                     end) with
| refl_equal => refl_equal 0
end
     : forall (x : A) (pf : x = elm), 0 = match pf with
                                          | refl_equal => 0
                                          end
 
    ]]

    Using what we know about shorthands for [match] annotations, we can write this proof in shorter form manually. *)

(* begin thide *)
  Definition lemma1' :=
    fun (x : A) (pf : x = elm) =>
      match pf return (0 = match pf with
                             | refl_equal => 0
                           end) with
        | refl_equal => refl_equal 0
      end.
(* end thide *)

  (** Surprisingly, what seems at first like a %\textit{%#<i>#simpler#</i>#%}% lemma is harder to prove. *)

  Lemma lemma2 : forall (x : A) (pf : x = x), O = match pf with refl_equal => O end.
(* begin thide *)
    (** %\vspace{-.25in}%[[
    simple destruct pf.
]]

<<
User error: Cannot solve a second-order unification problem
>>
      *)
  Abort.

  (** Nonetheless, we can adapt the last manual proof to handle this theorem. *)

(* begin thide *)
  Definition lemma2 :=
    fun (x : A) (pf : x = x) =>
      match pf return (0 = match pf with
                             | refl_equal => 0
                           end) with
        | refl_equal => refl_equal 0
      end.
(* end thide *)

  (** We can try to prove a lemma that would simplify proofs of many facts like [lemma2]: *)

  Lemma lemma3 : forall (x : A) (pf : x = x), pf = refl_equal x.
(* begin thide *)
    (** %\vspace{-.25in}%[[
    simple destruct pf.
]]

<<
User error: Cannot solve a second-order unification problem
>>
      %\vspace{-.15in}%*)

  Abort.

  (** This time, even our manual attempt fails.
     [[
  Definition lemma3' :=
    fun (x : A) (pf : x = x) =>
      match pf as pf' in (_ = x') return (pf' = refl_equal x') with
        | refl_equal => refl_equal _
      end.
]]

<<
The term "refl_equal x'" has type "x' = x'" while it is expected to have type
 "x = x'"
>>

     The type error comes from our [return] annotation.  In that annotation, the [as]-bound variable [pf'] has type [x = x'], referring to the [in]-bound variable [x'].  To do a dependent [match], we %\textit{%#<i>#must#</i>#%}% choose a fresh name for the second argument of [eq].  We are just as constrained to use the %``%#"#real#"#%''% value [x] for the first argument.  Thus, within the [return] clause, the proof we are matching on %\textit{%#<i>#must#</i>#%}% equate two non-matching terms, which makes it impossible to equate that proof with reflexivity.

     Nonetheless, it turns out that, with one catch, we %\textit{%#<i>#can#</i>#%}% prove this lemma. *)

  Lemma lemma3 : forall (x : A) (pf : x = x), pf = refl_equal x.
    intros; apply UIP_refl.
  Qed.

  Check UIP_refl.
  (** %\vspace{-.15in}% [[
UIP_refl
     : forall (U : Type) (x : U) (p : x = x), p = refl_equal x
     ]]

     The theorem %\index{Gallina terms!UIP\_refl}%[UIP_refl] comes from the [Eqdep] module of the standard library.  Do the Coq authors know of some clever trick for building such proofs that we have not seen yet?  If they do, they did not use it for this proof.  Rather, the proof is based on an %\textit{%#<i>#axiom#</i>#%}%. *)

  Print eq_rect_eq.
  (** %\vspace{-.15in}% [[
eq_rect_eq = 
fun U : Type => Eq_rect_eq.eq_rect_eq U
     : forall (U : Type) (p : U) (Q : U -> Type) (x : Q p) (h : p = p),
       x = eq_rect p Q x p h
      ]]

      The axiom %\index{Gallina terms!eq\_rect\_eq}%[eq_rect_eq] states a %``%#"#fact#"#%''% that seems like common sense, once the notation is deciphered.  The term [eq_rect] is the automatically generated recursion principle for [eq].  Calling [eq_rect] is another way of [match]ing on an equality proof.  The proof we match on is the argument [h], and [x] is the body of the [match].  The statement of [eq_rect_eq] just says that [match]es on proofs of [p = p], for any [p], are superfluous and may be removed.  We can see this intuition better in code by asking Coq to simplify the theorem statement with the [compute] reduction strategy (which, by the way, applies all applicable rules of the definitional equality presented in this chapter's first section). *)

  Eval compute in (forall (U : Type) (p : U) (Q : U -> Type) (x : Q p) (h : p = p),
    x = eq_rect p Q x p h).
  (** %\vspace{-.15in}%[[
     = forall (U : Type) (p : U) (Q : U -> Type) (x : Q p) (h : p = p),
       x = match h in (_ = y) return (Q y) with
           | eq_refl => x
           end
     ]]

     Perhaps surprisingly, we cannot prove [eq_rect_eq] from within Coq.  This proposition is introduced as an %\index{axioms}%axiom; that is, a proposition asserted as true without proof.  We cannot assert just any statement without proof.  Adding [False] as an axiom would allow us to prove any proposition, for instance, defeating the point of using a proof assistant.  In general, we need to be sure that we never assert %\textit{%#<i>#inconsistent#</i>#%}% sets of axioms.  A set of axioms is inconsistent if its conjunction implies [False].  For the case of [eq_rect_eq], consistency has been verified outside of Coq via %``%#"#informal#"#%''% metatheory%~\cite{AxiomK}%, in a study that also established unprovability of the axiom in CIC.

      This axiom is equivalent to another that is more commonly known and mentioned in type theory circles. *)

  Print Streicher_K.
(* end thide *)
(** %\vspace{-.15in}% [[
Streicher_K = 
fun U : Type => UIP_refl__Streicher_K U (UIP_refl U)
     : forall (U : Type) (x : U) (P : x = x -> Prop),
       P (refl_equal x) -> forall p : x = x, P p
  ]]

  This is the unfortunately named %\index{axiom K}``%#"#Streicher's axiom K,#"#%''% which says that a predicate on properly typed equality proofs holds of all such proofs if it holds of reflexivity. *)

End fhlist_map.

(** It is worth remarking that it is possible to avoid axioms altogether for equalities on types with decidable equality.  The [Eqdep_dec] module of the standard library contains a parametric proof of [UIP_refl] for such cases.  To simplify presentation, we will stick with the axiom version in the rest of this chapter. *)


(** * Type-Casts in Theorem Statements *)

(** Sometimes we need to use tricks with equality just to state the theorems that we care about.  To illustrate, we start by defining a concatenation function for [fhlist]s. *)

Section fhapp.
  Variable A : Type.
  Variable B : A -> Type.

  Fixpoint fhapp (ls1 ls2 : list A)
    : fhlist B ls1 -> fhlist B ls2 -> fhlist B (ls1 ++ ls2) :=
    match ls1 with
      | nil => fun _ hls2 => hls2
      | _ :: _ => fun hls1 hls2 => (fst hls1, fhapp _ _ (snd hls1) hls2)
    end.

  Implicit Arguments fhapp [ls1 ls2].

  (* EX: Prove that fhapp is associative. *)
(* begin thide *)

  (** We might like to prove that [fhapp] is associative.
     [[
  Theorem fhapp_ass : forall ls1 ls2 ls3
    (hls1 : fhlist B ls1) (hls2 : fhlist B ls2) (hls3 : fhlist B ls3),
    fhapp hls1 (fhapp hls2 hls3) = fhapp (fhapp hls1 hls2) hls3.
]]

<<
The term
 "fhapp (ls1:=ls1 ++ ls2) (ls2:=ls3) (fhapp (ls1:=ls1) (ls2:=ls2) hls1 hls2)
    hls3" has type "fhlist B ((ls1 ++ ls2) ++ ls3)"
 while it is expected to have type "fhlist B (ls1 ++ ls2 ++ ls3)"
>>

     This first cut at the theorem statement does not even type-check.  We know that the two [fhlist] types appearing in the error message are always equal, by associativity of normal list append, but this fact is not apparent to the type checker.  This stems from the fact that Coq's equality is %\index{intensional type theory}\textit{%#<i>#intensional#</i>#%}%, in the sense that type equality theorems can never be applied after the fact to get a term to type-check.  Instead, we need to make use of equality explicitly in the theorem statement. *)

  Theorem fhapp_ass : forall ls1 ls2 ls3
    (pf : (ls1 ++ ls2) ++ ls3 = ls1 ++ (ls2 ++ ls3))
    (hls1 : fhlist B ls1) (hls2 : fhlist B ls2) (hls3 : fhlist B ls3),
    fhapp hls1 (fhapp hls2 hls3)
    = match pf in (_ = ls) return fhlist _ ls with
        | refl_equal => fhapp (fhapp hls1 hls2) hls3
      end.
    induction ls1; crush.

    (** The first remaining subgoal looks trivial enough:
       [[
  ============================
   fhapp (ls1:=ls2) (ls2:=ls3) hls2 hls3 =
   match pf in (_ = ls) return (fhlist B ls) with
   | refl_equal => fhapp (ls1:=ls2) (ls2:=ls3) hls2 hls3
   end
       ]]

       We can try what worked in previous examples.
       [[
    case pf.
]]

<<
User error: Cannot solve a second-order unification problem
>>

        It seems we have reached another case where it is unclear how to use a dependent [match] to implement case analysis on our proof.  The [UIP_refl] theorem can come to our rescue again. *)

    rewrite (UIP_refl _ _ pf).
    (** [[
  ============================
   fhapp (ls1:=ls2) (ls2:=ls3) hls2 hls3 =
   fhapp (ls1:=ls2) (ls2:=ls3) hls2 hls3
        ]]
        *)

    reflexivity.

    (** Our second subgoal is trickier.
       [[
  pf : a :: (ls1 ++ ls2) ++ ls3 = a :: ls1 ++ ls2 ++ ls3
  ============================
   (a0,
   fhapp (ls1:=ls1) (ls2:=ls2 ++ ls3) b
     (fhapp (ls1:=ls2) (ls2:=ls3) hls2 hls3)) =
   match pf in (_ = ls) return (fhlist B ls) with
   | refl_equal =>
       (a0,
       fhapp (ls1:=ls1 ++ ls2) (ls2:=ls3)
         (fhapp (ls1:=ls1) (ls2:=ls2) b hls2) hls3)
   end

    rewrite (UIP_refl _ _ pf).
]]

<<
The term "pf" has type "a :: (ls1 ++ ls2) ++ ls3 = a :: ls1 ++ ls2 ++ ls3"
 while it is expected to have type "?556 = ?556"
>>

       We can only apply [UIP_refl] on proofs of equality with syntactically equal operands, which is not the case of [pf] here.  We will need to manipulate the form of this subgoal to get us to a point where we may use [UIP_refl].  A first step is obtaining a proof suitable to use in applying the induction hypothesis.  Inversion on the structure of [pf] is sufficient for that. *)

    injection pf; intro pf'.
    (** [[
  pf : a :: (ls1 ++ ls2) ++ ls3 = a :: ls1 ++ ls2 ++ ls3
  pf' : (ls1 ++ ls2) ++ ls3 = ls1 ++ ls2 ++ ls3
  ============================
   (a0,
   fhapp (ls1:=ls1) (ls2:=ls2 ++ ls3) b
     (fhapp (ls1:=ls2) (ls2:=ls3) hls2 hls3)) =
   match pf in (_ = ls) return (fhlist B ls) with
   | refl_equal =>
       (a0,
       fhapp (ls1:=ls1 ++ ls2) (ls2:=ls3)
         (fhapp (ls1:=ls1) (ls2:=ls2) b hls2) hls3)
   end
   ]]

   Now we can rewrite using the inductive hypothesis. *)

    rewrite (IHls1 _ _ pf').
    (** [[
  ============================
   (a0,
   match pf' in (_ = ls) return (fhlist B ls) with
   | refl_equal =>
       fhapp (ls1:=ls1 ++ ls2) (ls2:=ls3)
         (fhapp (ls1:=ls1) (ls2:=ls2) b hls2) hls3
   end) =
   match pf in (_ = ls) return (fhlist B ls) with
   | refl_equal =>
       (a0,
       fhapp (ls1:=ls1 ++ ls2) (ls2:=ls3)
         (fhapp (ls1:=ls1) (ls2:=ls2) b hls2) hls3)
   end
        ]]

        We have made an important bit of progress, as now only a single call to [fhapp] appears in the conclusion, repeated twice.  Trying case analysis on our proofs still will not work, but there is a move we can make to enable it.  Not only does just one call to [fhapp] matter to us now, but it also %\textit{%#<i>#does not matter what the result of the call is#</i>#%}%.  In other words, the subgoal should remain true if we replace this [fhapp] call with a fresh variable.  The %\index{tactics!generalize}%[generalize] tactic helps us do exactly that. *)

    generalize (fhapp (fhapp b hls2) hls3).
    (** [[
   forall f : fhlist B ((ls1 ++ ls2) ++ ls3),
   (a0,
   match pf' in (_ = ls) return (fhlist B ls) with
   | refl_equal => f
   end) =
   match pf in (_ = ls) return (fhlist B ls) with
   | refl_equal => (a0, f)
   end
        ]]

        The conclusion has gotten markedly simpler.  It seems counterintuitive that we can have an easier time of proving a more general theorem, but that is exactly the case here and for many other proofs that use dependent types heavily.  Speaking informally, the reason why this kind of activity helps is that [match] annotations only support variables in certain positions.  By reducing more elements of a goal to variables, built-in tactics can have more success building [match] terms under the hood.

        In this case, it is helpful to generalize over our two proofs as well. *)

    generalize pf pf'.
    (** [[
   forall (pf0 : a :: (ls1 ++ ls2) ++ ls3 = a :: ls1 ++ ls2 ++ ls3)
     (pf'0 : (ls1 ++ ls2) ++ ls3 = ls1 ++ ls2 ++ ls3)
     (f : fhlist B ((ls1 ++ ls2) ++ ls3)),
   (a0,
   match pf'0 in (_ = ls) return (fhlist B ls) with
   | refl_equal => f
   end) =
   match pf0 in (_ = ls) return (fhlist B ls) with
   | refl_equal => (a0, f)
   end
        ]]

        To an experienced dependent types hacker, the appearance of this goal term calls for a celebration.  The formula has a critical property that indicates that our problems are over.  To get our proofs into the right form to apply [UIP_refl], we need to use associativity of list append to rewrite their types.  We could not do that before because other parts of the goal require the proofs to retain their original types.  In particular, the call to [fhapp] that we generalized must have type [(ls1 ++ ls2) ++ ls3], for some values of the list variables.  If we rewrite the type of the proof used to type-cast this value to something like [ls1 ++ ls2 ++ ls3 = ls1 ++ ls2 ++ ls3], then the lefthand side of the equality would no longer match the type of the term we are trying to cast.

        However, now that we have generalized over the [fhapp] call, the type of the term being type-cast appears explicitly in the goal and %\textit{%#<i>#may be rewritten as well#</i>#%}%.  In particular, the final masterstroke is rewriting everywhere in our goal using associativity of list append. *)

    rewrite app_ass.
    (** [[
  ============================
   forall (pf0 : a :: ls1 ++ ls2 ++ ls3 = a :: ls1 ++ ls2 ++ ls3)
     (pf'0 : ls1 ++ ls2 ++ ls3 = ls1 ++ ls2 ++ ls3)
     (f : fhlist B (ls1 ++ ls2 ++ ls3)),
   (a0,
   match pf'0 in (_ = ls) return (fhlist B ls) with
   | refl_equal => f
   end) =
   match pf0 in (_ = ls) return (fhlist B ls) with
   | refl_equal => (a0, f)
   end
        ]]

        We can see that we have achieved the crucial property: the type of each generalized equality proof has syntactically equal operands.  This makes it easy to finish the proof with [UIP_refl]. *)

    intros.
    rewrite (UIP_refl _ _ pf0).
    rewrite (UIP_refl _ _ pf'0).
    reflexivity.
  Qed.
(* end thide *)
End fhapp.

Implicit Arguments fhapp [A B ls1 ls2].

(** This proof strategy was cumbersome and unorthodox, from the perspective of mainstream mathematics.  The next section explores an alternative that leads to simpler developments in some cases. *)


(** * Heterogeneous Equality *)

(** There is another equality predicate, defined in the %\index{Gallina terms!JMeq}%[JMeq] module of the standard library, implementing %\index{heterogeneous equality}\textit{%#<i>#heterogeneous equality#</i>#%}%. *)

Print JMeq.
(** %\vspace{-.15in}% [[
Inductive JMeq (A : Type) (x : A) : forall B : Type, B -> Prop :=
    JMeq_refl : JMeq x x
    ]]

The identity [JMeq] stands for %\index{John Major equality}``%#"#John Major equality,#"#%''% a name coined by Conor McBride%~\cite{JMeq}% as a sort of pun about British politics.  [JMeq] starts out looking a lot like [eq].  The crucial difference is that we may use [JMeq] %\textit{%#<i>#on arguments of different types#</i>#%}%.  For instance, a lemma that we failed to establish before is trivial with [JMeq].  It makes for prettier theorem statements to define some syntactic shorthand first. *)

Infix "==" := JMeq (at level 70, no associativity).

(* EX: Prove UIP_refl' : forall (A : Type) (x : A) (pf : x = x), pf == refl_equal x *)
(* begin thide *)
Definition UIP_refl' (A : Type) (x : A) (pf : x = x) : pf == refl_equal x :=
  match pf return (pf == refl_equal _) with
    | refl_equal => JMeq_refl _
  end.
(* end thide *)

(** There is no quick way to write such a proof by tactics, but the underlying proof term that we want is trivial.

   Suppose that we want to use [UIP_refl'] to establish another lemma of the kind we have run into several times so far. *)

Lemma lemma4 : forall (A : Type) (x : A) (pf : x = x),
  O = match pf with refl_equal => O end.
(* begin thide *)
  intros; rewrite (UIP_refl' pf); reflexivity.
Qed.
(* end thide *)

(** All in all, refreshingly straightforward, but there really is no such thing as a free lunch.  The use of [rewrite] is implemented in terms of an axiom: *)

Check JMeq_eq.
(** %\vspace{-.15in}% [[
JMeq_eq
     : forall (A : Type) (x y : A), x == y -> x = y
    ]]

    It may be surprising that we cannot prove that heterogeneous equality implies normal equality.  The difficulties are the same kind we have seen so far, based on limitations of [match] annotations.

   We can redo our [fhapp] associativity proof based around [JMeq]. *)

Section fhapp'.
  Variable A : Type.
  Variable B : A -> Type.

  (** This time, the naive theorem statement type-checks. *)

  (* EX: Prove [fhapp] associativity using [JMeq]. *)

(* begin thide *)
  Theorem fhapp_ass' : forall ls1 ls2 ls3 (hls1 : fhlist B ls1) (hls2 : fhlist B ls2)
    (hls3 : fhlist B ls3),
    fhapp hls1 (fhapp hls2 hls3) == fhapp (fhapp hls1 hls2) hls3.
    induction ls1; crush.

    (** Even better, [crush] discharges the first subgoal automatically.  The second subgoal is:
       [[
  ============================
   (a0, fhapp b (fhapp hls2 hls3)) == (a0, fhapp (fhapp b hls2) hls3)
       ]]

       It looks like one rewrite with the inductive hypothesis should be enough to make the goal trivial.  Here is what happens when we try that in Coq 8.2:
       [[
    rewrite IHls1.
]]

<<
Error: Impossible to unify "fhlist B ((ls1 ++ ?1572) ++ ?1573)" with
 "fhlist B (ls1 ++ ?1572 ++ ?1573)"
>>

       Coq 8.3 currently gives an error message about an uncaught exception.  Perhaps that will be fixed soon.  In any case, it is educational to consider a more explicit approach.

       We see that [JMeq] is not a silver bullet.  We can use it to simplify the statements of equality facts, but the Coq type-checker uses non-trivial heterogeneous equality facts no more readily than it uses standard equality facts.  Here, the problem is that the form [(e1, e2)] is syntactic sugar for an explicit application of a constructor of an inductive type.  That application mentions the type of each tuple element explicitly, and our [rewrite] tries to change one of those elements without updating the corresponding type argument.

       We can get around this problem by another multiple use of [generalize].  We want to bring into the goal the proper instance of the inductive hypothesis, and we also want to generalize the two relevant uses of [fhapp]. *)

    generalize (fhapp b (fhapp hls2 hls3))
      (fhapp (fhapp b hls2) hls3)
      (IHls1 _ _ b hls2 hls3).
    (** %\vspace{-.15in}%[[
  ============================
   forall (f : fhlist B (ls1 ++ ls2 ++ ls3))
     (f0 : fhlist B ((ls1 ++ ls2) ++ ls3)), f == f0 -> (a0, f) == (a0, f0)
        ]]

        Now we can rewrite with append associativity, as before. *)

    rewrite app_ass.
    (** %\vspace{-.15in}%[[
  ============================
   forall f f0 : fhlist B (ls1 ++ ls2 ++ ls3), f == f0 -> (a0, f) == (a0, f0)
       ]]

       From this point, the goal is trivial. *)

    intros f f0 H; rewrite H; reflexivity.
  Qed.
(* end thide *)
End fhapp'.

(** This example illustrates a general pattern: heterogeneous equality often simplifies theorem statements, but we still need to do some work to line up some dependent pattern matches that tactics will generate for us. *)


(** * Equivalence of Equality Axioms *)

(* EX: Show that the approaches based on K and JMeq are equivalent logically. *)

(* begin thide *)
(** Assuming axioms (like axiom K and [JMeq_eq]) is a hazardous business.  The due diligence associated with it is necessarily global in scope, since two axioms may be consistent alone but inconsistent together.  It turns out that all of the major axioms proposed for reasoning about equality in Coq are logically equivalent, so that we only need to pick one to assert without proof.  In this section, we demonstrate this by showing how each of the previous two sections' approaches reduces to the other logically.

   To show that [JMeq] and its axiom let us prove [UIP_refl], we start from the lemma [UIP_refl'] from the previous section.  The rest of the proof is trivial. *)

Lemma UIP_refl'' : forall (A : Type) (x : A) (pf : x = x), pf = refl_equal x.
  intros; rewrite (UIP_refl' pf); reflexivity.
Qed.

(** The other direction is perhaps more interesting.  Assume that we only have the axiom of the [Eqdep] module available.  We can define [JMeq] in a way that satisfies the same interface as the combination of the [JMeq] module's inductive definition and axiom. *)

Definition JMeq' (A : Type) (x : A) (B : Type) (y : B) : Prop :=
  exists pf : B = A, x = match pf with refl_equal => y end.

Infix "===" := JMeq' (at level 70, no associativity).

(** We say that, by definition, [x] and [y] are equal if and only if there exists a proof [pf] that their types are equal, such that [x] equals the result of casting [y] with [pf].  This statement can look strange from the standpoint of classical math, where we almost never mention proofs explicitly with quantifiers in formulas, but it is perfectly legal Coq code.

   We can easily prove a theorem with the same type as that of the [JMeq_refl] constructor of [JMeq]. *)

(** remove printing exists *)
Theorem JMeq_refl' : forall (A : Type) (x : A), x === x.
  intros; unfold JMeq'; exists (refl_equal A); reflexivity.
Qed.

(** printing exists $\exists$ *)

(** The proof of an analogue to [JMeq_eq] is a little more interesting, but most of the action is in appealing to [UIP_refl]. *)

Theorem JMeq_eq' : forall (A : Type) (x y : A),
  x === y -> x = y.
  unfold JMeq'; intros.
  (** [[
  H : exists pf : A = A,
        x = match pf in (_ = T) return T with
            | refl_equal => y
            end
  ============================
   x = y
      ]]
      *)

  destruct H.
  (** [[
  x0 : A = A
  H : x = match x0 in (_ = T) return T with
          | refl_equal => y
          end
  ============================
   x = y
      ]]
      *)

  rewrite H.
  (** [[
  x0 : A = A
  ============================
   match x0 in (_ = T) return T with
   | refl_equal => y
   end = y
      ]]
      *)

  rewrite (UIP_refl _ _ x0); reflexivity.
Qed.

(** We see that, in a very formal sense, we are free to switch back and forth between the two styles of proofs about equality proofs.  One style may be more convenient than the other for some proofs, but we can always interconvert between our results.  The style that does not use heterogeneous equality may be preferable in cases where many results do not require the tricks of this chapter, since then the use of axioms is avoided altogether for the simple cases, and a wider audience will be able to follow those %``%#"#simple#"#%''% proofs.  On the other hand, heterogeneous equality often makes for shorter and more readable theorem statements. *)

(* end thide *)


(** * Equality of Functions *)

(** The following seems like a reasonable theorem to want to hold, and it does hold in set theory. [[
   Theorem S_eta : S = (fun n => S n).
   ]]

   Unfortunately, this theorem is not provable in CIC without additional axioms.  None of the definitional equality rules force function equality to be %\index{extensionality of function equality}\textit{%#<i>#extensional#</i>#%}%.  That is, the fact that two functions return equal results on equal inputs does not imply that the functions are equal.  We %\textit{%#<i>#can#</i>#%}% assert function extensionality as an axiom. *)

(* begin thide *)
Axiom ext_eq : forall A B (f g : A -> B),
  (forall x, f x = g x)
  -> f = g.
(* end thide *)

(** This axiom has been verified metatheoretically to be consistent with CIC and the two equality axioms we considered previously.  With it, the proof of [S_eta] is trivial. *)

Theorem S_eta : S = (fun n => S n).
(* begin thide *)
  apply ext_eq; reflexivity.
Qed.
(* end thide *)

(** The same axiom can help us prove equality of types, where we need to %``%#"#reason under quantifiers.#"#%''% *)

Theorem forall_eq : (forall x : nat, match x with
                                      | O => True
                                      | S _ => True
                                    end)
  = (forall _ : nat, True).

  (** There are no immediate opportunities to apply [ext_eq], but we can use %\index{tactics!change}%[change] to fix that. *)

(* begin thide *)
  change ((forall x : nat, (fun x => match x with
                                       | 0 => True
                                       | S _ => True
                                     end) x) = (nat -> True)).
  rewrite (ext_eq (fun x => match x with
                              | 0 => True
                              | S _ => True
                            end) (fun _ => True)).
  (** [[
2 subgoals
  
  ============================
   (nat -> True) = (nat -> True)

subgoal 2 is:
 forall x : nat, match x with
                 | 0 => True
                 | S _ => True
                 end = True
      ]]
      *)

  reflexivity.

  destruct x; constructor.
Qed.
(* end thide *)

(** Unlike in the case of [eq_rect_eq], we have no way of deriving this axiom of %\index{functional extensionality}\emph{%#<i>#functional extensionality#</i>#%}% for types with decidable equality.  To allow equality reasoning without axioms, it may be worth rewriting a development to replace functions with alternate representations, such as finite map types for which extensionality is derivable in CIC. *)
