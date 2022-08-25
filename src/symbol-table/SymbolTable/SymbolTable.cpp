#include "SymbolTable.hpp"

using namespace std;

SymbolTable::SymbolTable(int total_buckets)
    : scope_tables(),
    current_scope_table(nullptr),
    total_buckets(total_buckets) {
    this->enter_scope();
}

SymbolTable::~SymbolTable() {
    ScopeTable* current = this->current_scope_table;

    while (this->scope_tables.size() != 0) {
        this->exit_scope();
    }
}

/**
 * @brief Pushes a new scope table on top of the scope table stack.
 */
void SymbolTable::enter_scope() {
    ScopeTable* new_scope_table = new ScopeTable(this->total_buckets, this->current_scope_table);
    this->scope_tables.push_back(new_scope_table);
    this->current_scope_table = new_scope_table;
}

/**
 * @brief Pops the current top scope from the scope table stack.
 *
 */
void SymbolTable::exit_scope() {
    if (this->current_scope_table == nullptr) {
        return;
    }

    ScopeTable* old_current_scope_table = this->current_scope_table;
    this->current_scope_table = this->current_scope_table->get_parent_scope();
    this->scope_tables.pop_back();

    delete old_current_scope_table;

    if (this->current_scope_table != nullptr) {
        this->current_scope_table->set_num_deleted_children(
            this->current_scope_table->get_num_deleted_children() + 1
        );
    }
}

/**
 * @brief Inserts the provided token into the current scope table.
 *
 * @param symbol Symbol name
 * @param token_type Token type
 * @return true When insertion is successful
 * @return false When insertion is not successful (collision or no scope table)
 */
bool SymbolTable::insert(const string& symbol, const string& token_type) {
    if (this->current_scope_table == nullptr) {
        return false;
    }

    return this->current_scope_table->insert(symbol, token_type);
}

/**
 * @brief Inserts the provided token into the current scope table.
 *
 * @param symbol Symbol name
 * @param token_type Token type
 * @param semantic_type Semantic type for semantic analysis
 * @return true When insertion is successful
 * @return false When insertion is not successful (collision or no scope table)
 */
bool SymbolTable::insert(const string& symbol, const string& token_type,
    string semantic_type) {
    if (this->current_scope_table == nullptr) {
        return false;
    }

    return this->current_scope_table->insert(symbol, token_type, semantic_type);
}

/**
 * @brief Inserts the provided token into the current scope table.
 *
 * @param symbol Symbol name
 * @param token_type Token type
 * @param semantic_type Semantic type for semantic analysis
 * @param data Additional data strings for semantic analysis
 * @return true When insertion is successful
 * @return false When insertion is not successful (collision or no scope table)
 */
bool SymbolTable::insert(const string& symbol, const string& token_type,
    string semantic_type, vector<string> data) {
    if (this->current_scope_table == nullptr) {
        return false;
    }

    return this->current_scope_table->insert(symbol, token_type, semantic_type, data);
}

/**
 * @brief Inserts a copy of the provided symbol ptr. Copies symbol name, token type semantic type, data[], 
 * and Code generation info. 
 * 
 * @param syminfo_ptr Pointer to the symbol to be inserted.
 * @return true Insert successful
 * @return false Collision
 */
bool SymbolTable::insert_copy(SymbolInfo* syminfo_ptr) {
    if (this->current_scope_table == nullptr) {
        return false;
    }

    return this->current_scope_table->insert_copy(syminfo_ptr);
}

/**
 * @brief Removes a token from the current scope table.
 *
 * @param symbol Symbol to delete
 * @return true When delete is successful
 * @return false When delete is not successful (Not found or no scope table)
 */
bool SymbolTable::remove(const string& symbol) {
    if (this->current_scope_table == nullptr) {
        return false;
    }

    return this->current_scope_table->delete_symbolinfo(symbol);
}

/**
 * @brief Searches for a token by name. Searches from the current scope. Traverses the scope stack
 * top to bottom until token is found. If not found, nullptr is returned.
 *
 * @param symbol Symbol name
 * @return SymbolInfo* Target token. If not found, nullptr is returned.
 */
SymbolInfo* SymbolTable::lookup(const string& symbol) {
    if (current_scope_table == nullptr) {
        return nullptr;
    }

    SymbolInfo* target = nullptr;
    ScopeTable* current_scope = this->current_scope_table;

    while (current_scope != nullptr) {
        target = current_scope->lookup(symbol);
        if (target != nullptr) {
            break;
        }
        current_scope = current_scope->get_parent_scope();
    }

    return target;
}

/**
 * @brief Returns the number of entries in the current scope-table. 
 * 
 * @return int number of entries in the current scope-table. 
 */
int SymbolTable::get_current_scope_size() {
    return this->current_scope_table->get_size();
}

ostream& operator<<(ostream& ostrm, SymbolTable& symbol_table) {
    ostrm << "==========================Symbol Table==================================\n";
    for (auto rev_iter = symbol_table.scope_tables.rbegin(); rev_iter != symbol_table.scope_tables.rend(); rev_iter++) {
        ScopeTable* scope_table = *rev_iter;

        ostrm << *scope_table;
    }
    ostrm << "==========================------X------=================================\n";
    return ostrm;
}