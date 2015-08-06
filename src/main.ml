
(* todo: locate *)

module H = struct
  include Digest

  let combine list =
    let list = List.sort Pervasives.compare list in
    string (String.concat "" (List.rev_map to_hex list))

  let empty = string ""

end

module Int64Map = Map.Make(Int64)
module HMap = Map.Make(H)
module StringMap = Map.Make(String)
module StringSet = Set.Make(String)

module StringUnsortedPair = struct
  type t = string * string
  let compare = Pervasives.compare
  let make s1 s2 =
    if s1 < s2 then s1, s2 else s2, s1
end
module SUP = StringUnsortedPair
module SUPMap = Map.Make(SUP)

let (@>) f g = fun x -> g (f x)
let fst3 (a, _, _) = a

let listRevSplit l =
  let rec aux ((rx, ry) as acc) = function
  | [] -> acc
  | (x, y)::l -> aux (x::rx, y::ry) l
  in
  aux ([], []) l

let rec listKeep n l = match l with (* /!\ not tailrec *)
| [] -> l
| _ when n <= 0 -> []
| hd::tl -> hd::(listKeep (n-1) tl)

let listKeepLast n l =
  if n <= 0 then [] else
    let rec aux all l = match l with
    | [] -> List.nth all (n-1)
    | _::tl -> aux (l::all) tl
    in
    try aux [] l with _ -> l

let rec listLast = function
| [] -> raise Not_found
| [x] -> x
| _::l -> listLast l

let stringStartsWith pref s =
  String.length s >= String.length pref &&
    String.sub s 0 (String.length pref) = pref

let stringChopPrefix s pref =
  String.sub s (String.length pref) (String.length s - String.length pref)

let stringIndexListFrom s i cList =
  let l = String.length s in
  let r = List.fold_left (fun r c -> min r (try String.index_from s i c with Not_found -> l)) l cList in
  if r = l then raise Not_found
  else r

let stringSplitKeepLastEmpty s cList =
  let l = String.length s in
  if l = 0 then []
  else
    let rec aux i =
      if i >= l then [""]
      else match stringIndexListFrom s i cList with
      | j when j = i -> aux (j+1)
      | j -> (String.sub s i (j-i))::(aux (j+1))
      | exception Not_found -> [String.sub s i (l-i)]
    in
    aux 0

let commaSeparatedString s =
  let l = String.length s in
  if l <= 3 then s
  else
    let l' = l + (l-1)/3 in
    let g k =
      let k' = l' - k - 1 in
      if k' mod 4 = 3 then ','
      else s.[l - k' + k'/4 - 1]
    in
    String.init l' g

let commaSeparatedInt64 i = commaSeparatedString (Int64.to_string i)
let commaSeparatedInt i = commaSeparatedString (string_of_int i)

let formatSize = commaSeparatedInt64
let formatInt = commaSeparatedInt

let formatPercent f =
  Printf.sprintf "%2.2f" (f *. 100.)

module Path = struct

  type t = { l: string list;
             s: string }
  
  let empty = { l = [];
                s = "/" } (* Unix only!!! *)

  let concat path name = { l = name::path.l;
                           s = Filename.concat path.s name }

  let toString path = path.s

  let baseName path = match path.l with
  | [] -> ""
  | hd::_ -> hd

  let filenameDirOpt filename =
    let d = Filename.dirname filename in
    if d = filename then None
    else Some d

  let rec filenameLength filename =
    match filenameDirOpt filename with
    | None -> 1
    | Some d -> 1 + (filenameLength d)

  let dirSepLength = String.length Filename.dir_sep

  let filenameIsParent f1 f2 =
    let l1 = String.length f1 in
    let l2 = String.length f2 in
    l1 + dirSepLength < l2 && String.sub f2 l1 dirSepLength = Filename.dir_sep && String.sub f2 0 l1 = f1

  let ofString path =
    let rec lOfString path =
      let b = Filename.basename path in
      match filenameDirOpt path with
      | None -> []
      | Some d -> b::(lOfString d)
    in
    { l = lOfString path;
      s = path }

  let currentDirPrefix = Filename.concat Filename.current_dir_name ""
  let parentDirPrefix = Filename.concat Filename.parent_dir_name ""

  let rec smartConcat cwd filename =
    if not (Filename.is_relative filename) then filename
    else if filename = Filename.current_dir_name then cwd
    else if filename = Filename.parent_dir_name then Filename.dirname cwd
    else if Filename.is_implicit filename then Filename.concat cwd filename
    else if stringStartsWith currentDirPrefix filename then smartConcat cwd (stringChopPrefix filename currentDirPrefix)
    else if stringStartsWith parentDirPrefix filename then smartConcat (Filename.dirname cwd) (stringChopPrefix filename parentDirPrefix)
    else begin
      Printf.printf "Don't know how to smartConcat '%S' with '%S'\n" cwd filename;
      filename
    end

  let cwd = Unix.getcwd ()

  let makeAbsolute filename =
    smartConcat cwd filename

