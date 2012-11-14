
(** TOOO dump intermediate file *)

open Utils

let usage () =
  Printf.eprintf "Usage: %s <options> <files>\n" (Filename.basename Sys.argv.(0));
  Printf.eprintf "SPECIFIC OPTIONS:\n";
  Printf.eprintf "  -dir <dir>\t\tThe directory for generated files (default %S)\n"
    (if !kind = `Client then default_client_dir else default_server_dir);
  Printf.eprintf "  -type-dir <dir>\t\tThe directory to read .type_mli files from (default %S)\n"
     default_type_dir;
  if !kind =  `Server || !kind = `ServerOpt then begin
    Printf.eprintf "  -infer\t\tOnly infer the type of values sent by the server\n";
  end else begin
    Printf.eprintf "  -jsopt <opt>\t\tAppend option <opt> to js_of_ocaml invocation\n";
    Printf.eprintf "  -server-opt <opt> <value>\tUse the option <opt> with parameter \
       <value> during infering the types of the server (only necessary if js_of_eliom \
       is called without -infer). Options may be -dir if eliomc was used with a special \
       values for that as well, or -package)";
  end;
  Printf.eprintf "  -noinfer\t\tDo not infer the type of values sent by the server\n";
  Printf.eprintf "  -package <name>\tRefer to package when compiling\n";
  Printf.eprintf "  -predicates <p>\tAdd predicate <p> when resolving package properties\n";
  Printf.eprintf "  -ppopt <p>\tAppend option <opt> to preprocessor invocation\n";
  Printf.eprintf "  -type <file>\tInfered types for the values sent by the server.\n";
  create_filter !compiler ["-help"] (help_filter 2 "STANDARD OPTIONS:");
  if !kind = `Client then
    create_filter !js_of_ocaml ["-help"] (help_filter 1 "JS_OF_OCAML OPTIONS:");
  exit 1

(** Context *)

let jsopt : string list ref = ref []
let output_name : string option ref = ref None
let noinfer = ref false

type mode = [ `Link | `Compile | `InferOnly | `Library  | `Pack | `Obj | `Shared | `Interface ]

let mode : mode ref = ref `Link

let do_compile () = !mode <> `InferOnly
let do_infer () = not !noinfer
let do_interface () = !mode = `Interface
let do_dump = ref false

let server_dir = ref None
let server_package = ref []

let create_process ?in_ ?out ?err name args =
  wait (create_process ?in_ ?out ?err name args)

let rec check_or_create_dir name =
  if name <> "/" then
    try ignore(Unix.stat name) with Unix.Unix_error _ ->
      check_or_create_dir (Filename.dirname name);
      Unix.mkdir name 0o777

let prefix_output_dir name =
  match !build_dir with
    | "" -> name
    | d -> d ^ "/" ^ name

let chop_extension_if_any name =
  try Filename.chop_extension name with Invalid_argument _ -> name

let output_prefix ?(ty = false) name =
  let name =
    match !output_name with
    | None ->
	if !mode = `InferOnly || ty
	then prefix_type_dir name
	else prefix_output_dir name
    | Some n ->
	if !mode = `Compile || !mode = `InferOnly
	then (output_name := None; n)
	else prefix_output_dir name in
  check_or_create_dir (Filename.dirname name);
  chop_extension_if_any name

let set_mode m =
 if !mode = `Link then
   ( if
       (m = `Shared && !kind <> `ServerOpt) ||
       (m = `InferOnly && !kind = `Client) ||
       (m = `Interface && !kind = `Client)
     then
       usage ()
     else
       mode := m )
 else
   let args =
     let basic_args = ["-pack"; "-a"; "-c"; "output-obj"] in
     let infer_args = if !kind <> `Client then ["-i"; "-infer"] else [] in
     let shared_args = if !kind <> `ServerOpt then ["-shared"] else [] in
     basic_args @ infer_args @ shared_args
   in
   Printf.eprintf
     "Please specify at most one of %s\n%!"
     (String.concat ", " args);
  exit 1

let get_product_name () = match !output_name with
  | None ->
      Printf.eprintf
	"Please specify the name of the output file, using option -o\n%!";
      exit 1
  | Some name ->
      check_or_create_dir (Filename.dirname name);
      name

let build_library () =
  create_process !compiler ( ["-a" ; "-o"  ; get_product_name () ]
			     @ get_common_include ()
			     @ !args )

let build_pack () =
  create_process !compiler ( [ "-pack" ; "-o"  ; get_product_name () ]
			     @ get_common_include ()
			     @ !args )

let build_obj () =
  create_process !compiler ( ["-output-obj" ; "-o"  ; get_product_name () ]
			     @ get_common_include ()
			     @ !args )

let build_shared () =
  create_process !compiler ( ["-shared" ; "-o"  ; get_product_name () ]
			     @ get_common_include ()
			     @ !args )

let get_thread_opt () = match !kind with
  | `Client -> []
  | `Server | `ServerOpt -> ["-thread"]

let obj_ext () = if !kind = `ServerOpt then ".cmx" else ".cmo"

(* Process ml and mli files *)

let compile_ocaml ~impl_intf file =
  let obj =
    let ext = match impl_intf with
      | `Impl -> obj_ext ()
      | `Intf -> ".cmi"
    in
    output_prefix file ^ ext in
  create_process !compiler ( ["-c" ;
                              "-o" ; obj ;
                              "-pp"; get_pp []]
                             @ !args
			     @ get_thread_opt ()
			     @ get_common_include ()
			     @ [impl_intf_opt impl_intf; file] )

let output_ocaml_interface file =
    create_process !compiler ( ["-i"; "-pp"; get_pp []] @ !args
                               @ get_common_include ()
                               @ [file] )

let process_ocaml ~impl_intf file =
  if do_compile () then
    compile_ocaml ~impl_intf file;
  if do_interface () then
    output_ocaml_interface file

let compile_obj file =
  if do_compile () then
    ( create_process !compiler (!args @ [file]);
      args := !args @ [output_prefix file ^ ext_obj] )

(* Process eliom and eliomi files *)

let get_ppopts ~impl_intf file =
  let pa_cmo =
    match !kind with
      | `Client -> "pa_eliom_client_client.cmo"
      | `Server | `ServerOpt -> "pa_eliom_client_server.cmo"
  in
  pa_cmo :: type_opt impl_intf file @ !ppopt @ [impl_intf_opt impl_intf]

let compile_server_type_eliom file =
  let obj = output_prefix ~ty:true file ^ type_file_suffix
  and ppopts = ["pa_eliom_type_filter.cmo"] @ !ppopt @ ["-impl"] in
  if !do_dump then begin
    let camlp4, ppopt = get_pp_dump ("-printer" :: "o" :: ppopts @ [file]) in
    create_process camlp4 ppopt;
    exit 0
  end;
  let out = Unix.openfile obj [Unix.O_WRONLY; Unix.O_CREAT; Unix.O_TRUNC] 0o666 in
  (* We have to override kind, build_dir, package if js_of_eliom is
     called without -infer. *)
  let kind, build_dir, package =
    if !kind = `Client then
      (Some `Server,
       Some
         (match !server_dir with
           | Some dir -> dir
           | None -> default_server_dir),
       Some !server_package)
    else
      None, None, None
  in
  create_process ~out !compiler ( [ "-i" ; "-pp"; get_pp ppopts]
				  @ !args
    				  @ get_common_include ?kind ?build_dir ?package ()
				  @ ["-impl"; file] );
  Unix.close out

