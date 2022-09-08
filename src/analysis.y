%{
    #include <iostream>
    #include <cstdlib>
    #include <cstring>
    #include <cmath>
    #include <string>
    #include <sstream>
    #include <vector>
    #include <algorithm>
    #include "./symbol-table/include.hpp"

    using namespace std;

    enum Phase {
        Analysis, Synthesis
    };

    Phase phase;

    extern FILE* yyin;
    extern int line_count;

    int yyparse();
    int yylex();
    void yyerror(char* str);

    FILE* input_file,* log_file,* error_file;

    int error_count = 0;
    const int SYM_TABLE_BUCKETS = 10;
    SymbolTable symbol_table(SYM_TABLE_BUCKETS);

    const string INT_TYPE = "int";
    const string INT_ARRAY_TYPE = "int_arr";
    const string FLOAT_TYPE = "float";
    const string FLOAT_ARRAY_TYPE = "float_arr";
    const string VOID_TYPE = "void";

    SymbolInfo* current_func_sym_ptr;
    vector<SymbolInfo*> params_for_func_scope;

    /**
        Analysis utils
    **/
    vector<string> split(string, char = ' ');
    bool is_sym_func(SymbolInfo*);
    bool is_func_sym_defined(SymbolInfo*);
    bool is_func_signatures_match(SymbolInfo*, SymbolInfo*);
    string vec_to_str(vector<string>);
    bool insert_into_symtable(string, string, string, vector<string> = {});
    bool insert_into_symtable(SymbolInfo*);
    bool insert_var_list_into_symtable(string, vector<string>);
    void write_log(string, SymbolInfo*);
    void write_error_log(string, string = "ERROR");
    void write_symtable_in_log(SymbolTable&);

    /**
        Synthesis utils
    **/
%}

%union {
    int int_val;
    SymbolInfo* syminfo_ptr;
}

%token<int_val>
    LPAREN RPAREN SEMICOLON COMMA LCURL RCURL INT FLOAT VOID LTHIRD RTHIRD FOR IF ELSE WHILE
    PRINTLN RETURN ASSIGNOP NOT INCOP DECOP

%token<syminfo_ptr>
    ID CONST_INT CONST_FLOAT LOGICOP RELOP ADDOP MULOP

%type<syminfo_ptr>
    start program unit var_declaration func_definition type_specifier parameter_list
    compound_statement statements declaration_list statement expression_statement expression
    variable logic_expression rel_expression simple_expression term unary_expression factor argument_list
    arguments func_declaration func_signature compound_statement_start

%destructor {
    delete $$;
} <syminfo_ptr>

%right COMMA
%right ASSIGNOP
%left LOGICOP
%left RELOP
%left ADDOP 
%left MULOP
%right NOT UNARY  // dummy token to reduce unary ADDOP before arithmetic ADDOP
%left INCOP DECOP LPAREN RPAREN LTHIRD RTHIRD 
 // each rule gets its precedence from the last terminal symbol mentioned in the components by default. 

 // ELSE has higher precedence than dummy token SHIFT_ELSE (telling to shift ELSE, rather than reduce lone if)
%nonassoc SHIFT_ELSE
%nonassoc ELSE

%%

start: 
    program {
        if (phase == Analysis) {
            $$ = new SymbolInfo($1->get_symbol(), "start", $1->get_semantic_type());

            string production = "start : program";
            write_log(production, $$);

            write_symtable_in_log(symbol_table);

            YYACCEPT;
        } else if (phase == Synthesis) {

        }
    }
    ;

program: 
    program unit {
        if (phase == Analysis) {
            $$ = new SymbolInfo($1->get_symbol() + $2->get_symbol(), "program", VOID_TYPE);

            string production = "program : program unit";
            write_log(production, $$);

            write_symtable_in_log(symbol_table);
        } else if (phase == Synthesis) {

        }
    }   
    | unit {
        if (phase == Analysis) {
            $$ = new SymbolInfo($1->get_symbol(), "program", VOID_TYPE);

            string production = "program : unit";
            write_log(production, $$);

            write_symtable_in_log(symbol_table);
        } else if (phase == Synthesis) {

        }
    }
    ;

unit:
    var_declaration {
        if (phase == Analysis) {
            $$ = new SymbolInfo($1->get_symbol(), "unit", VOID_TYPE);

            string production = "unit : var_declaration";
            write_log(production, $$);
        } else if (phase == Synthesis) {

        }
    }
    | func_declaration {
        if (phase == Analysis) {
            $$ = new SymbolInfo($1->get_symbol(), "unit", VOID_TYPE);

            string production = "unit : func_declaration";
            write_log(production, $$);
        } else if (phase == Synthesis) {

        }
    }
    | func_definition {
        if (phase == Analysis) {
            $$ = new SymbolInfo($1->get_symbol(), "unit", VOID_TYPE);

            string production = "unit : func_definition";
            write_log(production, $$);
        } else if (phase == Synthesis) {

        }
    }
    ;

