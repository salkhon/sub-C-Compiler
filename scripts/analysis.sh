cd ./src/
bison -d analysis.y
g++ -w -c analysis.tab.c

flex -o analysis.yy.c analysis.l
g++ -w -c analysis.yy.c

g++ analysis.tab.o analysis.yy.o \
    ./symbol-table/ScopeTable/ScopeTable.cpp \
    ./symbol-table/ScopeTable/SymbolInfoHashTable/SymbolInfoHashTable.cpp \
    ./symbol-table/SymbolInfo/SymbolInfo.cpp \
    ./symbol-table/SymbolTable/SymbolTable.cpp \
    ./symbol-table/SymbolInfo/CodeGenInfo/CodeGenInfo.cpp \
    -o analysis.out
./analysis.out "$1"

rm *.out *.c *.h *.o log.txt