cd ./src/
bison -d subcc.y
g++ -w -c subcc.tab.c

flex -o subcc.yy.c subcc.l
g++ -w -c subcc.yy.c

g++ subcc.tab.o subcc.yy.o \
    ./symbol-table/ScopeTable/ScopeTable.cpp \
    ./symbol-table/ScopeTable/SymbolInfoHashTable/SymbolInfoHashTable.cpp \
    ./symbol-table/SymbolInfo/SymbolInfo.cpp \
    ./symbol-table/SymbolTable/SymbolTable.cpp \
    ./symbol-table/SymbolInfo/CodeGenInfo/CodeGenInfo.cpp \
    -o ./../subcc.out

rm *.c *.h *.o