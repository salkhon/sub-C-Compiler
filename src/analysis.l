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
    #include "analysis.tab.h"

    using namespace std;

    void yyerror(char*);
    
    // counts
    int line_count = 1;
    int pending_line_inc = 0;
    extern int error_count;

    // buffer
    string matched_literal;

    char matched_char;
    string matched_str;
    string matched_comment;

    extern void write_error_log(string, string="ERROR");

    void write_log_lex(string, string, string);
    void write_token_and_log_lex(string, string, string);
    void write_error_log_lex(string, string lexeme = "");
    void write_symtable_in_log_lex(SymbolTable& symtable);
%}


%x BLOCK_COMMENT
%x LINE_COMMENT
%x CHAR
%x ERR_MULTIPLE_CHAR
%x STRING

UNRECOGNIZED_CHARSET [^a-zA-Z0-9\a\b\f\n\r\t\v\0!\*%&\(\)\[\]\{\}<>\+=_\-\|\\;'\",\.~ ]

IF_KW if
FOR_KW for
INT_KW int
FLOAT_KW float
VOID_KW void
ELSE_KW else
WHILE_KW while
RETURN_KW return

WHITESPACE [ \t]*

DIGIT [0-9]
DIGITS {DIGIT}+
INTNUM {DIGITS}
FLOATNUM {INTNUM}?\.{DIGITS}
EXPNUM ({INTNUM}|{FLOATNUM})[eE]{INTNUM}

ALERT \a
ALERT_LIT \\a
BACKSPACE \b
BACKSPACE_LIT \\b
FORMFEED \f
FORMFEED_LIT \\f
NEWLINE \n
NEWLINE_LIT \\n
CR_LIT \\r
TAB \t
TAB_LIT \\t
VERTICALTAB \v
VERTICALTAB_LIT \\v
NULLCHAR \0
NULLCHAR_LIT \\0
BACKSLASH \\
SINGLEQUOTES \'
DOUBLEQUOTES \"

ESCAPED_CHARS_SPECIAL_EXCEPT_NL {ALERT}|{BACKSPACE}|{FORMFEED}|{TAB}|{VERTICALTAB}|{NULLCHAR}

SINGLECHAR_LIT [ -~]{-}[\a\b\f\n\r\t\v\0]
ANY_ESCAPED_CHAR_LIT \\.

DOUBLEFORWARDSLASH \/\/ 


ESCAPED_LINE_BREAK {BACKSLASH}{NEWLINE}

ADDOP "+"|"-"
MULOP [\*\/%]
INCOP "++"
DECOP "--"
RELOP <|<=|>|>=|==|!=
ASSIGNOP =
LOGICOP &&|"||"
NOT !|~
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

BLOCK_COMMENT_START \/\*
BLOCK_COMMENT_END \*\/

STRING_NORMAL_CHAR [^\\\n\"]
LINE_COMMENT_NORMAL_CHAR [^\n]

ERR_TOO_MANY_DECIMAL ({DIGITS}?\.{DIGITS}?){2,}
ERR_ILL_FORMED_NUM {EXPNUM}\.{DIGITS}?
ERR_INVALID_SUFF_PREF {DIGITS}{ID}

%%

{UNRECOGNIZED_CHARSET} {
    write_error_log_lex("Unrecognized character", string(yytext));
}

{IF_KW} {
    string symbol = yytext;
    string token_type = "IF";
    write_token_and_log_lex(token_type, symbol, string(yytext));

    return IF;
}

{FOR_KW} {
    string symbol = yytext;
    string token_type = "FOR";
    write_token_and_log_lex(token_type, symbol, string(yytext));

    return FOR;
}

{INT_KW} {
    string symbol = yytext;
    string token_type = "INT";
    write_token_and_log_lex(token_type, symbol, string(yytext));

    return INT; 
}

{FLOAT_KW} {
    string symbol = yytext;
    string token_type = "FLOAT";
    write_token_and_log_lex(token_type, symbol, string(yytext));

    return FLOAT; 
}

{VOID_KW} {
    string symbol = yytext;
    string token_type = "VOID";
    write_token_and_log_lex(token_type, symbol, string(yytext));

    return VOID;
}

{ELSE_KW} {
    string symbol = yytext;
    string token_type = "ELSE";
    write_token_and_log_lex(token_type, symbol, string(yytext));

    return ELSE; 
}

{WHILE_KW} {
    string symbol = yytext;
    string token_type = "WHILE";
    write_token_and_log_lex(token_type, symbol, string(yytext));

    return WHILE;
}

{RETURN_KW} {
    string symbol = yytext;
    string token_type = "RETURN";
    write_token_and_log_lex(token_type, symbol, string(yytext));

    return RETURN;
}


{WHITESPACE} {

}


{INTNUM} {
    string symbol = yytext;
    string token_type = "CONST_INT";
    string token = string("<") + token_type + ", " + symbol + ">";
    write_token_and_log_lex(token_type, symbol, string(yytext));

    yylval.syminfo_ptr = new SymbolInfo(symbol, token_type);

    return CONST_INT;
}

{FLOATNUM}|{EXPNUM} {
    string symbol = yytext;
    string token_type = "CONST_FLOAT";
    string token = string("<") + token_type + ", " + symbol + ">";
    write_token_and_log_lex(token_type, symbol, string(yytext));

    yylval.syminfo_ptr = new SymbolInfo(symbol, token_type);

    return CONST_FLOAT;
}

{SINGLEQUOTES} {
    matched_char = -1; // used fo matching chars
    matched_literal = ""; // used for error lexeme
    BEGIN CHAR;
}

<CHAR>{SINGLEQUOTES} {
    if (matched_char == -1) {
        string lexeme = "''";
        write_error_log_lex("Empty character constant.", lexeme);
    } else {
        string symbol = string(1, matched_char);
        string token_type = "CONST_CHAR";
        string token = string("<") + token_type + ", " + symbol + ">";
        string lexeme = string("'") + matched_literal + string("'");
        write_token_and_log_lex(token_type, symbol, lexeme);
    }

    BEGIN INITIAL;
}

<CHAR>{NEWLINE} {
    string lexeme = string("'") + matched_literal;
    write_error_log_lex("Unterminated character.", lexeme);

    line_count++;

    BEGIN INITIAL;
}

<CHAR,ERR_MULTIPLE_CHAR>{ESCAPED_CHARS_SPECIAL_EXCEPT_NL} {
    write_error_log_lex("Not a valid character.", string(yytext));
}

<CHAR>{SINGLECHAR_LIT} {
    if (matched_char == -1) {
        matched_char = string(yytext)[0];
        matched_literal += string(yytext); // might need if error occurs
    } else {
        matched_literal += string(yytext); 
        BEGIN ERR_MULTIPLE_CHAR;
    }
}

<CHAR>{ALERT_LIT} {
    if (matched_char == -1) {
        matched_char = '\a';
        matched_literal += string(yytext); // might need if error occurs
    } else {
        matched_literal += string(yytext);
        BEGIN ERR_MULTIPLE_CHAR;
    }
}

<CHAR>{BACKSPACE_LIT} {
    if (matched_char == -1) {
        matched_char = '\b';
        matched_literal += string(yytext); // might need if error occurs
    } else {
        matched_literal += string(yytext);
        BEGIN ERR_MULTIPLE_CHAR;
    }
}

<CHAR>{FORMFEED_LIT} {
    if (matched_char == -1) {
        matched_char = '\f';
        matched_literal += string(yytext); // might need if error occurs
    } else {
        matched_literal += string(yytext);
        BEGIN ERR_MULTIPLE_CHAR;
    }
}

<CHAR>{NEWLINE_LIT} {
    if (matched_char == -1) {
        matched_char = '\n';
        matched_literal += string(yytext); // might need if error occurs
    } else {
        matched_literal += string(yytext);
        BEGIN ERR_MULTIPLE_CHAR;
    }
}

<CHAR>{CR_LIT} {
    if (matched_char == -1) {
        matched_char = '\r';
        matched_literal += string(yytext); // might need if error occurs
    } else {
        matched_literal += string(yytext);
        BEGIN ERR_MULTIPLE_CHAR;
    }
}

<CHAR>{TAB_LIT} {
    if (matched_char == -1) {
        matched_char = '\t';
        matched_literal += string(yytext); // might need if error occurs
    } else {
        matched_literal += string(yytext);
        BEGIN ERR_MULTIPLE_CHAR;
    }
}

<CHAR>{VERTICALTAB_LIT} {
    if (matched_char == -1) {
        matched_char = '\v';
        matched_literal += string(yytext); // might need if error occurs
    } else {
        matched_literal += string(yytext);
        BEGIN ERR_MULTIPLE_CHAR;
    }
}

<CHAR>{NULLCHAR_LIT} {
    if (matched_char == -1) {
        matched_char = '\0';
        matched_literal += string(yytext); // might need if error occurs
    } else {
        matched_literal += string(yytext);
        BEGIN ERR_MULTIPLE_CHAR;
    }
}

<CHAR>{ANY_ESCAPED_CHAR_LIT} {
    if (matched_char == -1) {
        matched_char = string(yytext)[1];
        matched_literal += string(yytext); // might need if error occurs
    } else {
        matched_literal += string(yytext);
        BEGIN ERR_MULTIPLE_CHAR;
    }
}

<ERR_MULTIPLE_CHAR>{SINGLEQUOTES} {
    string lexeme = string("'") + matched_literal + string("'");
    write_error_log_lex("Multiple character constant error.", lexeme);

    BEGIN INITIAL;
}

<ERR_MULTIPLE_CHAR>{NEWLINE} {
    string lexeme = string("'") + matched_literal;
    write_error_log_lex("Unterminated character.", lexeme);

    line_count++;

    BEGIN INITIAL;
}

<ERR_MULTIPLE_CHAR>[ -~]{-}[\n\'] {
    matched_literal += string(yytext);
}


{ADDOP} {
    string symbol = string(yytext);
    string token_type = "ADDOP";
    write_token_and_log_lex(token_type, symbol, string(yytext));

    yylval.syminfo_ptr = new SymbolInfo(symbol, token_type);

    return ADDOP;
}

{MULOP} {
    string symbol = string(yytext);
    string token_type = "MULOP";
    write_token_and_log_lex(token_type, symbol, string(yytext));

    yylval.syminfo_ptr = new SymbolInfo(symbol, token_type);

    return MULOP;
}

{INCOP} {
    string symbol = string(yytext);
    string token_type = "INCOP";
    write_token_and_log_lex(token_type, symbol, string(yytext));

    return INCOP;
}

{DECOP} {
    string symbol = string(yytext);
    string token_type = "DECOP";
    write_token_and_log_lex(token_type, symbol, string(yytext));

    return DECOP;
}

{RELOP} {
    string symbol = string(yytext);
    string token_type = "RELOP";
    write_token_and_log_lex(token_type, symbol, string(yytext));

    yylval.syminfo_ptr = new SymbolInfo(symbol, token_type);

    return RELOP;
}

{ASSIGNOP} {
    string symbol = string(yytext);
    string token_type = "ASSIGNOP";
    write_token_and_log_lex(token_type, symbol, string(yytext));

    return ASSIGNOP;
}

{LOGICOP} {
    string symbol = string(yytext);
    string token_type = "LOGICOP";
    write_token_and_log_lex(token_type, symbol, string(yytext));

    yylval.syminfo_ptr = new SymbolInfo(symbol, token_type);

    return LOGICOP;
}

{NOT} {
    string symbol = string(yytext);
    string token_type = "NOT";
    write_token_and_log_lex(token_type, symbol, string(yytext));

    yylval.syminfo_ptr = new SymbolInfo(symbol, token_type);

    return NOT;
}

{LPAREN} {
    string symbol = string(yytext);
    string token_type = "LPAREN";
    write_token_and_log_lex(token_type, symbol, string(yytext));

    return LPAREN;
}

{RPAREN} {
    string symbol = string(yytext);
    string token_type = "RPAREN";
    write_token_and_log_lex(token_type, symbol, string(yytext));

    return RPAREN;
}

{LCURL} {
    string symbol = string(yytext);
    string token_type = "LCURL";
    write_token_and_log_lex(token_type, symbol, string(yytext));
    
    return LCURL;
}

{RCURL} {
    string symbol = string(yytext);
    string token_type = "RCURL";
    write_token_and_log_lex(token_type, symbol, string(yytext));
    
    return RCURL;
}

{LTHIRD} {
    string symbol = string(yytext);
    string token_type = "LTHIRD";
    write_token_and_log_lex(token_type, symbol, string(yytext));

    return LTHIRD;
}

{RTHIRD} {
    string symbol = string(yytext);
    string token_type = "RTHIRD";
    write_token_and_log_lex(token_type, symbol, string(yytext));

    return RTHIRD;
}

{COMMA} {
    string symbol = string(yytext);
    string token_type = "COMMA";
    write_token_and_log_lex(token_type, symbol, string(yytext));

    return COMMA;
}

{SEMICOLON} {
    string symbol = string(yytext);
    string token_type = "SEMICOLON";
    write_token_and_log_lex(token_type, symbol, string(yytext));

    return SEMICOLON;
}

{PRINTLN} {
    string symbol = string(yytext);
    string token_type = "PRINTLN";
    write_token_and_log_lex(token_type, symbol, string(yytext));

    return PRINTLN;
}


{ID} {
    string symbol = string(yytext);
    string token_type = "ID";
    string token = string("<") + token_type + ", " + symbol + ">";
    write_token_and_log_lex(token_type, symbol, string(yytext));
   
    yylval.syminfo_ptr = new SymbolInfo(symbol, token_type);

    return ID;
}


{DOUBLEQUOTES} {
    BEGIN STRING;
    matched_str = "";
    matched_literal = "";
    pending_line_inc = 0;
}

<STRING>{DOUBLEQUOTES} {
    string symbol = matched_str;
    string token_type = "STRING";
    string lexeme = string("\"") + matched_literal + "\"";
    write_token_and_log_lex(token_type, symbol, lexeme);

    line_count += pending_line_inc;

    BEGIN INITIAL;
} 

<STRING>{ESCAPED_LINE_BREAK} {
    pending_line_inc++;
    matched_literal += string(yytext);
}

<STRING>{NEWLINE_LIT} {
    matched_str += '\n';
    matched_literal += string(yytext);
}

<STRING>{TAB_LIT} {
    matched_str += '\t';
    matched_literal += string(yytext);
}

<STRING>{CR_LIT} {
    pending_line_inc++;
    matched_str += '\r';
    matched_literal += string(yytext);
}

<STRING>{BACKSPACE_LIT} {
    matched_str += '\b';
    matched_literal += string(yytext);
}

<STRING>{FORMFEED_LIT} {
    matched_str += '\f';
    matched_literal += string(yytext);
}

<STRING>{ANY_ESCAPED_CHAR_LIT} {
    matched_str += string(yytext)[1];
    matched_literal += string(yytext);
}

<STRING>{STRING_NORMAL_CHAR} {
    matched_str += string(yytext);
    matched_literal += string(yytext);
}

<STRING>{NEWLINE} {
    line_count += pending_line_inc; // so error can point to actual line
    string lexeme = string("\"") + matched_literal;
    write_error_log_lex("Unterminated string.", lexeme);

    line_count++;

    BEGIN INITIAL;
}


{DOUBLEFORWARDSLASH} {
    BEGIN LINE_COMMENT;
    matched_comment = "";
    pending_line_inc = 0;
}

<LINE_COMMENT>{NEWLINE} {
    string symbol = matched_comment;
    string token_type = "COMMENT";
    string lexeme = "//" + matched_comment;
    write_log_lex(token_type, symbol, lexeme);

    line_count += pending_line_inc + 1;

    BEGIN INITIAL;
}

<LINE_COMMENT>{ESCAPED_LINE_BREAK} {
    pending_line_inc++;
    matched_comment += string(yytext);
}

<LINE_COMMENT>{LINE_COMMENT_NORMAL_CHAR} {
    matched_comment += string(yytext);
}


{BLOCK_COMMENT_START} {
    BEGIN BLOCK_COMMENT;
    matched_comment = "";
    pending_line_inc = 0;
}

<BLOCK_COMMENT>{BLOCK_COMMENT_END} {
    string symbol = matched_comment;
    string token_type = "COMMENT";
    string lexeme = "//" + matched_comment;
    write_log_lex(token_type, symbol, lexeme);

    line_count += pending_line_inc;

    BEGIN INITIAL;
}

<BLOCK_COMMENT>{NEWLINE} {
    pending_line_inc++;
}

<BLOCK_COMMENT><<EOF>> {
    string lexeme = string("\\**") + matched_comment;
    write_error_log_lex("Unterminated comment.", lexeme);

    line_count += pending_line_inc;
    pending_line_inc = 0;

    BEGIN INITIAL;
}

<BLOCK_COMMENT>. {
    matched_comment += string(yytext);
}


{NEWLINE} {
    line_count++;
}

{ERR_TOO_MANY_DECIMAL} {
    write_error_log_lex("Too many decimals.", string(yytext));    
}

{ERR_ILL_FORMED_NUM} {
    write_error_log_lex("Ill formed number.", string(yytext));
}

{ERR_INVALID_SUFF_PREF} {
    write_error_log_lex("Invalid suffix on numeric constant or invalid prefix on identifier.", string(yytext));
}

%%

void write_log_lex(string token_name, string token_attr, string lexeme) {
}

void write_token_and_log_lex(string token_name, string token_attr, string lexeme) {
}

void write_error_log_lex(string log, string lexeme) {
    error_count++;
    string log_with_lexemme = log + ". Lexeme: " + lexeme;
    write_error_log(log_with_lexemme, "LEX_ERR");
}