func_declaration: 
    func_signature SEMICOLON {
        if (phase == Analysis) {
            $$ = new SymbolInfo($1->get_symbol() + ";\n", "func_declaration", VOID_TYPE);
            // declaration, so no scope will be created, so have to manually insert the built func sym
            insert_into_symtable(current_func_sym_ptr);

            delete current_func_sym_ptr;
            current_func_sym_ptr = nullptr;
            params_for_func_scope.clear();

            string production = "func_declaration : type_specifier ID LPAREN parameter_list RPAREN SEMICOLON";
            write_log(production, $$);
        } else if (phase == Synthesis) {

        }
    }
    ;

func_definition:
    func_signature compound_statement {
        if (phase == Analysis) {
            if ($1->get_semantic_type() != VOID_TYPE && $2->get_semantic_type() == VOID_TYPE) {
                write_error_log(current_func_sym_ptr->get_symbol() + 
                    " with non void return type has to return something");
            }

            $$ = new SymbolInfo($1->get_symbol() +  " " + $2->get_symbol(), "func_definition", VOID_TYPE);

            string production = "func_definition : type_specifier ID LPAREN parameter_list RPAREN compound_statement";
            write_log(production, $$);

            current_func_sym_ptr->add_data("defined"); // to catch multiple definition error, but allow definition after declaration
            current_func_sym_ptr = nullptr;
        } else if (phase == Synthesis) {

        }
    }
    ;

func_signature:
    type_specifier ID LPAREN parameter_list RPAREN {
        if (phase == Analysis) {
            string return_type = $1->get_symbol();
            string func_name = $2->get_symbol();

            vector<string> param_type_list = $4->get_all_data(); 
            if (param_type_list.empty()) {
                param_type_list.push_back(VOID_TYPE); // if empty MUST HAVE VOID to know its a func
            }

            $$ = new SymbolInfo(return_type + " " + func_name + "(" + $4->get_symbol() + 
                ")", "func_signature", return_type, param_type_list);

            // definition will insert in compound_statement, declaration will insert in func_declaration
            current_func_sym_ptr = new SymbolInfo(func_name, "ID", return_type, param_type_list);
        } else if (phase == Synthesis) {

        }
    }
    | type_specifier ID LPAREN parameter_list error RPAREN {
        if (phase == Analysis) {
            string return_type = $1->get_symbol();
            string func_name = $2->get_symbol();

            vector<string> param_type_list = $4->get_all_data(); 
            if (param_type_list.empty()) {
                param_type_list.push_back(VOID_TYPE); // if empty MUST HAVE VOID to know its a func
            }

            $$ = new SymbolInfo(return_type + " " + func_name + "(" + $4->get_symbol() + 
                " [SYNTAX_ERR] )", "func_signature", return_type, param_type_list);

            current_func_sym_ptr = new SymbolInfo(func_name, "ID", return_type, param_type_list);
        
            // yyerror("resumed at RPAREN");
            yyerrok;
        } else if (phase == Synthesis) {

        }
    }
    ;

parameter_list:
    parameter_list COMMA type_specifier ID {
        if (phase == Analysis) {
            string param_type = $3->get_symbol();
            string param_name = $4->get_symbol();

            vector<string> param_type_list = $1->get_all_data(); // for $$ symbol info data list
            if (param_type != VOID_TYPE) {
                param_type_list.push_back(param_type);
                params_for_func_scope.push_back(new SymbolInfo(param_name, "ID", param_type));
            } else {
                write_error_log("parameters cannot be void type");
            }

            $$ = new SymbolInfo($1->get_symbol() + "," + param_type + " " + 
                param_name, "parameter_list", VOID_TYPE, param_type_list);

            string production = "parameter_list : parameter_list COMMA type_specifier ID";
            write_log(production, $$);
        } else if (phase == Synthesis) {

        }
    }
    | parameter_list COMMA type_specifier {
        if (phase == Analysis) {
            string param_type = $3->get_symbol();

            vector<string> param_type_list = $1->get_all_data();
            if (param_type != VOID_TYPE) {
                param_type_list.push_back(param_type);
            } else {
                write_error_log("parameters cannot be void type");
            }

            $$ = new SymbolInfo($1->get_symbol() + "," + param_type, "parameter_list", VOID_TYPE, param_type_list);

            string production = "parameter_list : parameter_list COMMA type_specifier";
            write_log(production, $$);
        } else if (phase == Synthesis) {

        }
    }
    | type_specifier ID {
        if (phase == Analysis) {
            string param_type = $1->get_symbol();
            string param_name = $2->get_symbol();

            vector<string> param_type_list;
            if (param_type != VOID_TYPE) {
                param_type_list.push_back(param_type);
                params_for_func_scope.push_back(new SymbolInfo(param_name, "ID", param_type));
            } else {
                write_error_log("parameters cannot be void type");
            }

            $$ = new SymbolInfo(param_type + " " + param_name, "parameter_list", VOID_TYPE, 
                param_type_list);

            string production = "parameter_list : type_specifier ID";
            write_log(production, $$);
        } else if (phase == Synthesis) {
            
        }
    }
    | type_specifier {
        if (phase == Analysis) {
            string param_type = $1->get_symbol();

            vector<string> param_type_list;
            if (param_type != VOID_TYPE) {
                param_type_list.push_back(param_type);
            }
            
            $$ = new SymbolInfo($1->get_symbol(), "parameter_list", VOID_TYPE, 
                param_type_list);

            string production = "parameter_list : type_specifier";
            write_log(production, $$);
        } else if (phase == Synthesis) {

        }
    }
    | %empty {
        if (phase == Analysis) {
            // empty param list will be added VOID_TYPE in function_signture
            $$ = new SymbolInfo("", "parameter_list", VOID_TYPE);

            string func_name = $<syminfo_ptr>-1->get_symbol();
            string return_type = $<syminfo_ptr>-2->get_symbol();

            string production = "parameter_list : epsilon";
            write_log(production, $$);
        } else if (phase == Synthesis) {

        }
    }
    ;

