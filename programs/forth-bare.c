/* **************************************************************************
 *        RISC-V Emulator - Bare-metal Forth interpreter for RISC-V
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

// Bare-metal Forth interpreter for RISC-V
// Adapted from forth.c to work without hosted libc
// By Ulrik Hørlyk Hjort 2026

#include <stdint.h>
#include <stddef.h>

// External functions from uart.c and syscalls.c
void putchar(char c);
char getchar(void);
void put_int(int val);
void put_string(const char *s);
void *malloc(unsigned long size);
void *realloc(void *ptr, unsigned long size);
void free(void *ptr);

// Simple string functions (if not provided by toolchain)
int my_strlen(const char *s) {
    int len = 0;
    while (*s++) len++;
    return len;
}

void my_strncpy(char *dest, const char *src, int n) {
    int i;
    for (i = 0; i < n - 1 && src[i]; i++) {
        dest[i] = src[i];
    }
    dest[i] = '\0';
}

int my_strcasecmp(const char *s1, const char *s2) {
    while (*s1 && *s2) {
        char c1 = *s1, c2 = *s2;
        if (c1 >= 'A' && c1 <= 'Z') c1 += 32;
        if (c2 >= 'A' && c2 <= 'Z') c2 += 32;
        if (c1 != c2) return c1 - c2;
        s1++; s2++;
    }
    return *s1 - *s2;
}

const char *my_strstr(const char *haystack, const char *needle) {
    if (!*needle) return haystack;
    for (; *haystack; haystack++) {
        const char *h = haystack;
        const char *n = needle;
        while (*h && *n && *h == *n) {
            h++; n++;
        }
        if (!*n) return haystack;
    }
    return 0;
}

int my_strcmp(const char *s1, const char *s2) {
    while (*s1 && *s1 == *s2) {
        s1++; s2++;
    }
    return *s1 - *s2;
}

unsigned long my_strcspn(const char *s, const char *reject) {
    unsigned long count = 0;
    while (*s) {
        const char *r = reject;
        while (*r) {
            if (*s == *r) return count;
            r++;
        }
        s++; count++;
    }
    return count;
}

long my_strtol(const char *str, char **endptr, int base) {
    long result = 0;
    int sign = 1;
    const char *orig = str;
    const char *digit_start;

    // Skip whitespace
    while (*str == ' ' || *str == '\t') str++;

    orig = str;  // Remember position before sign

    // Handle sign
    if (*str == '-') {
        sign = -1;
        str++;
    } else if (*str == '+') {
        str++;
    }

    // Remember where digits should start
    digit_start = str;

    // Convert digits
    while (*str >= '0' && *str <= '9') {
        result = result * base + (*str - '0');
        str++;
    }

    // If no digits were parsed, return original position (before sign)
    if (str == digit_start) {
        if (endptr) *endptr = (char *)orig;
        return 0;
    }

    if (endptr) *endptr = (char *)str;
    return result * sign;
}

// Forth interpreter code (same as original)
#define STACK_SIZE 256
#define DICT_SIZE 1024
#define WORD_SIZE 32
#define INPUT_SIZE 256

int stack[STACK_SIZE];
int sp = 0;

int rstack[STACK_SIZE];
int rsp = 0;

typedef struct Word {
    char name[WORD_SIZE];
    int is_immediate;
    void (*code)(void);
    void **data;
    int data_len;
    struct Word *next;
} Word;

Word *dictionary = NULL;
Word *current_word = NULL;

int compiling = 0;
void **compile_buffer = NULL;
int compile_pos = 0;
int compile_size = 0;

char input[INPUT_SIZE];
char *input_ptr;

// Stack operations
void push(int val) {
    if (sp >= STACK_SIZE) {
        put_string("Stack overflow!\n");
        while (1);
    }
    stack[sp++] = val;
}

int pop() {
    if (sp <= 0) {
        put_string("Stack underflow!\n");
        while (1);
    }
    return stack[--sp];
}

void rpush(int val) {
    if (rsp >= STACK_SIZE) {
        put_string("Return stack overflow!\n");
        while (1);
    }
    rstack[rsp++] = val;
}

int rpop() {
    if (rsp <= 0) {
        put_string("Return stack underflow!\n");
        while (1);
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
void emit() { putchar((char)pop()); }
void cr() { put_string("\n"); }
void dot() { put_int(pop()); putchar(' '); }
void dots() {
    put_string("<sp=");
    put_int(sp);
    put_string("> ");
    for (int i = 0; i < sp; i++) {
        put_int(stack[i]);
        putchar(' ');
    }
    put_string("\n");
}

void words() {
    Word *w = dictionary;
    put_string("Dictionary words:\n");
    while (w) {
        put_string("  ");
        put_string(w->name);
        put_string("\n");
        w = w->next;
    }
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
        if (my_strcasecmp(w->name, name) == 0) {
            return w;
        }
        w = w->next;
    }
    return NULL;
}

void add_word(const char *name, void (*code)(void), int immediate) {
    Word *w = malloc(sizeof(Word));
    if (w == NULL) return;
    my_strncpy(w->name, name, WORD_SIZE);
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
        for (int i = 0; i < w->data_len; i++) {
            void *val = w->data[i];
            if ((uintptr_t)val & 1) {
                int num = (int)((intptr_t)val >> 1);
                push(num);
            } else {
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

// Helper to read a word from input
int read_word(char *buf, int max_len) {
    // Skip whitespace
    while (*input_ptr == ' ' || *input_ptr == '\t') input_ptr++;

    // Read until whitespace or end
    int i = 0;
    while (*input_ptr && *input_ptr != ' ' && *input_ptr != '\t' && i < max_len - 1) {
        buf[i++] = *input_ptr++;
    }
    buf[i] = '\0';

    return i > 0;
}

// Forth words for compilation
void colon() {
    char name[WORD_SIZE];
    if (!read_word(name, WORD_SIZE)) {
        put_string("Error: expected word name after ':'\n");
        return;
    }

    Word *w = malloc(sizeof(Word));
    my_strncpy(w->name, name, WORD_SIZE);
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
        put_string("Error: ';' outside definition\n");
        return;
    }
    end_compile();
}

// Get a line of input from UART
void getline_uart(char *buf, int max_len) {
    int i = 0;
    while (i < max_len - 1) {
        char c = getchar();

        // Echo character
        putchar(c);

        // Handle CR/LF
        if (c == '\r' || c == '\n') {
            putchar('\n');  // Ensure newline is shown
            buf[i] = '\0';
            return;
        }

        // Handle backspace
        if (c == 8 || c == 127) {
            if (i > 0) {
                i--;
                putchar(' ');   // Erase character
                putchar(8);     // Move back
            }
            continue;
        }

        buf[i++] = c;
    }
    buf[i] = '\0';
}

// Main interpreter
void interpret(char *input_line) {
    input_ptr = input_line;
    char word[WORD_SIZE];

    while (read_word(word, WORD_SIZE)) {
        // Try to parse as number
        char *endptr;
        long num = my_strtol(word, &endptr, 10);
        if (*endptr == '\0') {
            if (compiling) {
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
                compile_item((void*)w);
            } else {
                execute_word(w);
            }
        } else {
            put_string("Unknown word: ");
            put_string(word);
            put_string("\n");
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
    add_word(";", semicolon, 1);
    add_word("WORDS", words, 0);
}

int main() {
    init_forth();

    put_string("RISC-V Forth Interpreter\n");
    put_string("Type 'BYE' to exit\n\n");

    while (1) {
        put_string(compiling ? "... " : "ok> ");
        getline_uart(input, INPUT_SIZE);

        // Check for exit command
        if (my_strcmp(input, "BYE") == 0 || my_strcmp(input, "bye") == 0) {
            put_string("Goodbye!\n");
            break;
        }

        interpret(input);
    }

    return 0;
}
