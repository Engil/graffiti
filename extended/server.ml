(* Graffiti
 * http://www.ocsigen.org/graffiti
 * Copyright (C) 2013 Vincent Balat
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

open Eliom_content
open Common
open Lwt

module My_app =
  Eliom_registration.App (struct
    let application_name = "graffiti"
  end)

let rgb_from_string color = (* color is in format "#rrggbb" *)
  let get_color i =
    (float_of_string ("0x"^(String.sub color (1+2*i) 2))) /. 255.
  in
  try get_color 0, get_color 1, get_color 2 with | _ -> 0., 0., 0.

let launch_server_canvas () =
  let bus = Eliom_bus.create Json.t<messages> in

  let draw_server, image_string =
    let rgb_ints_to_floats (r, g, b) =
      float r /. 255., float g /. 255., float b /. 255. in
    let surface = Cairo.Image.create Cairo.Image.ARGB32 ~width ~height in
    let ctx = Cairo.create surface in
    ((fun (rgb, size, (x1, y1), (x2, y2)) ->

      (* Set thickness of brush *)
      let r, g, b = rgb_ints_to_floats rgb in
      Cairo.set_line_width ctx (float size) ;
      Cairo.set_line_join ctx Cairo.JOIN_ROUND ;
      Cairo.set_line_cap ctx Cairo.ROUND ;
      Cairo.set_source_rgb ctx ~r ~g ~b ;

      Cairo.move_to ctx (float x1) (float y1) ;
      Cairo.line_to ctx (float x2) (float y2) ;
      Cairo.Path.close ctx ;

      (* Apply the ink *)
      Cairo.stroke ctx ;
     ),
     (fun () ->
       let b = Buffer.create 10000 in
       (* Output a PNG in a string *)
       Cairo.PNG.write_to_stream surface (Buffer.add_string b);
       Buffer.contents b
     ))
  in
  let _ = Lwt_stream.iter draw_server (Eliom_bus.stream bus) in
  bus,image_string

let graffiti_info = Hashtbl.create 0

let imageservice =
  Eliom_registration.String.register_service
    ~path:["image"]
    ~headers:Http_headers.dyn_headers
    ~get_params:(let open Eliom_parameter in string "name" ** int "q")
    (* we add another parameter for the browser not to cache: at least
       for chrome, there is no way to force the browser to reload the
       image without leaving the application *)
    (fun (name,_) () ->
      try_lwt
        let _ ,image_string = Hashtbl.find graffiti_info name in
	Lwt.return (image_string (), "image/png")
      with
	| Not_found -> raise_lwt Eliom_common.Eliom_404)

let get_bus (name:string) =
  (* create a new bus and image_string function only if it did not exists *)
  try
    fst (Hashtbl.find graffiti_info name)
  with
    | Not_found ->
      let bus,image_string = launch_server_canvas () in
      Hashtbl.add graffiti_info name (bus, image_string);
      bus

let main_service = Eliom_service.App.service ~path:[""]
  ~get_params:(Eliom_parameter.unit) ()
let multigraffiti_service = Eliom_service.App.service ~path:[""]
  ~get_params:(Eliom_parameter.suffix (Eliom_parameter.string "name")) ()

let choose_drawing_form () =
  Html5.D.get_form ~service:multigraffiti_service
    (fun (name) ->
      [Html5.D.p [Html5.D.pcdata "drawing name: ";
          Html5.D.string_input ~input_type:`Text ~name ();
          Html5.D.br ();
          Html5.D.string_input ~input_type:`Submit ~value:"Go" ()
         ]])

let connection_service =
  Eliom_service.Http.post_coservice'
    ~post_params:Eliom_parameter.(string "name" ** string "password")
    ()

let disconnection_service =
  Eliom_service.Http.post_coservice' ~post_params:Eliom_parameter.unit ()

let create_account_service =
  Eliom_service.Http.post_coservice
    ~fallback:main_service
    ~post_params:Eliom_parameter.(string "name" ** string "password")
    ()

let user_table = Ocsipersist.open_table "user_table"
let check_pwd name pwd =
  try_lwt
    lwt saved_password = Ocsipersist.find user_table name in
    Lwt.return (pwd = saved_password)
  with Not_found -> Lwt.return false

let () = Eliom_registration.Action.register
  ~service:create_account_service
  (fun () (name, pwd) -> Ocsipersist.add user_table name pwd)

let () = Eliom_registration.Action.register
  ~service:connection_service
  (fun () (name, password) ->
    match_lwt check_pwd name password with
      | true -> Eliom_state.set_volatile_data_session_group
	~scope:Eliom_common.default_session_scope name;
	Lwt.return ()
      | false -> Lwt.return ())

let () =
  Eliom_registration.Action.register
    ~service:disconnection_service
    (fun () () ->
      Eliom_state.discard ~scope:Eliom_common.default_session_scope ())

let disconnect_box () =
  Html5.D.post_form disconnection_service
    (fun _ -> [Html5.D.p [Html5.D.string_input
                  ~input_type:`Submit ~value:"Log out" ()]]) ()

let login_name_form service button_text =
  Html5.D.post_form ~service
    (fun (name1, name2) ->
      [Html5.D.p [Html5.D.pcdata "login: ";
          Html5.D.string_input ~input_type:`Text ~name:name1 ();
          Html5.D.br ();
          Html5.D.pcdata "password: ";
          Html5.D.string_input ~input_type:`Password ~name:name2 ();
          Html5.D.br ();
          Html5.D.string_input ~input_type:`Submit ~value:button_text ()
         ]]) ()

let oclosure_script =
  Html5.Id.create_global_elt
    (Html5.D.js_script
       ~uri:(Html5.D.Raw.uri_of_string "./graffiti_oclosure.js") ())

let make_page body =
  Lwt.return
    (Html5.D.html
       (Html5.D.head
	  (Html5.D.title (Html5.D.pcdata "Graffiti"))
 	  [
	    Html5.D.css_link
	      ~uri:(Html5.D.Raw.uri_of_string"./css/closure/common.css") ();
	    Html5.D.css_link
	      ~uri:(Html5.D.Raw.uri_of_string"./css/closure/hsvpalette.css") ();
	    Html5.D.css_link
	      ~uri:(Html5.D.Raw.uri_of_string"./css/slider.css") ();
            oclosure_script;
	    Html5.D.css_link
	      ~uri:(Html5.D.Raw.uri_of_string"./css/graffiti.css") ();
          ])
       (Html5.D.body body))


let default_content () =
  make_page
    [Html5.D.h1 [Html5.D.pcdata "Welcome to Multigraffiti"];
     Html5.D.h2 [Html5.D.pcdata "log in"];
     login_name_form connection_service "Connect";
     Html5.D.h2 [Html5.D.pcdata "create account"];
     login_name_form create_account_service "Create account";]

module Connected_translate =
struct
  type page = string -> My_app.page Lwt.t
  let translate page =
    match Eliom_state.get_volatile_data_session_group
      ~scope:Eliom_common.default_session_scope () with
	| None -> default_content ()
	| Some username -> page username
end

module Connected =
  Eliom_registration.Customize (My_app) (Connected_translate)

let ( !% ) f = fun a b -> return (fun c -> f a b c)

let () = Connected.register
  ~service:main_service
  !% (fun () () username ->
    make_page
      [Html5.D.h1 [Html5.D.pcdata ("Welcome to Multigraffiti " ^ username)];
       choose_drawing_form ()])