compound_statement:
    compound_statement_start statements RCURL {
        if (phase == Analysis) {
            $$ = new SymbolInfo($1->get_symbol() + "\n" + $2->get_symbol() + "}\n", "compound_statement", 
                $2->get_semantic_type());

            string production = "compound_statement : LCURL statements RCURL";
            write_log(production, $$);

            write_symtable_in_log(symbol_table);
            symbol_table.exit_scope();
        } else if (phase == Synthesis) {

        }
    }
    | compound_statement_start RCURL {
        if (phase == Analysis) {
            $$ = new SymbolInfo($1->get_symbol() + "\n" + "}\n", "compound_statement", VOID_TYPE);

            string production = "compound_statement : LCURL RCURL";
            write_log(production, $$);

            write_symtable_in_log(symbol_table);
            symbol_table.exit_scope();
        } else if (phase == Synthesis) {

        }
    }
    | error RCURL {
        if (phase == Analysis) {
            $$ = new SymbolInfo("{\n[SYNTAX_ERR]\n}\n", "compound_statement", VOID_TYPE);

            write_symtable_in_log(symbol_table);
            symbol_table.exit_scope();

            // yyerror("resumed at RCULR");
            yyerrok;
        } else if (phase == Synthesis) {

        }
    }
    ;

compound_statement_start:
    LCURL {
        if (phase == Analysis) {
            $$ = new SymbolInfo("{", "LCURL", VOID_TYPE);
            SymbolInfo* existing_symbol_ptr = symbol_table.lookup(current_func_sym_ptr->get_symbol());
            if (
                existing_symbol_ptr != nullptr && is_sym_func(existing_symbol_ptr) && 
                !is_func_sym_defined(existing_symbol_ptr)
            ) {
                // previously declared but not defined, okay
                if (!is_func_signatures_match(current_func_sym_ptr, existing_symbol_ptr)) {
                    write_error_log(current_func_sym_ptr->get_symbol() + 
                        " definition does not match declaration signature");
                }
            } else if (insert_into_symtable(current_func_sym_ptr)) {
                SymbolInfo* old_func_sym_ptr = current_func_sym_ptr;
                current_func_sym_ptr = symbol_table.lookup(current_func_sym_ptr->get_symbol());
                delete old_func_sym_ptr;
            } 

            symbol_table.enter_scope();

            for (SymbolInfo* param_symbol : params_for_func_scope) {
                insert_into_symtable(param_symbol);
            }

            params_for_func_scope.clear();
        } else if (phase == Synthesis) {

        }
    }
    | error LCURL {
        if (phase == Analysis) {
            $$ = new SymbolInfo("[SYNTAX_ERR] {", "LCURL", VOID_TYPE);    
            symbol_table.enter_scope();

            for (SymbolInfo* param_symbol : params_for_func_scope) {
                insert_into_symtable(param_symbol);
            }

            params_for_func_scope.clear();
            yyerrok;
        } else if (phase == Synthesis) {

        }
    }
    ;

var_declaration:
    type_specifier declaration_list SEMICOLON {
        if (phase == Analysis) {
            $$ = new SymbolInfo($1->get_symbol() + " " + $2->get_symbol() + ";\n", "var_declaration", VOID_TYPE);

            string var_type = $1->get_symbol();
            vector<string> var_names = split($2->get_symbol(), ',');
            insert_var_list_into_symtable(var_type, var_names);

            string production = "var_declaration : type_specifier declaration_list SEMICOLON";
            write_log(production, $$);
        } else if (phase == Synthesis) {

        }
    }
    | error SEMICOLON {
        if (phase == Analysis) {
            $$ = new SymbolInfo("[SYNTAX_ERR] ;\n", "var_declaration", VOID_TYPE);
            yyerrok;
        } else if (phase == Synthesis) {

        }
    }
    ;

type_specifier:
    INT {
        if (phase == Analysis) {
            $$ = new SymbolInfo("int", "type_specifier", VOID_TYPE);

            string production = "type_specifier : INT";
            write_log(production, $$);
        } else if (phase == Synthesis) {

        }
    }
    | FLOAT {
        if (phase == Analysis) {
            $$ = new SymbolInfo("float", "type_specifier", VOID_TYPE);

            string production = "type_specifier : FLOAT";
            write_log(production, $$);
        } else if (phase == Synthesis) {

        }
    }
    | VOID {
        if (phase == Analysis) {
            $$ = new SymbolInfo("void", "type_specifier", VOID_TYPE);

            string production = "type_specifier : VOID";
            write_log(production, $$);
        } else if (phase == Synthesis) {

        }
    }
    ;

