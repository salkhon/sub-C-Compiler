%{
    #include <iostream>
    #include <cstdlib>
    #include <cstring>
    #include <cstdio>
    #include <string>
    #include <fstream>
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

    FILE* input_file;
    ofstream log_file, error_file;

    int error_count = 0;
    const int SYM_TABLE_BUCKETS = 10;
    SymbolTable symbol_table(SYM_TABLE_BUCKETS);

    const string INT_TYPE = "int";
    const string INT_ARRAY_TYPE = "int_arr";
    const string FLOAT_TYPE = "float";
    const string FLOAT_ARRAY_TYPE = "float_arr";
    const string VOID_TYPE = "void";

    SymbolInfo* current_func_sym_ptr =  nullptr;
    vector<SymbolInfo*> params_for_func_scope;

    const string TEMP_CODE_FILE_NAME = "_code.asm", CODE_FILE_NAME = "code.asm", 
        OPTIM_CODE_FILE_NAME = "optimized_code.asm";
    const string SOURCE_MAIN_FUNC_NAME = "__main__";

    ofstream code_file;
    const int DW_SZ = 2;

    vector<SymbolInfo*> globals;
    int current_stack_offset;

    enum Label {
        FOR_LOOP_CONDITION, FOR_LOOP_INCREMENT, FOR_LOOP_BODY, FOR_LOOP_END, WHILE_LOOP_CONDITION, 
        WHILE_LOOP_BODY, WHILE_LOOP_END, ELSE_BODY, IF_ELSE_END, CMP_TRUE, CMP_FALSE, SHORT_CIRC
    };

    // number of label-requiring-statements encountered
    int label_count = 0;
    // depth of nested label-requiring-statements
    int label_depth = 0;

    /**
        Analysis utils
    **/
    bool is_sym_func(SymbolInfo*);
    bool is_func_sym_defined(SymbolInfo*);
    bool is_func_signatures_match(SymbolInfo*, SymbolInfo*);
    bool insert_into_symtable(string, string, string, vector<string> = {});
    bool insert_into_symtable(SymbolInfo*);
    bool insert_var_list_into_symtable(string, vector<string>);
    void write_log(string, SymbolInfo*);
    void write_error_log(string, string = "ERROR");
    void write_symtable_in_log(SymbolTable&);

    /**
        Synthesis utils
    **/
    string get_label(Label, int=-1);
    string _get_var_ref(SymbolInfo*);
    vector<string> _get_activation_record_teardown_code();
    void _alloc_int_var(string);
    void _alloc_int_array(string, int);
    void write_code(const string&, int=0);
    void write_code(const vector<string>&, int=0);
    void append_print_proc_def_to_codefile();
    void structure_main_asm_codefile();

    /**
        Optimization utils
    **/
    void peephole_optimization();
    void do_peephole(vector<string>&);
    void write_optimized_code_to_file(vector<string>&);
    vector<string> load_code_into_mem();
    
    /**
        General utils
    **/
    bool starts_with(const string&, const string&);
    vector<string> split_str(const string, const string);
    string vec_to_str(vector<string>);
    vector<string> split(string, char = ' ');
    void replace_substr(string&, const string, const string);
    void trim(string&);
    void copy_txt_file(ifstream&, ofstream&);
    void delete_debug_files();
%}

%union {
    SymbolInfo* SymPtr;
    // int will be used to keep track of labeled statements' opening and closing label id in between nested statements
    int IntVal;
}

%token
    LPAREN RPAREN SEMICOLON COMMA LCURL RCURL INT FLOAT VOID LTHIRD RTHIRD FOR IF ELSE WHILE
    PRINTLN RETURN ASSIGNOP NOT INCOP DECOP

%token<SymPtr>
    ID CONST_INT CONST_FLOAT LOGICOP RELOP ADDOP MULOP

%type<SymPtr>
    start program unit var_declaration func_definition type_specifier parameter_list
    compound_statement statements declaration_list statement expression_statement expression
    variable rel_expression simple_expression term unary_expression factor func_declaration 
    func_signature compound_statement_start func_signature_start
    
// requires both int and syminfoptr
%type
    logic_expression if_condition argument_list arguments

%destructor {
    delete $$;
} <SymPtr>

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
            append_print_proc_def_to_codefile();
            YYACCEPT;
        }
    }
    ;

program: 
    program unit {
        if (phase == Analysis) {
            $$ = new SymbolInfo($1->get_symbol() + "\n" + $2->get_symbol(), "program", VOID_TYPE);

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
            write_code("");
        }
    }
    ;

func_declaration: 
    func_signature SEMICOLON {
        if (phase == Analysis) {
            $$ = new SymbolInfo($1->get_symbol() + ";", "func_declaration", VOID_TYPE);
            // declaration, so no scope will be created, so have to manually insert the built func sym
            insert_into_symtable(current_func_sym_ptr);

            delete current_func_sym_ptr;
            current_func_sym_ptr = nullptr;
            params_for_func_scope.clear();

            string production = "func_declaration : type_specifier ID LPAREN parameter_list RPAREN SEMICOLON";
            write_log(production, $$);
        } else if (phase == Synthesis) {
            delete current_func_sym_ptr;
            current_func_sym_ptr = nullptr;
            params_for_func_scope.clear();
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

            $$ = new SymbolInfo($1->get_symbol() +  "\n" + $2->get_symbol(), "func_definition", VOID_TYPE);

            string production = "func_definition : type_specifier ID LPAREN parameter_list RPAREN compound_statement";
            write_log(production, $$);

            current_func_sym_ptr->add_data("defined"); // to catch multiple definition error, but allow definition after declaration
            current_func_sym_ptr = nullptr;
        } else if (phase == Synthesis) {
            if (current_func_sym_ptr->get_semantic_type() == VOID_TYPE) {
                vector<string> code = _get_activation_record_teardown_code();
                write_code(code, label_depth);
            }

            write_code("ENDP", --label_depth);

            delete current_func_sym_ptr;
            current_func_sym_ptr = nullptr;
            params_for_func_scope.clear();
            symbol_table.exit_scope();
        }
    }
    ;

