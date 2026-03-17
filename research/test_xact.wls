#!/usr/bin/env wolframscript
(* Test script for xAct *)

(* Add xAct to path *)
AppendTo[$Path, "/opt"];

(* Load xTensor *)
Needs["xAct`xTensor`"];

(* Define a manifold *)
DefManifold[M4, 4, {\[Mu], \[Nu], \[Rho], \[Sigma]}];

(* Define a metric *)
DefMetric[-1, g[-\[Mu], -\[Nu]], CD, {";", "\[Del]"}];

Print["Successfully defined manifold M4 and metric g"];

(* Define the Riemann tensor *)
PrintAs[Riemann] ^= "R";

Print["xAct is working! You can now use xTensor for tensor calculations."];
