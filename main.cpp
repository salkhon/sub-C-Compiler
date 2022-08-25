#include <iostream>
#include <fstream>
#include <string>

using namespace std;

bool is_file_empty(ifstream&);

int main(int argc, char* argv[]) {
    if (argc != 2) {
        cerr << "No filename was provided" << endl;
        return 1;
    }

    const string analysis_script = "./scripts/analysis.sh";
    const string synthesis_script = "./scripts/synthesis.sh";

    string script = "chmod +x " + analysis_script + " " + synthesis_script;
    system(script.c_str());

    script = analysis_script + " \"../" + argv[1] + "\"";
    system(script.c_str());

    ifstream error_file("error.txt");
    if (is_file_empty(error_file)) {
        script = synthesis_script + " \"../" + argv[1] + "\"";
        system(script.c_str());
    } else {
        cout << error_file.rdbuf();
        script = "rm error.txt";
        system(script.c_str());
    }
    return 0;
}

bool is_file_empty(ifstream& file) {
    return file.peek() == EOF;
}