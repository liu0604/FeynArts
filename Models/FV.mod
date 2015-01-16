(*
	FV.mod
		Add-on model file for non-minimal flavour-violation
		("upgrades" ordinary to full 6x6 squark mixing)
		by Thomas Hahn and Jose Illana
		last modified 14 Jun 08 by th
*)


IndexRange[Index[AllSfermion]] = NoUnfold[Range[6]]


M$ClassesDescription = M$ClassesDescription /.
  S[t:13 | 14] == desc_ :> S[t] == (desc /.
    {Sfermion -> AllSfermion, Index[Generation] -> Sequence[]} /.
    ComposedChar[a_, b_, d_] -> ComposedChar[a, b, Null, d])


TheMass[ S[t:12 | 13 | 14, {s_, g_, ___}] ] =.

TheMass[ S[t:12, {s_, g_, ___}] ] := MSf[s, t - 10, g]

TheMass[ S[t:13 | 14, {as_, ___}] ] := MASf[as, t - 10]


ReplaceCoupling[lhs_ == rhs_, {n_}] :=
  ReplaceSf[ReplaceAf[lhs == (rhs /. {
    Af[t:3 | 4, __] -> af[t],
    AfC[t:3 | 4, __] -> Conjugate[af[t]] }), n], n]


ReplaceAf[
  (lhs:C[_, S[13 | 14, {s1_, j1_, _}], -S[13 | 14, {s2_, j2_, _}]]) ==
  rhs_, n_ ] :=
Block[ {sel, new},
  Attributes[sel] = {Listable, HoldFirst};
  sel[r_ IndexDelta[j1, j2], d_, m__] :=
    sel[r, IndexDelta[j1, j2] d, m];
  sel[r_ Mass[F[t:3 | 4, j_]], d_, m_, si_, so_] :=
    sel[r, d, Mass[F[t, j]] m, si, so];
  sel[r_ Conjugate[usf[t_, _][s1, si_]], d_, m_, _, so_] :=
    Conjugate[usf[t, j1][s1, si]] sel[r, d, m, si, so];
  sel[r_ usf[t_, _][s2, so_], d_, m_, si_, _] :=
    usf[t, j2][s2, so] sel[r, d, m, si, so];
  sel[x_, d_, m_, __] := x d m /; FreeQ[x, af];
  sel[r_ x_, d__] := x sel[r, d] /; FreeQ[x, af];
  sel[x_Plus, d__] := sel[#, d]&/@ x;
  sel[x_af, d__] := sel[Identity[x], d];
  sel[c_[af[t_]], _, m_, i__] :=
  Block[ {g1, g2},
    {g1, g2} = {j1, j2}[[{i}]];
    c[Af[t, g1, g2]] (m /. Mass[F[t, _]] -> Mass[F[t, {g1}]])
  ];
  new = sel[rhs, 1, 1, 0, 0];
  If[ !FreeQ[new, af], Message[ReplaceCoupling::warning, n, Af] ];
  lhs == new
] /; !FreeQ[rhs, af]


ReplaceAf[other_, _] = other


ReplaceSf[ok___, C[x_. S[t:13 | 14, {s_, j_, o_}], r___] == rhs_, n_] :=
Block[ {as = ToExpression["a" <> ToString[s]]},
  ReplaceSf[ok, x S[t, {as, o}],
    C[r] == ReplaceUSf[rhs, t - 10, s, j, as, n] /. ISum -> IndexSum,
    n]
]

ReplaceSf[ok___, C[f_, r___] == rhs_, n_] :=
  ReplaceSf[ok, f, C[r] == rhs, n]

ReplaceSf[ok___, C[] == rhs_, _] := C[ok] == rhs


Attributes[ReplaceUSf] = {Listable}

ReplaceUSf[IndexSum[expr_, i___], r__] :=
  IndexSum[ReplaceUSf[expr, r], i]

ReplaceUSf[expr_, t_, s_, j_, as_, n_] :=
Block[ {sel, new},
  sel[x_] := x /; FreeQ[x, s];
  sel[x_Times] := sel/@ x;
  sel[x_Plus] := sel/@ x;
  sel[Conjugate[x_]] := Conjugate[sel[x]];
  sel[IndexDelta[s, s2_]] := IndexDelta[as, s2] IndexDelta[j, 1];
  sel[usf[t, _][s, s2_]] := UASf[t][as, j + 3 (s2 - 1)];
  new = ISum[sel[expr], {j, 3}];
  If[ !FreeQ[new, s], Message[ReplaceCoupling::warning, n, s] ];
  new
]


ReplaceCoupling::warning = "Coupling #`` still contains ``."


ISum[IndexDelta[a_, b_] r_, {a_, _}] := r /. a -> b

ISum/: IndexSum[ISum[expr_, i_], j__] :=
  IndexSum[expr, Sequence@@ Sort[{i, j}]]


M$CouplingMatrices = MapIndexed[ReplaceCoupling,
  M$CouplingMatrices /. {
    USf[t:3 | 4, g_][a_, b_] -> usf[t, g][a, b],
    USf[a_, b_, t:3 | 4, g_] -> usf[t, g][a, b],
   USfC[a_, b_, t:3 | 4, g_] -> Conjugate[usf[t, g][a, b]] } ]

