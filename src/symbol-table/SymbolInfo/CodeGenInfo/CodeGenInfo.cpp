#include "CodeGenInfo.hpp"

/**
 * @brief Construct a new Code Gen Info:: Code Gen Info object.
 * Default stack_offset = 0, islocal = false
 */
CodeGenInfo::CodeGenInfo()
    : stack_offset{ 0 }, islocal{ false }, code{} {
}

CodeGenInfo::CodeGenInfo(CodeGenInfo const& other) {
    this->stack_offset = other.stack_offset;
    this->islocal = other.islocal;
    this->code = vector<string>{ other.code };
}

bool CodeGenInfo::is_local() {
    return this->islocal;
}

int CodeGenInfo::get_stack_offset() {
    return this->stack_offset;
}

vector<string> CodeGenInfo::get_all_code() {
    return this->code;
}

void CodeGenInfo::set_is_local(bool islocal) {
    this->islocal = islocal;
}

void CodeGenInfo::set_stack_offset(int stack_offset) {
    this->stack_offset = stack_offset;
}

void CodeGenInfo::add_code(string code) {
    this->code.push_back(code);
}

void CodeGenInfo::add_code(vector<string> code) {
    this->code.insert(this->code.end(), code.begin(), code.end());
}