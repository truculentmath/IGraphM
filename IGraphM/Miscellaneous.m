(* Mathematica Package *)
(* Created by Mathematica plugin for IntelliJ IDEA *)

(* :Author: szhorvat *)
(* :Date: 2018-10-24 *)
(* :Copyright: (c) 2019 Szabolcs Horvát *)

Package["IGraphM`"]
igContextSetup[igPackagePrivateSymbol]

(***********************************)
(***** Miscellaneous functions *****)
(***********************************)


(***** Directed acyclic graphs *****)

PackageExport["IGDirectedAcyclicGraphQ"]
IGDirectedAcyclicGraphQ::usage = "IGDirectedAcyclicGraphQ[graph] tests if graph is directed and acyclic.";

SyntaxInformation[IGDirectedAcyclicGraphQ] = {"ArgumentsPattern" -> {_}};
IGDirectedAcyclicGraphQ[g_?igGraphQ] := Block[{ig = igMakeFast[g]}, sck@ig@"dagQ"[]]
IGDirectedAcyclicGraphQ[_] := False


PackageExport["IGTopologicalOrdering"]
IGTopologicalOrdering::usage =
    "IGTopologicalOrdering[graph] returns a permutation that sorts the vertices in topological order. " <>
    "Note that the values returned are vertex indices, not vertex names.";

SyntaxInformation[IGTopologicalOrdering] = {"ArgumentsPattern" -> {_}};
IGTopologicalOrdering[graph_?igGraphQ] :=
    catch@Block[{ig = igMakeFast[graph]},
      igIndexVec@check@ig@"topologicalSorting"[]
    ]


PackageExport["IGFeedbackArcSet"]
IGFeedbackArcSet::usage = "IGFeedbackArcSet[graph] computes a feedback edge set of graph. Removing these edges makes the graph acyclic.";

igFeedbackArcSetMethods = <| "IntegerProgramming" -> True, "EadesLinSmyth" -> False |>;

Options[IGFeedbackArcSet] = { Method -> "IntegerProgramming" };
SyntaxInformation[IGFeedbackArcSet] = {"ArgumentsPattern" -> {_, OptionsPattern[]} };

IGFeedbackArcSet::bdmtd =
    "Value of option Method -> `` is not one of " <>
    ToString[Keys[igFeedbackArcSetMethods], InputForm] <> ".";

amendUsage[IGFeedbackArcSet, "Available Method options: <*Keys[igFeedbackArcSetMethods]*>. \"IntegerProgramming\" is guaranteed to find a minimum feedback arc set."];

IGFeedbackArcSet[graph_?igGraphQ, opt : OptionsPattern[]] :=
    catch@Block[{ig = igMake[graph]}, (* use igMake because edge ordering matters *)
      Part[
        EdgeList[graph],
        igIndexVec@check@ig@"feedbackArcSet"[Lookup[igFeedbackArcSetMethods, OptionValue[Method], Message[IGFeedbackArcSet::bdmtd, OptionValue[Method]]; throw[$Failed]]]
      ]
    ]


(***** Voronoi cells with graph distance *****)

PackageExport["IGVoronoiCells"]
IGVoronoiCells::usage = "IGVoronoiCells[graph, {v1, v2, \[Ellipsis]}] find the sets of vertices closest to each given vertex.";