declaration_list:
    declaration_list COMMA ID {
        if (phase == Analysis) {
            $$ = new SymbolInfo($1->get_symbol() + "," + $3->get_symbol(), "declaration_list", VOID_TYPE);

            string production = "declaration_list : declaration_list COMMA ID";
            write_log(production, $$);
        } else if (phase == Synthesis) {

        }
    }
    | declaration_list COMMA ID LTHIRD CONST_INT RTHIRD {
        if (phase == Analysis) {
            $$ = new SymbolInfo($1->get_symbol() + "," + $3->get_symbol() + 
                "[" + $5->get_symbol() + "]", "declaration_list", VOID_TYPE);

            string production = "declaration_list : declaration_list COMMA ID LTHIRD CONST_INT RTHIRD";
            write_log(production, $$);
        } else if (phase == Synthesis) {

        }
    }
    | ID {
        if (phase == Analysis) {
            $$ = new SymbolInfo($1->get_symbol(), "declaration_list", VOID_TYPE);

            string production = "declaration_list : ID";
            write_log(production, $$);
        } else if (phase == Synthesis) {

        }
    }
    | ID LTHIRD CONST_INT RTHIRD {
        if (phase == Analysis) {
            $$ = new SymbolInfo($1->get_symbol() + "[" + $3->get_symbol() + "]", "declaration_list", VOID_TYPE);

            string production = "declaration_list : ID LTHIRD CONST_INT RTHIRD";
            write_log(production, $$);
        } else if (phase == Synthesis) {

        }
    }
    | declaration_list error COMMA ID {
        if (phase == Analysis) {
            $$ = new SymbolInfo($1->get_symbol() + "," + $4->get_symbol(), "declaration_list", VOID_TYPE);

            string production = "declaration_list : ID LTHIRD CONST_INT RTHIRD";
            write_log(production, $$);
        } else if (phase == Synthesis) {

        }
    }
    ;

statements:
    statement {
        if (phase == Analysis) {
            $$ = new SymbolInfo($1->get_symbol(), "statements", $1->get_semantic_type());

            string production = "statements : statement";
            write_log(production, $$);
        } else if (phase == Synthesis) {

        }
    }
    | statements statement {
        if (phase == Analysis) {
            string statement_type = VOID_TYPE;
            if  ($1->get_semantic_type() == FLOAT_TYPE || $2->get_semantic_type() == FLOAT_TYPE) {
                statement_type = FLOAT_TYPE;
            } else if ($1->get_semantic_type() == INT_TYPE || $2->get_semantic_type() == INT_TYPE) {
                statement_type = INT_TYPE;
            }

            $$ = new SymbolInfo($1->get_symbol() + $2->get_symbol(), "statements", statement_type);
            
            string production = "statements : statements statement";
            write_log(production, $$);
        } else if (phase == Synthesis) {

        }
    }
    ;

statement:
    var_declaration {
        if (phase == Analysis) {
            $$ = new SymbolInfo($1->get_symbol(), "statement", VOID_TYPE);

            string production = "statement : var_declaration";
            write_log(production, $$);
        } else if (phase == Synthesis) {

        }
    }
    | expression_statement {
        if (phase == Analysis) {
            $$ = new SymbolInfo($1->get_symbol(), "statement", VOID_TYPE);

            string production = "statement : expression_statement";
            write_log(production, $$);
        } else if (phase == Synthesis) {

        }
    }
    | compound_statement {
        if (phase == Analysis) {
            $$ = new SymbolInfo($1->get_symbol(), "statement", $1->get_semantic_type());

            string production = "statement : compound_statement";
            write_log(production, $$);
        } else if (phase == Synthesis) {

        }
    }
    | FOR LPAREN expression_statement expression_statement expression RPAREN statement {
        if (phase == Analysis) {
            if ($4->get_semantic_type() == VOID_TYPE) {
                write_error_log("for conditional expression cannot be void type");
            }

            $$ = new SymbolInfo("for (" + $3->get_symbol() + " " + $4->get_symbol() + " " + 
                $5->get_symbol() + ")\n" + $7->get_symbol(), "statement", $7->get_semantic_type());
                
            string production = "statement : FOR LPAREN expression_statement expression_statement expression RPAREN statement";
            write_log(production, $$);
        } else if (phase == Synthesis) {

        }
    }
    | IF LPAREN expression RPAREN statement 
    %prec SHIFT_ELSE {
        if (phase == Analysis) {
            if ($3->get_semantic_type() == VOID_TYPE) {
                write_error_log("if expression cannot be void type");
            }

            $$ = new SymbolInfo("if (" + $3->get_symbol() + ")\n" + $5->get_symbol(), "statement", 
                $5->get_semantic_type());

            string production = "statement : IF LPAREN expression RPAREN statement";
            write_log(production, $$);
        } else if (phase == Synthesis) {

        }
    } 
    | IF LPAREN expression RPAREN statement ELSE statement {
        if (phase == Analysis) {
            if ($3->get_semantic_type() == VOID_TYPE) {
                write_error_log("if expression cannot be void type");
            }

            string statement_type = VOID_TYPE;
            if  ($5->get_semantic_type() == FLOAT_TYPE || $7->get_semantic_type() == FLOAT_TYPE) {
                statement_type = FLOAT_TYPE;
            } else if ($5->get_semantic_type() == INT_TYPE || $7->get_semantic_type() == INT_TYPE) {
                statement_type = INT_TYPE;
            }

            $$ = new SymbolInfo("if (" + $3->get_symbol() + ")\n" + $5->get_symbol() + " else\n" + 
                $7->get_symbol(), "statement", statement_type);

            string production = "statement : IF LPAREN expression RPAREN statement ELSE statement";
            write_log(production, $$);
        } else if (phase == Synthesis) {

        }
    }
    | WHILE LPAREN expression RPAREN statement {
        if (phase == Analysis) {
            if ($3->get_semantic_type() == VOID_TYPE) {
                write_error_log("while loop expression cannot be void type");
            }

            $$ = new SymbolInfo("while (" + $3->get_symbol() + ")\n" + $5->get_symbol(), "statement", 
                $5->get_semantic_type());

            string production = "statement : WHILE LPAREN expression RPAREN statement";
            write_log(production, $$);
        } else if (phase == Synthesis) {

        }
    }
    | PRINTLN LPAREN variable RPAREN SEMICOLON {
        if (phase == Analysis) {
            $$ = new SymbolInfo("printf(" + $3->get_symbol() + ");\n", "statement", VOID_TYPE);

            string production = "statement : PRINTLN LPAREN ID RPAREN SEMICOLON";
            write_log(production, $$);
        } else if (phase == Synthesis) {

        }
    }
    | RETURN expression SEMICOLON {
        if (phase == Analysis) {
            $$ = new SymbolInfo("return " + $2->get_symbol() + ";\n", "statement", $2->get_semantic_type());

            string production = "statement : RETURN expression SEMICOLON";
            write_log(production, $$);

            string expression_type = $2->get_semantic_type();
            string func_return_type = VOID_TYPE;
            if (current_func_sym_ptr != nullptr) {
                func_return_type = current_func_sym_ptr->get_semantic_type();
            }

            if (func_return_type == FLOAT_TYPE && expression_type == INT_TYPE) {
                // okay
            } else if (func_return_type == INT_TYPE && expression_type == FLOAT_TYPE) {
                write_error_log("Returning float type from a function with int return type", "WARNING");
            } else if (func_return_type != expression_type) {
                write_error_log("Cannot return " + expression_type + " from a function of " + 
                    func_return_type + " return type");
            }
        } else if (phase == Synthesis) {

        }
    }
    ;

