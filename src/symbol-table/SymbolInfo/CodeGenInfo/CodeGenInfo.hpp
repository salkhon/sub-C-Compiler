#pragma once
#include <string>
#include <vector>

using namespace std;

/**
 * @brief Satellite container for code gen data to be included in SymbolInfo. Will contain code lines,
 * stack_offset.
 */
class CodeGenInfo {
    int stack_offset;
    bool islocal;
    vector<string> code;
public:
    CodeGenInfo();
    CodeGenInfo(CodeGenInfo const&);

    bool is_local();

    int get_stack_offset();
    vector<string> get_all_code();

    void set_is_local(bool);
    void set_stack_offset(int);
    void add_code(string code);
    void add_code(vector<string> code);
};