end

module type NodeAndLeaf = sig

  type node
  type leaf
  val emptyNode: node
  val nodeOfLeaf: leaf -> node
  val replace: (* from *) node -> (* to *) node -> (* in *) node -> node

end

module MakePathTree(NAL : NodeAndLeaf) = struct

  type t =
  | Node of (NAL.node * t StringMap.t)
  | Leaf of NAL.leaf

  let nodeEmpty = NAL.emptyNode, StringMap.empty
  let empty = Node nodeEmpty

  let nodeOfTree = function
  | Leaf l -> NAL.nodeOfLeaf l
  | Node (n, _) -> n

  let nodeReplace pathElt ot t n m =
    NAL.replace (nodeOfTree ot) (nodeOfTree t) n, StringMap.add pathElt t m

  let getSubElt (tree, mk) pathElt =
    let n, m = match tree with
    | Leaf _ -> nodeEmpty
    | Node nm -> nm
    in
    let subTree = try StringMap.find pathElt m with Not_found -> empty in
    subTree, fun t -> mk (Node (nodeReplace pathElt subTree t n m))

  let subElt tree pathElt = getSubElt (tree, fun x -> x) pathElt

  let subPath tree path =
    let rpath = List.rev path.Path.l in
    List.fold_left getSubElt (tree, fun x -> x) rpath

  let nodeOfSubPath tree path =
    let subTree, _ = subPath tree path in
    nodeOfTree subTree

  let getLeaf tree = match tree with
  | Leaf x -> x
  | Node _ -> raise Not_found (* TODO: make diff between empty/non-empty dir *)

  let getLeaves tree =
    let rec aux _ tree acc = match tree with
    | Leaf x -> x::acc
    | Node (_, m) -> StringMap.fold aux m acc
    in
    aux "" tree []

  let getNodes tree =
    let rec auxOfTree path tree acc =
      match tree with
      | Leaf x -> (path, NAL.nodeOfLeaf x)::acc
      | Node (n, m) -> StringMap.fold (aux path) m ((path, n)::acc)
    and aux path name tree acc =
      let path = Path.concat path name in
      auxOfTree path tree acc
    in
    auxOfTree Path.empty tree []

  let switch onLeaf onNode tree = match tree with
  | Leaf x -> onLeaf x
  | Node (n, t) -> onNode n t

  let switchFold onLeaf onNodeElt tree acc = match tree with
  | Leaf x -> onLeaf x acc
  | Node (_, m) -> StringMap.fold onNodeElt m acc

  let leaf x = Leaf x

  let node n m = Node (n, m)

end

module FsNode = struct

  type node = { nbFiles: int; size: int64 }
  type leaf = int64 * float * H.t

  let emptyNode = { nbFiles = 0; size = 0L }

  let nodeOfLeaf (size, _, _) = { nbFiles = 1; size = size }

  let replace fromNode toNode inNode =
    { nbFiles = inNode.nbFiles - fromNode.nbFiles + toNode.nbFiles;
      size = Int64.add (Int64.sub inNode.size fromNode.size) toNode.size }
end

module PathTree = MakePathTree(FsNode)

module DirHashNode = struct

  type leaf = int64 * H.t
  type node = leaf * leaf list

  let emptyNode = (0L, H.empty), []

  let nodeOfLeaf x = x, [x]

  let replace _fromNode _toNode _inNode = assert false

  let makeNode leaves =
    let sizes, hashes = listRevSplit leaves in
    let size = List.fold_left Int64.add 0L sizes in
    let hash = H.combine hashes in
    (size, hash), leaves

end

module DHTree = MakePathTree(DirHashNode)

type 'tree genIndex = {
  hashes: StringSet.t HMap.t Int64Map.t;
  tree: 'tree;
}

module DHIndex = struct

  let empty = { hashes = Int64Map.empty;
                tree = DHTree.empty }

end

type index = PathTree.t genIndex

module Index = struct

  let empty = { hashes = Int64Map.empty;
                tree = PathTree.empty }

  let fromFile filename =
    let ic = open_in_bin filename in
    let index = Marshal.from_channel ic in
    close_in ic;
    (index : index)

  let fromFileOrEmpty filename =
    try fromFile filename with _ -> empty

  let toFile filename (index : index) =
    let oc = open_out_bin filename in
    Marshal.to_channel oc index [];
    close_out oc

  let mkSub f index path =
    let subTree, mk = f index.tree path in
    let mk index = { index with tree = mk index.tree } in
    { index with tree = subTree }, mk

  let subPath = mkSub PathTree.subPath
  let subElt = mkSub PathTree.subElt

  let switchFold onLeaf onNodeElt index =
    PathTree.switchFold onLeaf onNodeElt index.tree index

