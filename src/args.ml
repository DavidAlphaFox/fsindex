
open ArgSpec
open More

type 'a t = 'a argSpec

type wrapped = Wrapped : 'a t -> wrapped

let completeCommand cmd arg =
  cmd |> List.map fst3 |> List.filter (stringStartsWith arg) |> List.iter print_endline
let completeFile arg = Sys.command (Printf.sprintf "bash -c \"compgen -f -- '%s'\"" arg) |> ignore
let completeDir arg = Sys.command (Printf.sprintf "bash -c \"compgen -d -- '%s'\"" arg) |> ignore

let rec completeT : type a. a t -> string -> unit = fun t arg ->
  match t with
  | Apply (_, t') -> completeT t' arg
  | Commands cmd -> completeCommand cmd arg
  | Dir -> completeDir arg
  | File -> completeFile arg
  | List t' -> completeT t' arg
  | Nothing -> ()
  | Or (t1, t2) -> completeT t1 arg; completeT t2 arg
  | Then (t1, t2) -> completeT t1 arg

let rec matchFirst : type a. a t -> string -> wrapped = fun t0 a ->
  match t0 with
  | Apply (_, t') -> matchFirst t' a
  | Commands cmd ->
    Wrapped (snd3 (List.find (fst3 @> ((=) a)) cmd))
  | Dir -> Wrapped Nothing
  | File -> Wrapped Nothing
  | List t ->
    (match matchFirst t a with
    | Wrapped Nothing -> Wrapped (List t)
    | Wrapped t' -> Wrapped (Then (t', t0)))
  | Nothing -> raise Not_found
  | Or (t1, t2) ->
    (match matchFirst t1 a with
    | exception Not_found -> matchFirst t2 a
    | Wrapped Nothing -> matchFirst t2 a
    | Wrapped t1 -> Wrapped t1)
  | Then (t1, t2) ->
    match matchFirst t1 a with
    | Wrapped Nothing -> Wrapped t2
    | Wrapped t1 -> Wrapped (Then (t1, t2))

let rec doComplete : type a. a t -> string list -> unit= fun t args ->
  match args with
  | [] -> completeT t ""
  | [a] -> completeT t a
  | a0::args ->
    match matchFirst t a0 with
    | exception Not_found -> ()
    | Wrapped t' -> doComplete t' args

let compute : type a. a t -> string list -> a = fun t args ->
  let rec aux : type a. a t -> string list -> a Lazy.t * string list = fun t args ->
    match t, args with
    | Apply (f, t'), _ ->
      let res, rem = aux t' args in
      lazy (f (Lazy.force res)), rem
    | Commands _, [] -> raise (Arg.Bad "Missing command")
    | Commands cmd, command::args ->
      (match List.find (fst3 @> ((=) command)) cmd with
      | _, t, _ -> aux t args
      | exception Not_found -> raise (Arg.Bad "Unknown command"))
    | Dir, [] -> raise (Arg.Bad "Missing directory name")
    | File, [] -> raise (Arg.Bad "Missing file name")
    | Dir, arg::args -> lazy arg, args
    | File, arg::args -> lazy arg, args
    | List _, [] -> lazy [], []
    | List t', args ->
      (match aux t' args with
      | exception (Arg.Bad _) -> lazy [], args
      | res, rem ->
        let res', rem = aux t rem in
        lazy ((Lazy.force res)::(Lazy.force res')), rem)
    | Nothing, args -> lazy (), args
    | Or (t1, t2), args ->
      (try aux t1 args with
      | Arg.Bad _ -> aux t2 args)
    | Then (t1, t2), args ->
      let res1, rem1 = aux t1 args in
      let res2, rem = aux t2 rem1 in
      lazy (Lazy.force res1, Lazy.force res2), rem
  in
  match aux t args with
  | v, [] -> Lazy.force v
  | _, rem -> raise (Arg.Bad "Too many arguments")
