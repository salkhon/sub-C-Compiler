# sub-C Compiler
Compiler for a subset of the C programming language. This compiler generates x86 assembly for a correct source program. It also shows various lexical and syntax errors on erroneous source programs. 

# Overview
This is a compiler for a subset of the C programming language. The syntax of the language is similar to C. Although for the sake of simplicity, the syntax, and features of this language is not as versatile as C. The source program can be written in any file, and passed into the compiler executable as you would do with `gcc`.  

The compiler generates x86 assembly files as output, as opposed to directly assembling to target machine code. You can use x86 assemblers to generate executables for your machine, or simulate the x86 assembly using any emulator, a popular tool is [emu8086](https://emu8086-microprocessor-emulator.en.softonic.com/download).

## Tools Used
![C++](https://img.shields.io/badge/C%2B%2B-00599C?style=for-the-badge&logo=c%2B%2B&logoColor=white)
![C](https://img.shields.io/badge/C-00599C?style=for-the-badge&logo=c&logoColor=white)
[Bison](https://www.gnu.org/software/bison/)
[Flex](https://github.com/westes/flex)

# Table of Contents
- [Language Syntax](#language-syntax)
    - [`main` function](#main-function)
    - [Type](#type)
    - [Array](#array)
    - [Print](#print)
    - [If-Else](#if-else)
    - [Loops](#loops)
    - [Functions](#functions)
- [Compile and Run](#compile-and-run)
    - [Binary](#binary)
    - [From source file](#from-source-file)
        - [Installing `flex`](#installing-flex)
        - [Installing `bison`](#installing-bison)
        - [Compiling the compiler](#compiling-the-compiler)
- [Output](#output)
- [References](#references)

# Language Syntax
Will be written soon. 
## `main` Function

## Type

## Array

## Print

## If-Else

## Loops

## Functions

# Compile and Run

## Binary
Will be released soon. 
## From source file
The compiler sources are available at inside the `src/` directory. You can directly compile them using `flex` and `bison`. 

### Installing `flex`
Run from your terminal: 
```
sudo apt install flex
```

### Installing `bison`
Run from your terminal: 
```
sudo apt install bison
```

### Compiling the compiler
First give permission to `build.sh`:
```
chmod +x build.sh
```

Then execute the shell file: 
```
./build.sh
```

This will generate the compiler executable `subcc.o`. You can directly invoke it to your `.c` file. 

```
subcc.o mycode.c
```

# Output
The compiler will output two x86 assembly files, `code.asm` and `optimized_code.asm`. They are identical, but `optimized_code.asm` performs some *Peephole Optimization* on the code of `code.asm`. 

You can simulate the assembly files using [emu8086](https://emu8086-microprocessor-emulator.en.softonic.com/download). This emulator is made for windows. To run it on linux you need to install [wine](https://www.winehq.org/). Which will allow you to run windows applications on linux. 

# References
* Alfred V. Aho, Ravi Sethi, and Jeffrey D. Ullman. 1986. Compilers: principles, techniques, and tools. Addison-Wesley Longman Publishing Co., Inc., USA.
* Linda Torczon and Keith Cooper. 2007. Engineering A Compiler (2nd. ed.). Morgan Kaufmann Publishers Inc., San Francisco, CA, USA.
* John Levine and Levine John. 2009. Flex & Bison (1st. ed.). O'Reilly Media, Inc.
