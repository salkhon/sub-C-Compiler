cd ./src/
bison -d synthesis.y
g++ -w -c synthesis.tab.c

flex -o synthesis.yy.c synthesis.l 
g++ -w -c synthesis.yy.c

g++ synthesis.tab.o synthesis.yy.o \
    ./symbol-table/ScopeTable/ScopeTable.cpp \
    ./symbol-table/ScopeTable/SymbolInfoHashTable/SymbolInfoHashTable.cpp \
    ./symbol-table/SymbolInfo/SymbolInfo.cpp \
    ./symbol-table/SymbolTable/SymbolTable.cpp \
    ./symbol-table/SymbolInfo/CodeGenInfo/CodeGenInfo.cpp \
    -o synthesis.out
./synthesis.out "$1"

rm *.out *.c *.h *.o error.txt