end

module Exclusion = struct

  module ExclNode = struct
    type node = unit
    type leaf = unit
    let emptyNode = ()
    let nodeOfLeaf unit = unit
    let replace _from _to _in = assert false
  end

  module ExclTree = MakePathTree(ExclNode)

  let add f tree =
    let f = Path.makeAbsolute f in
    let path = Path.ofString f in
    let rpath = List.rev path.Path.l in
    let rec aux tree rpath =
      match rpath with
      | [] -> ExclTree.leaf ()
      | name::rpath ->
        let onLeaf () = tree in
        let onNode () m =
          let subTree = try StringMap.find name m with Not_found -> ExclTree.empty in
          ExclTree.node () (StringMap.add name (aux subTree rpath) m)
        in
        ExclTree.switch onLeaf onNode tree
    in
    aux tree rpath

  let read filename =
    match open_in filename with
    | ic ->
      let rec aux tree =
        match String.trim (input_line ic) with
        | "" -> aux tree
        | f when f.[0] = '#' -> aux tree
        | f -> aux (add f tree)
        | exception End_of_file ->
          close_in ic;
          tree
      in
      aux ExclTree.empty
    | exception _ -> ExclTree.empty

  let filename indexFile =
    indexFile ^ ".excl"

  let isExcluded tree =
    ExclTree.switch (fun _ -> true) (fun _ _ -> false) tree

  let subElt tree filename =
    fst (ExclTree.subElt tree filename)

end

let rmFileFromHashes index size h filename = 
  let hm = Int64Map.find size index.hashes in
  let fs = HMap.find h hm in
  let fs = StringSet.remove filename fs in
  let hm = if StringSet.is_empty fs then
      HMap.remove h hm
    else
      HMap.add h fs hm in
  let hashes = if HMap.is_empty hm then
      Int64Map.remove size index.hashes
    else
      Int64Map.add size hm index.hashes
  in
  { index with hashes = hashes }

let isFileInHashes index size h filename =
  match Int64Map.find size index.hashes with
  | hm ->
    begin match HMap.find h hm with
    | fs -> StringSet.mem filename fs
    | exception Not_found -> false
    end
  | exception Not_found -> false

let addFileToHashes index size h filename =
  let hm = match Int64Map.find size index.hashes with
  | hm ->
    let fs = match HMap.find h hm with
    | fs -> StringSet.add filename fs
    | exception Not_found -> StringSet.singleton filename
    in
    HMap.add h fs hm
  | exception Not_found -> HMap.singleton h (StringSet.singleton filename)
  in
  { index with hashes = Int64Map.add size hm index.hashes }

let rec rmAllFiles index path =
  let onLeaf (sz, _, h) index = rmFileFromHashes index sz h (Path.toString path) in
  let onNodeElt name tree index = rmAllFiles { index with tree = tree } (Path.concat path name) in
  let index = Index.switchFold onLeaf onNodeElt index in
  { index with tree = PathTree.empty }

let rmRemovedFiles path files index =
  let onLeaf _ index = index in
  let onNodeElt name t index =
    if StringSet.mem name files then index
    else
      let index, mk = Index.subElt index name in
      mk (rmAllFiles index (Path.concat path name))
  in
  Index.switchFold onLeaf onNodeElt index

let addRegFileToIndex index path stats =
  let size = stats.Unix.LargeFile.st_size in
  let filename = Path.toString path in
  Printf.printf "File %s (%s) " filename (formatSize size);
  let toAdd, toRm = match PathTree.getLeaf index.tree with
  | sz, _, h when sz <> size ->
    Printf.printf "changed (size was %s)\n" (formatSize sz);
    true, Some (sz, h)
  | sz, tm, h when tm < stats.Unix.LargeFile.st_mtime ->
    Printf.printf "changed (time)\n";
    true, Some (sz, h)
  | _ ->
    Printf.printf "unchanged\n";
    false, None
  | exception Not_found ->
    Printf.printf "new\n";
    true, None
  in
  let index = match toRm with
  | Some (sz, h) -> rmFileFromHashes index sz h filename
  | None -> index
  in
  if toAdd then
    match H.file filename with
    | h ->
      let index = addFileToHashes index size h filename in
      { index with tree = PathTree.leaf (size, Unix.gettimeofday (), h) }
    | exception _ ->
      Printf.printf "Failed to hash file %s\n" filename;
      index
  else
    index