let output_eliom_interface ~impl_intf file =
  let ppopts = get_ppopts ~impl_intf file in
  let indent ch =
    try
      while true do
        let line = input_line ch in
        Printf.printf "  %s\n" line
      done
    with End_of_file -> ()
  in
  Printf.printf "(* WARNING `eliomc -i' generated this pretty ad-hoc - use with care! *)\n";
  Printf.printf "{server{\n";
    create_filter !compiler ( [ "-i" ; "-pp" ; get_pp ppopts; "-intf-suffix"; ".eliomi" ]
			         @ !args
			         @ get_common_include ~kind:`Server ()
			         @ [impl_intf_opt impl_intf; file] )
      indent;
  Printf.printf "}}\n";
  Printf.printf "{client{\n";
    create_filter !compiler ( [ "-i" ; "-pp" ; get_pp ppopts; "-intf-suffix"; ".eliomi" ]
			         @ !args
			         @ get_common_include ~kind:`Server ()
			         @ [impl_intf_opt impl_intf; file] )
      indent;
  Printf.printf "}}\n"

let compile_eliom ~impl_intf file =
  let obj =
    let ext = match !kind with
      | `Client -> ".cmo"
      | `Server | `ServerOpt -> obj_ext ()
    in
    output_prefix file ^ ext
  in
  let ppopts = get_ppopts ~impl_intf file in
  if !do_dump then begin
    let camlp4, ppopt = get_pp_dump ("-printer" :: "o" :: ppopts @ [file]) in
    create_process camlp4 ppopt;
    exit 0
  end;
  create_process !compiler ( [ "-c" ;
                               "-o"  ; obj ;
                               "-pp" ; get_pp ppopts;
                               "-intf-suffix"; ".eliomi" ]
                             @ get_thread_opt ()
			     @ !args
			     @ get_common_include ()
			     @ [impl_intf_opt impl_intf; file] );
  args := !args @ [obj]

let process_eliom ~impl_intf file =
  if impl_intf = `Impl && do_infer () then
    compile_server_type_eliom file;
  if do_compile () then
    compile_eliom ~impl_intf file;
  if do_interface () then
    output_eliom_interface ~impl_intf file

let build_server ?(name = "a.out") () =
  fail "Linking eliom server is not yet supported"
  (* TODO ? Build a staticaly linked ocsigenserver. *)

let build_client () =
  let name = chop_extension_if_any (get_product_name ()) in
  let exe = prefix_output_dir (Filename.basename name) in
  check_or_create_dir (Filename.dirname exe);
  let js = name ^ ".js" in
  create_process !compiler ( ["-o"  ;  exe ]
			     @ get_common_include ()
			     @ get_client_lib ()
			     @ !args );
  create_process !js_of_ocaml ( ["-o" ; js ]
				@ get_client_js ()
				@ !jsopt
				@ [exe] )

