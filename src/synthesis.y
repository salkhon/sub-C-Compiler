%{
    #include <iostream>
    #include <fstream>
    #include <cstdlib>
    #include <cstdio>
    #include <cstring>
    #include <string>
    #include <sstream>
    #include <vector>
    #include <algorithm>
    #include <stack>
    #include "./symbol-table/include.hpp"

    using namespace std;

    extern FILE* yyin;
    extern int line_count;

    int yyparse();
    int yylex();
    extern int yyerror(char*);

    const string TEMP_CODE_FILE_NAME = "_code.asm", CODE_FILE_NAME = "../code.asm", 
        OPTIM_CODE_FILE_NAME = "../optimized_code.asm";
    const string SOURCE_MAIN_FUNC_NAME = "__main__";
    
    FILE* input_file;
    ofstream code_file;

    const int SYM_TABLE_BUCKETS = 10;

    // only needed for code generation, referring to local variables with corresponding offset assigned
    SymbolTable symbol_table(SYM_TABLE_BUCKETS);

    const string INT_TYPE = "int";
    const string INT_ARRAY_TYPE = "int_arr";
    const string VOID_TYPE = "void";

    const int DW_SZ = 2;

    vector<SymbolInfo*> globals;

    SymbolInfo* current_func_sym_ptr = nullptr;
    vector<SymbolInfo*> params_for_func_scope;
    int current_stack_offset;

    // number of label-requiring-statements encountered
    int label_count = 0;
    // depth of nested label-requiring-statements
    int label_depth = 0;

    enum Label {
        FOR_LOOP_CONDITION, FOR_LOOP_INCREMENT, FOR_LOOP_BODY, FOR_LOOP_END, WHILE_LOOP_CONDITION, 
        WHILE_LOOP_BODY, WHILE_LOOP_END, ELSE_BODY, IF_ELSE_END, CMP_TRUE, CMP_FALSE, SHORT_CIRC
    };

    vector<string> split(string, char = ' ');
    string get_label(Label, int=-1);
    string _get_var_ref(SymbolInfo*);
    vector<string> _get_activation_record_teardown_code();
    void _alloc_int_var(string);
    void _alloc_int_array(string, int);
    bool is_sym_func(SymbolInfo*);
    string vec_to_str(vector<string>);
    bool insert_into_symtable(string, string, string, vector<string> = {});
    bool insert_into_symtable(SymbolInfo*);
    void write_code(const string&, int=0);
    void write_code(const vector<string>&, int=0);
    void append_print_proc_def_to_codefile();
    void prepend_data_segment_to_codefile();
    void copy_txt_file(ifstream& from_file, ofstream& to_file);

    void peephole_optimization();
    void do_peephole(vector<string>&);
    void write_optimized_code_to_file(vector<string>&);
    bool starts_with(const string&, const string&);
    vector<string> split_str(const string, const string);
    void replace_substr(string&, const string, const string);
    void trim(string&);
    void copy_txt_file(ifstream&, ofstream&);
    vector<string> load_code_into_mem();
%}

%union {
    SymbolInfo* syminfo_ptr;
    // int will be used to keep track of labeled statements' opening and closing label in between nested statements
    int int_val;
}

%token
    LPAREN RPAREN SEMICOLON COMMA LCURL RCURL INT VOID LTHIRD RTHIRD FOR IF ELSE WHILE
    PRINTLN RETURN ASSIGNOP NOT INCOP DECOP

%token<syminfo_ptr>
    ID CONST_INT LOGICOP RELOP ADDOP MULOP

%type
    start program unit var_declaration func_declaration func_definition statements parameter_list
    declaration_list statement expression_statement expression compound_statement rel_expression 
    simple_expression term unary_expression factor func_signature

%type<int_val>
    logic_expression if_condition argument_list arguments

%type<syminfo_ptr>
    type_specifier variable

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

// ELSE has higher precedence than dummy token SHIFT_ELSE (telling to shift ELSE, rather than reduce lone if)
%nonassoc SHIFT_ELSE
%nonassoc ELSE

%%

start: 
    program {
        append_print_proc_def_to_codefile();
        YYACCEPT;
        // temp code file does not have data segment yet, final code with data segment, will be generated after parsing
    }
    ;

program: 
    program unit {}   
    | unit {}
    ;