let rec addFileToIndex excl index path =
  if Exclusion.isExcluded excl then begin
    Printf.printf "Excluded file %s\n" (Path.toString path);
    index
  end else
    match Unix.LargeFile.lstat (Path.toString path) with
    | stats ->
      let index = match stats.Unix.LargeFile.st_kind with
      | Unix.S_REG -> addRegFileToIndex index path stats
      | Unix.S_DIR -> addDirToIndex excl index path
      | _ ->
        Printf.printf "Ignore file %s\n" (Path.toString path);
        index
      in
      index
    | exception _ ->
      Printf.printf "Failed to lstat file %s\n" (Path.toString path);
      index

and addDirToIndex excl index path =
  Printf.printf "In %s\n" (Path.toString path);
  let rec aux dh files index =
    match Unix.readdir dh with
    | filename when filename = Filename.current_dir_name
               || filename = Filename.parent_dir_name ->
      aux dh files index
    | filename ->
      let index, mk = Index.subElt index filename in
      let index = addFileToIndex (Exclusion.subElt excl filename) index (Path.concat path filename) in
      aux dh (StringSet.add filename files) (mk index)
    | exception End_of_file ->
      Unix.closedir dh;
      rmRemovedFiles path files index
  in
  match Unix.opendir (Path.toString path) with
  | dh -> aux dh StringSet.empty index
  | exception _ ->
    Printf.printf "Failed!\n";
    index

let addOneToIndex excl index filename =
  let path = Path.ofString filename in
  let index, mk = Index.subPath index path in
  let index = addFileToIndex excl index path in
  mk index

let printSummaryDiff node0 node1 =
  if node1.FsNode.nbFiles < node0.FsNode.nbFiles then
    Printf.printf "%s file(s) removed\n" (formatInt (node0.FsNode.nbFiles - node1.FsNode.nbFiles))
  else
    Printf.printf "%s file(s) added\n" (formatInt (node1.FsNode.nbFiles - node0.FsNode.nbFiles));
  if node1.FsNode.size < node0.FsNode.size then
    Printf.printf "%s byte(s) removed\n" (formatSize (Int64.sub node0.FsNode.size node1.FsNode.size))
  else
    Printf.printf "%s byte(s) added\n" (formatSize (Int64.sub node1.FsNode.size node0.FsNode.size))

let addToSavedIndex dirl excl index =
  let node0 = PathTree.nodeOfTree index.tree in
  let index = List.fold_left (addOneToIndex excl) index (List.map Path.makeAbsolute dirl) in
  let node1 = PathTree.nodeOfTree index.tree in
  printSummaryDiff node0 node1;
  index

let rmOneFromIndex index filename =
  let path = Path.ofString filename in
  let index, mk = Index.subPath index path in
  let index = rmAllFiles index path in
  mk index

let rmFromSavedIndex dirl index =
  let node0 = PathTree.nodeOfTree index.tree in
  let index = List.fold_left rmOneFromIndex index (List.map Path.makeAbsolute dirl) in
  let node1 = PathTree.nodeOfTree index.tree in
  printSummaryDiff node0 node1;
  index

let listDup index =
  let forHash size _h set l =
    if StringSet.is_empty set || (StringSet.min_elt set == StringSet.max_elt set) then l
    else (size, StringSet.elements set)::l
  in
  let forSize size hm l = HMap.fold (forHash size) hm l in
  Int64Map.fold forSize index.hashes []

let listFiles index =
  let forHash size _h set l = (size, StringSet.elements set)::l in
  let forSize size hm l = HMap.fold (forHash size) hm l in
  Int64Map.fold forSize index.hashes []

let noFilter x = x

let printFileList l =
  let printOneFile filename =
    Printf.printf " %s\n" filename
  in
  let printOne (size, list) =
    Printf.printf "Size %s\n" (formatSize size);
    List.iter printOneFile list
  in
  List.iter printOne l

let printSizeLost fileList =
  let totalSize = List.fold_left (fun tot (size, list) -> Int64.add tot (Int64.mul (Int64.of_int ((List.length list) - 1)) size)) 0L fileList in
  Printf.printf "Total size lost: %s\n" (formatSize totalSize)

let printDup filter final () index =
  let ldup = listDup index in
  let ldup = filter ldup in
  let ldup = List.sort Pervasives.compare ldup in
  printFileList ldup;
  final ldup

type simInfo = {
  simIndex: float;
  fileSim: float;
  sizeSim: float;
  simFiles: int;
  simSize: int64;
}
  
type sim = simInfo SUPMap.t

let dirHashIndex index =
  let rec aux path hashes tree =
    let onLeaf (sz, _, h) = { hashes = hashes; tree = DHTree.leaf (sz, h) } in
    let onNode _ m =
      let f name tree (m, hashes) =
        let index = aux (Path.concat path name) hashes tree in
        let m = StringMap.add name index.tree m in
        m, index.hashes
      in
      let m, hashes = StringMap.fold f m (StringMap.empty, hashes) in
      let dhl = List.map (snd @> DHTree.nodeOfTree @> snd) (StringMap.bindings m) in
      let dh = List.flatten dhl in
      let dh = List.sort Pervasives.compare dh in
      let ((size, hash), dh) as node = DirHashNode.makeNode dh in
      let index = { hashes = hashes; tree = DHTree.node node m } in
      addFileToHashes index size hash (Path.toString path)
    in
    PathTree.switch onLeaf onNode tree
  in
  aux Path.empty Int64Map.empty index.tree