let rec process_option () =
  let i = ref 1 in
  while !i < Array.length Sys.argv do
    match Sys.argv.(!i) with
    | "-help" | "--help" -> usage ()
    | "-i" -> set_mode `Interface; incr i
    | "-c" -> set_mode `Compile; incr i
    | "-a" -> set_mode `Library; incr i
    | "-pack" -> set_mode `Pack; incr i
    | "-output-obj" -> set_mode `Obj; incr i
    | "-shared" -> set_mode `Shared; incr i
    | "-infer" -> set_mode `InferOnly; incr i
    | "-verbose" -> verbose := true; args := !args @ ["-verbose"] ;incr i
    | "-noinfer"  ->
	noinfer := true; incr i
    | "-vmthread" -> Printf.eprintf "The -vmthread option isn't supported yet."; exit 1
    | "-o" ->
      if !i+1 >= Array.length Sys.argv then usage ();
      output_name := Some Sys.argv.(!i+1);
      i := !i+2
    | "-dump" ->
      do_dump := not !do_dump;
      i := !i+1
    | "-dir" ->
      if !i+1 >= Array.length Sys.argv then usage ();
      build_dir := Sys.argv.(!i+1);
      i := !i+2
    | "-type-dir" ->
      if !i+1 >= Array.length Sys.argv then usage ();
      type_dir := Sys.argv.(!i+1);
      i := !i+2
    | "-server-opt" ->
      if !kind <> `Client || !i+2 >= Array.length Sys.argv then usage ();
      (match Sys.argv.(!i+1) with
        | "-dir" ->
          server_dir := Some Sys.argv.(!i+2)
        | "-package" ->
          server_package := !server_package @ split ',' Sys.argv.(!i+2)
        | value ->
          usage ());
      i := !i+3;
    | "-package" ->
      if !i+1 >= Array.length Sys.argv then usage ();
      package := !package @ split ',' Sys.argv.(!i+1);
      i := !i+2
    | "-predicates" ->
      if !i+1 >= Array.length Sys.argv then usage ();
      predicates := !predicates @ split ',' Sys.argv.(!i+1);
      i := !i+2
    | "-pp" ->
      if !i+1 >= Array.length Sys.argv then usage ();
      pp := Some Sys.argv.(!i+1);
      i := !i+2
    | "-jsopt" ->
      if !kind <> `Client then usage ();
      if !i+1 >= Array.length Sys.argv then usage ();
      jsopt := !jsopt @ [Sys.argv.(!i+1)];
      i := !i+2
    | "-ppopt" ->
      if !i+1 >= Array.length Sys.argv then usage ();
      ppopt := !ppopt @ [Sys.argv.(!i+1)];
      i := !i+2
    | "-type" ->
      if !i+1 >= Array.length Sys.argv then usage ();
      type_file := Some Sys.argv.(!i+1);
      i := !i+2
    | "-intf" ->
      if !i+1 >= Array.length Sys.argv then usage ();
      process_eliom ~impl_intf:`Intf Sys.argv.(!i+1);
      i := !i+2
    | "-impl" ->
      if !i+1 >= Array.length Sys.argv then usage ();
      process_eliom ~impl_intf:`Impl Sys.argv.(!i+1);
      i := !i+2
    | arg when Filename.check_suffix arg ".mli" ->
      process_ocaml ~impl_intf:`Intf arg;
      incr i
    | arg when Filename.check_suffix arg ".ml" ->
      process_ocaml ~impl_intf:`Impl arg;
      incr i
    | arg when Filename.check_suffix arg ".eliom" ->
      process_eliom ~impl_intf:`Impl arg;
      incr i
    | arg when Filename.check_suffix arg ".eliomi" ->
      process_eliom ~impl_intf:`Intf arg;
      incr i
    | arg when Filename.check_suffix arg ".c" ->
      compile_obj arg; incr i
    | arg -> args := !args @ [arg]; incr i
  done;
  match !mode with
  | `Library -> build_library ()
  | `Pack -> build_pack ()
  | `Obj -> build_obj ()
  | `Shared -> build_shared ()
  | `Link when !kind = `Client -> build_client ()
  | `Link (* Server and ServerOpt *) -> build_server ?name:(!output_name) ()
  | `Compile | `InferOnly | `Interface -> ()

let main () =
  let k =
    match Filename.basename Sys.argv.(0) with
      | "eliomopt" ->
	  compiler := ocamlopt;
	  build_dir := default_server_dir;
	  `ServerOpt
      | "eliomcp" ->
	  compiler := ocamlcp;
	  build_dir := default_server_dir;
	  `Server
      | "js_of_eliom" ->
	  compiler := ocamlc;
	  build_dir := default_client_dir;
	  `Client
      | "eliomc" | _ ->
	  compiler := ocamlc;
	  build_dir := default_server_dir;
	  `Server in
  kind := k;
  process_option ()

let _ = main ()
