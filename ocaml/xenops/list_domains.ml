(*
 * Copyright (C) 2006-2009 Citrix Systems Inc.
 *
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU Lesser General Public License as published
 * by the Free Software Foundation; version 2.1 only. with the special
 * exception on linking described in file LICENSE.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU Lesser General Public License for more details.
 *)
open Pervasiveext

let domid = ref None
let minimal = ref false
let memory = ref false
let bytes = ref false
let pages = ref false
let all_the_rest = ref false

let xc_handle = Xc.interface_open() 

let hashtbl_of_domaininfo (x: Xc.domaininfo) : (string, string) Hashtbl.t = 
  let table = Hashtbl.create 10 in

  let pages_to_string_bytes    x = Int64.to_string (Memory.bytes_of_pages    (Int64.of_nativeint (x))) in
  let pages_to_string_mib_used x = Int64.to_string (Memory.mib_of_pages_used (Int64.of_nativeint (x))) in
  let pages_to_string_pages    x = Int64.to_string (                         (Int64.of_nativeint (x))) in

  let int = string_of_int and int64 = Int64.to_string and int32 = Int32.to_string in
  Hashtbl.add table "id" (int x.Xc.domid);
  let state = let bool ch = function true -> ch | _ -> " " in
  (bool "D" x.Xc.dying) ^ (bool "S" x.Xc.shutdown) ^ 
  (bool "P" x.Xc.paused) ^ (bool "B" x.Xc.blocked) ^ 
  (bool "R" x.Xc.running) ^ (bool "H" x.Xc.hvm_guest) in
  Hashtbl.add table "state" state;
  Hashtbl.add table "shutdown code" (int x.Xc.shutdown_code);
  Hashtbl.add table "tot bytes" (pages_to_string_bytes    x.Xc.total_memory_pages);
  Hashtbl.add table "tot pages" (pages_to_string_pages    x.Xc.total_memory_pages);
  Hashtbl.add table "tot MiB"   (pages_to_string_mib_used x.Xc.total_memory_pages);
  Hashtbl.add table "max bytes" (if x.Xc.domid = 0 then "N/A" else (pages_to_string_bytes    x.Xc.max_memory_pages));
  Hashtbl.add table "max pages" (if x.Xc.domid = 0 then "N/A" else (pages_to_string_pages    x.Xc.max_memory_pages));
  Hashtbl.add table "max MiB"   (if x.Xc.domid = 0 then "N/A" else (pages_to_string_mib_used x.Xc.max_memory_pages));
  Hashtbl.add table "sif" (int64 x.Xc.shared_info_frame);
  Hashtbl.add table "cpu time" (int64 x.Xc.cpu_time);
  Hashtbl.add table "vcpus online" (int x.Xc.nr_online_vcpus);
  Hashtbl.add table "max vcpu id" (int x.Xc.max_vcpu_id);
  Hashtbl.add table "ssidref" (int32 x.Xc.ssidref);
  Hashtbl.add table "uuid" (Uuid.to_string (Uuid.uuid_of_int_array x.Xc.handle));
  (* Ask for shadow allocation separately *)
  let shadow_mib =
    try Some (Int64.of_int (Xc.shadow_allocation_get xc_handle x.Xc.domid))
    with _ -> None in
  let shadow_bytes = may Memory.bytes_of_mib shadow_mib in
  let shadow_pages = may Memory.pages_of_mib shadow_mib in
  Hashtbl.add table "shadow bytes" (Opt.default "N/A" (may Int64.to_string shadow_bytes));
  Hashtbl.add table "shadow pages" (Opt.default "N/A" (may Int64.to_string shadow_pages));
  Hashtbl.add table "shadow MiB"   (Opt.default "N/A" (may Int64.to_string shadow_mib  ));
  table

let select table keys = 
  List.map (fun key -> 
	      if not(Hashtbl.mem table key) then failwith (Printf.sprintf "Failed to find key: %s" key);
	      Hashtbl.find table key) keys

let columns () =
	let common = [ "id"; "uuid"; "state" ] in
	let mem_mib   = [ "tot MiB"  ; "max MiB"  ; "shadow MiB"   ] in
	let mem_bytes = [ "tot bytes"; "max bytes"; "shadow bytes" ] in
	let mem_pages = [ "tot pages"; "max pages"; "shadow pages" ] in
	let rest = [ "shutdown code"; "sif"; "cpu time"; "vcpus online"; "max vcpu id"; "ssidref" ] in
	if !minimal
	then [ "uuid" ]
	else
		common @ (
			match !memory, !bytes, !pages with
			| _   , true, true -> failwith (Printf.sprintf "Too many units specified."); []
			| true, _   , true -> mem_pages
			| true, true, _    -> mem_bytes
			| true, _   , _    -> mem_mib
			| _                -> []
		) @ (
			if !all_the_rest
			then rest
			else []
		)

open Table

let print (rows: string list list) =
  let widths = compute_col_widths rows in
  let sll = List.map (List.map2 right widths) rows in
  List.iter (fun line -> print_endline (String.concat " | " line)) sll

let _ =
	Arg.parse (Arg.align [
		"-all", Arg.Unit (fun () -> memory := true; all_the_rest := true),
			" show all available stats (needs a wide window!)";
		"-bytes", Arg.Set bytes,
			" use bytes for memory values";
		"-domid", Arg.Int (fun i -> domid := Some i),
			" show only a particular domain";
		"-memory", Arg.Set memory,
			" show memory statistics";
		"-minimal", Arg.Set minimal,
			" show only domain UUID";
		"-pages", Arg.Set pages,
			" use pages for memory values";
		]) (fun x -> Printf.printf "Warning, ignoring unknown argument: %s" x)
		"List domains";
	let cols = columns () in
	let list = match !domid with
		| None -> Xc.domain_getinfolist xc_handle 0
		| Some d -> [Xc.domain_getinfo xc_handle d]
	in
	let infos = List.map (fun di -> select (hashtbl_of_domaininfo di) cols) list in
	if !minimal
	then print (infos)
	else print (cols :: infos)