IGVoronoiCells::ivert = "The given centers `1` are not vertices of the graph.";
Options[IGVoronoiCells] = { "Tiebreaker" -> Automatic };
SyntaxInformation[IGVoronoiCells] = {"ArgumentsPattern" -> {_, _, OptionsPattern[]}};
IGVoronoiCells[g_?igGraphQ, centers_List, opt : OptionsPattern[]] :=
    Module[{clist = DeleteDuplicates[centers], vlist = VertexList[g], tiebreaker = OptionValue["Tiebreaker"], idx, dmat},
      If[Not@SubsetQ[vlist, clist],
        Message[IGVoronoiCells::ivert, Complement[clist, vlist]];
        Return[$Failed]
      ];
      dmat = Transpose@IGDistanceMatrix[g, centers];
      idx = If[MatchQ[tiebreaker, Automatic|First],
        Ordering[#, 1]& /@ dmat,
        With[{min = Min[#]}, tiebreaker@Position[#, min]]& /@ dmat
      ];
      GroupBy[
        Transpose[{Extract[vlist, idx], vlist}],
        First -> Last
      ]
    ]


(***** k-cores *****)

PackageExport["IGCoreness"]
IGCoreness::usage =
    "IGCoreness[graph] returns the coreness of each vertex. Coreness is the highest order of a k-core containing the vertex.\n" <>
    "IGCoreness[graph, \"In\"] considers only in-degrees in a directed graph.\n" <>
    "IGCoreness[graph, \"Out\"] considers only out-degrees in a directed graph.";

corenessModes = <|"In" -> -1, "Out" -> 1, "All" -> 0|>;
SyntaxInformation[IGCoreness] = {"ArgumentsPattern" -> {_, _.}};
expr : IGCoreness[graph_?igGraphQ, mode_ : "All"] :=
    catch@Block[{ig = igMakeFast[graph]},
      Round@check@ig@"coreness"[Lookup[corenessModes, mode, Message[IGCoreness::inv, HoldForm@OutputForm[expr], mode, "parameter"]; throw[$Failed]]]
    ]
addCompletion[IGCoreness, {0, {"In", "Out", "All"}}]


(***** Degree sequences *****)

PackageExport["IGGraphicalQ"]
IGGraphicalQ::usage =
    "IGGraphicalQ[degrees] tests if degrees is the degree sequence of any simple undirected graph.\n" <>
    "IGGraphicalQ[indegrees, outdegrees] tests if indegrees with outdegrees is the degree sequence of any simple directed graph.";

SyntaxInformation[IGGraphicalQ] = {"ArgumentsPattern" -> {_, _.}};
IGGraphicalQ[degrees_?nonNegIntVecQ] := sck@igraphGlobal@"erdosGallai"[degrees] (* use fast custom implementation instead of igraph *)
IGGraphicalQ[indeg_?nonNegIntVecQ, outdeg_?nonNegIntVecQ] := sck@igraphGlobal@"graphicalQ"[outdeg, indeg]
IGGraphicalQ[___] := False


(***** Dominators *****)

PackageExport["IGDominatorTree"]
IGDominatorTree::usage = "IGDominatorTree[graph, root] returns the dominator tree of a directed graph starting from root.";
SyntaxInformation[IGDominatorTree] = {"ArgumentsPattern" -> {_, _, OptionsPattern[]}, "OptionNames" -> optNames[Graph]};
IGDominatorTree[graph_?igGraphQ, root_, opt : OptionsPattern[Graph]] :=
    catch@Block[{new = igMakeEmpty[], ig = igMakeUnweighted[graph]},
      check@new@"dominatorTree"[ManagedLibraryExpressionID[ig], vs[graph][root]];
      igToGraphWithNames[new, VertexList[graph], opt, GraphRoot -> root]
    ]


PackageExport["IGImmediateDominators"]
IGImmediateDominators::usage = "IGImmediateDominators[graph, root] returns the immediate dominator of each vertex relative to root.";
SyntaxInformation[IGImmediateDominators] = {"ArgumentsPattern" -> {_, _}};
IGImmediateDominators[graph_?igGraphQ, root_] :=
    catch@Block[{ig = igMakeUnweighted[graph], dominators, mask},
      dominators = check@ig@"immediateDominators"[vs[graph][root]];
      mask = UnitStep[dominators];
      AssociationThread[Pick[VertexList[graph], mask, 1], VertexList[graph][[Pick[igIndexVec[dominators], mask, 1]]]]
    ]


(***** Other functions *****)

PackageExport["IGTreelikeComponents"]
IGTreelikeComponents::usage = "IGTreelikeComponents[graph] returns the vertices that make up tree-like components.";

SyntaxInformation[IGTreelikeComponents] = {"ArgumentsPattern" -> {_}};
IGTreelikeComponents[graph_?igGraphQ] :=
    catch@Block[{ig = igMakeFast[graph]},
      igVertexNames[graph]@igIndexVec@check@ig@"treelikeComponents"[]
    ]


(* Notes on graph types:

   Directed: $Failed because some authors do define directed cacti, and it could be implemented.
   Self-loops: Ignore them.
   Multi-edges: Support.
*)
PackageExport["IGCactusQ"]
IGCactusQ::usage = "IGCactusQ[graph] tests if graph is a cactus";
SyntaxInformation[IGCactusQ] = {"ArgumentsPattern" -> {_}};
IGCactusQ[graph_?UndirectedGraphQ] :=
    catch@Block[{ig = igMakeUnweighted[graph]},
      If[SimpleGraphQ[graph],
        check@ig@"cactusQ"[],
        check@ig@"nonSimpleCactusQ"[]
      ]
    ]
(* Some authors define cactus graphs for the directed case as well. Consider implementing this in the future. *)
IGCactusQ::dirg = "IGCactusQ is not implemented for directed graphs.";
IGCactusQ[_?DirectedGraphQ] := (Message[IGCactusQ::dirg]; $Failed)
IGCactusQ[_] := False


PackageExport["IGRegularQ"]
IGRegularQ::usage =
    "IGRegularQ[graph] tests if graph is regular, i.e. all vertices have the same degree.\n" <>
    "IGRegularQ[graph, k] tests if graph is k-regular, i.e. all vertices have degree k.";
SyntaxInformation[IGRegularQ] = {"ArgumentsPattern" -> {_, _.}};
IGRegularQ[graph_?igGraphQ] :=
    If[UndirectedGraphQ[graph],
      Equal @@ VertexDegree[graph],
      Equal @@ VertexOutDegree[graph] && VertexInDegree[graph] == VertexOutDegree[graph]
    ]
IGRegularQ[graph_?EmptyGraphQ, k_Integer?NonNegative] := k == 0 (* required because First@VertexDegree[g] is not usable for the null graph *)
IGRegularQ[graph_?igGraphQ, k_Integer?NonNegative] :=
    If[UndirectedGraphQ[graph],
      With[{vd = VertexDegree[graph]},
        First[vd] == k && Equal @@ vd
      ]
      ,
      With[{vod = VertexOutDegree[graph], vid = VertexInDegree[graph]},
        First[vod] == k && Equal @@ vod && vid == vod
      ]
    ]
IGRegularQ[_] := False


PackageExport["IGCompleteQ"]
IGCompleteQ::usage = "IGCompleteQ[graph] tests if all pairs of vertices are connected in graph.";

igCompleteQ[graph_?SimpleGraphQ] :=
    With[{vc = VertexCount[graph], ec = EdgeCount[graph]},
      If[UndirectedGraphQ[graph],
        vc*(vc-1)/2 == ec,
        vc*(vc-1) == ec
      ]
    ]
igCompleteQ[graph_] := igCompleteQ@SimpleGraph[graph]

SyntaxInformation[IGCompleteQ] = {"ArgumentsPattern" -> {_}};
IGCompleteQ[graph_?igGraphQ] := igCompleteQ[graph]
IGCompleteQ[_] := False


PackageExport["IGStronglyRegularQ"]
IGStronglyRegularQ::usage = "IGStronglyRegularQ[graph] tests if graph is strongly regular.";

igStronglyRegularQ[g_?EmptyGraphQ] := True
igStronglyRegularQ[g_ /; UndirectedGraphQ[g] && SimpleGraphQ[g]] :=
    IGRegularQ[g] && (IGCompleteQ[g] ||
    Module[{vc = VertexCount[g], am = AdjacencyMatrix[g], k = First@VertexDegree[g], lambda, mu},
      lambda = Dot @@ am[[ First[am["NonzeroPositions"]] ]];
      mu = k*(k - lambda - 1) / (vc - k - 1);
      If[
        IntegerQ[mu]
        (* The optimization below seems to have minimal effect, thus for the moment it is excluded.
           Source of the formula: "Strongly regular graphs" by Peter J. Cameron *)
        (* && IntegerQ[1/2 (vc - 1 + ((vc - 1) (mu - lambda) - 2 k)/ Sqrt[(mu - lambda)^2 + 4 (k - mu)])] *)
        ,
        am.am == k IdentityMatrix[vc, SparseArray] + lambda am + mu (ConstantArray[1, {vc, vc}, SparseArray] - IdentityMatrix[vc, SparseArray] - am)
        ,
        False
      ]
    ])

(* TODO implement for directed graphs including parameters
   https://homepages.cwi.nl/~aeb/math/dsrg/dsrg.html *)
IGStronglyRegularQ::dirg = "Directed graphs are not supported.";
igStronglyRegularQ[g_?DirectedGraphQ] := (Message[IGStronglyRegularQ::dirg]; $Failed)

IGStronglyRegularQ::nsg  = "Non-simple graphs are not supported.";
igStronglyRegularQ[g_] := (Message[IGStronglyRegularQ::nsg]; $Failed)

SyntaxInformation[IGStronglyRegularQ] = {"ArgumentsPattern" -> {_}};
IGStronglyRegularQ[graph_?igGraphQ] := igStronglyRegularQ[graph]
IGStronglyRegularQ[_] := False


PackageExport["IGStronglyRegularParameters"]
IGStronglyRegularParameters::usage = "IGStronglyRegularParameters[graph] returns the parameters {v, k, \[Lambda], \[Mu]} of a strongly regular graph. For non-strongly-regular graphs {} is returned.";
SyntaxInformation[IGStronglyRegularParameters] = {"ArgumentsPattern" -> {_}};
IGStronglyRegularParameters[g_?EmptyGraphQ] := {VertexCount[g], 0, 0, 0}
IGStronglyRegularParameters[g_ /; SimpleGraphQ[g] && IGCompleteQ[g]] := {VertexCount[g], VertexCount[g]-1, VertexCount[g]-2, 0}
IGStronglyRegularParameters[g_?IGStronglyRegularQ] :=
    Module[{vc = VertexCount[g], am = AdjacencyMatrix[g], k = First@VertexDegree[g], lambda, mu},
      lambda = Dot @@ am[[ First[am["NonzeroPositions"]] ]];
      mu = k * (k - lambda - 1) / (vc - k - 1);
      {vc, k, lambda, mu}
    ]
IGStronglyRegularParameters[g_?GraphQ] := {}


PackageExport["IGIntersectionArray"]
IGIntersectionArray::usage = "IGIntersectionArray[graph] computes the intersection array {b, c} of a distance regular graph. For non-distance-regular graphs {} is returned.";
IGIntersectionArray::dirg = "Directed graphs are not supported.";
IGIntersectionArray::nsg  = "Non-simple graphs are not supported.";
SyntaxInformation[IGIntersectionArray] = {"ArgumentsPattern" -> {_}};
IGIntersectionArray[graph_?igGraphQ] :=
    Which[
      UndirectedGraphQ[graph] && SimpleGraphQ[graph],
      If[IGRegularQ[graph],
        catch@Block[{ig = igMakeUnweighted[graph]},
          check@ig@"intersectionArray"[]
        ],
        {}
      ]
      ,
      DirectedGraphQ[graph],
      Message[IGIntersectionArray::dirg]; $Failed
      ,
      True, (* non-simple undirected graph *)
      Message[IGIntersectionArray::nsg]; $Failed
    ]


PackageExport["IGDistanceRegularQ"]
IGDistanceRegularQ::usage = "IGDistanceRegularQ[graph] tests if graph is distance regular.";
SyntaxInformation[IGDistanceRegularQ] = {"ArgumentsPattern" -> {_}};
IGDistanceRegularQ[graph_?igGraphQ] := catch[check@IGIntersectionArray[graph] =!= {}]
IGDistanceRegularQ[_] := False
