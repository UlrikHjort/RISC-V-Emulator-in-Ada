/* **************************************************************************
 *                   RISC-V Emulator - Forth Interpreter
 *
 *           Copyright (C) 2026 By Ulrik Hørlyk Hjort
 *
 * Permission is hereby granted, free of charge, to any person obtaining
 * a copy of this software and associated documentation files (the
 * "Software"), to deal in the Software without restriction, including
 * without limitation the rights to use, copy, modify, merge, publish,
 * distribute, sublicense, and/or sell copies of the Software, and to
 * permit persons to whom the Software is furnished to do so, subject to
 * the following conditions:
 *
 * The above copyright notice and this permission notice shall be
 * included in all copies or substantial portions of the Software.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
 * EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
 * MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
 * NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE
 * LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION
 * OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION
 * WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
 * **************************************************************************/

// By Ulrik Hørlyk Hjort 2026
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <ctype.h>
#include <stdint.h>

#define STACK_SIZE 256
#define DICT_SIZE 1024
#define WORD_SIZE 32
#define INPUT_SIZE 256

// Data stack
int stack[STACK_SIZE];
int sp = 0;

// Return stack (for control flow)
int rstack[STACK_SIZE];
int rsp = 0;

// Dictionary entry
typedef struct Word {
    char name[WORD_SIZE];
    int is_immediate;
    void (*code)(void);
    void **data;  // Changed to void** to store pointers properly
    int data_len;
    struct Word *next;
} Word;

Word *dictionary = NULL;
Word *current_word = NULL;

// Compilation state
int compiling = 0;
void **compile_buffer = NULL;  // Changed to void**
int compile_pos = 0;
int compile_size = 0;

// Input buffer
char input[INPUT_SIZE];
char *input_ptr;

// Stack operations
void push(int val) {
    if (sp >= STACK_SIZE) {
        printf("Stack overflow!\n");
        exit(1);
    }
    stack[sp++] = val;
}

int pop() {
    if (sp <= 0) {
        printf("Stack underflow!\n");
        exit(1);
    }
    return stack[--sp];
}

void rpush(int val) {
    if (rsp >= STACK_SIZE) {
        printf("Return stack overflow!\n");
        exit(1);
    }
    rstack[rsp++] = val;
}

int rpop() {
    if (rsp <= 0) {
        printf("Return stack underflow!\n");
        exit(1);
    }
    return rstack[--rsp];
}

// Primitive words
void add() { int b = pop(); int a = pop(); push(a + b); }
void sub() { int b = pop(); int a = pop(); push(a - b); }
void mul() { int b = pop(); int a = pop(); push(a * b); }
void divide() { int b = pop(); int a = pop(); push(a / b); }
void mod() { int b = pop(); int a = pop(); push(a % b); }
void dup() { int a = stack[sp-1]; push(a); }
void drop() { pop(); }
void swap() { int a = pop(); int b = pop(); push(a); push(b); }
void over() { int a = pop(); int b = pop(); push(b); push(a); push(b); }
void rot() { int c = pop(); int b = pop(); int a = pop(); push(b); push(c); push(a); }
void emit() { printf("%c", pop()); }
void cr() { printf("\n"); }
void dot() { printf("%d ", pop()); }
void dots() {
    printf("<sp=%d> ", sp);
    for (int i = 0; i < sp; i++) {
        printf("%d ", stack[i]);
    }
    printf("\n");
}
void eq() { int b = pop(); int a = pop(); push(a == b ? -1 : 0); }
void lt() { int b = pop(); int a = pop(); push(a < b ? -1 : 0); }
void gt() { int b = pop(); int a = pop(); push(a > b ? -1 : 0); }
void and() { int b = pop(); int a = pop(); push(a & b); }
void or() { int b = pop(); int a = pop(); push(a | b); }
void not() { push(~pop()); }

// Dictionary operations
Word* find_word(const char *name) {
    Word *w = dictionary;
    while (w) {
        if (strcasecmp(w->name, name) == 0) {
            return w;
        }
        w = w->next;
    }
    return NULL;
}

void add_word(const char *name, void (*code)(void), int immediate) {
    Word *w = malloc(sizeof(Word));
    strncpy(w->name, name, WORD_SIZE-1);
    w->name[WORD_SIZE-1] = '\0';
    w->is_immediate = immediate;
    w->code = code;
    w->data = NULL;
    w->data_len = 0;
    w->next = dictionary;
    dictionary = w;
}