func_signature:
    func_signature_start parameter_list RPAREN {
        if (phase == Analysis) {
            string return_type = $1->get_semantic_type();
            string func_name = $1->get_symbol();

            vector<string> param_type_list = $2->get_all_data(); 
            if (param_type_list.empty()) {
                param_type_list.push_back(VOID_TYPE); // if empty MUST HAVE VOID to know its a func
            }

            $$ = new SymbolInfo(return_type + " " + func_name + "(" + $2->get_symbol() + 
                ")", "func_signature", return_type, param_type_list);

            // definition will insert in compound_statement, declaration will insert in func_declaration
            current_func_sym_ptr = new SymbolInfo(func_name, "ID", return_type, param_type_list);
        } else if (phase == Synthesis) {

        }
    }
    | func_signature_start parameter_list error RPAREN {
        if (phase == Analysis) {
            string func_name = $1->get_symbol();
            string return_type = $1->get_semantic_type();

            vector<string> param_type_list = $2->get_all_data(); 
            if (param_type_list.empty()) {
                param_type_list.push_back(VOID_TYPE); // if empty MUST HAVE VOID to know its a func
            }

            $$ = new SymbolInfo(return_type + " " + func_name + "(" + $2->get_symbol() + 
                " [SYNTAX_ERR] )", "func_signature", return_type, param_type_list);

            current_func_sym_ptr = new SymbolInfo(func_name, "ID", return_type, param_type_list);
        
            // yyerror("resumed at RPAREN");
            yyerrok;
        } else if (phase == Synthesis) {

        }
    }
    ;

func_signature_start:
    type_specifier ID LPAREN {
        if (phase == Analysis) {
            string return_type = $1->get_symbol();
            string func_name = $2->get_symbol();
            $$ = new SymbolInfo(func_name, "func_signature_start", return_type);
        } else if (phase == Synthesis) {
            string ret_type = $1->get_symbol();
            string func_name = $2->get_symbol();

            current_func_sym_ptr = new SymbolInfo(func_name, "ID", ret_type);
        }
    }

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
            string param_type = $3->get_symbol();
            string param_name = $4->get_symbol();
            current_func_sym_ptr->add_data(param_type);
            
            params_for_func_scope.push_back(new SymbolInfo(param_name, "ID", param_type)); // .clear() calls delete
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
            string param_type = $1->get_symbol();
            string param_name = $2->get_symbol();
            current_func_sym_ptr->add_data(param_type);
            
            params_for_func_scope.push_back(new SymbolInfo(param_name, "ID", param_type));
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
            string production = "parameter_list : epsilon";
            write_log(production, $$);
        } else if (phase == Synthesis) {
            // empty param list will be added VOID_TYPE in function_signture
            current_func_sym_ptr->add_data(VOID_TYPE);
        }
    }
    ;