unit:
    var_declaration {}
    | func_declaration {}
    | func_definition {
        write_code("");
    }
    ;

/**
    A -> B {} C {}
    Midrule semantic actions are rewritten as:
    T -> %empty {}
    A -> B T C {}
    Which means the action code of T -> %empty {} will execute before A -> B T C {} is executed. 
    It simulates inheritted attribute semantic actions. 
    Practically it just breaks the production into two separate productions. 
**/

/**
    Func declarations are used for type analysis. But for code generation they are useless. Because in an error 
    free code, you can allocate function frame from the number of arguments. Plus their is only one type INT. 
    So args are PUSHED arg_size times. So no need to insert function symbols into symbol table. 
**/
func_declaration: 
    func_signature SEMICOLON {
        delete current_func_sym_ptr;
        current_func_sym_ptr = nullptr;
        params_for_func_scope.clear();
    }
    ;

/**
    function call needs to push base pointer, and pop and set base pointer on return. 
    Doing this on stack enables recursive calls. 
    current_stack_pointer needn't be modified, because that's only relevant for code generation.
**/
func_definition:
    func_signature LCURL {
        // symbol table insertions of parameters in new scope, var names are not available in calling sequence
        // new BP is set at the top of func def. args were pushed before that BP. So, param offsets need to be positive, 
        // if local offsets are negative. args are pushed from first to last, so offset will go from positive toward zero. 
        current_stack_offset = params_for_func_scope.size(); // offset 0 is for return IP, paramsize+1 is for old BP. 
        symbol_table.enter_scope();
        for (SymbolInfo* param_symbol : params_for_func_scope) {
            // base pointer is reset on on every call, so identifying local vars based on offset works
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
    } statements RCURL {
        if (current_func_sym_ptr->get_semantic_type() == VOID_TYPE) {
            // void functions can end without explicit return statement
            vector<string> code = _get_activation_record_teardown_code();
            write_code(code, label_depth);
        }

        write_code("ENDP", --label_depth);

        delete current_func_sym_ptr;
        current_func_sym_ptr = nullptr;
        params_for_func_scope.clear();
        symbol_table.exit_scope();
    }
    ;

func_signature:
    type_specifier ID LPAREN {
        string ret_type = $1->get_symbol();
        string func_name = $2->get_symbol();

        current_func_sym_ptr = new SymbolInfo(func_name, "ID", ret_type);
    } parameter_list RPAREN {}
    ;

parameter_list:
    parameter_list COMMA type_specifier ID {
        string param_type = $3->get_symbol();
        string param_name = $4->get_symbol();
        current_func_sym_ptr->add_data(param_type);
        
        params_for_func_scope.push_back(new SymbolInfo(param_name, "ID", param_type)); // .clear() calls delete
    }
    | parameter_list COMMA type_specifier {
        delete $3;
    }
    | type_specifier ID {
        string param_type = $1->get_symbol();
        string param_name = $2->get_symbol();
        current_func_sym_ptr->add_data(param_type);
        
        params_for_func_scope.push_back(new SymbolInfo(param_name, "ID", param_type));
    }
    | type_specifier {
        delete $1;
    }
    | %empty {
        // empty param list will be added VOID_TYPE in function_signture
        current_func_sym_ptr->add_data(VOID_TYPE);
    }
    ;

compound_statement:
    LCURL {
        // this is nested scope
        // no conflict with func_def because closure includes compound statement only after encountering statement non terminal.
        symbol_table.enter_scope();
    } statements RCURL {
        symbol_table.exit_scope();
    }
    | LCURL RCURL {
    }
    ;

/**
    LCURL can mean 2 things. Start of a function, or a nested scope. If it's a functions, current_func_sym_ptr
    will have function signature. If so, write PROC code. 
    If it's just a nested scope, no new frame. Means no new base ptr. We can use the old stack offset. Just create
    new scope to refer to actual variables with proper offset. And the ability to declare same named variables as
    the outer scope. 
    To solve this, separate out nested scope and func_def in the grammar.
**/

var_declaration:
    type_specifier declaration_list SEMICOLON {
        delete $1;
    }
    ;

type_specifier:
    INT {
        // necessary for instantiating current_func_sym_ptr in func_signature
        $$ = new SymbolInfo(INT_TYPE, INT_TYPE);
    }
    | VOID {
        $$ = new SymbolInfo(VOID_TYPE, VOID_TYPE);
    }
    ;

declaration_list:
    declaration_list COMMA ID {
        _alloc_int_var($3->get_symbol());
    }
    | declaration_list COMMA ID LTHIRD CONST_INT RTHIRD {
        _alloc_int_array($3->get_symbol(), stoi($5->get_symbol()));
    }
    | ID {
        _alloc_int_var($1->get_symbol());
    }
    | ID LTHIRD CONST_INT RTHIRD {
        _alloc_int_array($1->get_symbol(), stoi($3->get_symbol()));
    }
    ;

statements:
    statement {}
    | statements statement {}
    ;

/**
    Surprisingly, this if-else grammar automatically covers if-elseif ladder. Because if-elseif ladders
    can be broken down to nested if-else s.
        if (A) {

        } else if (B) {

        } else if (C) {

        } else {

        }
    To, 
        if (A) {

        } else {
            if (B) {

            } else {
                if (C) {

                } else {

                }
            }
        }
    If one of the if condition enters, no else-ifs enter. Amazing. 
**/
statement:
    var_declaration {}
    | expression_statement {}
    | compound_statement {}
    | FOR LPAREN expression_statement {
        // expression code written, value stored on AX (assignment mostly)
        // need label to comeback to following condition checking expression
        vector<string> code{
            "; FOR LOOP START", 
            get_label(FOR_LOOP_CONDITION) + ":"
        };
        // $S will be used as a label identifier, so we can label corresponding opening and closing labels with same id
        write_code(code, label_depth);

        $<int_val>$ = label_count - 1; 
    } expression_statement {
        // conditional statement value in AX, code written
        const int CURR_LABEL_ID = $<int_val>4;
        vector<string> code{
            "; FOR LOOP CONDITION CHECK",
            "CMP AX, 0", 
            "JNE " + get_label(FOR_LOOP_BODY, CURR_LABEL_ID), 
            "JMP " + get_label(FOR_LOOP_END, CURR_LABEL_ID),
            get_label(FOR_LOOP_INCREMENT, CURR_LABEL_ID) + ":"
        };
        write_code(code, label_depth);

        $<int_val>$ = $<int_val>4;
    } expression RPAREN {
        // expression val in AX, mostly assignment
        const int CURR_LABEL_ID = $<int_val>6;
        vector<string> code{
            "JMP " + get_label(FOR_LOOP_CONDITION, CURR_LABEL_ID),
            get_label(FOR_LOOP_BODY, CURR_LABEL_ID) + ":"
        };
        write_code(code, label_depth++);

        $<int_val>$ = $<int_val>6;
    } statement {
        const int CURR_LABEL_ID = $<int_val>9;
        vector<string> code{
            "JMP " + get_label(FOR_LOOP_INCREMENT, CURR_LABEL_ID), 
            get_label(FOR_LOOP_END, CURR_LABEL_ID) + ":"
        };
        write_code(code, --label_depth);
    }
    | if_condition statement 
    %prec SHIFT_ELSE {
        const int CURR_LABEL_ID = $<int_val>1;
        vector<string> code{
            get_label(ELSE_BODY, CURR_LABEL_ID) + ":", // if_condition always assumes if-else, so dummy else label
            get_label(IF_ELSE_END, CURR_LABEL_ID) + ":"
        };
        write_code(code, --label_depth);
    } 
    | if_condition statement ELSE {
        const int CURR_LABEL_ID = $<int_val>1;
        vector<string> code{
            "JMP " + get_label(IF_ELSE_END, CURR_LABEL_ID), // if body execution ends in jumping over else body
            get_label(ELSE_BODY, CURR_LABEL_ID) + ":"
        };
        write_code(code, label_depth-1);

        $<int_val>$ = $<int_val>1;
    } statement {
        const int CURR_LABEL_ID = $<int_val>4;
        string code = get_label(IF_ELSE_END, CURR_LABEL_ID) + ":";
        write_code(code, --label_depth);
    }
    | WHILE LPAREN {
        vector<string> code{
            "; WHILE LOOP START",
            get_label(WHILE_LOOP_CONDITION) + ":"
        };
        write_code(code, label_depth);

        $<int_val>$ = label_count - 1;
    } expression RPAREN {
        const int CURR_LABEL_ID = $<int_val>3;
        vector<string> code{
            "; WHILE LOOP CONDITION CHECK",
            "CMP AX, 0", 
            "JNE " + get_label(WHILE_LOOP_BODY, CURR_LABEL_ID), 
            "JMP " + get_label(WHILE_LOOP_END, CURR_LABEL_ID), 
            get_label(WHILE_LOOP_BODY, CURR_LABEL_ID) + ":"
        };
        write_code(code, label_depth++);

        $<int_val>$ = $<int_val>3;
    } statement {
        const int CURR_LABEL_ID = $<int_val>6;
        vector<string> code{
            "JMP " + get_label(WHILE_LOOP_CONDITION, CURR_LABEL_ID), 
            get_label(WHILE_LOOP_END, CURR_LABEL_ID) + ":"
        };
        write_code(code, --label_depth);
    }
    | PRINTLN LPAREN variable RPAREN SEMICOLON {
        SymbolInfo* var_sym = symbol_table.lookup($3->get_symbol());
        string var_ref = _get_var_ref(var_sym);
        vector<string> code{
            "; PRINT STATEMENT VAR " + var_sym->get_symbol(), 
            "MOV AX, " + var_ref, 
            "CALL PRINT_INT_IN_AX"
        };
        write_code(code, label_depth);
    }
    | RETURN expression SEMICOLON {
        vector<string> code = _get_activation_record_teardown_code();
        // everything on the current scope is a parameter or a local, just pop x sizeof currentscope
        write_code(code, label_depth);
    }
    ;

if_condition:
    IF LPAREN expression RPAREN {
        // if_condition assumes if-else. If condition is false, jump to ELSE_BODY label, which will exist for
        // if without else as a dummy. 
        vector<string> code{
            "; IF STATEMENT START",
            "CMP AX, 0", 
            "JE " + get_label(ELSE_BODY)
        };
        write_code(code, label_depth++);

        $<int_val>$ = label_count - 1;
    }

expression_statement:
    SEMICOLON {}
    | expression SEMICOLON {}
    ;

/**
    variable can be global or local. Global is stored by name, can be called in x86 by name. Local has to 
    be popped from the stack. So the stack offset would be it's identifier. 
    If its local, put stack offset in x86, if its global put name in x86. 
**/
/**
    expression value cannot be evaluated in compile time.
    expression code needs to store result in AX. Since we know the latest expression value is in AX, 
    if we need to store 2 expressions, we can just add a midrule code in the earlier expression to push
    the AX val to stack.  
    If you find variable from symbol table is an array, you can find it's index expression at AX. 
**/
variable:
    ID {
        // can be l value or r value - so not resolving now, just inheritting symbol name to find in sym table.
        $$ = $1;
    }
    | ID LTHIRD expression RTHIRD {
        // expression value on AX, since its an index, move it to SI, in word size
        vector<string> code{
            "MOV BX, " + to_string(DW_SZ),
            "MUL BX",
            "MOV SI, AX" 
        };
        write_code(code, 1);
        $$ = new SymbolInfo(*$1); 
    }
    ;

expression:
    logic_expression {}   
    | variable ASSIGNOP logic_expression {
        // variable can be an array, if so, index is in SI.
        SymbolInfo* var_sym_ptr = symbol_table.lookup($1->get_symbol());
        string var_ref = _get_var_ref(var_sym_ptr);
        string code = "MOV " + var_ref + ", AX";
        write_code(code, label_depth);
    }
    ;

logic_expression:
    rel_expression {}
    | rel_expression LOGICOP {
        // make expression value persist
        // AFTER EACH EXPRESSION part, STACK NEEDS TO BE AS IT WAS BEFORE. That way current_stack_offset needn't be changed
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

        $<int_val>$ = label_count - 1;
    } rel_expression {
        vector<string> code{
            "MOV BX, AX", 
            "POP AX"
        };
        if ($2->get_symbol() == "&&") {
            code.push_back("AND AX, BX");
        } else if ($2->get_symbol() == "||") {
            code.push_back("OR AX, BX");
        }
        code.push_back(get_label(SHORT_CIRC, $<int_val>3) + ":");
        write_code(code, label_depth);
    }
    ;

rel_expression:
    simple_expression {}
    | simple_expression {
        vector<string> code{
            "; COMPARISON START",
            "PUSH AX"
        };
        write_code(code, label_depth);
    } RELOP simple_expression {
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
    ;

simple_expression:
    term {}
    | simple_expression {
        string code = "PUSH AX";
        write_code(code, label_depth);
    } ADDOP term {
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
    ;

term:
    unary_expression {}
    | term {
        string code = "PUSH AX";
        write_code(code, 1);
    } MULOP unary_expression {
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
    ;

unary_expression:
    ADDOP unary_expression 
    %prec UNARY {
        string addop = $1->get_symbol();
        if (addop == "-") {
            string code = "NEG AX";
            write_code(code, label_depth);
        }
    }
    | NOT unary_expression {
        vector<string> code = {
            "CMP AX, 0",
            "MOV AX, 0", 
            "SETE AL"
        };
        write_code(code, 1);
    }
    | factor {}
    ;

factor:
    variable {
        // when variable reduces to factor, it's symbol table info is no longer needed, just the value on AX. 
        SymbolInfo* var_sym_ptr = symbol_table.lookup($1->get_symbol());
        string var_ref = _get_var_ref(var_sym_ptr);
        string code = "MOV AX, " + var_ref;
        write_code(code, label_depth);
    }
    | ID LPAREN {
        // the definition code for the procedure we are calling is independent, written with its own current_stack_offset, 
        string func_name = $1->get_symbol();
        vector<string> code{
            "; ACTIVATION RECORD SETUP FOR FUNCTION " + func_name,
            "PUSH BP", 
        };
        write_code(code, label_depth);
    } argument_list RPAREN {
        string func_name = $1->get_symbol();
        size_t arg_count = $4;
        vector<string> code(arg_count, "POP BX"); // pop args
        code.insert(code.begin(), "CALL " + func_name);
        code.insert(code.end(), {
            "POP BP", // restore old BP
            "; EXECUTION COMPLETE FOR FUNCTION " + func_name
        });
        write_code(code, label_depth);
    }
    | LPAREN expression RPAREN {}
    | CONST_INT {
        string code = "MOV AX, " + $1->get_symbol();
        write_code(code, label_depth);
    }
    | variable INCOP {
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
    | variable DECOP {
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
    ;

argument_list:
    arguments {
        $$ = $1; // arg count
    }
    | %empty {
        $$ = 0;
    }
    ;

arguments:
    arguments COMMA logic_expression {
        string code = "PUSH AX";
        write_code(code, label_depth);
        $$ = $1 + 1; // return total arg count
    }
    | logic_expression {
        string code = "PUSH AX";
        write_code(code, label_depth);
        $$ = 1;
    }
    ;

%%

int main(int argc, char* argv[]) {
    if (argc != 2) {
        cout << "ERROR: Code generator needs input file as argument\n";
        return 1;
    }

    input_file = fopen(argv[1], "r");
    code_file.open(TEMP_CODE_FILE_NAME);

    if (!input_file || !code_file) {
        cout << "ERROR: Could not open input or code file\n";
        return 1;
    }

    yyin = input_file;

    yyparse();

    fclose(input_file);
    code_file.close();

    prepend_data_segment_to_codefile();
    peephole_optimization();

    return 0;
}

/**
    utils
**/

vector<string> split(string str, char delim) {
    stringstream sstrm(str);
    string split_str;
    vector<string> split_strs;

    while (getline(sstrm, split_str, delim)) {
        split_strs.push_back(split_str);    
    }

    return split_strs; 
}

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

bool is_sym_func(SymbolInfo* syminfo) {
    return !syminfo->get_all_data().empty();
}

string vec_to_str(vector<string> strings) {
    stringstream ss;
    for (string str : strings) {
        ss << str << " ";
    }
    return ss.str();
}

bool insert_into_symtable(string symbol, string token_type, string semantic_type, vector<string> data) {
    return symbol_table.insert(symbol, token_type, semantic_type, data);
}

bool insert_into_symtable(SymbolInfo* syminfo) {
    return symbol_table.insert_copy(syminfo);
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

void prepend_data_segment_to_codefile() {
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
    Peephole Optimization
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

        /* cout << i << " - " << prev_line << " - " << curr_line << endl; */

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
    x86 assembly instructions: http://www.mathemainzel.info/files/x86asmref.html#idiv
    x86 assembly registers: https://www.eecg.utoronto.ca/~amza/www.mindsec.com/files/x86regs.html#:~:text=The%20main%20tools%20to%20write,the%20process%20faster%20and%20cleaner.
**/