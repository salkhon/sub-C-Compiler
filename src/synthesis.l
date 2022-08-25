%option noyywrap
%option noinput
%option nounput

%{
    #include <iostream>
    #include <sstream>
    #include <string>
    #include <cctype>
    #include <stdlib.h>
    #include <cstring>
    #include "./symbol-table/include.hpp"
    #include "synthesis.tab.h"

    using namespace std;

    void yyerror(char*) {}
    
    // counts
    int line_count = 1;
    int pending_line_inc = 0;
%}


IF_KW if
FOR_KW for
INT_KW int
VOID_KW void
ELSE_KW else
WHILE_KW while
RETURN_KW return

WHITESPACE [ \t]*

DIGIT [0-9]
DIGITS {DIGIT}+
INTNUM {DIGITS}

NEWLINE \n

ADDOP "+"|"-"
MULOP [\*\/%]
INCOP "++"
DECOP "--"
RELOP <|<=|>|>=|==|!=
ASSIGNOP =
LOGICOP &&|"||"
NOT !
LPAREN "("
RPAREN ")"
LCURL "{"
RCURL "}"
LTHIRD "["
RTHIRD "]"
COMMA ","
SEMICOLON ";"
PRINTLN "println"|"printf"

ALPHABET [a-zA-Z]

ID ({ALPHABET}|_)({ALPHABET}|{DIGIT}|_)*

%%

{IF_KW} {
    return IF;
}

{FOR_KW} {
    return FOR;
}

{INT_KW} {
    return INT; 
}

{VOID_KW} {
    return VOID;
}

{ELSE_KW} {
    return ELSE; 
}

{WHILE_KW} {
    return WHILE;
}

{RETURN_KW} {
    return RETURN;
}


{WHITESPACE} {

}


{INTNUM} {
    string symbol = yytext;
    string token_type = "CONST_INT";

    yylval.syminfo_ptr = new SymbolInfo(symbol, token_type);

    return CONST_INT;
}

{ADDOP} {
    string symbol = string(yytext);
    string token_type = "ADDOP";

    yylval.syminfo_ptr = new SymbolInfo(symbol, token_type);

    return ADDOP;
}

{MULOP} {
    string symbol = string(yytext);
    string token_type = "MULOP";

    yylval.syminfo_ptr = new SymbolInfo(symbol, token_type);

    return MULOP;
}

{INCOP} {
    return INCOP;
}

{DECOP} {
    return DECOP;
}

{RELOP} {
    string symbol = string(yytext);
    string token_type = "RELOP";

    yylval.syminfo_ptr = new SymbolInfo(symbol, token_type);

    return RELOP;
}

{ASSIGNOP} {
    return ASSIGNOP;
}

{LOGICOP} {
    string symbol = string(yytext);
    string token_type = "LOGICOP";

    yylval.syminfo_ptr = new SymbolInfo(symbol, token_type);

    return LOGICOP;
}

{NOT} {
    return NOT;
}

{LPAREN} {
    return LPAREN;
}

{RPAREN} {
    return RPAREN;
}

{LCURL} {
    return LCURL;
}

{RCURL} {
    return RCURL;
}

{LTHIRD} {
    return LTHIRD;
}

{RTHIRD} {
    return RTHIRD;
}

{COMMA} {
    return COMMA;
}

{SEMICOLON} {
    return SEMICOLON;
}

{PRINTLN} {
    return PRINTLN;
}

{ID} {
    string symbol = string(yytext);
    string token_type = "ID";

    yylval.syminfo_ptr = new SymbolInfo(symbol, token_type);

    return ID;
}

{NEWLINE} {
    line_count++;
}

%%