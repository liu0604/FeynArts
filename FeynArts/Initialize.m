(*
	Initialize.m
		Functions for the initialization of models
		last modified 21 Apr 00 th
*)

Begin["`Initialize`"]

(* InitializeModel.

   The functions defined for a certain model are:
	F$AllGeneric:		all generic fields
	F$AllClasses:		all classes of the model
	F$AllParticles:		all particles of the model
   These lists are static for the initialized model. For InsertFields
   the following lists are also used; they might be changed by the
   function RestrictCurrentModel:
	F$Generic:		currently used generic fields
	F$Classes:		currently used classes
	F$Particles:		currently used particles
	F$AllowedFields:	all used fields
   For the construction of the couplings the following lists are defined:
	FieldPoints[0, 1, 2, ...]
	ReferenceOrder[Generic | Classes]
   Furthermore, InitializeModel defines the functions
	PossibleFields	-> fields `fitting' on a half-filled vertex
	CheckFieldPoint	-> is this vertex in the current model?
	AnalyticalCoupling	-> analytical expression for a coupling
	AnalyticalPropagator	-> ditto for propagators
   InitializeModel also sets the functions that return certain
   properties of the fields like
	AntiParticle, Indices, SelfConjugate, TheMass, TheLabel, etc.

   There are two restrictions on entering the model file:
   a) the coupling definitions in the classes model file have to be made
      with classes couplings of the same ordering as in the generic
      coupling definition.
   b) the FermionFlipRules have to match the field positions of the
      fermionic fields of the generic coupling (it is thus safest to
      keep the fermions in front for this).
*)


Attributes[ FieldPoint ] = {Orderless}


Options[ InitializeModel ] = {
  GenericModel -> "Lorentz",
  Reinitialize -> True
}

InsertFields::modspec =
"Invalid model specification `1`."

InitializeModel::norange =
"Index `1` has no IndexRange specification."

InitializeModel::incomp1 =
"Coupling definition in model file for `1` is incompatible to generic
coupling structure. Coupling is not a vector of length `2`."

InitializeModel::incomp2 =
"Incompatible index structure in classes coupling `1`. Field `2`
needs `3` indices, not `4`."

InitializeModel::nogeneric =
"Warning: Classes coupling `1` matches no generic coupling."

InitializeModel::rhs1 =
"R.h.s. of generic coupling `1` has G-expressions inside the
kinematic vector."

InitializeModel::rhs2 =
"Generic coupling `1` is not of the form
AnalyticalCoupling[__] == G[_][__] . {__}."

InitializeModel::badrestr =
"Warning: `1` is not a valid model restriction."

InitializeModel::nosymb =
"Cannot properly analyze the field specification `1`. Either the
overall format is wrong, or it contains symbols that were already
assigned values somewhere in your model file (most often \"i\" or \"j\").
Please check your generic model file and try again."

InitializeModel[ model_?AtomQ, options___Rule ] :=
Block[ {filelist, reini, genmod, mod = ToString[model],
opt = ActualOptions[InitializeModel, options]},

  reini = TrueQ[Reinitialize /. opt];
  genmod = ToString[GenericModel /. opt];
  If[ reini || genmod =!= $GenericModel, InitGenericModel[genmod] ];
  If[ reini || mod =!= $Model, InitClassesModel[mod] ];
  True
]

InitializeModel[ mod_, ___Rule ] :=
  (Message[InsertFields::modspec, mod]; Abort[])


(* initializing a generic model: *)

InitGenericModel[ genmod_ ] :=
Block[ {savecp = $ContextPath, file = $ModelDir <> genmod <> ".gen"},

	(* no Global symbols allowed for these operations *)
  $ContextPath = DeleteCases[$ContextPath, "Global`"];
  $GenericModel = $Model = "";

  FAPrint[2, ""];
  FAPrint[2, "initializing generic model file ", file];
  Clear[ AnalyticalPropagator, AnalyticalCoupling,
    ReferenceCoupling, CouplingVector,
    PossibleFields, CheckFieldPoint, Combinations,
    Compatibles, MixingPartners, M$FermionFlipRule ];
  $ExcludedFPs = $ExcludedParticleFPs = {};
  M$TruncationRules = M$LastGenericRules = {};
  Off[Syntax::newl, Syntax::com]; 
  If[ Get[file] === $Failed, Abort[] ];
  On[Syntax::newl, Syntax::com];

  ReferenceOrder[Generic] =
    Union[ ToGeneric[(List@@ #[[1]])&/@ M$GenericCouplings] ];
  GenericFieldPoints[] = (FieldPoint@@ #)&/@ ReferenceOrder[Generic];
  Scan[ BuildCombinations, Union[Length/@ ReferenceOrder[Generic]] ];

  F$Generic = Union[ ToGeneric[#[[1, 1]]&/@ M$GenericPropagators] ];
  If[ $SVMixing && !FreeQ[F$Generic, SV],
    FAPrint[2, "> $SVMixing is ON"];
    MixingPartners[ SV ] = {S, V};
    MixingPartners[ VS ] = {V, S};
    Compatibles[ S ] = {S, VS};
    Compatibles[ V ] = {V, SV};
    AppendTo[F$Generic, VS],
  (* else *)
    FAPrint[2, "> $SVMixing is OFF"]
  ];
  F$AllGeneric = F$Generic;
  MixingPartners[ p_ ] = {p};
  Compatibles[ p_ ] = {p};
  SVCompatibles[ _ ] = {};

  Apply[ (CheckFieldPoint[ FieldPoint[_][##] ] = True)&,
    GenericFieldPoints[], 1 ];
	(* CheckFieldPoint must yield True in cases where some part
	   of the vertex is yet unknown, e.g. FieldPoint[0, V, V, V] *)
  CheckFieldPoint[ fp_ ] :=
    MemberQ[fp, 0] || !FreeQ[fp, Field] ||
      Length[Union[AtomQ/@ fp]] =!= 1;

  M$FermionFlipRule[ __ ] = {};

  PossibleFields[_][ __ ] = {};
  SetPossibleFields[_, Table[0, {Length[#]}]&, GenericFieldPoints[]];

  (SetDelayed@@ {PropFieldPattern/@ #[[1]], PV[ #[[2]] ]})&/@
    M$GenericPropagators;
  InitGenericCoupling/@ M$GenericCouplings;

  $ContextPath = savecp;
  $GenericModel = genmod;
  FAPrint[1, "generic model ", genmod, " initialized"];
]


(* BuildCombinations generates all combinations of valence 
   configurations of a vertex with n legs, e.g.
	Combinations[{f1_, f2_}, {h1_, h2_}] :=
	  { {{h1, FieldPoint[h1, f2]}, f1},
	    {{h2, FieldPoint[f1, h2]}, f2},
	    {{h1, FieldPoint[h1, h2]}, f1},
	    {{h2, FieldPoint[h1, h2]}, f2} }
   The first line is interpreted as: for the vertex FieldPoint[h1, f2] 
   where h1 is a `wildcard' (0 or a Generic field), f1 is a possible 
   field to insert. *)

BuildCombinations[ n_ ] := 
Block[ {f, h, i, v},
  f = Array[ToExpression["f" <> ToString[#]]&, n];
  h = Array[ToExpression["h" <> ToString[#]]&, n];
  SetDelayed@@
    { Combinations[Pattern[#, _]&/@ f, Pattern[#, _]&/@ h],
      Flatten[ Table[
        (v = f; Scan[(v[[#]] = h[[#]])&, #];
          { {h[[#]], FieldPoint@@ v}, f[[#]] }&/@ #)&/@ TakeOut[i, n],
        {i, n} ], 2 ] }
]


(* TakeOut[m, n] returns all possible m-tuples that can be constructed 
   from an n-tuple *)

TakeOut[ 1, n_ ] := Array[List, n]

TakeOut[ m_, n_ ] := TakeOut[m, n] =
   Join@@ Function[z, Append[z, #]&/@ Range[Last[z] + 1, n]]/@
     TakeOut[m - 1, n]


(* construct PossibleFields from the vertex lists: *) 

SetPossibleFields[ cto_, func_, fp_ ] :=
Block[ {id = Sequence[], pl = {}},
  Scan[
	(* this is NOT the same as `=!=' since id = Sequence[] at first *)
    ( If[ !(#[[1]] === id),
        (PossibleFields[cto][##] = Union[pl])&@@ id;
        pl = {} ];
      id = #[[1]];
      AppendTo[ pl, #[[2]] ] )&,
    Append[ Union[Flatten[
      Combinations[List@@ #, func[List@@ #]]&/@ fp, 1 ]], {0, 0} ] ]
]


(* Transformation of Equal in the generic couplings to SetDelayed:
   lhs has to be changed to patterns, rhs is changed from
   G . {g1, g2, ...} to {G[g1], G[g2], ...} * {g1, g2, ...}.
   Both lhs and rhs get an additional argument, the counterterm order.
   Also, the function CouplingVector is defined which gives only the
   G part of the coupling *)

InitGenericCoupling[ lhs_ == s_. g:G[_][__] ] :=
  InitGenericCoupling[ lhs == g . {s} ]

InitGenericCoupling[
  AnalyticalCoupling[f__] == G[_][__] . kinvec_List ] :=
  Message[InitializeModel::rhs1, ToGeneric[{f}]] /; !FreeQ[kinvec, G]

InitGenericCoupling[
  AnalyticalCoupling[f__] == G[n_][g__] . kinvec_List ] :=
Block[ {lhs, cpl, Global`cto, x, ref},

  lhs = CoupFieldPattern/@ {f};
  Evaluate[cpl@@ lhs] = G[n][Global`cto][g] . kinvec;

	(* put Mom and KI dummies in the fields on the rhs. These dummies 
	   will appear as part of the Lorentz term indexing of the G's. *)
  ref = ToGeneric[{f}];
  x = Evaluate[CouplingVector@@ ref] =
    cpl@@ MapIndexed[ #1 /. {
      (fi:P$Generic)[i__, _, ki:{__}] :>
        fi[i, Mom@@ #2, Through[ Take[KIarr, Length[ki]][ #2[[1]] ] ]],
      (fi:P$Generic)[i__, _] :> fi[i, Mom@@ #2]
    }&, {f} ] /. Dot -> Map;

  SetDelayed@@ {AnalyticalCoupling[Global`cto_]@@ lhs, PV[x . kinvec]}
]

InitGenericCoupling[ AnalyticalCoupling[f__] == _ ] :=
  Message[InitializeModel::rhs2, ToGeneric[{f}]]


KIarr = Array[ToExpression["Global`KI" <> ToString[#]]&, 10]


Off[RuleDelayed::rhs]


(* Change field representation to patterns. Coupling patterns include
   ___ so that they match also in mixing cases. *)

PropFieldPattern[ fi_[i_Symbol, m_Symbol] ] := fi[i__, m_]

PropFieldPattern[ fi_[i_Symbol, m_Symbol, ki:{__Symbol}] ] := 
  fi[i__, m_, Pattern[#, _]&/@ ki]

PropFieldPattern[
  fi_[i_Symbol, m_Symbol, ki:({__Symbol} -> {__Symbol})] ] := 
  fi[i__, m_, Map[Pattern[#, _]&, ki, {2}]]

PropFieldPattern[ s_Symbol fi:_[___] ] := s_. PropFieldPattern[fi]

PropFieldPattern[ fi_ ] :=
  (Message[InitializeModel::nosymb, FullForm[f]]; Interrupt[])


CoupFieldPattern[ fi_[i_Symbol, m_Symbol] ] := fi[i__, m_, ___List]

CoupFieldPattern[ fi_[i_Symbol, m_Symbol, ki:{__Symbol}] ] := 
  fi[i__, m_, Append[Pattern[#, _]&/@ ki, ___]]

CoupFieldPattern[
  fi_[i_Symbol, m_Symbol, ki:({__Symbol} -> {__Symbol})] ] := 
  fi[i__, m_, Append[#, ___]&/@ Map[Pattern[#, _]&, ki, {2}]]

CoupFieldPattern[ s_Symbol fi:_[___] ] := s_. CoupFieldPattern[fi]

CoupFieldPattern[ fi_ ] :=
  (Message[InitializeModel::nosymb, FullForm[f]]; Interrupt[])


On[RuleDelayed::rhs]


AllFields[ fi_ ] :=
  If[ Length[MixingPartners[fi]] === 1, #, {#, 2 #} ]&[
    If[SelfConjugate[fi], fi, {fi, -fi}] ]


(* Initialization of a classes model: *)

InitClassesModel[ mod_ ] :=
Block[ {unsortedFP, unsortedCT, savecp = $ContextPath,
file = $ModelDir <> mod <> ".mod"},

	(* no Global symbols allowed for these operations *)
  $ContextPath = DeleteCases[$ContextPath, "Global`"];
  $Model = "";

  FAPrint[2, ""];
  FAPrint[2, "initializing classes model file ", file];
  Clear[ InsertOnly, Diagonal, TheC, QuantumNumbers ];
  M$LastModelRules = {};
  Off[Syntax::newl, Syntax::com];
  If[ Get[file] === $Failed, Abort[] ];
  On[Syntax::newl, Syntax::com];

	(* initialize particles:
	   set properties of classes from their description list: *)
  QuantumNumbers[ -fi_ ] := -QuantumNumbers[fi];
  QuantumNumbers[ _ ] = {};
  Cases[ Thread[#], (fi_ == (a_ -> b_)) :> (a[fi] = b) ]&/@
    ( M$ClassesDescription /.
      {Mass -> TheMass, PropagatorLabel -> TheLabel} );

  Cases[ DownValues[MixingPartners],
    (_[_[p:_[__]]] :> m_) :> AssignMixing[p, m] ];

  F$Classes = First/@ M$ClassesDescription;
	(* set all possible index combinations for a class: *)
  F$AllParticles = Flatten[
    Function[ fi, If[ Indices[fi] === {}, fi,
      Outer[Append[fi, {##}]&, Sequence@@
        (IndexRange/@ Indices[fi] /. {} | _NoUnfold -> {_})] ] ]/@
      F$Classes ];
  F$Particles = F$AllParticles = Flatten[AllFields/@ F$AllParticles];

  FAPrint[2, "> ", Length[F$AllParticles],
    " particles (incl. antiparticles) in ",
    Length[F$Classes], " classes"];

  F$Classes = F$AllClasses = Flatten[AllFields/@ F$Classes];
  F$AllowedFields = Union[F$AllGeneric, F$AllClasses, F$AllParticles];

  Diagonal[ _ ] = Sequence[];

	(* forming the explicit and half-generic vertex lists: *)
  Off[Rule::rhs];
  unsortedFP = Flatten[InitClassesCoupling/@ M$CouplingMatrices, 1];
  On[Rule::rhs];
  ReferenceOrder[Classes] = Union[Apply[List, unsortedFP, 1]];
  FieldPoints[] = (FieldPoint@@ #)&/@ ReferenceOrder[Classes];

  L$CTOrders = Union[Cases[unsortedFP, FieldPoint[n_][__] -> n]];
  Scan[
    Function[cto,
      unsortedCT = Union[Select[unsortedFP, #[[0, 1]] === cto &]];
      FieldPoints[cto] = Apply[FieldPoint, unsortedCT, 1];
      FAPrint[2, "> ", Length[unsortedCT],
        If[ cto === 0, " vertices",
          " counter terms of order " <> ToString[cto] ]];
      Apply[ (CheckFieldPoint[ FieldPoint[cto][##] ] = True)&,
        FieldPoints[cto], 1 ];
      SetPossibleFields[cto, ToGeneric, FieldPoints[cto]] ],
    If[ $CounterTerms,
      FAPrint[2, "> $CounterTerms are ON"]; L$CTOrders,
      FAPrint[2, "> $CounterTerms are OFF"]; {0} ] ];

  $Model = mod;
  FAPrint[1, "classes model ", mod, " initialized"];
  $ContextPath = savecp;
]


CC[ fi__ ] == coup_ ^:= Sequence[
  C[fi] == coup,
  AntiParticle/@ C[fi] == ConjugateCoupling[fi][coup]
]


KinematicVector[ a___, _. (f:P$Generic)[__], b___ ] :=
  KinematicVector[a, f, b]

KinematicVector[ a___, _Integer f:P$Generic, b___ ] :=
  KinematicVector[a, f, b]

KinematicVector[ fi__ ] :=
Block[ {p = Position[GenericFieldPoints[], FieldPoint[fi]]},
  If[ Length[p] === 0, {},
    First/@ CouplingVector@@ ReferenceOrder[Generic][[ p[[1, 1]] ]] ]
] /; Head[GenericFieldPoints[]] === List


ConjugateCoupling[__][ ConjugateCoupling[__][coup_] ] = coup

ConjugateCoupling[fi__][ coup:(_Plus | _List) ] :=
  ConjugateCoupling[fi]/@ coup

ConjugateCoupling[__][ n:(_Integer | _Rational | _IndexDelta) ] := n


(* Assigning the mixing propagators. There are in general 4 cases which
   are distinguished by the following factors multiplying the fields:
	-->--~~>~~	SV = {S, V}
	--<--~~<~~	-SV = {-S, -V} 
	~~>~~-->--	2 SV = {V, S}
	~~<~~--<--	-2 SV = {-V, -S}  *)

AssignMixing[ part_, {left_, right_} ] :=
Block[ {comp, i, ppart, pleft, pright},
  ppart = Append[part, i___];
  pleft = Append[left, i];
  pright = Append[right, i];
  comp = If[ Head[part] === SV, SVCompatibles, Compatibles ];
  Unionize[comp, right, part];
  Unionize[comp, left, 2 part];
  MixingPartners[part] = .;
  MixingPartners[ppart] = {pleft, pright};
  MixingPartners[2 ppart] = {pright, pleft};
  If[ !SelfConjugate[part],
    Unionize[comp, -right, -part];
    Unionize[comp, -left, -2 part];
    MixingPartners[-ppart] = {-pleft, -pright};
    MixingPartners[-2 ppart] = {-pright, -pleft} ]
]

Unionize[ n_, arg_, new_ ] := n[arg] = Union[Flatten[{n[arg], new}]]


(* InitClassesCoupling converts a single classes coupling definition 
   (Equal) to a function definition (SetDelayed). It checks for 
   compatibility of the generic and the classes coupling structure and 
   sets the Diagonal function for the field point.
   The structure of the classes coupling is
	{ {a[0], a[1], ...}, {b[0], b[1], ...}, ... }
   where a, b, etc. refer to the kinematic vector G = {Ga, Gb, ..} and the 
   inner lists stand for increasing order of the vertices. For a 
   one-dimensional generic coupling we need only {c[0], c[1], ...}. *)

InitClassesCoupling[ vert_ == coup_ ] :=
Block[ {lhs, rhs, l, cv, x, res, genref = ToGeneric[List@@ vert]},

	(* find corresponding generic coupling.
	   Note: whereas formerly the classes coupling was allowed to be
	         given in a different order than the generic coupling, a
	         strict match is now required *)
  If[ Position[ReferenceOrder[Generic], genref, 1, 1] === {},
    Message[InitializeModel::nogeneric, vert]; Return[{}] ];

	(* in the special case of a one-dimensional coupling supply
	   the extra List if omitted *)
  l = Length[cv = CouplingVector@@ genref];
  rhs = If[ l === 1 && !MatchQ[coup, {{__}}], {coup},
    If[ l =!= Length[coup],
      Message[InitializeModel::incomp1, vert, l];
      Abort[] ];
    coup ];

	(* check structure of field indices in coupling: *)
  If[ Or@@ (If[ SameQ@@ (x = IndexCount[#]), False,
        Message[InitializeModel::incomp2, vert, #, Sequence@@ x];
        True ]&)/@ vert,
    Abort[] ];

	(* change symbols in model file to patterns: *)
  lhs = vert //. {a___, j_Symbol, b___} -> {a, j_, b};
	(* this assigns TheC for all components of the coupling vector *)
  Evaluate[ ((TheC@@ #)@@ lhs)&/@ cv ] = rhs;

  lhs = VSort[lhs];
  cv = ToClasses[vert];
  res = {};
  MapIndexed[
    If[ !VectorQ[#1, # === 0 &],	(* complete ct order is zero *)
      res = {res, (l = FieldPoint[#2[[1]] - 1])@@ cv};
      If[ Length[x = DeltaSelect[#1]] =!= 0,
        Diagonal[ Evaluate[l@@ lhs] ] := Evaluate[x] ] ]&,
    Transpose[rhs] ];
	(* transposing rhs yields a list of coupling vectors for each ct 
	   order: { {a[0], b[0], ...}, {a[1], b[1], ...}, ...} *)
  Flatten[res]
]


IndexCount[ _. fi_[n_, ndx_List:{}] ] :=
  {Length[Indices[fi[n]]], Length[ndx]}

IndexCount[ _ ] = {0, 0}


DeltaSelect[ expr_Times ] := Cases[expr, _IndexDelta]

DeltaSelect[ expr_List ] := Flatten[Intersection[DeltaSelect/@ expr]]

DeltaSelect[ expr_Plus ] :=
  If[ Head[#] === Plus, {}, DeltaSelect[#] ]& @
    Collect[ expr, Union[Cases[expr, IndexDelta[__], Infinity]] ] /;
  !FreeQ[expr, IndexDelta]

DeltaSelect[ expr_IndexDelta ] = expr

DeltaSelect[ _ ] = {}


(* some defaults for the classes properties: *)

IndexRange[ error_ ] :=
  (Message[InitializeModel::norange, error]; IndexRange[error] = {})

Indices[ _Integer fi_ ] := Indices[fi]

Indices[ fi_[i_, __] ] := Indices[fi[i]]

Indices[ _ ] = {}


KinematicIndices[ VS ] := KinematicIndices[SV]

KinematicIndices[ _ ] = {}


MatrixTraceFactor[ _Integer fi_ ] := MatrixTraceFactor[fi]

MatrixTraceFactor[ fi_[i_, __] ] := MatrixTraceFactor[fi[i]]

MatrixTraceFactor[ _ ] = 1


SelfConjugate[ _Integer fi_ ] := SelfConjugate[fi]

SelfConjugate[ fi_[i_, __] ] := SelfConjugate[fi[i]]

SelfConjugate[ _ ] = False


(* There are no direct definitions for the masses of the particles since
   we want to keep track of the field contents of a propagator and the
   mass replacement rules (e.g. Mass[particle] = Mass[antiparticle])
   destroy this information. All those definitions are given for the
   function TheMass. *)

TheMass[ _Integer fi_ ] := TheMass[fi]

TheMass[ fi_[i_, j_List, __] ] := TheMass[fi[i, j]]

TheMass[ fi_[i_, {j___}] ] :=
  If[NumberQ[#], #, #[j]]&[ TheMass[fi[i]] ] /;
  Head[ TheMass[fi[i]] ] =!= Mass

TheMass[ fi_ ] = Mass[fi]


(* Note: AntiParticle[...] := AntiParticle[...] = ... is not possible
   because if another model with different SelfConjugate behaviour is
   loaded, AntiParticle must be rebuilt. *)

AntiParticle[ 0 ] = 0

AntiParticle[ SV ] = VS

AntiParticle[ VS ] = SV

AntiParticle[ AntiParticle[fi_] ] = fi

AntiParticle[ (s:2 | -2) part:(fi:P$Generic)[i_, ___] ] :=
  s / 2 If[SelfConjugate[fi[i]], part, -part] /.
  mom_FourMomentum -> -mom

AntiParticle[ s_. part:(fi:P$Generic)[i_, ___] ] :=
  s Length[MixingPartners[fi[i]]] If[SelfConjugate[fi[i]], part, -part] /.
  mom_FourMomentum -> -mom

	(* there are no antiparticles at Generic level.
	   Note that it is important to have _Symbol here to prevent
	   AntiParticle[Field[i]] from being evaluated. *)
AntiParticle[ fi_Symbol ] = fi


	(* VS is present only at generic level and is needed to
	   distinguish which side of a mixing propagator has the S and
	   which has the V coupling. Logically, VS should be represented
	   by 2 SV, but there are no factors in front of fields at
	   generic level. *)
VS[ i__ ] := -SV[i]


PropagatorType[ V ] = Sine

PropagatorType[ S ] = ScalarDash

PropagatorType[ U ] = GhostDash

PropagatorType[ SV ] = {ScalarDash, Sine}

PropagatorType[ VS ] = {Sine, ScalarDash}

PropagatorType[ (2 | -2) fi_ ] := Reverse[Flatten[{PropagatorType[fi]}]]

PropagatorType[ -fi_ ] := PropagatorType[fi]

PropagatorType[ fi_[i_, __] ] := PropagatorType[fi[i]]

PropagatorType[ _ ] = Straight


PropagatorArrow[ _?Negative fi_ ] :=
  PropagatorArrow[fi] /. {Forward -> Backward, Backward -> Forward}

PropagatorArrow[ 2 fi_ ] := PropagatorArrow[fi]

PropagatorArrow[ fi_[i_, __] ] := PropagatorArrow[fi[i]]

PropagatorArrow[ _ ] = None


TheLabel::undef = "No label defined for `1`."

TheLabel[ SV ] = {"S", "V"}

TheLabel[ VS ] = {"V", "S"}

TheLabel[ i_Integer ] := ToString[i]

TheLabel[ fi:P$Generic ] := ToString[fi]

TheLabel[ (2 | -2) fi_ ] := Reverse[Flatten[{TheLabel[fi]}]]

TheLabel[ -fi_ ] := TheLabel[fi]

TheLabel[ fi_[i_Integer, ndx_List] ] :=
  TheLabel[fi[i]] /. Thread[ Indices[fi[i]] ->
    Join[Appearance/@ ndx,
      Table[Null, {Length[Indices[fi[i]]] - Length[ndx]}]] ]

TheLabel[ fi_ ] := (Message[TheLabel::undef, fi]; ToString[fi])


Appearance[ Index[_, i_] ] := Alph[i]

Appearance[ expr_ ] = expr


GaugeXi[ _Integer fi_ ] := GaugeXi[fi]


(* RestrictCurrentModel accepts any number of ExcludeFieldPoints or
   ExcludeParticles rules and correspondingly sets the CheckFieldPoint
   functions for the vertices to False or deletes the fields from the
   F$xxx lists
   RestrictCurrentModel[] removes all restrictions from the current
   model *)

RestrictCurrentModel::badfp =
"`1` is not a valid coupling specification of the form
FieldPoint[cto][fields]."

$ExcludedFPs = $ExcludedParticleFPs = {}

RestrictCurrentModel[] :=
Block[ {lG, lC, lP},
  lG = Length[F$AllGeneric] - Length[F$Generic];
  lC = Length[F$AllClasses] - Length[F$Classes];
  lP = Length[F$AllParticles] - Length[F$Particles];
  If[ {lG, lC, lP} =!= {0, 0, 0},
    F$Generic = F$AllGeneric;
    F$Classes = F$AllClasses;
    F$Particles = F$AllParticles;
    F$AllowedFields = Union[F$Generic, F$Classes, F$Particles];
    FAPrint[2, ""];
    FAPrint[2, "Restoring ",
      lG, " Generic, ", lC, " Classes, and ", lP, " Particles fields"]
  ];
  If[ (lP = Length[$ExcludedFPs] + Length[$ExcludedParticleFPs]) > 0,
    Scan[ (CheckFieldPoint[#] = True)&, $ExcludedFPs ];
    FAPrint[2, ""];
    FAPrint[2, "Restoring ", lP, " field point(s)"];
    $ExcludedFPs = $ExcludedParticleFPs = {}
  ];
]

RestrictCurrentModel[ args__ ] :=
Block[ {ex, exclFP, exclP, lG, lC, lP, fps},
  ex = Select[ Flatten[{args}],
    If[ MatchQ[#, ExcludeParticles | ExcludeFieldPoints -> _], True,
      Message[InitializeModel::badrestr, #]; False ]& ];

  exclP = Union[Flatten[ Cases[ex, (ExcludeParticles -> p_) -> p] ]];
  If[ Length[exclP] > 0,
    exclP = Union[Flatten[
      Function[fi, Select[F$AllowedFields, FieldMatchQ[#, fi]&]]/@
        exclP ]];
    {lG, lC, lP} = Length/@ {F$Generic, F$Classes, F$Particles};
    F$Generic = Complement[F$Generic, exclP];
    F$Classes = Complement[F$Classes, exclP];
    F$Particles = Complement[F$Particles, exclP];
    F$AllowedFields = Complement[F$AllowedFields, exclP];
    FAPrint[2, ""];
    FAPrint[2, "Excluding ",
      lG - Length[F$Generic], " Generic, ",
      lC - Length[F$Classes], " Classes, and ",
      lP - Length[F$Particles], " Particles fields"];
  ];

  exclFP = Union[Flatten[ Cases[ex, (ExcludeFieldPoints -> p_) -> p] ]];
  If[ Length[exclFP] > 0,
    exclFP = Union[ VSort/@ #,
      VSort/@ Map[AntiParticle, #, {2}] ]&[ ValidFP/@ exclFP ];
    ex = Select[exclFP, !FreeQ[#, P$Generic[_, _]]&];
    $ExcludedParticleFPs = Union[Join[$ExcludedParticleFPs, ex]];
    fps = Cases[ DownValues[CheckFieldPoint],
      (_[_[ fp_ ]] :> True) -> fp ];
    exclFP = Union[Flatten[
      Function[fi, Select[fps, FieldPointMatchQ[#, fi]&]]/@
        Complement[exclFP, ex] ]];
    Scan[ (CheckFieldPoint[#] = .)&, exclFP ];
    $ExcludedFPs = Union[ Join[$ExcludedFPs, exclFP] ];
    FAPrint[2, ""];
    FAPrint[2, "Excluding ", Length[exclFP] + Length[ex],
      " field point(s) (incl. charge conjugate ones)"];
  ];

  {ExcludeParticles -> exclP, ExcludeFieldPoints -> exclFP}
]


ValidFP[ FieldPoint[f__] ] := FieldPoint[_][f]

ValidFP[ f:FieldPoint[_][__] ] = f

ValidFP[ f_ ] := (Message[RestrictCurrentModel::badfp, f]; Seq[])


FieldMatchQ[ _. fi_[___], _. fi_ ] = True

FieldMatchQ[ _. fi_[i_, ___], _. fi_[j_] ] := MatchQ[i, j]

FieldMatchQ[ _. fi_[i__], _. fi_[j__] ] := MatchQ[{i}, {j}]

FieldMatchQ[ _. fi_, _. fi_ ] = True

FieldMatchQ[ fi1_, fi2_ ] := MatchQ[fi1, fi2]


FieldPointMatchQ[ FieldPoint[cto1_][fi1__], FieldPoint[cto2_][fi2__] ] :=
  MatchQ[cto1, cto2] &&
    Length[{fi1}] === Length[{fi2}] &&
    VectorQ[ Transpose[{{fi1}, {fi2}}], FieldMatchQ@@ # & ]

FieldPointMatchQ[ ___ ] = False


ExcludedQ[ vertlist_ ] :=
  Catch[
    Outer[ If[FieldPointMatchQ[##], Throw[True]]&,
      VSort/@ vertlist, $ExcludedParticleFPs ];
    False ]


End[]