void execute_word(Word *w) {
    if (w->code) {
        w->code();
    } else if (w->data) {
        // Execute compiled word
        for (int i = 0; i < w->data_len; i++) {
            void *val = w->data[i];
            // Use pointer tagging: low bit set means it's a number
            if ((uintptr_t)val & 1) {
                // It's a number - decode it
                int num = (int)((intptr_t)val >> 1);
                push(num);
            } else {
                // It's a word pointer
                execute_word((Word*)val);
            }
        }
    }
}

// Compilation
void start_compile() {
    compile_size = 64;
    compile_buffer = malloc(compile_size * sizeof(void*));
    compile_pos = 0;
    compiling = 1;
}

void compile_item(void *val) {
    if (compile_pos >= compile_size) {
        compile_size *= 2;
        compile_buffer = realloc(compile_buffer, compile_size * sizeof(void*));
    }
    compile_buffer[compile_pos++] = val;
}

void end_compile() {
    if (current_word) {
        current_word->data = compile_buffer;
        current_word->data_len = compile_pos;
    }
    compile_buffer = NULL;
    compile_pos = 0;
    compile_size = 0;
    compiling = 0;
    current_word = NULL;
}

// Forth words for compilation
void colon() {
    char name[WORD_SIZE];
    if (sscanf(input_ptr, "%s", name) != 1) {
        printf("Error: expected word name after ':'\n");
        return;
    }
    input_ptr = strstr(input_ptr, name) + strlen(name);
    
    Word *w = malloc(sizeof(Word));
    strncpy(w->name, name, WORD_SIZE-1);
    w->name[WORD_SIZE-1] = '\0';
    w->is_immediate = 0;
    w->code = NULL;
    w->data = NULL;
    w->data_len = 0;
    w->next = dictionary;
    dictionary = w;
    current_word = w;
    
    start_compile();
}

void semicolon() {
    if (!compiling) {
        printf("Error: ';' outside definition\n");
        return;
    }
    end_compile();
}

// Main interpreter
void interpret(char *input_line) {
    input_ptr = input_line;
    char word[WORD_SIZE];
    
    while (sscanf(input_ptr, "%s", word) == 1) {
        input_ptr = strstr(input_ptr, word) + strlen(word);
        
        // Try to parse as number
        char *endptr;
        long num = strtol(word, &endptr, 10);
        if (*endptr == '\0') {
            if (compiling) {
                // Tag the number with low bit set
                void *tagged = (void*)((intptr_t)(num << 1) | 1);
                compile_item(tagged);
            } else {
                push((int)num);
            }
            continue;
        }
        
        // Look up in dictionary
        Word *w = find_word(word);
        if (w) {
            if (compiling && !w->is_immediate) {
                compile_item((void*)w);  // Store word pointer
            } else {
                execute_word(w);
            }
        } else {
            printf("Unknown word: %s\n", word);
            if (compiling) {
                end_compile();
            }
            return;
        }
    }
}

// Initialize dictionary
void init_forth() {
    add_word("+", add, 0);
    add_word("-", sub, 0);
    add_word("*", mul, 0);
    add_word("/", divide, 0);
    add_word("MOD", mod, 0);
    add_word("DUP", dup, 0);
    add_word("DROP", drop, 0);
    add_word("SWAP", swap, 0);
    add_word("OVER", over, 0);
    add_word("ROT", rot, 0);
    add_word("EMIT", emit, 0);
    add_word("CR", cr, 0);
    add_word(".", dot, 0);
    add_word(".S", dots, 0);
    add_word("=", eq, 0);
    add_word("<", lt, 0);
    add_word(">", gt, 0);
    add_word("AND", and, 0);
    add_word("OR", or, 0);
    add_word("NOT", not, 0);
    add_word(":", colon, 0);
    add_word(";", semicolon, 1);  // Immediate
}

int main() {
    init_forth();
    
    printf("Simple Forth Interpreter\n");
    printf("Type 'exit' to quit\n\n");
    
    while (1) {
        printf(compiling ? "... " : "ok> ");
        if (!fgets(input, INPUT_SIZE, stdin)) break;
        
        // Remove newline
        input[strcspn(input, "\n")] = 0;
        
        if (strcmp(input, "exit") == 0) break;
        
        interpret(input);
    }
    
    return 0;
}
