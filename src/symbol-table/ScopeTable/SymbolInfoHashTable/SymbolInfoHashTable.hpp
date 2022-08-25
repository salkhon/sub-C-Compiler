#pragma once
#include <memory>
#include <vector>
#include <iostream>
#include "../../SymbolInfo/SymbolInfo.hpp"
#include "../ScopeTable.hpp"

using namespace std;

// when ScopeTable is imported in main, this file is recursively imported BEFORE ScopeTable. 
// Which would mean ScopeTable* is used before declaration of class ScopeTable. 
class ScopeTable; 

/**
 * @brief Implementation for the token hash table of a Scope Table.
 */
class SymbolInfoHashTable {
    const int total_buckets;
    vector<SymbolInfo*> table;
    int size;
public:
    ScopeTable* enclosing_scope_table_ptr;

    SymbolInfoHashTable(const int total_buckets);

    ~SymbolInfoHashTable();

    int get_num_buckets();

    int get_size();

    bool insert(const string&, const string&);

    bool insert(const string&, const string&, string&);
    
    bool insert(const string&, const string&, string&, vector<string>&);

    bool insert_copy(SymbolInfo*);

    SymbolInfo* lookup(const string&);

    bool delete_symbolinfo(const string&);

    void print();

    friend ostream& operator<<(ostream&, SymbolInfoHashTable&);

private:
    int hash(const string&);
};