let printDDup () index =
  let rec self_or_parent_in path set =
    if StringSet.mem path set then true
    else match Path.filenameDirOpt path with
    | Some path -> self_or_parent_in path set
    | None -> false
  in
  let rec filter set acc list =
    match list with
    | [] -> acc
    | (size, _)::list when size <= 1L -> filter set acc list
    | (size, l)::list ->
      let rec aux set acc l =
        match l with
        | [] -> set, acc
        | f::l when self_or_parent_in f set -> aux set acc l
        | f::l -> aux (StringSet.add f set) (f::acc) l
      in
      let set', l = aux set [] l in
      match l with
      | [] | [_] -> filter set acc list
      | l -> filter set' ((size, l)::acc) list
  in
  printDup (filter StringSet.empty []) printSizeLost () (dirHashIndex index)

let listSim maxToShow () index =
  let dirHashIndex = dirHashIndex index in
  let dirHashTree = dirHashIndex.tree in
  let getDirHashes dir = DHTree.nodeOfSubPath dirHashTree (Path.ofString dir) in
  let compSim (dir1, dir2) =
    Printf.printf "Comparing %s and %s\n" dir1 dir2;
    let ((s1, _) as dH1), dh1 = getDirHashes dir1 in
    let ((s2, _) as dH2), dh2 = getDirHashes dir2 in
    let n1 = List.length dh1 in
    let n2 = List.length dh2 in
    let simF, simS =
      if dH1 = dH2 then min n1 n2, s1
      else
        let rec aux dh1 dh2 ((simF, simS) as simInf) = match dh1, dh2 with
        | _, [] | [], _ -> simInf
        | f1::dh1, f2::dh2 when f1 = f2 -> aux dh1 dh2 (simF + 1, Int64.add simS s1)
        | f1::dh1, f2::_ when f1 < f2 -> aux dh1 dh2 (simF, simS)
        | _, _::dh2 -> aux dh1 dh2 (simF, simS)
        in
        aux dh1 dh2 (0, 0L)
    in
    let maxN = max n1 n2 in
    let maxS = max s1 s2 in
    let fileSim = if maxN = 0 then 0. else (float_of_int simF) /. (float_of_int maxN) in
    let sizeSim = if maxS = 0L then 0. else (Int64.to_float simS) /. (Int64.to_float maxS) in
    let simIndex = max fileSim sizeSim in
    { simIndex = simIndex;
      fileSim = fileSim;
      sizeSim = sizeSim;
      simFiles = simF;
      simSize = simS }
  in
  let rec trySim dir1 dir2 sim =
    if dir1 = dir2 || Path.filenameIsParent dir1 dir2 || Path.filenameIsParent dir2 dir1 then sim
    else
      let dirp = SUP.make dir1 dir2 in
      if SUPMap.mem dirp sim then sim
      else
        let si = compSim dirp in
        let sim = SUPMap.add dirp si sim in
        match si, Path.filenameDirOpt dir1, Path.filenameDirOpt dir2 with
        | si, Some dir1, Some dir2 when si.simIndex > 0.1 -> trySim dir1 dir2 sim
        | _ -> sim
  in
  let rec tryPairsWith dir1 files sim = match files with
  | [] -> sim
  | file2::files ->
    let sim = trySim dir1 (Filename.dirname file2) sim in
    tryPairsWith dir1 files sim
  in
  let rec tryPairs files sim = match files with
  | [] | [_] -> sim
  | file1::files ->
    let sim = tryPairsWith (Filename.dirname file1) files sim in
    tryPairs files sim
  in
  let forHash _h set sim =
    tryPairs (StringSet.elements set) sim
  in
  let forSize size hm sim =
    if size >= 10L then
      HMap.fold forHash hm sim
    else
      sim
  in
  let sim = Int64Map.fold forSize index.hashes SUPMap.empty in
  let siml = SUPMap.bindings sim in
  let simEltVal (_, si) = si.simIndex, si.sizeSim, si.simSize, si.simFiles in
  let simEltCmp e1 e2 = Pervasives.compare (simEltVal e1) (simEltVal e2) in
  let siml = List.sort simEltCmp siml in
  let siml = listKeepLast maxToShow siml in
  let printSim ((d1, d2), si) =
    Printf.printf "Similarity %s%%: files %s%% (%s), size %s%% (%s)\n"
      (formatPercent si.simIndex)
      (formatPercent si.fileSim) (formatInt si.simFiles)
      (formatPercent si.sizeSim) (formatSize si.simSize);
    Printf.printf " Path %s\n" d1;
    Printf.printf "  and %s\n\n" d2;
  in
  List.iter printSim siml

