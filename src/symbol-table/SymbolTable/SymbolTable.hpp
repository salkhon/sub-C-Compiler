#pragma once
#include <vector>
#include "../ScopeTable/ScopeTable.hpp"

using namespace std;

/**
 * @brief Implementation of the compiler symbol table. Consists of a stack of scope tables for different
 * scopes. Can create push new scope upon entering, pop old scope upon exitting. Can insert new token
 * remove token from current scope. Also can lookup token by name, inside current scope - and all 
 * scopes below it as long as token is not found.  
 */
class SymbolTable {
    ScopeTable* current_scope_table;
    vector<ScopeTable*> scope_tables;
    const int total_buckets;

public:
    SymbolTable(int);

    SymbolTable(int, ostream&);

    ~SymbolTable();

    void enter_scope();

    void exit_scope();

    bool insert(const string&, const string&);

    bool insert(const string&, const string&, string);

    bool insert(const string&, const string&, string, vector<string>);

    bool insert_copy(SymbolInfo*);

    bool remove(const string&);

    SymbolInfo* lookup(const string&);

    int get_current_scope_size();

    friend ostream& operator<<(ostream&, SymbolTable&);
};