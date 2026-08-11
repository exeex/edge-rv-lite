    .option push
    .option norelax
    .section .text, "ax", @progbits
    .globl __start
    .type __start, @function

__start:
    call    edge_main
    ebreak
1:
    j       1b

    .size __start, .-__start
    .option pop