expression_statement:
    SEMICOLON {
        if (phase == Analysis) {
            $$ = new SymbolInfo(";\n", "expression_statement", VOID_TYPE);

            string production = "expression_statement : SEMICOLON";
            write_log(production, $$);
        } else if (phase == Synthesis) {

        }
    }
    | expression SEMICOLON {
        if (phase == Analysis) {
            $$ = new SymbolInfo($1->get_symbol() + ";\n", "expression_statement", $1->get_semantic_type());

            string production = "expression_statement : expression SEMICOLON";
            write_log(production, $$);
        } else if (phase == Synthesis) {
            
        }
    }
    ;

variable:
    ID {
        if (phase == Analysis) {
            string var_name = $1->get_symbol();
            SymbolInfo* var_sym_ptr = symbol_table.lookup(var_name);
            string var_type = INT_TYPE;

            if (var_sym_ptr == nullptr) {
                write_error_log(var_name + " does not exist");
            } else {
                var_type = var_sym_ptr->get_semantic_type();
            }

            if (var_type == INT_ARRAY_TYPE) {
                write_error_log(var_name + " is an array and has to be indexed");
                var_type = INT_TYPE;
            } else if (var_type == FLOAT_ARRAY_TYPE) {
                write_error_log(var_name + " is an array and has to be indexed");
                var_type = FLOAT_TYPE;
            }

            $$ = new SymbolInfo($1->get_symbol(), "variable", var_type);

            string production = "variable : ID";
            write_log(production, $$);
        } else if (phase == Synthesis) {

        }
    }
    | ID LTHIRD expression RTHIRD {
        if (phase == Analysis) {
            if ($3->get_semantic_type() != INT_TYPE) {
                write_error_log("array index can only be int type");
            }

            string var_name = $1->get_symbol();
            SymbolInfo* var_sym_ptr = symbol_table.lookup(var_name);
            string var_type = INT_ARRAY_TYPE;

            if (var_sym_ptr == nullptr) {
                write_error_log(var_name + " does not exist");
            } else {
                var_type = var_sym_ptr->get_semantic_type();
            }

            if (var_type == INT_TYPE || var_type == FLOAT_TYPE) {
                write_error_log(var_name + " is not an array and cannot be indexed");
                var_type = INT_ARRAY_TYPE;
            }

            if (var_type == INT_ARRAY_TYPE) {
                var_type = INT_TYPE;
            } else {
                var_type = FLOAT_TYPE;
            }

            $$ = new SymbolInfo($1->get_symbol() + "[" + $3->get_symbol() + "]", "variable", var_type);

            string production = "variable : ID LTHIRD expression RTHIRD";
            write_log(production, $$);
        } else if (phase == Synthesis) {

        }
    }
    ;

