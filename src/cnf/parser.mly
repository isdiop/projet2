

%token <int> INT 
%token MINUS ENDC EOF



%start main             	
%type <int*((int list) list)> main

%%


main:                      
| formule EOF                 { $1 }
  ;

  formule:														
| INT INT liste_clause	      { ($1,$3) }
  ;
  
  liste_clause:
| clause ENDC liste_clause    { $1::$3}
|                             { [] }
  ;
  
  clause:
| literal clause             {$1::$2}
|                             {[]}
  ;

literal:
| INT                         {$1}
| MINUS INT                   {-$2}










