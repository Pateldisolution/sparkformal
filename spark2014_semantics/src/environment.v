(** 
_AUTHOR_

<<
Zhi Zhang
Department of Computer and Information Sciences
Kansas State University
zhangzhi@ksu.edu
>>
*)

Require Import FunInd.
Require Export values.

(** for any valid variable x, it has an in/out mode, type and value 
    (either defined or undefined); as the in/out mode and type are
    invariant since the variable is declared, and they are used only
    at compile time, we keep these invariant information in a symbol 
    table called _symtb_; while the value of a variable will change 
    as the program executes, and it's used in run time evaluation, 
    so we keep this information in a store called _store_;
*)

(** * Store *)
(** it's a map from a variable, represented with natural number,
    to its value;
*)

Module Type ENTRY.
  Parameter T:Type.
End ENTRY.

Module STORE(V:ENTRY).

  Notation V:=V.T.

  Definition store : Type := list (idnum * V).

  (** ** Store Operation *)
  (** check whether variable x has already been declared *)
  Function resides (x : idnum) (s : store) := 
    match s with 
    | (y, v) :: s' =>
      if beq_nat x y then true else resides x s' 
    | nil => false
    end.

  (** fetch the value of x that has already been initialized in store *)
  Function fetches (x : idnum) (s : store): option V := 
    match s with 
    | (y, v) :: s' =>
      if beq_nat x y then Some v
      else fetches x s' 
    | nil => None
    end.

  (** [cut_to x s] return the pair (s',s'') where s = s' ++ s'' and s''
      starts with the first occurrence of [x] in [s]. If no occurrence
      of [x] exists in [s] then (nil,nil) is returned. *)
  Function cuts_to (x : idnum) (s : store): store*store := 
    match s with 
    | (y, v) :: s' =>
      (if beq_nat x y then (nil,s) 
       else let (l1,l2) := cuts_to x s' in
            (((y, v)::l1) , l2))
    | nil => (nil, nil)
    end.

  (** update the latest binding for x *)
  Function updates (s: store) (x : idnum) (v: V): option store := 
    match s with 
    | (y, v') :: s' => 
      if beq_nat x y then 
        Some ((y,v)::s') 
      else 
        match updates s' x v with
        | Some s'' => Some ((y,v')::s'')
        | None => None
        end
   | nil => None
   end.

  (** ** Lemmas About Store Operation *)

  Lemma updates_length: forall s x v s', 
    updates s x v = Some s' -> 
      List.length s = List.length s'.
  Proof.
    intros s x v.
    functional induction updates s x v;simpl
    ; intros updateds heq; inversion heq;clear heq
    ; subst;simpl;auto.
  Qed.


  (** * State *)

  (* The global state is a stack of stores. One store per procedure
     currently running. *)
  Definition scope_level := nat. (* the scope level of the declared procedure to be called *)

  Definition frame := prod scope_level store.
  
  Definition level_of (f: frame) := fst f.

  Definition store_of (f: frame) := snd f.
  
  Definition state := list frame.  



  Definition reside (x: idnum) (f: frame) := resides x (store_of f).

  Definition fetch (x: idnum) (f: frame) := fetches x (store_of f).
  
  Definition cut_to (x: idnum) (f: frame) := cuts_to x (store_of f).

  Function update (f: frame) (x: idnum) (v: V): option frame := 
    match updates (store_of f) x v with 
    | Some s => Some (level_of f, s)
    | None => None 
    end.
  
  Definition push (f: frame) (x: idnum) (v: V) := (level_of f, (x, v) :: (store_of f)).
  
  Definition newFrame (n: scope_level): frame := (n, nil). 


  (** ** State Operation *)

  Definition pushG x v (s: state) :=
    match s with
    | nil => None
    | f :: s' => Some ((push f x v) :: s')
    end.

  Function fetchG (x : idnum) (s : state) := 
    match s with 
    | f :: s' =>
      match fetch x f with
        | Some v => Some v
        | None => fetchG x s'
      end
    | nil => None
    end.

  Function updateG (s: state) (x: idnum) (v: V): option state := 
    match s with 
    | f :: s' =>
      match update f x v with
      | Some f' => Some (f' :: s')
      | None => match (updateG s' x v) with
                | Some s'' => Some (f :: s'')
                | None  => None
                end
      end
    | nil => None
    end.

  Function resideG (x : idnum) (s : state) := 
    match s with 
    | f :: s' =>
      if reside x f then
        true
      else 
        resideG x s' 
    | nil => false
    end.



  (* These three functions are used by Compcert compilation *)
  Function frameG (x : idnum) (s : state): option frame :=
    match s with
    | f :: s' => if reside x f then Some f
                 else frameG x s'
    | nil => None
    end.

  Definition pop_frame (s:state) : option frame :=
    match s with
      | nil => None
      | cons f _ => Some f
    end.

  Definition level_of_top (s:state): option scope_level :=
    match pop_frame  s with
      | Some (lvl,_) => Some lvl
      | None => None
    end.


  (** [cut_until s n s' s''] means cutting the state s until to a frame 
    whose corresponding procedure's nested declaration level is less 
    than n, and s' is a state with all its frame's corresponding procedure's 
    nested declaration level greater or equal n, and s'' is a state holds 
    frames whose procedure's nested declaration levels are less than n, 
    and s = s' ++ s'';
   *)
  Inductive cut_until: state -> scope_level -> state -> state -> Prop :=
  | Cut_Until_Nil: forall n,
      cut_until nil n nil nil
  | Cut_Until_Head: forall f n s,
      (level_of f) < n ->
      cut_until (f :: s) n nil (f :: s) 
  | Cut_Until_Tail: forall f n s s' s'',
      ~ (level_of f < n) ->
      cut_until s n s' s'' -> 
      cut_until (f :: s) n (f :: s') s''.

  Lemma cut_until_uniqueness: forall s n intact_s' s' intact_s'' s'',
      cut_until s n intact_s' s' ->
      cut_until s n intact_s'' s'' ->
      intact_s' = intact_s'' /\ s' = s''.
  Proof.
    intros s n intact_s' s' intact_s'' s'' H; revert intact_s'' s''.
    induction H; intros;
    match goal with
    | [H: cut_until nil _ _ _ |- _] => inversion H
    | [H: cut_until (?f :: ?s) _ _ _ |- _] => inversion H
    end; smack;
    specialize (IHcut_until _ _ H8); smack.
  Qed.

  Lemma cut_until_spec1:
    forall s pb_lvl s' s'' ,
      cut_until s pb_lvl s'  s''
      -> s' ++ s'' = s.
  Proof.
    intros s pb_lvl s' s'' H.
    induction H;auto.
    simpl.
    rewrite IHcut_until.
    reflexivity.
  Qed.

  Inductive stack_eq_length : state -> state -> Prop :=
    | eqnil: stack_eq_length nil nil
    | eqncons: forall s s' f f',
        stack_eq_length s s' ->
        List.length (store_of f) = List.length (store_of f') ->
        stack_eq_length (f :: s) (f' :: s').

  (** ** Lemmas About State Operation *)

  Lemma stack_eq_length_refl: forall s s', 
    s = s' -> 
      stack_eq_length s s'.
  Proof.
    intros s.
    induction s;intros s' heq.
    - subst.
      constructor.
    - subst.
      constructor.
      + apply IHs.
        reflexivity.
      + reflexivity.
  Qed.

  Require Import Setoid.
  Require Import Morphisms.

  Lemma stack_eq_length_refl2: reflexive _ stack_eq_length.
  Proof.
    hnf.
    intros x.
    apply stack_eq_length_refl.
    reflexivity.
  Qed.

  Lemma stack_eq_length_sym: forall s s', 
    stack_eq_length s s' -> 
      stack_eq_length s' s.
  Proof.
    intros s.
    induction s;intros s' heq.
    - inversion heq.
      constructor.
    - inversion heq.
      constructor.
      + apply IHs.
        assumption.
      + symmetry.
        assumption.
  Qed.

  Lemma stack_eq_length_trans: forall s' s s'',
    stack_eq_length s s' ->
      stack_eq_length s' s'' -> 
        stack_eq_length s s''.
  Proof.
    intros s'.
    induction s';intros s s'' heq1 heq2
    ; try now (inversion heq1; inversion heq2;subst;constructor).
    inversion heq1.
    inversion heq2.
    subst.
    constructor.
    + apply IHs' ;assumption.
    + transitivity (List.length (store_of a));auto.
  Qed.

  Lemma stack_eq_length_trans2: transitive _ stack_eq_length.
  Proof.
    hnf.
    intros x y z H H0.
    apply stack_eq_length_trans with (s':= y);auto.
  Qed.

  Add Parametric Relation: state stack_eq_length
      reflexivity proved by stack_eq_length_refl2
      symmetry proved by stack_eq_length_sym
      transitivity proved by stack_eq_length_trans2
        as stack_eq_length_equiv_rel.

  Add Parametric Morphism: (@List.app frame)
      with signature stack_eq_length ==> stack_eq_length ==> stack_eq_length
        as app_morph_stack_eq_length.
  Proof.
    intros x y H.
    induction H;simpl;intros.
    - assumption.
    - constructor 2.
      + apply IHstack_eq_length.
        assumption.
      + assumption.
  Qed.

  Lemma updateG_length: forall s x v s', 
    updateG s x v = Some s' -> 
      List.length s = List.length s'.
  Proof.
    intros s x v.
    functional induction updateG s x v;simpl
    ; intros updateds heq; inversion heq;clear heq
    ; subst;simpl;auto.
  Qed.

End STORE.

