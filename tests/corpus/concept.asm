; concept.asm — NASM stand-in corpus (ADR 0006): a small x86-64 Linux
; program — sections, data, a macro, conditionals, local labels, and
; every number and string form the grammar reads.

%include "macros.inc"
%define SYS_WRITE 1
%define SYS_EXIT  60
%assign COUNT 3

%macro syscall3 4
    mov     rax, %1
    mov     rdi, %2
    mov     rsi, %3
    mov     rdx, %4
    syscall
%endmacro

%ifdef DEBUG
    %warning "debug build"
%elif COUNT > 2
    %define VERBOSE 1
%else
    %define VERBOSE 0
%endif

bits 64
default rel

section .data
greeting:   db "Hello, world", 10, 0
            db 'single quoted', 0
            db `escapes: \t tab, \n newline`, 0
            dw 0x1F, 0b1010, 0o17, 777q, 1010b, 10h, 99d
            dd 1_000_000, 3.14159, 1.5e-3
            dq 0x7fff_ffff_ffff_ffff
len         equ $ - greeting
table:      times 4 dd 0

section .bss
buffer:     resb 64
counts:     resq COUNT

struc point
    .x:     resd 1
    .y:     resd 1
endstruc

; A macro line continued with `\`, and an escaped symbol.
%macro checked_call 2 \
    ; (continued)
%endmacro
$@feat.00 equ 1

section .text
global _start
extern printf

_start:
    lea     rsi, [rel greeting]
    syscall3 SYS_WRITE, 1, rsi, len
    xor     ecx, ecx
.loop:
    cmp     ecx, COUNT
    jge     .done
    mov     dword [counts + rcx*8], ecx
    add     qword [table], 4 << 2
    inc     ecx
    jmp     short .loop
.done:
    mov     eax, (SYS_EXIT % 64) + 0
    xor     edi, edi
    syscall
