#include "ScopeTable.hpp"
#include <iostream>

using namespace std;

ScopeTable::ScopeTable(const int total_buckets, ScopeTable* parent_scope_ptr)
    : hashtable(new SymbolInfoHashTable(total_buckets)), num_deleted_children(0) {
    this->hashtable->enclosing_scope_table_ptr = this;
    this->set_parent_scope_ptr_with_id_currentid(parent_scope_ptr);

    // cout << "New ScopeTable with id " << this->id << " created\n";
}

ScopeTable::~ScopeTable() {
    delete this->hashtable;
    // cout << "ScopeTable with id " << this->id << " removed\n";
}

/**
 * @brief Allocates symbol info with provided args. Hashes them into the chain of the proper bucket.
 *
 * @param symbol Name of the token to be allocated
 * @param token_type Type of the token to be allocated
 * @return true When insertion is successful.
 * @return false When insertion is not successful. (collision)
 */
bool ScopeTable::insert(const string& symbol, const string& token_type) {
    return this->hashtable->insert(symbol, token_type);
}

/**
 * @brief Allocates symbol info with provided args. Hashes them into the chain of the proper bucket.
 *
 * @param symbol Name of the token to be allocated
 * @param token_type Type of the token to be allocated
 * @param semantic_type Type for semantic analysis
 * @return true When insertion is successful.
 * @return false When insertion is not successful. (collision)
 */
bool ScopeTable::insert(const string& symbol, const string& token_type, string& semantic_type) {
    return this->hashtable->insert(symbol, token_type, semantic_type);
}

/**
 * @brief Allocates symbol info with provided args. Hashes them into the chain of the proper bucket.
 *
 * @param symbol Name of the token to be allocated
 * @param token_type Type of the token to be allocated
 * @param semantic_type Type for semantic analysis
 * @param data Additional data strings for semantic analysis
 * @return true When insertion is successful.
 * @return false When insertion is not successful. (collision)
 */
bool ScopeTable::insert(const string& symbol, const string& token_type, string& semantic_type, vector<string>& data) {
    return this->hashtable->insert(symbol, token_type, semantic_type, data);
}

/**
 * @brief Calles the copy constructor using the provided symbol pointer. Inserts that copy. 
 * 
 * @param syminfo_ptr 
 * @return true Insertion successful
 * @return false Collision
 */
bool ScopeTable::insert_copy(SymbolInfo* syminfo_ptr) {
    return this->hashtable->insert_copy(syminfo_ptr);
}

/**
 * @brief Looks up the token by name.
 *
 * @param symbol Name of token to search.
 * @return SymbolInfo* Pointer to the searched token. If not found, nullptr is returned.
 */
SymbolInfo* ScopeTable::lookup(const string& symbol) {
    return this->hashtable->lookup(symbol);
}

/**
 * @brief Deallocates the token of the provided name.
 *
 * @param symbol Name of the token to be deleted
 * @return true When deletion was successful
 * @return false When deletion was not successful (Not found)
 */
bool ScopeTable::delete_symbolinfo(const string& symbol) {
    return this->hashtable->delete_symbolinfo(symbol);
}

/**
 * @brief Sets parent_scope_ptr attribute for this scope table. It also sets current_id (int)
 * and id (string) attribute for this scope table from the parent scope.
 *
 * When parent scope ptr is set to nullptr, it is interpreted that the scope table has no parent
 * scope, therefore is of depth 1.
 */
void ScopeTable::set_parent_scope_ptr_with_id_currentid(ScopeTable* parent_scope_ptr) {
    this->parent_scope_ptr = parent_scope_ptr;

    if (this->parent_scope_ptr != nullptr) {
        this->current_id = this->parent_scope_ptr->current_id + 1;
        this->id = this->parent_scope_ptr->get_id() + "." +
            to_string(this->parent_scope_ptr->get_num_deleted_children() + 1);
    } else {
        this->current_id = 1;
        this->id = "1";
    }
}

int ScopeTable::get_num_deleted_children() {
    return this->num_deleted_children;
}

void ScopeTable::set_num_deleted_children(int num_deleted_childred) {
    this->num_deleted_children = num_deleted_childred;
}

ScopeTable* ScopeTable::get_parent_scope() {
    return this->parent_scope_ptr;
}

string ScopeTable::get_id() {
    return this->id;
}

int ScopeTable::get_current_id() {
    return this->current_id;
}

int ScopeTable::get_size() {
    return this->hashtable->get_size();
}

void ScopeTable::print() {
    const string INDENT = "\t";
    cout << endl;
    cout << INDENT;
    cout << "Scopetable # " << this->id << endl;
    this->hashtable->print();
}

ostream& operator<<(ostream& ostrm, ScopeTable& scope_table) {
    const string INDENT = "\t";
    ostrm << endl;
    ostrm << INDENT;
    ostrm << "Scopetable # " << scope_table.id << endl;
    ostrm << *scope_table.hashtable;
    return ostrm;
}