let printStats () index =
  Printf.printf "Sizes: %s different\n" (formatInt (Int64Map.cardinal index.hashes));
  Printf.printf "       from %s\n" (formatSize (fst (Int64Map.min_binding index.hashes)));
  Printf.printf "       to %s\n\n" (formatSize (fst (Int64Map.max_binding index.hashes)));
  let count, sizeLost = Int64Map.fold (
    fun sz h (count, sizeLost) ->
      let card = HMap.cardinal h in
      count + card, Int64.add sizeLost (Int64.mul sz (Int64.of_int (card - 1)))
  ) index.hashes (0, 0L) in
  Printf.printf "Hashes: %s\n\n" (formatInt count);
  let node = PathTree.nodeOfTree index.tree in
  Printf.printf "Files: %s\n" (formatInt node.FsNode.nbFiles);
  Printf.printf "Total size: %s\n" (formatSize node.FsNode.size);
  Printf.printf "Total size lost: %s\n" (formatSize sizeLost)

let collectAllFiles tree =
  let nodes = PathTree.getNodes tree in
  let nodeV (_, n) = n.FsNode.size in
  let cmpNode n1 n2 = Pervasives.compare (nodeV n1) (nodeV n2) in
  List.sort cmpNode nodes

let diskUsage maxToShow filename index =
  let filename = Path.makeAbsolute filename in
  let path = Path.ofString filename in
  let tree, _ = PathTree.subPath index.tree path in
  let root = PathTree.nodeOfTree tree in
  if root.FsNode.size <= 0L then
    Printf.printf "Empty!\n"
  else
    let files = collectAllFiles tree in
    let files = listKeepLast maxToShow files in
    let printFile (path, n) =
      Printf.printf "%s%% (%s) %s (%s file(s))\n"
        (formatPercent ((Int64.to_float n.FsNode.size) /. (Int64.to_float root.FsNode.size)))
        (formatSize n.FsNode.size) (Path.toString path)
        (formatInt n.FsNode.nbFiles);
    in
    List.iter printFile files

let diskUsageTree maxToShow filename index =
  let path = Path.ofString filename in
  let tree, _ = PathTree.subPath index.tree path in
  let root = PathTree.nodeOfTree tree in
  if root.FsNode.size <= 0L then
    Printf.printf "Empty!\n"
  else
    let files = collectAllFiles tree in
    let files = listKeepLast maxToShow files in
    let addToSet s (path, _) = StringSet.add (Path.toString path) s in
    let bigFiles = List.fold_left addToSet StringSet.empty files in
    let printFile margin path n isFile =
      Printf.printf "%s%s%% (%s) %s%s\n" margin
        (formatPercent ((Int64.to_float n.FsNode.size) /. (Int64.to_float root.FsNode.size)))
        (formatSize n.FsNode.size) (Path.toString path)
        (if isFile then "" else Printf.sprintf " (%s file(s))" (formatInt n.FsNode.nbFiles))
    in
    let rec walkPath margin path tree =
      if StringSet.mem (Path.toString path) bigFiles then begin
        let onFile leaf = printFile margin path (FsNode.nodeOfLeaf leaf) true in
        let onNode node m =
          printFile margin path node false;
          let l = StringMap.bindings m in
          let nodeV (_, tree) = (PathTree.nodeOfTree tree).FsNode.size in
          let cmpNode n1 n2 = Pervasives.compare (nodeV n1) (nodeV n2) in
          let l = List.sort cmpNode l in
          List.iter (walk (margin ^ "  ") path) l in
        PathTree.switch onFile onNode tree
      end
    and walk margin parent (name, tree) =
      walkPath margin (Path.concat parent name) tree
    in
    walkPath "" Path.empty tree

let printHashes () index =
  printFileList (listFiles index)  

let printDirHashes () index =
  printHashes () (dirHashIndex index)