expression:
    logic_expression {
        if (phase == Analysis) {
            $$ = new SymbolInfo($1->get_symbol(), "expression", $1->get_semantic_type());

            string production = "expression : logic_expression";
            write_log(production, $$);
        } else if (phase == Synthesis) {

        }
    }
    | variable ASSIGNOP logic_expression {
        if (phase == Analysis) {
            string type = $1->get_semantic_type();

            if ($3->get_semantic_type() == VOID_TYPE) {
                write_error_log("Void type cannot be assigned to any type");
            } else if ($1->get_semantic_type() == FLOAT_TYPE && $3->get_semantic_type() == INT_TYPE) {
                // okay  
            } else if ($1->get_semantic_type() == INT_TYPE && $3->get_semantic_type() == FLOAT_TYPE) {
                write_error_log("Assigning float to int", "WARNING");
            } else if ($1->get_semantic_type() != $3->get_semantic_type()) {
                write_error_log("Cannot assign " + $3->get_semantic_type() + " to " + $1->get_semantic_type());
            }

            $$ = new SymbolInfo($1->get_symbol() + " = " + $3->get_symbol(), "expression", type);

            string production = "expression : variable ASSIGNOP logic_expression";
            write_log(production, $$);
        } else if (phase == Synthesis) {

        }
    }
    ;

logic_expression:
    rel_expression {
        if (phase == Analysis) {
            $$ = new SymbolInfo($1->get_symbol(), "logic_expression", $1->get_semantic_type());

            string production = "logic_expression : rel_expression";
            write_log(production, $$);
        } else if (phase == Synthesis) {

        }
    }
    | rel_expression LOGICOP rel_expression {
        if (phase == Analysis) {
            if ($1->get_semantic_type() == VOID_TYPE || $3->get_semantic_type() == VOID_TYPE) {
                write_error_log("Logical operation not defined on void type");
            }

            $$ = new SymbolInfo($1->get_symbol() + " " + $2->get_symbol() + " " +
                $3->get_symbol(), "logic_expression", INT_TYPE);

            string production = "logic_expression : rel_expression LOGICOP rel_expression";
            write_log(production, $$);
        } else if (phase == Synthesis) {

        }
    }
    ;

rel_expression:
    simple_expression {
        if (phase == Analysis) {
            $$ = new SymbolInfo($1->get_symbol(), "rel_expression", $1->get_semantic_type());

            string production = "rel_expression : simple_expression";
            write_log(production, $$);
        } else if (phase == Synthesis) {

        }
    }
    | simple_expression RELOP simple_expression {
        if (phase == Analysis) {
            if ($1->get_semantic_type() == VOID_TYPE || $3->get_semantic_type() == VOID_TYPE) {
                write_error_log("Relational operation not defined on void type");
            }

            $$ = new SymbolInfo($1->get_symbol() + " " + $2->get_symbol() + " " + 
                $3->get_symbol(), "rel_expression", INT_TYPE);

            string production = "rel_expression : simple_expression RELOP simple_expression";
            write_log(production, $$);
        } else if (phase == Synthesis) {
            
        }
    }
    ;

simple_expression:
    term {
        if (phase == Analysis) {
            $$ = new SymbolInfo($1->get_symbol(), "simple_expression", $1->get_semantic_type());

            string production = "simple_expression : term";
            write_log(production, $$);
        } else if (phase == Synthesis) {

        }
    }
    | simple_expression ADDOP term {
        if (phase == Analysis) {
            string type = INT_TYPE;
            if ($1->get_semantic_type() == VOID_TYPE || $3->get_semantic_type() == VOID_TYPE) {
                write_error_log("Addition not defined on void type");
            } else if ($1->get_semantic_type() == FLOAT_TYPE || $3->get_semantic_type() == FLOAT_TYPE) {
                type = FLOAT_TYPE;
            }

            $$ = new SymbolInfo($1->get_symbol() + " " + $2->get_symbol() + " " + 
                $3->get_symbol(), "simple_expression", type);

            string production = "simple_expression : simple_expression ADDOP term";
            write_log(production, $$);
        } else if (phase == Synthesis) {

        }
    }
    ;

term:
    unary_expression {
        if (phase == Analysis) {
            $$ = new SymbolInfo($1->get_symbol(), "term", $1->get_semantic_type());

            string production = "term : unary_expression";
            write_log(production, $$);
        } else if (phase == Synthesis) {

        }
    }
    | term MULOP unary_expression {
        if (phase == Analysis) {
            string type = INT_TYPE;
            if ($1->get_semantic_type() == VOID_TYPE || $3->get_semantic_type() == VOID_TYPE) {
                write_error_log("Multiplication not defined on void type");
            } else if (
                $2->get_symbol() != "%" && 
                ($1->get_semantic_type() == FLOAT_TYPE || $3->get_semantic_type() == FLOAT_TYPE)
            ) {
                type = FLOAT_TYPE;
            }

            if ($2->get_symbol() == "%" && ($1->get_semantic_type() != INT_TYPE || $3->get_semantic_type() != INT_TYPE)) {
                write_error_log("modulo operation only defined on int types");
            }

            $$ = new SymbolInfo($1->get_symbol() + " " + $2->get_symbol() + " " +  $3->get_symbol(),
                "term", type);

            string production = "term : term MULOP unary_expression";
            write_log(production, $$);
        } else if (phase == Synthesis) {

        }
    }
    ;