compound_statement:
    compound_statement_start statements RCURL {
        if (phase == Analysis) {
            $$ = new SymbolInfo($1->get_symbol() + "\n" + $2->get_symbol() + "\n}", "compound_statement", 
                $2->get_semantic_type());

            string production = "compound_statement : LCURL statements RCURL";
            write_log(production, $$);

            write_symtable_in_log(symbol_table);
            symbol_table.exit_scope();
        } else if (phase == Synthesis) {
            symbol_table.exit_scope();
        }
    }
    | compound_statement_start RCURL {
        if (phase == Analysis) {
            $$ = new SymbolInfo($1->get_symbol() + "\n}", "compound_statement", VOID_TYPE);

            string production = "compound_statement : LCURL RCURL";
            write_log(production, $$);

            write_symtable_in_log(symbol_table);
            symbol_table.exit_scope();
        } else if (phase == Synthesis) {
            symbol_table.exit_scope();
        }
    }
    | error RCURL {
        if (phase == Analysis) {
            $$ = new SymbolInfo("{\n[SYNTAX_ERR]\n}", "compound_statement", VOID_TYPE);

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
            // start of new scope, but need to check if start of new function before setting up symbol table
            symbol_table.enter_scope();

            if (label_depth == 0) {
                // only global functions allowed (depth=0)
                current_stack_offset = params_for_func_scope.size(); // offset 0 is for return IP, paramsize+1 is for old BP. 
                for (SymbolInfo* param_symbol : params_for_func_scope) {
                    param_symbol->get_codegen_info_ptr()->set_is_local(true);
                    param_symbol->get_codegen_info_ptr()->set_stack_offset(current_stack_offset--);
                    insert_into_symtable(param_symbol);
                }
                current_stack_offset--; // one extra position stores the return IP (at BP, offset=0)
        
                string func_name = current_func_sym_ptr->get_symbol();
                func_name = func_name == "main" ? SOURCE_MAIN_FUNC_NAME : func_name;
                string code = func_name + " PROC";
                write_code(code, label_depth++);

                code = "MOV BP, SP"; // set new BP, with params above, locals below - return IP pointed at
                write_code(code, label_depth);
            }
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
            $$ = new SymbolInfo(INT_TYPE, "type_specifier");
        }
    }
    | FLOAT {
        if (phase == Analysis) {
            $$ = new SymbolInfo("float", "type_specifier", VOID_TYPE);

            string production = "type_specifier : FLOAT";
            write_log(production, $$);
        } else if (phase == Synthesis) {
            $$ = new SymbolInfo(FLOAT_TYPE, "type_specifier");
        }
    }
    | VOID {
        if (phase == Analysis) {
            $$ = new SymbolInfo("void", "type_specifier", VOID_TYPE);

            string production = "type_specifier : VOID";
            write_log(production, $$);
        } else if (phase == Synthesis) {
            $$ = new SymbolInfo(VOID_TYPE, "type_specifier");
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
            _alloc_int_var($3->get_symbol());
        }
    }
    | declaration_list COMMA ID LTHIRD CONST_INT RTHIRD {
        if (phase == Analysis) {
            $$ = new SymbolInfo($1->get_symbol() + "," + $3->get_symbol() + 
                "[" + $5->get_symbol() + "]", "declaration_list", VOID_TYPE);

            string production = "declaration_list : declaration_list COMMA ID LTHIRD CONST_INT RTHIRD";
            write_log(production, $$);
        } else if (phase == Synthesis) {
            _alloc_int_array($3->get_symbol(), stoi($5->get_symbol()));
        }
    }
    | ID {
        if (phase == Analysis) {
            $$ = new SymbolInfo($1->get_symbol(), "declaration_list", VOID_TYPE);

            string production = "declaration_list : ID";
            write_log(production, $$);
        } else if (phase == Synthesis) {
            _alloc_int_var($1->get_symbol());
        }
    }
    | ID LTHIRD CONST_INT RTHIRD {
        if (phase == Analysis) {
            $$ = new SymbolInfo($1->get_symbol() + "[" + $3->get_symbol() + "]", "declaration_list", VOID_TYPE);

            string production = "declaration_list : ID LTHIRD CONST_INT RTHIRD";
            write_log(production, $$);
        } else if (phase == Synthesis) {
            _alloc_int_array($1->get_symbol(), stoi($3->get_symbol()));
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

            $$ = new SymbolInfo($1->get_symbol() + "\n" + $2->get_symbol(), "statements", statement_type);
            
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
    | FOR LPAREN expression_statement {
        if (phase == Analysis) {

        } else if (phase == Synthesis) {
            vector<string> code{
                "; FOR LOOP START", 
                get_label(FOR_LOOP_CONDITION) + ":"
            };
            // $S will be used as a label identifier, so we can label corresponding opening and closing labels with same id
            write_code(code, label_depth);

            $<IntVal>$ = label_count - 1; 
        }
    } expression_statement {
        if (phase == Analysis) {
            if ($5->get_semantic_type() == VOID_TYPE) {
                write_error_log("for conditional expression cannot be void type");
            }
        } else if (phase == Synthesis) {
            const int CURR_LABEL_ID = $<IntVal>4;
            vector<string> code{
                "; FOR LOOP CONDITION CHECK",
                "CMP AX, 0", 
                "JNE " + get_label(FOR_LOOP_BODY, CURR_LABEL_ID), 
                "JMP " + get_label(FOR_LOOP_END, CURR_LABEL_ID),
                get_label(FOR_LOOP_INCREMENT, CURR_LABEL_ID) + ":"
            };
            write_code(code, label_depth);

            $<IntVal>$ = $<IntVal>4;
        }
    } expression RPAREN {
        if (phase == Analysis) {

        } else if (phase == Synthesis) {
            const int CURR_LABEL_ID = $<IntVal>6;
            vector<string> code{
                "JMP " + get_label(FOR_LOOP_CONDITION, CURR_LABEL_ID),
                get_label(FOR_LOOP_BODY, CURR_LABEL_ID) + ":"
            };
            write_code(code, label_depth++);

            $<IntVal>$ = $<IntVal>6;
        }
    } statement {
        if (phase == Analysis) {    
            $$ = new SymbolInfo("for (" + $3->get_symbol() + " " + $5->get_symbol() + " " + 
                $7->get_symbol() + ")\n" + $10->get_symbol(), "statement", $10->get_semantic_type());

            string production = "statement : FOR LPAREN expression_statement expression_statement expression RPAREN statement";
            write_log(production, $$);
        } else if (phase == Synthesis) {
            const int CURR_LABEL_ID = $<IntVal>9;
            vector<string> code{
                "JMP " + get_label(FOR_LOOP_INCREMENT, CURR_LABEL_ID), 
                get_label(FOR_LOOP_END, CURR_LABEL_ID) + ":"
            };
            write_code(code, --label_depth);
        }
    }
    | if_condition statement 
    %prec SHIFT_ELSE {
        if (phase == Analysis) {
            $$ = new SymbolInfo($<SymPtr>1->get_symbol() + "\n" + $2->get_symbol(), "statement", 
                $2->get_semantic_type());

            string production = "statement : IF LPAREN expression RPAREN statement";
            write_log(production, $$);
        } else if (phase == Synthesis) {
            const int CURR_LABEL_ID = $<IntVal>1;
            vector<string> code{
                get_label(ELSE_BODY, CURR_LABEL_ID) + ":", // if_condition always assumes if-else, so dummy else label
                get_label(IF_ELSE_END, CURR_LABEL_ID) + ":"
            };
            write_code(code, --label_depth);    
        }
    }
    | if_condition statement ELSE {
        if (phase == Analysis) {

        } else if (phase == Synthesis) {
            const int CURR_LABEL_ID = $<IntVal>1;
            vector<string> code{
                "JMP " + get_label(IF_ELSE_END, CURR_LABEL_ID), // if body execution ends in jumping over else body
                get_label(ELSE_BODY, CURR_LABEL_ID) + ":"
            };
            write_code(code, label_depth-1);

            $<IntVal>$ = $<IntVal>1;
        }
    } statement {
        if (phase == Analysis) {
            string statement_type = VOID_TYPE;
            if  ($2->get_semantic_type() == FLOAT_TYPE || $5->get_semantic_type() == FLOAT_TYPE) {
                statement_type = FLOAT_TYPE;
            } else if ($2->get_semantic_type() == INT_TYPE || $5->get_semantic_type() == INT_TYPE) {
                statement_type = INT_TYPE;
            }

            $$ = new SymbolInfo($<SymPtr>1->get_symbol() + "\n" + $2->get_symbol() + " else " + 
                $5->get_symbol(), "statement", statement_type);

            string production = "statement : IF LPAREN expression RPAREN statement ELSE statement";
            write_log(production, $$);
        } else if (phase == Synthesis) {
            const int CURR_LABEL_ID = $<IntVal>4;
            string code = get_label(IF_ELSE_END, CURR_LABEL_ID) + ":";
            write_code(code, --label_depth);
        }
    }
    | WHILE LPAREN {
        if (phase == Analysis) {

        } else if (phase == Synthesis) {
            vector<string> code{
                "; WHILE LOOP START",
                get_label(WHILE_LOOP_CONDITION) + ":"
            };
            write_code(code, label_depth);

            $<IntVal>$ = label_count - 1;
        }
    } expression RPAREN {
        if (phase == Analysis) {
            if ($4->get_semantic_type() == VOID_TYPE) {
                write_error_log("while loop expression cannot be void type");
            }
        } else if (phase == Synthesis) {
            const int CURR_LABEL_ID = $<IntVal>3;
            vector<string> code{
                "; WHILE LOOP CONDITION CHECK",
                "CMP AX, 0", 
                "JNE " + get_label(WHILE_LOOP_BODY, CURR_LABEL_ID), 
                "JMP " + get_label(WHILE_LOOP_END, CURR_LABEL_ID), 
                get_label(WHILE_LOOP_BODY, CURR_LABEL_ID) + ":"
            };
            write_code(code, label_depth++);

            $<IntVal>$ = $<IntVal>3;
        }
    } statement {
        if (phase == Analysis) {
            $$ = new SymbolInfo("while (" + $4->get_symbol() + ")\n" + $7->get_symbol(), "statement", 
                $7->get_semantic_type());

            string production = "statement : WHILE LPAREN expression RPAREN statement";
            write_log(production, $$);
        } else if (phase == Synthesis) {
            const int CURR_LABEL_ID = $<IntVal>6;
            vector<string> code{
                "JMP " + get_label(WHILE_LOOP_CONDITION, CURR_LABEL_ID), 
                get_label(WHILE_LOOP_END, CURR_LABEL_ID) + ":"
            };
            write_code(code, --label_depth);
        }
    }
    | PRINTLN LPAREN variable RPAREN SEMICOLON {
        if (phase == Analysis) {
            $$ = new SymbolInfo("printf(" + $3->get_symbol() + ");", "statement", VOID_TYPE);

            string production = "statement : PRINTLN LPAREN ID RPAREN SEMICOLON";
            write_log(production, $$);
        } else if (phase == Synthesis) {
            SymbolInfo* var_sym = symbol_table.lookup($3->get_symbol());
            string var_ref = _get_var_ref(var_sym);
            vector<string> code{
                "; PRINT STATEMENT VAR " + var_sym->get_symbol(), 
                "MOV AX, " + var_ref, 
                "CALL PRINT_INT_IN_AX"
            };
            write_code(code, label_depth);    
        }
    }
    | RETURN expression SEMICOLON {
        if (phase == Analysis) {
            $$ = new SymbolInfo("return " + $2->get_symbol() + ";", "statement", $2->get_semantic_type());

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
            vector<string> code = _get_activation_record_teardown_code();
            write_code(code, label_depth);
        }
    }
    ;

if_condition:
    IF LPAREN expression RPAREN {
        if (phase == Analysis) {
            if ($3->get_semantic_type() == VOID_TYPE) {
                write_error_log("if expression cannot be void type");
            }
            $<SymPtr>$ = new SymbolInfo("if (" + $3->get_symbol() + ")", "if_condition", VOID_TYPE);
        } else if (phase == Synthesis) {
            vector<string> code{
                "; IF STATEMENT START",
                "CMP AX, 0", 
                "JE " + get_label(ELSE_BODY)
            };
            write_code(code, label_depth++);

            $<IntVal>$ = label_count - 1;
        }
    }

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
            // can be l value or r value - so not resolving now, just inheritting symbol name to find in sym table.
            $$ = $1;
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
            // expression value on AX, since its an index, move it to SI, in word size
            vector<string> code{
                "MOV BX, " + to_string(DW_SZ),
                "MUL BX",
                "MOV SI, AX" 
            };
            write_code(code, 1);
            $$ = new SymbolInfo(*$1); 
        }
    }
    ;

