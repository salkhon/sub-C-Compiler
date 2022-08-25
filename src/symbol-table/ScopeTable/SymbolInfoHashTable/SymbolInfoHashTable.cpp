#include "SymbolInfoHashTable.hpp"

using namespace std;

namespace printing_info {
    int _chain_index = -1;
}

SymbolInfoHashTable::SymbolInfoHashTable(const int total_buckets)
    : total_buckets(total_buckets), table(total_buckets, nullptr), size{0} {}

void _delete_chain(SymbolInfo* const chain_root) {
    SymbolInfo* current = chain_root;
    while (current != nullptr) {
        SymbolInfo* next = current->next_syminfo_ptr;
        delete current;
        current = next;
    }
}

SymbolInfoHashTable::~SymbolInfoHashTable() {
    for (SymbolInfo* chain_root : this->table) {
        _delete_chain(chain_root);
    }
}

SymbolInfo* _find_syminfo_name_in_chain(const string& symbol, SymbolInfo* const chain_root) {
    SymbolInfo* current = chain_root;
    int idx = 0;
    while (current != nullptr) {
        if (current->get_symbol() == symbol) {
            break;
        }
        current = current->next_syminfo_ptr;
        idx++;
    }
    printing_info::_chain_index = idx;

    return current;
}

int SymbolInfoHashTable::get_num_buckets() {
    return this->total_buckets;
}

int SymbolInfoHashTable::get_size() {
    return this->size;
}

void _insert_at_the_end_of_chain(SymbolInfo* const insertion, vector<SymbolInfo*>& table, int bucket) {
    SymbolInfo* current_sym_info = table[bucket];

    int idx = 0;
    if (current_sym_info == nullptr) {
        table[bucket] = insertion;
    } else {
        idx++;
        while (current_sym_info->next_syminfo_ptr != nullptr) {
            idx++;
            current_sym_info = current_sym_info->next_syminfo_ptr;
        }
        current_sym_info->next_syminfo_ptr = insertion;
    }
    printing_info::_chain_index = idx;
}

bool SymbolInfoHashTable::insert(const string& symbol, const string& token_type) {
    int bucket = this->hash(symbol);
    SymbolInfo* collision = _find_syminfo_name_in_chain(symbol, this->table[bucket]);

    if (collision == nullptr) {
        SymbolInfo* insertion = new SymbolInfo(symbol, token_type);
        _insert_at_the_end_of_chain(insertion, this->table, bucket);
        this->size++;
        return true;
    } else {
        return false;
    }
}

bool SymbolInfoHashTable::insert(const string& symbol, const string& token_type, string& semantic_type) {
    int bucket = this->hash(symbol);
    SymbolInfo* collision = _find_syminfo_name_in_chain(symbol, this->table[bucket]);

    if (collision == nullptr) {
        SymbolInfo* insertion = new SymbolInfo(symbol, token_type, semantic_type);
        _insert_at_the_end_of_chain(insertion, this->table, bucket);
        this->size++;
        return true;
    } else {
        return false;
    }
}

bool SymbolInfoHashTable::insert(const string& symbol, const string& token_type, string& semantic_type, 
    vector<string>& data) {
    int bucket = this->hash(symbol);
    SymbolInfo* collision = _find_syminfo_name_in_chain(symbol, this->table[bucket]);

    if (collision == nullptr) {
        SymbolInfo* insertion = new SymbolInfo(symbol, token_type, semantic_type, data);
        _insert_at_the_end_of_chain(insertion, this->table, bucket);
        this->size++;
        return true;
    } else {
        return false;
    }
}

bool SymbolInfoHashTable::insert_copy(SymbolInfo* syminfo_ptr) {
    int bucket = this->hash(syminfo_ptr->get_symbol());
    SymbolInfo* collision = _find_syminfo_name_in_chain(syminfo_ptr->get_symbol(), this->table[bucket]);

    if (collision == nullptr) {
        SymbolInfo* insertion = new SymbolInfo(*syminfo_ptr);
        _insert_at_the_end_of_chain(insertion, this->table, bucket);
        this->size++;
        return true;
    } else {
        return false;
    }
}

SymbolInfo* SymbolInfoHashTable::lookup(const string& symbol) {
    int bucket = this->hash(symbol);
    SymbolInfo* target = _find_syminfo_name_in_chain(symbol, this->table[bucket]);

    return target;
}

bool SymbolInfoHashTable::delete_symbolinfo(const string& symbol) {
    int bucket = this->hash(symbol);

    SymbolInfo* current = this->table[bucket];

    bool is_successful_delete = false;

    if (current != nullptr && current->get_symbol() == symbol) {
        this->table[bucket] = current->next_syminfo_ptr;

        delete current;
        is_successful_delete = true;

        printing_info::_chain_index = 0;
    } else {
        // keep track of prev to connect chain after removing target.
        SymbolInfo* prev = nullptr;

        int idx = 0;
        while (current != nullptr) {
            if (current->get_symbol() == symbol) {
                break;
            }
            prev = current;
            current = current->next_syminfo_ptr;
            idx++;
        }

        if (current != nullptr) {
            prev->next_syminfo_ptr = current->next_syminfo_ptr;

            delete current;
            is_successful_delete = true;
            printing_info::_chain_index = idx;
        }
    }

    if (is_successful_delete) {
        this->size--;
    }

    return is_successful_delete;
}

int SymbolInfoHashTable::hash(const string& symbol) {
    unsigned long hash = 0;
    for (auto ch : symbol) {
        hash = ch + (hash << 6) + (hash << 16) - hash;
    }
    return hash % this->total_buckets;
}

void _print_chain(SymbolInfo* const symbol_info_ptr) {
    SymbolInfo* current = symbol_info_ptr;
    while (current != nullptr) {
        current = current->next_syminfo_ptr;
    }
}

void _print_chain(SymbolInfo* const symbol_info_ptr, ostream& ostrm) {
    SymbolInfo* current = symbol_info_ptr;
    while (current != nullptr) {
        ostrm << *current << " ";

        current = current->next_syminfo_ptr;
    }
}

void SymbolInfoHashTable::print() {
    const string INDENT = "\t\t";
    cout << endl;
    for (int i = 0; i < this->total_buckets; i++) {
        cout << INDENT;
        cout << "Bucket " << i << " : ";
        _print_chain(this->table[i]);
        cout << endl;
    }
}

ostream& operator<<(ostream& ostrm, SymbolInfoHashTable& hash_table) {
    const string INDENT = "\t\t";
    ostrm << endl;
    for (int i = 0; i < hash_table.total_buckets; i++) {
        if (hash_table.table[i] != nullptr) {
            ostrm << INDENT;
            ostrm << "Bucket " << i << " : ";
            _print_chain(hash_table.table[i], ostrm);
            ostrm << endl;
        }
    }
    return ostrm;
}