let checkIndex () index =
  let rec checkTree path index =
    let onLeaf (sz, _, h) index =
      if isFileInHashes index sz h (Path.toString path) then index
      else begin
        Printf.printf "%s (hash missing)\n" (Path.toString path);
        { index with tree = PathTree.empty }
      end
    in
    let onNodeElt name t index =
      let index, mk = Index.subElt index name in
      mk (checkTree (Path.concat path name) index)
    in
    Index.switchFold onLeaf onNodeElt index
  in
  let checkHashes index =
    let forFile size h filename index =
      let path = Path.ofString filename in
      let tree, mk = PathTree.subPath index.tree path in
      match PathTree.getLeaf tree with
      | (sz, _, _) when size <> sz ->
        Printf.printf "%s (size mismatch)\n" filename;
        let index = rmFileFromHashes index size h filename in
        { index with tree = mk PathTree.empty }
      | (_, _, h') when h <> h' ->
        Printf.printf "%s (hash mismatch)\n" filename;
        let index = rmFileFromHashes index size h filename in
        { index with tree = mk PathTree.empty }
      | _ -> index
      | exception Not_found ->
        Printf.printf "%s (missing tree leaf)\n" filename; (* todo: diff empty/non-empty dir *)
        rmFileFromHashes index size h filename
    in
    let forHash size h set index = StringSet.fold (forFile size h) set index in
    let forSize size hm index = HMap.fold (forHash size) hm index in
    Int64Map.fold forSize index.hashes index
  in
  let index = checkTree Path.empty index in
  checkHashes index

let withIndexFileRO f indexFile =
  let index = Index.fromFileOrEmpty indexFile in
  f index

let withIndexFileRW f indexFile =
  let index = Index.fromFileOrEmpty indexFile in
  let index = f index in
  Index.toFile indexFile index

let withIndexAndExclFilesRW f indexFile =
  let index = Index.fromFileOrEmpty indexFile in
  let excl = Exclusion.read (Exclusion.filename indexFile) in
  let index = f excl index in
  Index.toFile indexFile index


let maxToShow = 10000
let maxToShowSmall = 200
let myName = "fsindex"


type ('z, 'o, 'l, 'b) genGenSpec =
  | Zero of 'z
  | One of 'o * 'b
  | List of 'l * 'b

module BashComplete = struct

  type t = File | Dir | Nothing | FunAll of (string list -> unit)

  let completeCommand cmd arg =
    cmd |> List.map fst3 |> List.filter (stringStartsWith arg) |> List.iter print_endline
  let completeFile arg = Sys.command (Printf.sprintf "bash -c \"compgen -f -- '%s'\"" arg) |> ignore
  let completeDir arg = Sys.command (Printf.sprintf "bash -c \"compgen -d -- '%s'\"" arg) |> ignore

  let completeT t args arg =
    match t with
    | File -> completeFile arg
    | Dir -> completeDir arg
    | Nothing -> ()
    | FunAll f -> f args

  let completeSpec spec args =
    match spec with
    | Zero _ -> ()
    | One (_, t) ->
      let first a = completeT t args a in
      begin match args with
      | [] -> first ""
      | [a] -> first a
      | _ -> () end
    | List (_, t) ->
      completeT t args (try listLast args with Not_found -> "")

  let genCommand cmd more default args =
    let first a = completeCommand cmd a; more a in
    match args with
    | [] -> first ""
    | [a] -> first a
    | a0::args ->
      match List.find (fst3 @> ((=) a0)) cmd with
      | (_, spec, _) -> completeSpec spec args
      | exception Not_found -> default args

  let command cmd args = genCommand cmd ignore ignore args

  let commandOrFile cmd following args = genCommand cmd completeFile following args

end

module type ArgSpec = sig

  type 'arg t
  type acc

  val doCommand: 'arg -> 'arg t -> acc -> unit

end

type ('z, 'o, 'l) genSpec = ('z, 'o, 'l, BashComplete.t) genGenSpec

module type MadeArg = sig
  module ArgSpec : ArgSpec
  type spec = (unit ArgSpec.t, string ArgSpec.t, string list ArgSpec.t) genSpec
end

module MakeArg(AS : ArgSpec) : (MadeArg with module ArgSpec = AS) = struct
  module ArgSpec = AS
  type spec = (unit AS.t, string AS.t, string list AS.t) genSpec
end

module type ArgCommand = sig
  module A : MadeArg

  val commands : (string * A.spec * string) list

  val default : A.ArgSpec.acc -> string -> string list -> unit
    
end

module MakeCommands(AC : ArgCommand) = struct
  module AS = AC.A.ArgSpec

  let doCommand acc command spec args =
    let checkExactArgs n =
      let a = List.length args in
      if a <> n then
        raise (Arg.Bad (Printf.sprintf "Command %s expect %d arguments, %d given" command n a))
    in
    match spec with
    | Zero t -> checkExactArgs 0; AS.doCommand () t acc
    | One (t, _) -> checkExactArgs 1; AS.doCommand (List.hd args) t acc
    | List (t, _) -> AS.doCommand args t acc

  let parse acc args = match args with
  | [] -> raise (Arg.Bad "Missing command")
  | command::args ->
    match List.find (fst3 @> ((=) command)) AC.commands with
    | _, indexSpec, _ -> doCommand acc command indexSpec args
    | exception Not_found -> AC.default acc command args

  let usage () =
    let padFor =
      let maxLength = List.fold_left (fun m (k, _, _) -> max m (String.length k)) 0 AC.commands in
      fun s -> String.make (maxLength + 3 - String.length s) ' '
    in
    let commandUsage (k, _, doc) = Printf.printf " %s%s%s\n" k (padFor k) doc in
    List.iter commandUsage AC.commands

end

module IndexCmd = struct
  module ArgSpec = struct
    type 'arg t =
    | RWExcl of ('arg -> Exclusion.ExclTree.t -> index -> index)
    | RW of ('arg -> index -> index)
    | RO of ('arg -> index -> unit)

    type acc = string

    let doCommand arg t =
      match t with
      | RWExcl f -> withIndexAndExclFilesRW (f arg)
      | RW f -> withIndexFileRW (f arg)
      | RO f -> withIndexFileRO (f arg)
  end

  module A = MakeArg(ArgSpec)
  open ArgSpec

  let commands = [
    "add", List (RWExcl addToSavedIndex, BashComplete.File), "add/update files/directories to index";
    "rm", List (RW rmFromSavedIndex, BashComplete.File), "remove files/directories from index";
    "ldup", Zero (RO (printDup noFilter printSizeLost)), "list duplicate files";
    "ddup", Zero (RO printDDup), "list duplicate directories";
    "lsim", Zero (RO (listSim maxToShow)), "list similar directories";
    "stats", Zero (RO printStats), "print stats";
    "du", One (RO (diskUsage maxToShow), BashComplete.Dir), "print biggest files/directories in some directory";
    "dut", One (RO (diskUsageTree maxToShowSmall), BashComplete.Dir), "print biggest files/directories in some directory (shown as a tree)";
    "phashes", Zero (RO printHashes), "print all files in index";
    "pdhashes", Zero (RO printDirHashes), "print all directories in index";
    "check", Zero (RW checkIndex), "check index and remove partial entries";
  ]

  let default command args =
    raise (Arg.Bad ("Unknown command " ^ command))

  let bashComplete args = BashComplete.command commands args
end
module IndexCommands = MakeCommands(IndexCmd)

module MainCmd = struct
  module ArgSpec = struct
    type 'arg t = 'arg -> unit
    type acc = unit
    let doCommand arg t () = t arg
  end
  module A = MakeArg(ArgSpec)
  
  let help () = raise (Arg.Help "Help requested")

  let saveArgv args =
    let oc = open_out "argv" in 
    List.iter (fun a -> output_string oc (a ^ "\n")) args;
    close_out oc

  let bashCompletion () =
    Printf.printf "# Bash completion script for %s\n" myName;
    Printf.printf "# Put this script in /etc/bash_completion.d/\n\n";
    Printf.printf "complete -C %s %s\n" myName myName

  let rec bashComplete args =
    BashComplete.commandOrFile commands IndexCmd.bashComplete args

  and bashCompleteMain args =
    saveArgv args;
    match args with
    | [] -> ()
    | _::args -> bashComplete args

  and commands = [
    "--help", Zero help, "print this help";
    (* "--bashcomplete", List (bashCompleteMain, BashComplete.FunAll bashCompleteMain), "help completion script"; *)
    "--bashcompletion", Zero bashCompletion, "print completion script";
  ]

  let default () = IndexCommands.parse
end
module MainCommands = MakeCommands(MainCmd)

let main () =
  let usage () =
    Printf.printf "Usage (1): %s <command> [<command args>]\n\n" myName;
    Printf.printf "where <command> can be:\n";
    MainCommands.usage ();
    Printf.printf "\n";
    Printf.printf "Usage (2): %s <index file> <command> [<command args>]\n\n" myName;
    Printf.printf "where <command> can be:\n";
    IndexCommands.usage ();
    Printf.printf "\n"
  in
  let help msg =
    Printf.printf "%s\n\n" msg;
    usage ()
  in
  try
    MainCommands.parse () (List.tl (Array.to_list Sys.argv))
  with
  | Arg.Help msg -> help msg
  | Arg.Bad msg -> help ("Error: " ^ msg)

let complete line =
  let wordBreaks = [' ';'\t';'\r';'\n'] in
  let point = try int_of_string (Sys.getenv "COMP_POINT") with Not_found -> String.length line in
  let line = if point < String.length line then String.sub line 0 point else line in
  let args = stringSplitKeepLastEmpty line wordBreaks in
  MainCmd.bashCompleteMain args

let mainOrComplete () =
  match Sys.getenv "COMP_LINE" with
  | line -> complete line
  | exception Not_found -> main ()

let _ =
  Printexc.record_backtrace true;
  try mainOrComplete () with
  | exn ->
    Printf.printf "Exception:\n %s\n" (Printexc.to_string exn);
    Printexc.print_backtrace stdout