expression:
    logic_expression {
        if (phase == Analysis) {
            $$ = new SymbolInfo($<SymPtr>1->get_symbol(), "expression", $<SymPtr>1->get_semantic_type());

            string production = "expression : logic_expression";
            write_log(production, $$);
        } else if (phase == Synthesis) {

        }
    }
    | variable ASSIGNOP logic_expression {
        if (phase == Analysis) {
            string type = $1->get_semantic_type();

            if ($<SymPtr>3->get_semantic_type() == VOID_TYPE) {
                write_error_log("Void type cannot be assigned to any type");
            } else if ($1->get_semantic_type() == FLOAT_TYPE && $<SymPtr>3->get_semantic_type() == INT_TYPE) {
                // okay  
            } else if ($1->get_semantic_type() == INT_TYPE && $<SymPtr>3->get_semantic_type() == FLOAT_TYPE) {
                write_error_log("Assigning float to int", "WARNING");
            } else if ($1->get_semantic_type() != $<SymPtr>3->get_semantic_type()) {
                write_error_log("Cannot assign " + $<SymPtr>3->get_semantic_type() + " to " + $1->get_semantic_type());
            }

            $$ = new SymbolInfo($1->get_symbol() + " = " + $<SymPtr>3->get_symbol(), "expression", type);

            string production = "expression : variable ASSIGNOP logic_expression";
            write_log(production, $$);
        } else if (phase == Synthesis) {
            // variable can be an array, if so, index is in SI.
            SymbolInfo* var_sym_ptr = symbol_table.lookup($1->get_symbol());
            string var_ref = _get_var_ref(var_sym_ptr);
            string code = "MOV " + var_ref + ", AX";
            write_code(code, label_depth);
        }
    }
    ;

