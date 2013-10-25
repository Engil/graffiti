(* Graffiti
 * http://www.ocsigen.org/graffiti
 * Copyright (C) 2013 Arnaud Parant
 * Laboratoire PPS - CNRS Université Paris Diderot
 *
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU Lesser General Public License as published by
 * the Free Software Foundation, with linking exception;
 * either version 2.1 of the License, or (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
 * GNU Lesser General Public License for more details.
 *
 * You should have received a copy of the GNU Lesser General Public License
 * along with this program; if not, write to the Free Software
 * Foundation, Inc., 59 Temple Place - Suite 330, Boston, MA 02111-1307, USA.
 *)

let make_element name v =
  Ocsigen_extensions.Configuration.element
    ~name ?pcdata:(Some (fun s -> v := s)) ()

let logdir_ref = ref ""
let logdir_elt = make_element "logdir" logdir_ref

let datadir_ref = ref ""
let datadir_elt = make_element "datadir" datadir_ref

let () = Eliom_config.parse_config [logdir_elt; datadir_elt]

let logdir = !logdir_ref ^ "/"
let datadir = !datadir_ref ^ "/"

let null_date = "1/1/1992_0h0m0s0"

let strdate_of_tm tm mls =
  let to_str = string_of_int in
  (to_str tm.Unix.tm_mday) ^ "/" ^ (to_str (tm.Unix.tm_mon + 1)) ^ "/" ^
  (to_str (tm.Unix.tm_year + 1900)) ^ "_" ^ (to_str tm.Unix.tm_hour) ^ "h" ^
  (to_str tm.Unix.tm_min) ^ "m" ^ (to_str tm.Unix.tm_sec) ^ "s" ^
  (to_str mls)

let datevalue_of_tm tm mls =
  tm.Unix.tm_mday, tm.Unix.tm_mon + 1, tm.Unix.tm_year + 1900,
  tm.Unix.tm_hour, tm.Unix.tm_min, tm.Unix.tm_sec, mls

let get_str_localdate () =
  let tm = Unix.localtime (Unix.time ()) in
  let mls = int_of_float ((mod_float (Unix.gettimeofday ()) 1.) *. 1000.) in
  strdate_of_tm tm mls

let get_date_value str_date =
  try
    let to_int = int_of_string in
    let ltime = Str.split (Str.regexp "[_/hms]") str_date in
    let mday = to_int (List.nth ltime 0) in
    let mon = to_int (List.nth ltime 1) in
    let year = to_int (List.nth ltime 2) in
    let hour = to_int (List.nth ltime 3) in
    let min = to_int (List.nth ltime 4) in
    let sec = to_int (List.nth ltime 5) in
    (** It is to allow old sys which not log millisecond *)
    let mls = if (List.length ltime) >= 7
      then to_int (List.nth ltime 6)
      else 0
    in
    mday, mon, year, hour, min, sec, mls
  with e        -> failwith "Invalide format"

let check_and_fix_date (mday, mon, year, hour, min, sec, _) =
  let tm:Unix.tm =
    { Unix.tm_sec = sec;
      Unix.tm_min = min;
      Unix.tm_hour = hour;
      Unix.tm_mday = mday;
      Unix.tm_mon = mon - 1;
      Unix.tm_year = year - 1900;
      Unix.tm_wday = 0;
      Unix.tm_yday = 0;
      Unix.tm_isdst = true }
  in Unix.mktime tm

let sec_of_date (mday, mon, year, hour, min, sec, mls) =
  let sec, _ = check_and_fix_date (mday, mon, year, hour, min, sec, mls) in
  sec +. ((float_of_int mls) /. 1000.)

let date_of_jsdate d =
  let rgd = Str.split (Str.regexp "[-]") d in
  try
    let (^^) a b = a ^ "/" ^ b in
    let y = (List.nth rgd 0) in
    let m = (List.nth rgd 1) in
    let j = (List.nth rgd 2) in
    j ^^ m ^^ y
  with e        -> failwith "Invalide format"

let time_of_jstime t =
  let rgt = Str.split (Str.regexp "[:]") t in
  try
    let h = (List.nth rgt 0) in
    let m = (List.nth rgt 1) in
    h ^ "h" ^ m ^ "m0s0"
  with e        -> failwith "Invalide format"

let datetime_of_jsdatetime js_d js_t =
  let d = date_of_jsdate js_d in
  let t = time_of_jstime js_t in
  d ^ "_" ^ t
