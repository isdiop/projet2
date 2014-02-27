open Clause
open Debug

module ClauseSet = Set.Make(OrderedClause)

type f_repr = ClauseSet.t

exception Clause_vide

exception Found of (variable*bool)

class clauseset =
object
  val mutable vis = ClauseSet.empty (* clauses visibles *)
  val mutable hid = ClauseSet.empty (* clauses cachées *)

  method hide c = (* cacher la clause c si elle est déjà visible *)
    if (ClauseSet.mem c vis) then 
      begin
        vis <- ClauseSet.remove c vis;
        hid <- ClauseSet.add c hid
      end 
      
  method show c = (* montrer la clause c, si elle est déjà cachée *)
    if (ClauseSet.mem c hid) then
      begin
        hid <- ClauseSet.remove c hid;
        vis <- ClauseSet.add c vis
      end
        
  method add c = vis <- ClauseSet.add c vis (* ajouter la clause c aux clauses visibles *)
     
  method mem c = ClauseSet.mem c vis (* indique si c est une clause visible *)

  method is_empty = ClauseSet.is_empty vis (* indique s'il n'y a aucune clause visible *)

  method reset = 
    vis <- ClauseSet.empty;
    hid <- ClauseSet.empty

  method iter f = ClauseSet.iter f vis

  method fold : 'a.(clause -> 'a -> 'a) -> 'a -> 'a = fun f -> fun a -> ClauseSet.fold f vis a

  method remove c = vis <- ClauseSet.remove c vis (***)

end

(*******)