unary_expression:
    ADDOP unary_expression 
    %prec UNARY {
        if (phase == Analysis) {
            $$ = new SymbolInfo($1->get_symbol() + $2->get_symbol(), "unary_expression", $2->get_semantic_type());

            string production = "unary_expression : ADDOP unary_expression";
            write_log(production, $$);
        } else if (phase == Synthesis) {

        }
    }
    | NOT unary_expression {
        if (phase == Analysis) {
            if ($2->get_semantic_type() == VOID_TYPE) {
                write_error_log("Not operation cannot be performed on void type");
            }
            
            $$ = new SymbolInfo("!" + $2->get_symbol(), "unary_expression", INT_TYPE);

            string production = "unary_expression : NOT unary_expression";
            write_log(production, $$);
        } else if (phase == Synthesis) {

        }
    }
    | factor {
        if (phase == Analysis) {
            $$ = new SymbolInfo($1->get_symbol(), "factor", $1->get_semantic_type());

            string production = "unary_expression : factor";
            write_log(production, $$);
        } else if (phase == Synthesis) {

        }
    }
    ;

factor:
    variable {
        if (phase == Analysis) {
            $$ = new SymbolInfo($1->get_symbol(), "factor", $1->get_semantic_type());

            string production = "factor : variable";
            write_log(production, $$);
        } else if (phase == Synthesis) {

        }
    }
    | ID LPAREN argument_list RPAREN {
        if (phase == Analysis) {
            string func_name = $1->get_symbol();
            SymbolInfo* func_sym_ptr = symbol_table.lookup(func_name);
            string return_type = VOID_TYPE;
            vector<string> param_type_list = {};

            if (func_sym_ptr == nullptr) {
                write_error_log(func_name + " does not exist and cannot be called");
            } else if (!is_sym_func(func_sym_ptr)) {
                write_error_log(func_name + " is not callable");
            } else {
                return_type = func_sym_ptr->get_semantic_type();
                param_type_list = func_sym_ptr->get_all_data();
                if (!is_func_sym_defined(func_sym_ptr)) {
                    param_type_list = vector<string>(param_type_list.begin(), param_type_list.end());
                } else {
                    param_type_list = vector<string>(param_type_list.begin(), param_type_list.end()-1);
                }

                vector<string> arg_types = $3->get_all_data();

                if (param_type_list[0] == VOID_TYPE && !arg_types.empty()) {
                    // catches VOID_TYPE argument error
                    write_error_log(func_name + " expects 0 arguments, but got " + to_string(arg_types.size()));
                } else if (param_type_list[0] != VOID_TYPE && param_type_list.size() != arg_types.size()) {
                    write_error_log(func_name + " expects " + to_string(param_type_list.size()) + 
                        " arguments, but got " + to_string(arg_types.size()));
                } else if (param_type_list[0] != VOID_TYPE && param_type_list != arg_types) {
                    write_error_log(func_name + " has parameters of type: " + vec_to_str(param_type_list) +
                        ", but got arguments of type: " + vec_to_str(arg_types));
                }
            }

            $$ = new SymbolInfo($1->get_symbol() + "(" + $3->get_symbol() + ")", "factor", return_type);

            string production = "factor : ID LPAREN argument_list RPAREN";
            write_log(production, $$);
        } else if (phase == Synthesis) {

        }
    }
    | LPAREN expression RPAREN {
        if (phase == Analysis) {
            $$ = new SymbolInfo("(" + $2->get_symbol() + ")", "factor", $2->get_semantic_type());

            string production = "factor : LPAREN expression RPAREN";
            write_log(production, $$);
        } else if (phase == Synthesis) {

        }
    }
    | CONST_INT {
        if (phase == Analysis) {
            $$ = new SymbolInfo($1->get_symbol(), "factor", INT_TYPE);

            string production = "factor : CONST_INT";
            write_log(production, $$);
        } else if (phase == Synthesis) {

        }
    }
    | CONST_FLOAT {
        if (phase == Analysis) {
            $$ = new SymbolInfo($1->get_symbol(), "factor", FLOAT_TYPE);

            string production = "factor : CONST_FLOAT";
            write_log(production, $$);
        } else if (phase == Synthesis) {

        }
    }
    | variable INCOP {
        if (phase == Analysis) {
            $$ = new SymbolInfo($1->get_symbol() + "++", "factor", $1->get_semantic_type());

            string production = "factor : variable INCOP";
            write_log(production, $$);
        } else if (phase == Synthesis) {

        }
    }
    | variable DECOP {
        if (phase == Analysis) {
            $$ = new SymbolInfo($1->get_symbol() + "--", "factor", $1->get_semantic_type());

            string production = "factor : variable DECOP";
            write_log(production, $$);
        } else if (phase == Synthesis) {

        }
    }
    ;

argument_list:
    arguments {
        if (phase == Analysis) {
            $$ = new SymbolInfo($1->get_symbol(), "argument_list", VOID_TYPE, $1->get_all_data());

            string production = "argument_list : arguments";
            write_log(production, $$);
        } else if (phase == Synthesis) {

        }
    }
    | %empty {
        if (phase == Analysis) {
            // empty params have void type data, but empty args don't
            $$ = new SymbolInfo("", "argument_list", VOID_TYPE); 

            string production = "argument_list : ";
            write_log(production, $$);
        } else if (phase == Synthesis) {

        }
    }
    ;