logic_expression:
    rel_expression {
        if (phase == Analysis) {
            $<SymPtr>$ = new SymbolInfo($1->get_symbol(), "logic_expression", $1->get_semantic_type());

            string production = "logic_expression : rel_expression";
            write_log(production, $<SymPtr>$);
        } else if (phase == Synthesis) {
            
        }
    }
    | rel_expression LOGICOP {
        if (phase == Analysis) {

        } else if (phase == Synthesis) {
            vector<string> code;

            if ($2->get_symbol() == "&&") {
                code.push_back("CMP AX, 0");
            } else if ($2->get_symbol() == "||") {
                code.push_back("CMP AX, 1");
            }
            code.insert(code.end(), {
                "JE " + get_label(SHORT_CIRC), 
                "PUSH AX" // if not short circuited
            });

            write_code(code, label_depth);

            $<IntVal>$ = label_count - 1;
        }
    } rel_expression {
        if (phase == Analysis) {
            if ($1->get_semantic_type() == VOID_TYPE || $4->get_semantic_type() == VOID_TYPE) {
                write_error_log("Logical operation not defined on void type");
            }

            $<SymPtr>$ = new SymbolInfo($1->get_symbol() + " " + $2->get_symbol() + " " +
                $4->get_symbol(), "logic_expression", INT_TYPE);

            string production = "logic_expression : rel_expression LOGICOP rel_expression";
            write_log(production, $<SymPtr>$);
        } else if (phase == Synthesis) {
            vector<string> code{
                "MOV BX, AX", 
                "POP AX"
            };
            if ($2->get_symbol() == "&&") {
                code.push_back("AND AX, BX");
            } else if ($2->get_symbol() == "||") {
                code.push_back("OR AX, BX");
            }
            code.push_back(get_label(SHORT_CIRC, $<IntVal>3) + ":");
            write_code(code, label_depth);
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
    | simple_expression {
        if (phase == Analysis) {

        } else if (phase == Synthesis) {
            vector<string> code{
                "; COMPARISON START",
                "PUSH AX"
            };
            write_code(code, label_depth);
        }
    } RELOP simple_expression {
        if (phase == Analysis) {
            if ($1->get_semantic_type() == VOID_TYPE || $3->get_semantic_type() == VOID_TYPE) {
                write_error_log("Relational operation not defined on void type");
            }

            $$ = new SymbolInfo($1->get_symbol() + " " + $3->get_symbol() + " " + 
                $4->get_symbol(), "rel_expression", INT_TYPE);

            string production = "rel_expression : simple_expression RELOP simple_expression";
            write_log(production, $$);
        } else if (phase == Synthesis) {
            string relop = $3->get_symbol();
            vector<string> code = {
                "MOV BX, AX", 
                "POP AX",
                "CMP AX, BX", 
                "MOV AX, 0" // default false
            };

            const size_t CURR_LABEL_ID = label_count;

            if (relop == "<") {
                code.push_back("JL " + get_label(CMP_TRUE));
            } else if (relop == "<=") {
                code.push_back("JLE " + get_label(CMP_TRUE));
            } else if (relop == ">") {
                code.push_back("JG " + get_label(CMP_TRUE));
            } else if (relop == ">=") {
                code.push_back("JGE " + get_label(CMP_TRUE));
            } else if (relop == "==") {
                code.push_back("JE " + get_label(CMP_TRUE));
            } else if (relop == "!=") {
                code.push_back("JNE " + get_label(CMP_TRUE));
            } // label_count incremented

            code.push_back("JMP " + get_label(CMP_FALSE, CURR_LABEL_ID)); // default false

            code.push_back(get_label(CMP_TRUE, CURR_LABEL_ID) + ":");
            code.push_back("MOV AX, 1");

            code.push_back(get_label(CMP_FALSE, CURR_LABEL_ID) + ":"); // default false
            code.push_back("; COMPARISON END");

            write_code(code, label_depth);
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
    | simple_expression {
        if (phase == Analysis) {

        } else if (phase == Synthesis) {
            string code = "PUSH AX";
            write_code(code, label_depth);
        }
    } ADDOP term {
        if (phase == Analysis) {
            string type = INT_TYPE;
            if ($1->get_semantic_type() == VOID_TYPE || $3->get_semantic_type() == VOID_TYPE) {
                write_error_log("Addition not defined on void type");
            } else if ($1->get_semantic_type() == FLOAT_TYPE || $3->get_semantic_type() == FLOAT_TYPE) {
                type = FLOAT_TYPE;
            }

            $$ = new SymbolInfo($1->get_symbol() + " " + $3->get_symbol() + " " + 
                $4->get_symbol(), "simple_expression", type);

            string production = "simple_expression : simple_expression ADDOP term";
            write_log(production, $$);
        } else if (phase == Synthesis) {
            string addop = $3->get_symbol();
            vector<string> code{
                "MOV BX, AX", 
                "POP AX"
            };

            if (addop == "+") {
                code.push_back("ADD AX, BX");
            } else if (addop == "-") {
                code.push_back("SUB AX, BX");
            }
            write_code(code, label_depth);
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
    | term {
        if (phase == Analysis) {

        } else if (phase == Synthesis) {
            string code = "PUSH AX";
            write_code(code, 1);
        }
    } MULOP unary_expression {
        if (phase == Analysis) {
            string type = INT_TYPE;
            if ($1->get_semantic_type() == VOID_TYPE || $3->get_semantic_type() == VOID_TYPE) {
                write_error_log("Multiplication not defined on void type");
            } else if (
                $3->get_symbol() != "%" && 
                ($1->get_semantic_type() == FLOAT_TYPE || $4->get_semantic_type() == FLOAT_TYPE)
            ) {
                type = FLOAT_TYPE;
            }

            if ($3->get_symbol() == "%" && ($1->get_semantic_type() != INT_TYPE || $4->get_semantic_type() != INT_TYPE)) {
                write_error_log("modulo operation only defined on int types");
            }

            $$ = new SymbolInfo($1->get_symbol() + " " + $3->get_symbol() + " " +  $4->get_symbol(),
                "term", type);

            string production = "term : term MULOP unary_expression";
            write_log(production, $$);
        } else if (phase == Synthesis) {
            string mulop = $3->get_symbol();
            vector<string> code = {
                "MOV BX, AX", 
                "POP AX",
            }; 

            if (mulop == "*") {
                code.push_back("IMUL BX"); // result in DX:AX, we'll take AX
            } else if (mulop == "/") {
                code.push_back("MOV DX, 0");
                code.push_back("IDIV BX"); // AX quo, DX rem
            } else if (mulop == "%") {
                code.push_back("MOV DX, 0");
                code.push_back("IDIV BX");
                code.push_back("MOV AX, DX");
            }
            write_code(code, 1);
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
            string addop = $1->get_symbol();
            if (addop == "-") {
                string code = "NEG AX";
                write_code(code, label_depth);
            }
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
            vector<string> code = {
                "CMP AX, 0",
                "MOV AX, 0", 
                "SETE AL"
            };
            write_code(code, 1);
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
            // when variable reduces to factor, it's symbol table info is no longer needed, just the value on AX. 
            SymbolInfo* var_sym_ptr = symbol_table.lookup($1->get_symbol());
            string var_ref = _get_var_ref(var_sym_ptr);
            string code = "MOV AX, " + var_ref;
            write_code(code, label_depth);
        }
    }
    | ID LPAREN {
        if (phase == Analysis) {

        } else if (phase == Synthesis) {
            // the definition code for the procedure we are calling is independent, written with its own current_stack_offset, 
            string func_name = $1->get_symbol();
            vector<string> code{
                "; ACTIVATION RECORD SETUP FOR FUNCTION " + func_name,
                "PUSH BP", 
            };
            write_code(code, label_depth);
        }
    } argument_list RPAREN {
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

                vector<string> arg_types = $<SymPtr>4->get_all_data();

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

            $$ = new SymbolInfo($1->get_symbol() + "(" + $<SymPtr>3->get_symbol() + ")", "factor", return_type);

            string production = "factor : ID LPAREN argument_list RPAREN";
            write_log(production, $$);
        } else if (phase == Synthesis) {
            string func_name = $1->get_symbol();
            size_t arg_count = $<IntVal>4;
            vector<string> code(arg_count, "POP BX"); // pop args
            code.insert(code.begin(), "CALL " + func_name);
            code.insert(code.end(), {
                "POP BP", // restore old BP
                "; EXECUTION COMPLETE FOR FUNCTION " + func_name
            });
            write_code(code, label_depth);
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
            string code = "MOV AX, " + $1->get_symbol();
            write_code(code, label_depth);
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
            SymbolInfo* var_sym_ptr = symbol_table.lookup($1->get_symbol());
            string var_ref = _get_var_ref(var_sym_ptr);
            vector<string> code = {
                "MOV AX, " + var_ref, 
                "MOV BX, AX", 
                "INC BX", 
                "MOV " + var_ref + ", BX"
            };
            write_code(code, label_depth);
        }
    }
    | variable DECOP {
        if (phase == Analysis) {
            $$ = new SymbolInfo($1->get_symbol() + "--", "factor", $1->get_semantic_type());

            string production = "factor : variable DECOP";
            write_log(production, $$);
        } else if (phase == Synthesis) {
            SymbolInfo* var_sym_ptr = symbol_table.lookup($1->get_symbol());
            string var_ref = _get_var_ref(var_sym_ptr);
            vector<string> code = {
                "MOV AX, " + var_ref, 
                "MOV BX, AX",
                "DEC BX",
                "MOV " + var_ref + ", BX"
            };
            write_code(code, label_depth);
        }
    }
    ;

argument_list:
    arguments {
        if (phase == Analysis) {
            $<SymPtr>$ = new SymbolInfo($<SymPtr>1->get_symbol(), "argument_list", VOID_TYPE, 
                $<SymPtr>1->get_all_data());

            string production = "argument_list : arguments";
            write_log(production, $<SymPtr>$);
        } else if (phase == Synthesis) {
            $<IntVal>$ = $<IntVal>1; // arg count
        }
    }
    | %empty {
        if (phase == Analysis) {
            // empty params have void type data, but empty args don't
            $<SymPtr>$ = new SymbolInfo("", "argument_list", VOID_TYPE); 

            string production = "argument_list : ";
            write_log(production, $<SymPtr>$);
        } else if (phase == Synthesis) {
            $<IntVal>$ = 0;
        }
    }
    ;

arguments:
    arguments COMMA logic_expression {
        if (phase == Analysis) {
            // if logic_expression has VOID_TYPE, function call will report that error
            vector<string> arg_type_data = $<SymPtr>1->get_all_data();
            arg_type_data.push_back($<SymPtr>3->get_semantic_type());

            $<SymPtr>$ = new SymbolInfo($<SymPtr>1->get_symbol() + "," + $<SymPtr>3->get_symbol(), "arguments", VOID_TYPE, 
                arg_type_data);

            string production = "arguments : arguments COMMA logic_expression";
            write_log(production, $<SymPtr>$);
        } else if (phase == Synthesis) {
            string code = "PUSH AX";
            write_code(code, label_depth);
            $<IntVal>$ = $<IntVal>1 + 1; // return total arg count
        }
    }
    | logic_expression {
        if (phase == Analysis) {
            $<SymPtr>$ = new SymbolInfo($<SymPtr>1->get_symbol(), "arguments", VOID_TYPE, 
                {$<SymPtr>1->get_semantic_type()});

            string production = "arguments : logic_expression";
            write_log(production, $<SymPtr>$);
        } else if (phase == Synthesis) {
            string code = "PUSH AX";
            write_code(code, label_depth);
            $<IntVal>$ = 1;
        }
    }
    ;

%%

int main(int argc, char* argv[]) {
    if (argc != 2) {
        cout << "ERROR: Parser needs input file as argument\n";
        return 1;
    }

    // Analysis
    phase = Analysis;

    input_file = fopen(argv[1], "r");
    log_file.open("log.txt");
    error_file.open("error.txt");

    if (!input_file || !log_file || !error_file) {
        cerr << "ERROR: Could not open file\n";
        return 1;
    }

    yyin = input_file;
    yyparse();
    log_file << "Total lines: " << --line_count << endl;
    log_file << "Total errors: " << error_count << endl;

    log_file.close();
    error_file.close();

    if (error_count > 0) {
        error_file.open("error.txt");
        cout << error_file.rdbuf();
        error_file.close();
        cout << "COMPILATION FAILED: There are errors in your program" << endl;
        delete_debug_files();
        return 0;
    }

    delete_debug_files();

    // Synthesis
    phase = Synthesis;

    fseek(input_file, 0, SEEK_SET); // reset file cursor
    code_file.open(TEMP_CODE_FILE_NAME);

    if (!input_file || !code_file) {
        cout << "ERROR: Could not open input or code file\n";
        return 1;
    }

    symbol_table.exit_scope();
    symbol_table.enter_scope();
    current_func_sym_ptr = nullptr;

    yyin = input_file;
    yyparse();

    fclose(input_file);
    code_file.close();

    structure_main_asm_codefile();
    peephole_optimization();

    return 0;
}



/**
    Analysis utils
**/

void yyerror(char* s) {
    write_error_log(s, "SYNTAX_ERR");
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

bool insert_into_symtable(string symbol, string token_type, string semantic_type, vector<string> data) {
    if (!symbol_table.insert(symbol, token_type, semantic_type, data)) {
        write_error_log("Symbol name " + symbol + " already exists");
        return false;
    }
    return true;
}

bool insert_into_symtable(SymbolInfo* syminfo) {
    return symbol_table.insert_copy(syminfo);
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
    log_file << "Line " << to_string(line_count) << ": " << production << endl;
    log_file << matched_sym_ptr->get_symbol() << endl;
}

void write_error_log(string log_str, string tag) {
    error_count++;
    log_file << "[" << tag << "] Line " << to_string(line_count) << ": " << log_str << endl; 
    error_file << "[" << tag << "] Line " << to_string(line_count) << ": " << log_str << endl; 
}

void write_symtable_in_log(SymbolTable& symtable) {
    ostringstream osstrm;
    osstrm << symtable;
    log_file << osstrm.str() << endl;
}



/**
    Synthesis utils
**/

/**
    Generates label, with new id if label id is not provided or with provided id otherwise. 
    If new label is generated, global label_count is incremented. 

    @param Label Label type to generate
    @param label_id Label id to append after label name
    @return The label string with id appended
**/
string get_label(Label label, int label_id) {
    if (label_id < 0) {
        label_id = label_count++; // no label_id provided, generate new label_id
    }

    string label_str;
    switch(label) {
        case FOR_LOOP_CONDITION:
            label_str = "FOR_LOOP_CND_";
            break;
        case FOR_LOOP_INCREMENT:
            label_str = "FOR_LOOP_INC_";
            break;
        case FOR_LOOP_BODY:
            label_str = "FOR_LOOP_BODY_";
            break;
        case FOR_LOOP_END:
            label_str = "FOR_LOOP_END_";
            break;
        case WHILE_LOOP_CONDITION:
            label_str = "WHILE_LOOP_CND_";
            break;
        case WHILE_LOOP_BODY:
            label_str = "WHILE_LOOP_BODY_";
            break;
        case WHILE_LOOP_END:
            label_str = "WHILE_LOOP_END_";
            break;
        case ELSE_BODY:
            label_str = "ELSE_BODY_";
            break;
        case IF_ELSE_END:
            label_str = "IF_ELSE_END_";
            break;
        case CMP_TRUE:
            label_str = "CMP_TRUE_";
            break;
        case CMP_FALSE:
            label_str = "CMP_FALSE_";
            break;
        case SHORT_CIRC:
            label_str = "SHORT_CIRC_";
    }

    return label_str + to_string(label_id);
}

/**
    Resolves the identifier of a variable in assembly, based on if it's local or global and if it's an array or 
    not. 

    @param var_sym_ptr Pointer to the SymbolInfo of the variable from the symbol table whose identifier needs to be resolved.
    @return string Identifier that can be included in assembly code
**/
string _get_var_ref(SymbolInfo* var_sym_ptr) {
    string var_type = var_sym_ptr->get_semantic_type();
    CodeGenInfo* var_cgi_ptr = var_sym_ptr->get_codegen_info_ptr();
    string var_ref;
    if (var_cgi_ptr->is_local()) {
        var_ref = "BP+" + to_string(DW_SZ * var_cgi_ptr->get_stack_offset());
        if (var_type == INT_ARRAY_TYPE) {
            var_ref += "-SI"; // array index in SI from expression
        }
        var_ref = "[" + var_ref + "]";
    } else {
        var_ref = var_sym_ptr->get_symbol();
        if (var_type == INT_ARRAY_TYPE) {
            var_ref += "[SI]"; // array indec in SI from expression
        }
    }
    return var_ref;
}

/**
    @brief Returns code for popping local variables, with return using IP on stack top. 
**/
vector<string> _get_activation_record_teardown_code() {
    // return expression already in AX, don't touch AX, pop locals off stack.
    // symbol table count incudes params and local vars. params will be popped off by caller action code
    size_t local_decl_count = (-current_stack_offset) - 1;
    vector<string> code(local_decl_count, "POP BX");
    code.push_back("RET"); // will find IP on top
    return code;
}

/**
    Writes allocation asm code of int variable into code_file based on if the variable is a local or global. 
    Also inserts new symbol for the allocated variable in the symbol table.

    @param var_name name of the variable to be allocated  
**/
void _alloc_int_var(string var_name) {
    SymbolInfo* var_sym_ptr = new SymbolInfo(var_name, "ID", INT_TYPE); // can do this because that's the only type

    if (current_func_sym_ptr == nullptr) {
        // global
        string code = var_name + " DW 0";
        var_sym_ptr->get_codegen_info_ptr()->add_code(code);
        // write data segment code at the end
        globals.push_back(new SymbolInfo(*var_sym_ptr)); // .clear() calls delete
    } else {
        // local
        vector<string> code{
            "; INITIALIZING BASIC VARIABLE " + var_name + " at stack offset " + to_string(current_stack_offset), 
            "PUSH 0"
        };
        var_sym_ptr->get_codegen_info_ptr()->set_is_local(true);
        var_sym_ptr->get_codegen_info_ptr()->set_stack_offset(current_stack_offset--); // stack grows downward
        write_code(code, label_depth);
    }
    insert_into_symtable(var_sym_ptr);
    delete var_sym_ptr;
}

/**
    Writes allocation asm code of int array into code_file based on if the array is a local or global. 
    Also inserts new symbol for the allocated array in the symbol table.

    @param arr_name name of the array to be allocated  
    @param arr_size size of the array
**/
void _alloc_int_array(string arr_name, int arr_size) {
    string arr_sz_str = to_string(arr_size);
    SymbolInfo* arr_sym_ptr = new SymbolInfo(arr_name, "ID", INT_ARRAY_TYPE, { arr_sz_str });

    if (current_func_sym_ptr == nullptr) {
        // global
        string code = arr_name + " DW " + arr_sz_str + " DUP(0)";
        arr_sym_ptr->get_codegen_info_ptr()->add_code(code);
        globals.push_back(new SymbolInfo(*arr_sym_ptr));
    } else {
        // local
        vector<string> code(arr_size, "PUSH 0");
        code.insert(code.begin(), "; INTIALIZING ARRAY VARIABLE " + arr_name + "[" + arr_sz_str + "]" + 
            " at stack offset " + to_string(current_stack_offset));
        arr_sym_ptr->get_codegen_info_ptr()->set_is_local(true);
        arr_sym_ptr->get_codegen_info_ptr()->set_stack_offset(current_stack_offset);
        current_stack_offset -= arr_size; // stack grows downward
        write_code(code, label_depth);
    }

    insert_into_symtable(arr_sym_ptr);
    delete arr_sym_ptr;
}

void write_code(const string& code, int indentation) {
    string indent = "";
    for (int i = 0; i < indentation; i++) {
        indent += "\t";
    }
    code_file << indent << code << endl;
}

void write_code(const vector<string>& code, int indentation) {
    for (string code_line : code) {
        write_code(code_line, indentation);
    }
}

void structure_main_asm_codefile() {
    // open actual code file for writing
    code_file.open(CODE_FILE_NAME);

    if (!code_file) {
        cerr << "Error: Could not open code file to write data segment" << endl;
        return;
    }

    // write data segment on new code file
    write_code(".MODEL SMALL");
    write_code(".STACK 300H");
    write_code(".DATA");
    vector<string> code;
    for (SymbolInfo* global_sym_ptr : globals) {
        code.push_back(global_sym_ptr->get_codegen_info_ptr()->get_all_code()[0]);
    }
    write_code(code, 1);
    globals.clear();

    // write __main__ function
    code.clear();
    code.insert(code.end(), {
        ".CODE", 
        "MAIN PROC" 
    });
    write_code(code);
    code.clear();
    code.insert(code.end(), {
        "MOV AX, @DATA", 
        "MOV DS, AX", 
        "MOV BP, SP",
        "CALL " + SOURCE_MAIN_FUNC_NAME, 
        "MOV AH, 4CH", 
        "INT 21H", // end prog
    });
    write_code(code, 1);
    write_code("ENDP MAIN");

    // append old code file to new code file
    ifstream temp_code_file(TEMP_CODE_FILE_NAME);
    if (temp_code_file.good()) {
        copy_txt_file(temp_code_file, code_file);
    } else {
        cerr << "Error: Could not copy temp code file" << endl;
        return;
    }

    write_code("END MAIN");

    // delete old code file
    temp_code_file.close();
    if (remove(TEMP_CODE_FILE_NAME.c_str()) != 0) {
        cerr << "Error: Could not delete temp code file" << endl;
    }
}

void append_print_proc_def_to_codefile() {
    write_code("PRINT_INT_IN_AX PROC");
    // divide and push the remainder
    vector<string> code{
        "MOV CX, 0",
        "TEST AX, AX",
        "JNS POSITIVE_NUM",
        "MOV BX, 1",
        "NEG AX",
        "JMP OUTPUT_STACK_START",

        "POSITIVE_NUM:",
        "MOV BX, 0",
        
        "OUTPUT_STACK_START:",
        "INC CX",
        "PUSH CX",
        "MOV CX, 10",
        "MOV DX, 0",
        "DIV CX",
        "POP CX",
        "PUSH DX",
        "CMP AX, 0",
        "JNE OUTPUT_STACK_START",
        "CMP BX, 1",
        "JNE STACK_PRINT_LOOP",
        "MOV DX, -3",
        "PUSH DX",
        "INC CX",
        
        "STACK_PRINT_LOOP:",
        "POP DX",
        "ADD DL, '0'",
        "MOV AH, 2",
        "INT 21H", 
        "LOOP STACK_PRINT_LOOP",
        
        "MOV DL, 10", 
        "MOV AH, 2",
        "INT 21H",
        "MOV DL, 13", 
        "MOV AH, 2",
        "INT 21H",

        "RET"    
    };
    write_code(code, 1);
    write_code("ENDP");
}



/**
    Optimization utils
**/

void peephole_optimization() {
    vector<string> all_code = load_code_into_mem();

    // do optim
    do_peephole(all_code);

    write_optimized_code_to_file(all_code);
}

void do_peephole(vector<string>& all_code) {
    bool skip_mode = false;
    string curr_line, prev_line = all_code[0];

    for (int i = 1, prev_idx = 0; i < all_code.size(); i++) {
        if (all_code[i].find(";") != string::npos) {
            continue;
        }

        curr_line = all_code[i];
        prev_line = all_code[prev_idx];
        trim(curr_line); // preserving original indentation on all_code
        trim(prev_line);

        if (starts_with("JMP", curr_line) || starts_with("RET", curr_line)) {
            // skip until next label, or end of function
            i++;
            while (
                (all_code[i].find(':') == string::npos) &&
                (all_code[i].find("ENDP") == string::npos)
            ) {
                all_code[i] = "; PEEPHOLE " + all_code[i];
                i++;
            }
        } else if (starts_with("MOV", curr_line) && starts_with("MOV", prev_line)) {
            curr_line.erase(0, 4); // removing "MOV "
            vector<string> curr_line_regs = split_str(curr_line, ", ");

            prev_line.erase(0, 4); 
            vector<string> prev_line_regs = split_str(prev_line, ", ");
            
            if (curr_line_regs[0] == prev_line_regs[1] && curr_line_regs[1] == prev_line_regs[0]) {
                all_code[i] = "; PEEPHOLE " + all_code[i];
            }
        } else if (starts_with("ADD", curr_line)) {
            curr_line.erase(0, 4); // removing "ADD "
            vector<string> operands = split_str(curr_line, ", ");
            if (operands[1] == "0") {
                all_code[i] = "; PEEPHOLE " + all_code[i];
            }
        } else if (starts_with("PUSH", curr_line) && starts_with("POP", prev_line)) {
            prev_line.erase(0, 4); // removing "POP "
            curr_line.erase(0, 5); // removing "PUSH "
            
            if (curr_line == prev_line) {
                all_code[prev_idx] = "; PEEPHOLE" + all_code[prev_idx];
                all_code[i] = "; PEEPHOLE" + all_code[i];
            }
        } else if (starts_with("POP", curr_line) && starts_with("PUSH", prev_line)) {
            prev_line.erase(0, 5); // removing "PUSH "
            curr_line.erase(0, 4); // removing "POP "
            
            if (curr_line == prev_line) {
                all_code[prev_idx] = "; PEEPHOLE" + all_code[prev_idx];
                all_code[i] = "; PEEPHOLE" + all_code[i];
            }
        }

        prev_idx = i;
    }
}

void write_optimized_code_to_file(vector<string>& all_code) {
    ofstream optim_code_file(OPTIM_CODE_FILE_NAME);
    if (!optim_code_file) {
        cerr << "Could not open optimized code file\n";
        return;
    }

    for (string& line : all_code) {
        optim_code_file << line << endl;
    }
    optim_code_file.close();
}

vector<string> load_code_into_mem() {
    vector<string> all_code;
    ifstream code_file(CODE_FILE_NAME);
    string line;
    if (code_file.good()) {
        while (getline(code_file, line)) {
            all_code.push_back(line);
        }
    } else {
        cerr << "Could not open code file to load into memory for optimization\n";
    }
    code_file.close();
    return all_code;
}



/** 
    General utils
**/

string vec_to_str(vector<string> strings) {
    stringstream ss;
    for (string str : strings) {
        ss << str << " ";
    }
    return ss.str();
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

bool starts_with(const string& start, const string& subject) {
    return subject.find(start) == 0;
}

vector<string> split_str(const string str, const string delim) {
    vector<string> split;
    int str_start = 0;
    for (int delim_pos = str.find(delim); delim_pos != string::npos; delim_pos = str.find(delim, str_start)) {
        split.push_back(str.substr(str_start, delim_pos - str_start));
        str_start = delim_pos + delim.length();
    }
    if (str_start < str.size()) {
        split.push_back(str.substr(str_start));
    }
    return split;
}

void replace_substr(string& subject, const string target, const string replacement) {
    size_t pos = 0;
    while ((pos = subject.find(target, pos)) != string::npos) {
        subject.replace(pos, target.length(), replacement);
        pos += replacement.length();
    }
}

void trim(string& str) {
    string ws = " \t";
    str.erase(0, str.find_first_not_of(ws));
    str.erase(str.find_last_not_of(ws) + 1);
}

void copy_txt_file(ifstream& from_file, ofstream& to_file) {
    string line;
    while (getline(from_file, line)) {
        to_file << line << endl;
    }
}

void delete_debug_files() {
    if (remove("error.txt") != 0 || remove("log.txt") != 0) {
        cerr << "Error: Could not delete debug files" << endl;
    }   
}