(* Pour stocker occurences, valeurs, n'importe quoi en rapport avec les variables *)
class ['a] vartable n =
object (self)
  val data : (variable,'a) Hashtbl.t = Hashtbl.create n
    
  method size = Hashtbl.length data

  method is_empty = Hashtbl.length data = 0

  method reset = Hashtbl.clear data

  method set v x = Hashtbl.replace data v x (* peut être utilisé comme fonction d'ajout ou de remplacement : on associe la valeur x à la variable v *)

  method find v = try Some (Hashtbl.find data v) with Not_found -> None

  method mem v = not (self#find v = None)

  method remove v = Hashtbl.remove data v

  method iter f = Hashtbl.iter f data
end


(********)


class formule =
object (self)
  val mutable nb_vars = 0
  val x = ref 0 (* compteur de clause *)
  val clauses = new clauseset (* ensemble des clauses de la formule, peut contenir des clauses cachées/visibles *)
  val paris : bool vartable = new vartable 0 (* associe à chaque variable un pari : None si aucun, Some b si pari b *)

  method private reset n =
    x := 0;
    nb_vars <- n;
    clauses#reset;
    paris#reset
    
  method init n clauses_init =
    self#reset n;
    List.iter (fun c -> clauses#add (new clause x c)) clauses_init;
    clauses#iter (fun c -> if c#is_tauto then clauses#remove c)

  (***)

  method get_nb_vars = nb_vars

  method get_pari v = (* indique si v a subi un pari, et si oui lequel *)
    paris#find v

  method get_paris = paris
    
  (***)

  method add_clause c = (* ajoute la clause c, dans les clauses et les occurences *)
    clauses#add c

  method get_clauses = clauses

  method set_val b v =
    match paris#find v with
      | None -> paris#set v b
      | Some _ -> assert false 

  method reset_val v =
    match paris#find v with
      | None -> assert false
      | Some b -> paris#remove v

  (******)

  method find_singleton = (* renvoie la liste des (var,b) sans pari qui forment une clause singleton *)
    try 
      clauses#iter (fun c -> 
        match c#singleton with  
          | Some x -> 
              raise (Found x) 
          | None -> ());
      None
    with 
      | Found x -> Some x

  method check_empty_clause = clauses#iter (fun c -> if c#is_empty then raise Clause_vide)

  method eval =
    let aux b v =
      match paris#find v with
        | Some b' when b=b' -> raise Exit
        | _ -> () in
    try clauses#iter 
          (fun c -> 
            let b = try 
              c#get_vpos#iter (aux true);
              c#get_vneg#iter (aux false);
              false
            with Exit -> true in
            if not b then raise Exit);
        true
    with Exit -> false

end

class formule_dpll =
object(self)
  inherit formule as super

  val occurences_pos : clauseset vartable = new vartable 0 (* associe à chaque variable les clauses auxquelles elle appartient *)
  val occurences_neg : clauseset vartable = new vartable 0

  method init n clauses_init =
    super#init n clauses_init;
    for i=1 to n do
      occurences_pos#set i (new clauseset);
      occurences_neg#set i (new clauseset)
    done;
    clauses#iter self#register_clause

  method add_clause c =
    super#add_clause c;
    self#register_clause c
      
  method private add_occurence b c v = (* ajoute la clause c dans les occurences_pos ou occurences_neg de v, suivant la polarité b *)
    let dest = if b then occurences_pos else occurences_neg in
    let set = match dest#find v with
      | None -> 
          let set = new clauseset in (***)
          dest#set v set;
          set
      | Some set -> set in
    set#add c
      
  method private register_clause c = (* Met c dans les listes d'occurences de ses variables *)
    c#get_vpos#iter (self#add_occurence true c);
    c#get_vneg#iter (self#add_occurence false c)

  (* Accède à l'une des listes d'occurences en supposant qu'elle a été initialisée *)
  method private get_occurences occ v =
    match occ#find v with
      | None -> assert false 
      (* Cette variable aurait du être initialisée à l'ajout de la clause *) 
      | Some occurences -> occurences

  (* Cache une clause des listes d'occurences de toutes les variables sauf v_ref *)
  method private hide_occurences v_ref c =
    c#get_vpos#iter 
      (fun v -> 
        if v<>v_ref then 
          (self#get_occurences occurences_pos v)#hide c);     
    c#get_vneg#iter 
      (fun v -> 
        if v<>v_ref then 
          (self#get_occurences occurences_neg v)#hide c)    

  method set_val b v = (* on souhaite assigner la variable v à b (true ou false), et faire évoluer les clauses en conséquences *)
    let _ = match paris#find v with
      | None -> paris#set v b
      | Some _ -> assert false in (* Pas de double paris *)
    let (valider,supprimer) =
      if b then
        (occurences_pos,occurences_neg)
      else
        (occurences_neg,occurences_pos) in
    (* On supprime (valide) les clauses où apparait le littéral, elles ne sont plus pointées que par la liste des occurences de v*)
    (self#get_occurences valider v)#iter 
      (fun c -> 
        clauses#hide c ; 
        self#hide_occurences v c);
    (* On supprime la négation du littéral des clauses où elle apparait, si on créé un conflit on le dit *)
    (self#get_occurences supprimer v)#iter 
      (fun c -> 
        c#hide_var (not b) v;
        if c#is_empty then 
          raise Clause_vide)

  method private show_occurences v_ref c =
    c#get_vpos#iter 
      (fun v -> 
        if v<>v_ref then 
          (self#get_occurences occurences_pos v)#show c);
    c#get_vneg#iter 
      (fun v -> 
        if v<>v_ref then 
          (self#get_occurences occurences_neg v)#show c) 
      
  (* Replace une clause dans les listes d'occurences de ses variables *)
  method reset_val v =
    let b = match paris#find v with
      | None -> assert false (* On ne revient pas sur un pari pas fait *)
      | Some b -> 
          paris#remove v ; 
          b in
    let (invalider,restaurer) =
      if b then
        (occurences_pos,occurences_neg)
      else
        (occurences_neg,occurences_pos) in
    (* On invalide les clauses où apparaissait le littéral *)
    (self#get_occurences invalider v)#iter 
      (fun c -> 
        clauses#show c;
        self#show_occurences v c);
    (* On restaure les clauses où apparait la négation du littéral, on remet à jour les occurences des variables y apparaissant*)
    (self#get_occurences restaurer v)#iter 
      (fun c -> 
        c#show_var (not b) v) (* On replace les occurences du littéral *)

(***)

  method find_single_polarite = (* on cherche une var sans pari qui n'apparaitrait qu'avec une seule polarité *)
    let rec parcours_polar m n = 
      if m>n 
      then None 
      else  if not (paris#mem m) 
        then if (self#get_occurences occurences_pos m)#is_empty 
          then Some (m,false) (* on peut à ce stade renvoyer une var qui n'apparaitrait dans aucune clause *)
          else if (self#get_occurences occurences_neg m)#is_empty
          then Some (m,true)
          else parcours_polar (m+1) n
          else parcours_polar (m+1) n
    in parcours_polar 1 self#get_nb_vars

end

class formule_wl =
object
  inherit formule as super

  val wl_pos : clauseset vartable = new vartable 0
  val wl_neg : clauseset vartable = new vartable 0

  method init n clauses_init =
    super#init n clauses_init;
    let (occ_pos,occ_neg) = (new vartable n, new vartable n) in
    let add_occurence dest c v = (* ajoute la clause c dans les occurences_pos ou occurences_neg de v, suivant la polarité b *)
      let set = match dest#find v with
        | None -> 
            let set = new clauseset in
            dest#set v set;
            set
        | Some set -> set in
      set#add c in
    let register_clause c = (* Met c dans les listes d'occurences de ses variables *)
      c#get_vpos#iter (add_occurence occ_pos c);
      c#get_vneg#iter (add_occurence occ_neg c) in
    clauses#iter register_clause;
    let get_occurences occ var = 
      match occ#find var with
        | None -> new clauseset
        | Some occurences -> occurences in
    let rec prepare () =
      let res = 
        try 
          clauses#iter (fun c -> match c#singleton with Some s -> raise (Found s) | None -> ());
          None
        with Found s -> Some s in
      match res with
        | None -> ()
        | Some (v,b) ->
            paris#set v b;
            let (valider,supprimer) =
              if b then
                (occ_pos,occ_neg)
              else
                (occ_neg,occ_pos) in
            (get_occurences valider v)#iter 
              (fun c -> clauses#remove c);
            (get_occurences supprimer v)#iter 
              (fun c -> c#hide_var (not b) v);
            prepare() in
    prepare()

    

end















