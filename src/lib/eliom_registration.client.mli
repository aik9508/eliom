(* Ocsigen
 * http://www.ocsigen.org
 * Copyright (C) 2016 Vasilis Papavasileiou
 *
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU Lesser General Public License as published by
 * the Free Software Foundation, with linking exception;
 * either version 2.1 of the License, or (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU Lesser General Public License for more details.
 *
 * You should have received a copy of the GNU Lesser General Public License
 * along with this program; if not, write to the Free Software
 * Foundation, Inc., 59 Temple Place - Suite 330, Boston, MA 02111-1307, USA.
 *)

type frame

module Html : Eliom_registration_sigs.S
  with type page = Html_types.html Eliom_content.Html.elt
   and type options = unit
   and type return = Eliom_service.non_ocaml
   and type frame := frame

module Action : Eliom_registration_sigs.S
  with type page = unit
   and type options = [ `Reload | `NoReload ]
   and type return = Eliom_service.non_ocaml
   and type frame := frame

module Unit : Eliom_registration_sigs.S
  with type page = unit
   and type options = unit
   and type return = Eliom_service.non_ocaml
   and type frame := frame

(** Has no effect on client ; for compatibility with server *)
type appl_service_options = { do_not_launch : bool }

module App (P : Eliom_registration_sigs.APP_PARAM) : sig

  val application_name : string

  (** The type [appl] is an abstract type for identifying an
      application. It usually used a phantom parameter for
      {!application_content}. *)
  type app_id

  include Eliom_registration_sigs.S
    with type page = Html_types.html Eliom_content.Html.elt
     and type options = appl_service_options
     and type return = Eliom_service.non_ocaml
     and type frame := frame

end

type _ redirection =
    Redirection :
      (unit, unit, Eliom_service.get , _, _, _, _,
       [ `WithoutSuffix ], unit, unit, 'a) Eliom_service.t ->
    'a redirection

(** [page] et al. are not really polymorphic. The type variables are
    necessary for maintaining type-level compatibility with server
    (for injections) *)
module Redirection : Eliom_registration_sigs.S_poly
  with type 'a page = Eliom_service.non_ocaml redirection
   and type options =
         [ `MovedPermanently
         | `Found
         | `SeeOther
         | `NotNodifed
         | `UseProxy
         | `TemporaryRedirect ]
   and type 'a return = Eliom_service.non_ocaml
   and type frame := frame

module Any : Eliom_registration_sigs.S_poly
  with type 'a page = frame
   and type options = unit
   and type 'a return = Eliom_service.non_ocaml
   and type frame := frame

(** For compatibility with server-side [appl_self_redirect] *)
val appl_self_redirect :
  ('page -> frame Lwt.t) -> 'page -> frame Lwt.t

(**/**)

module type Base = sig
  type return = Eliom_service.non_ocaml
end

module Block5 : Base
module Html_text : Base
module CssText : Base
module Text : Base
module String : Base
module String_redirection : Base
module Streamlist : Base

module Ocaml : sig
  type 'a return = 'a Eliom_service.ocaml
end