arguments:
    arguments COMMA logic_expression {
        if (phase == Analysis) {
            // if logic_expression has VOID_TYPE, function call will report that error
            vector<string> arg_type_data = $1->get_all_data();
            arg_type_data.push_back($3->get_semantic_type());

            $$ = new SymbolInfo($1->get_symbol() + "," + $3->get_symbol(), "arguments", VOID_TYPE, 
                arg_type_data);

            string production = "arguments : arguments COMMA logic_expression";
            write_log(production, $$);
        } else if (phase == Synthesis) {

        }
    }
    | logic_expression {
        if (phase == Analysis) {
            $$ = new SymbolInfo($1->get_symbol(), "arguments", VOID_TYPE, {$1->get_semantic_type()});

            string production = "arguments : logic_expression";
            write_log(production, $$);
        } else if (phase == Synthesis) {

        }
    }
    ;

%%

void yyerror(char* s) {
    write_error_log(s, "SYNTAX_ERR");
}

vector<string> split(string str, char delim) {
    stringstream sstrm(str);
    string split_str;
    vector<string> split_strs;

    while (getline(sstrm, split_str, delim)) {
        split_strs.push_back(split_str);    
    }

    return split_strs; 
}

bool is_sym_func(SymbolInfo* syminfo) {
    return !syminfo->get_all_data().empty();
}

bool is_func_sym_defined(SymbolInfo* syminfo) {
    return syminfo->get_all_data()[syminfo->get_all_data().size()-1] == "defined";
}

bool is_func_signatures_match(SymbolInfo* func_sym_ptr1, SymbolInfo* func_sym_ptr2) {
    vector<string> param_type_list1 = func_sym_ptr1->get_all_data();
    vector<string> param_type_list2 = func_sym_ptr2->get_all_data();
    if (param_type_list1[param_type_list1.size()-1] == "defined") {
        param_type_list1 = vector<string>(param_type_list1.begin(), param_type_list1.end()-1);
    }
    if (param_type_list2[param_type_list2.size()-1] == "defined") {
        param_type_list2 = vector<string>(param_type_list2.begin(), param_type_list2.end()-1);
    }

    return func_sym_ptr1->get_symbol() == func_sym_ptr2->get_symbol() && 
        func_sym_ptr1->get_semantic_type() == func_sym_ptr2->get_semantic_type() &&
        param_type_list1 == param_type_list2;
}

string vec_to_str(vector<string> strings) {
    stringstream ss;
    for (string str : strings) {
        ss << str << " ";
    }
    return ss.str();
}

bool insert_into_symtable(string symbol, string token_type, string semantic_type, vector<string> data) {
    if (!symbol_table.insert(symbol, token_type, semantic_type, data)) {
        write_error_log("Symbol name " + symbol + " already exists");
        return false;
    }
    return true;
}

bool insert_into_symtable(SymbolInfo* syminfo) {
    return insert_into_symtable(syminfo->get_symbol(), syminfo->get_token_type(), syminfo->get_semantic_type(), 
        syminfo->get_all_data());
}

bool insert_var_list_into_symtable(string var_type, vector<string> var_names) {
    bool is_all_success = true;
    for (string var_name : var_names) {
        if (var_name.find("[") < var_name.length()) {
            // variable is array
            var_name = var_name.substr(0, var_name.find("["));
            if (var_type == INT_TYPE) {
                is_all_success = is_all_success && insert_into_symtable(var_name, "ID", INT_ARRAY_TYPE);
            } else if (var_type == FLOAT_TYPE) {
                is_all_success = is_all_success && insert_into_symtable(var_name, "ID", FLOAT_ARRAY_TYPE);
            }
        } else {
            is_all_success = is_all_success && insert_into_symtable(var_name, "ID", var_type);
        }
    }
    return is_all_success;
}

void write_log(string production, SymbolInfo* matched_sym_ptr) {
    fprintf(log_file, "Line %d: %s\n\n", line_count, production.c_str());
    fprintf(log_file, "%s\n\n", matched_sym_ptr->get_symbol().c_str());
}

void write_error_log(string log_str, string tag) {
    error_count++;
    fprintf(log_file, "[%s] Line %d: %s\n\n", tag.c_str(), line_count, log_str.c_str());
    fprintf(error_file, "[%s] Line %d: %s\n\n", tag.c_str(), line_count, log_str.c_str());
}

void write_symtable_in_log(SymbolTable& symtable) {
    ostringstream osstrm;
    osstrm << symtable;
    fprintf(log_file, "%s\n\n", osstrm.str().c_str());
}

int main(int argc, char* argv[]) {
    if (argc != 2) {
        cout << "ERROR: Parser needs input file as argument\n";
        return 1;
    }

    input_file = fopen(argv[1], "r");
    log_file = fopen("log.txt", "w");
    error_file = fopen("error.txt", "w");

    if (!input_file || !log_file || !error_file) {
        cerr << "ERROR: Could not open file\n";
        cout << input_file << " - " << log_file << " - " << error_file << endl;
        return 1;
    }

    phase = Analysis;

    yyin = input_file;

    yyparse();

    fprintf(log_file, "Total lines: %d\nTotal errors: %d", --line_count, error_count);

    fclose(input_file);
    fclose(log_file);
    fclose(error_file);

    return 0;
}