; SO 2021/22 - zadanie 2
; Michał Napiórkowski
; 429573

; Funkcja so_state_t so_emul(uint16_t const *code, uint8_t *data, size_t steps, size_t core)
; parametry: *code -> rdi, *data -> rsi, steps -> rdx, core -> rcx
; wynik: rax
; modyfikowane rejestry: rax, r8 - r11

global so_emul

%ifndef CORES
%define CORES 1
%endif

%macro GET_ARG1 2                       ; makro do obliczania kodu arg1
                                        ; [%1] - rejestr, w którym znajduje się kod instrukcji (zostanie nadpisany przez arg1)
                                        ; [%2] - wartość pierwszego składnika z sumy tworzącej kod instrukcji
        sub     %1, %2
        shr     %1, 8
%endmacro

%macro GET_IMM8 2                       ; makro do obliczania wartości imm8
                                        ; [%1] - rejestr, w którym znajduje się kod instrukcji (zostanie nadpisany przez imm8)
                                        ; [%2] - wartość pierwszego składnika z sumy tworzącej kod instrukcji
        sub     %1, %2
%endmacro

%macro GET_ARG1_ARG2 3                  ; makro do obliczania kodów arg1 i arg2
                                        ; [%1] - rejestr, w którym znajduje się kod instrukcji (zostanie nadpisany przez arg1)
                                        ; [%2] - rejestr, do którego zostanie zapisany kod arg2
                                        ; [%3] - wartość pierwszego składnika z sumy tworzącej kod instrukcji
        sub     %1, %3
        mov     %2, %1
        shr     %2, 11                  ; dzielę przez 2^11 (0x800) -> %2 = arg2
        mov     r11w, %2
        shl     r11w, 11                ; mnożę przez 2^11
        sub     %1, r11w                ; odejmuję od początkowej liczby pomniejszonej o pierwszy składnik
        shr     %1, 8                   ; dzielę przez 2^8 (0x100) -> %1 = arg1
%endmacro

%macro GET_IMM8_ARG1 3                  ; makro do obliczania kodu arg1 i wartości imm8
                                        ; [%1] - rejestr, w którym znajduje się kod instrukcji (zostanie nadpisany przez imm8)
                                        ; [%2] - rejestr, do którego zostanie zapisany kod arg1
                                        ; [%3] - wartość pierwszego składnika z sumy tworzącej kod instrukcji
        sub     %1, %3
        mov     %2, %1
        shr     %2, 8                   ; dzielę przez 2^8 (0x100) -> r10w = arg1
        mov     r11w, %2
        shl     r11w, 8                 ; mnożę przez 2^8
        sub     %1, r11w                ; r9w = imm8
%endmacro

%macro CHECK_ARG_CODE 2                 ; makro do przetłumacznia kodu argumentu na odpowiednie adresy
                                        ; [%1] - rejestr, w którym jest kod argumentu
                                        ; [%2] - rejestr, do którego zostanie zapisany adres odpowiedniego rejestru / komórki pamięci
        cmp     %1, 0
        jne     %%arg_one
        lea     rax, [rel A]
        lea     %2, [rax+rcx]
        jmp     %%end
%%arg_one:
        cmp     %1, 1
        jne     %%arg_two
        lea     rax, [rel D]
        lea     %2, [rax+rcx]
        jmp     %%end
%%arg_two:
        cmp     %1, 2
        jne     %%arg_three
        lea     rax, [rel X]
        lea     %2, [rax+rcx]
        jmp     %%end
%%arg_three:
        cmp     %1, 3
        jne     %%arg_four
        lea     rax, [rel Y]
        lea     %2, [rax+rcx]
        jmp     %%end
%%arg_four:
        cmp     %1, 4
        jne     %%arg_five
        lea     rax, [rel X]
        movzx   r11, byte [rax+rcx]
        lea     %2, [rsi+r11]
        jmp     %%end
%%arg_five:
        cmp     %1, 5
        jne     %%arg_six
        lea     rax, [rel Y]
        movzx   r11, byte [rax+rcx]
        lea     %2, [rsi+r11]
        jmp     %%end
%%arg_six:
        cmp     %1, 6
        jne     %%arg_seven
        xor     r11, r11
        lea     rax, [rel X]
        mov     r11b, byte [rax+rcx]
        lea     rax, [rel D]
        add     r11b, byte [rax+rcx]
        lea     %2, [rsi+r11]
        jmp     %%end
%%arg_seven:
        cmp     %1, 7
        jne     so_emul.instr_end       ; arg nie jest z przedziału [0, 7]
        xor     r11, r11
        lea     rax, [rel Y]
        mov     r11b, byte [rax+rcx]
        lea     rax, [rel D]
        add     r11b, byte [rax+rcx]
        lea     %2, [rsi+r11]
%%end:
%endmacro

%macro SET_Z 0                          ; makro do ustawiania znacznika Z zgodnie z ZF
        lea     rax, [rel Z]
        setz    byte [rax+rcx]
%endmacro

%macro SET_C 0                          ; makro do ustawiania znacznika C zgodnie z CF
        lea     rax, [rel C]
        setc    byte [rax+rcx]
%endmacro

%macro SET_CF 0                         ; makro do ustawiania CF zgodnie ze znacznikiem C
        lea     rax, [rel C]
        mov     r11b, byte [rax+rcx]    ; r11b = C
        bt      r11w, 0                 ; CF = najmniej znaczący bit rejestru r11w
%endmacro

%macro ACQUIRE 0                        ; makro do wchodzenia do sekcji krytycznej
%%wait:
        lea     rax, [rel spinlock]
        lock \
        bts     dword [rax], 0
        jc      %%wait
%endmacro

%macro RELEASE 0                        ; makro do wychodzenia z sekcji krytycznej
        lea     rax, [rel spinlock]
        btr     dword [rax], 0
%endmacro

section .bss                            ; zmienne inicjowane zerami

A: resb CORES
D: resb CORES
X: resb CORES
Y: resb CORES
PC: resb CORES
C: resb CORES
Z: resb CORES
spinlock: resd 1

section .text                           ; kod wykonywalny

so_emul:
        cmp     rdx, 0
        jz      .exit                   ; jeśli mamy do wykonania zero kroków, to wychodzę
        xor     r8, r8                  ; r8 = licznik pętli po krokach (zeruję)
.next_step:
        lea     rax, [rel PC]
        movzx   r11, byte [rax+rcx]     ; r11 = którą instrukcję mam wykonać
        mov     r9w, word [rdi+r11*2]   ; r9w = kolejne słowo z pamięci programu
        cmp     r9w, 0xffff             ; porównując z wartościami granicznymi, skaczę do odpowiedniej instrukcji
        je      .brk_instr
        cmp     r9w, 0xc600
        jae     .instr_end
        cmp     r9w, 0xc500
        jae     .jz_instr
        cmp     r9w, 0xc400
        jae     .jnz_instr
        cmp     r9w, 0xc300
        jae     .jc_instr
        cmp     r9w, 0xc200
        jae     .jnc_instr
        cmp     r9w, 0xc100
        jae     .instr_end
        cmp     r9w, 0xc000
        jae     .jmp_instr
        cmp     r9w, 0x8100
        ja      .instr_end
        je      .stc_instr
        cmp     r9w, 0x8000
        ja      .instr_end
        je      .clc_instr
        cmp     r9w, 0x7800
        jae     .instr_end
        cmp     r9w, 0x7000
        jae     .rcr_instr
        cmp     r9w, 0x6800
        jae     .cmpi_instr
        cmp     r9w, 0x6000
        jae     .addi_instr
        cmp     r9w, 0x5800
        jae     .xori_instr
        cmp     r9w, 0x4800
        jae     .instr_end
        cmp     r9w, 0x4000
        jae     .movi_instr
        cmp     r9b, 0x00
        je      .mov_instr
        cmp     r9b, 0x02
        je      .or_instr
        cmp     r9b, 0x04
        je      .add_instr
        cmp     r9b, 0x05
        je      .sub_instr
        cmp     r9b, 0x06
        je      .adc_instr
        cmp     r9b, 0x07
        je      .sbb_instr
        cmp     r9b, 0x08
        je      .xchg_instr
        jmp     .instr_end
.mov_instr:
GET_ARG1_ARG2   r9w, r10w, 0x0000
ACQUIRE                                 ; wchodzę do sekcji krytycznej
CHECK_ARG_CODE  r9w, r9                 ; r9 = *arg1
CHECK_ARG_CODE  r10w, r10               ; r10 = *arg2
        mov     r11b, byte [r10]        ; r11b = arg2
        mov     [r9], r11b              ; r9 = *arg2
RELEASE                                 ; wychodzę z sekcji krytycznej
        jmp     .instr_end
.or_instr:
GET_ARG1_ARG2   r9w, r10w, 0x0002
CHECK_ARG_CODE  r9w, r9                 ; r9 = *arg1
CHECK_ARG_CODE  r10w, r10               ; r10 = *arg2
        mov     r11b, byte [r10]        ; r11b = arg2
        or      byte [r9], r11b         ; modyfikuje ZF
SET_Z                                   ; Z = ZF
        jmp     .instr_end
.add_instr:
GET_ARG1_ARG2   r9w, r10w, 0x0004
CHECK_ARG_CODE  r9w, r9                 ; r9 = *arg1
CHECK_ARG_CODE  r10w, r10               ; r10 = *arg2
        mov     r11b, byte [r10]        ; r11b = arg2
        add     byte [r9], r11b         ; modyfikuje ZF
SET_Z                                   ; Z = ZF
        jmp     .instr_end
.sub_instr:
GET_ARG1_ARG2   r9w, r10w, 0x0005
CHECK_ARG_CODE  r9w, r9                 ; r9 = *arg1
CHECK_ARG_CODE  r10w, r10               ; r10 = *arg2
        mov     r11b, byte [r10]        ; r11b = arg2
        sub     byte [r9], r11b         ; modyfikuje ZF
SET_Z                                   ; Z = ZF
        jmp     .instr_end
.adc_instr:
GET_ARG1_ARG2   r9w, r10w, 0x0006
CHECK_ARG_CODE  r9w, r9                 ; r9 = *arg1
CHECK_ARG_CODE  r10w, r10               ; r10 = *arg2
SET_CF                                  ; CF = C
        mov     r11b, byte [r10]        ; r11b = arg2
        adc     byte [r9], r11b         ; wykorzystuje CF, modyfikuje CF i ZF
SET_C                                   ; C = CF
SET_Z                                   ; Z = ZF
        jmp     .instr_end
.sbb_instr:
GET_ARG1_ARG2   r9w, r10w, 0x0007
CHECK_ARG_CODE  r9w, r9                 ; r9 = *arg1
CHECK_ARG_CODE  r10w, r10               ; r10 = *arg2
SET_CF                                  ; CF = C
        mov     r11b, byte [r10]        ; r11b = arg2
        sbb     byte [r9], r11b         ; wykorzystuje CF, modyfikuje CF i ZF
SET_C                                   ; C = CF
SET_Z                                   ; Z = ZF
        jmp     .instr_end
.xchg_instr:
GET_ARG1_ARG2   r9w, r10w, 0x0008
ACQUIRE                                 ; wchodzę do sekcji krytycznej
CHECK_ARG_CODE  r9w, r9                 ; r9 = *arg1
CHECK_ARG_CODE  r10w, r10               ; r10 = *arg2
        mov     r11b, byte [r10]        ; r11b = arg2
        mov     al, byte [r9]           ; al = arg1
        mov     byte [r10], al          ; r10 = *arg1
        mov     byte [r9], r11b         ; r9 = *arg2
RELEASE                                 ; wychodzę z sekcji krytycznej
        jmp     .instr_end
.movi_instr:
GET_IMM8_ARG1   r9w, r10w, 0x4000       ; r9b = imm8
ACQUIRE                                 ; wchodzę do sekcji krytycznej
CHECK_ARG_CODE  r10w, r10               ; r10 = *arg1
        mov     byte [r10], r9b         ; r10 = *imm8
RELEASE                                 ; wychodzę z sekcji krytycznej
        jmp     .instr_end
.xori_instr:
GET_IMM8_ARG1   r9w, r10w, 0x5800       ; r9b = imm8
CHECK_ARG_CODE  r10w, r10               ; r10 = *arg1
        xor     byte [r10], r9b         ; modyfikuje ZF
SET_Z                                   ; Z = ZF
        jmp     .instr_end
.addi_instr:
GET_IMM8_ARG1   r9w, r10w, 0x6000       ; r9b = imm8
CHECK_ARG_CODE  r10w, r10               ; r10 = *arg1
        add     byte [r10], r9b         ; modyfikuje ZF
SET_Z                                   ; Z = ZF
        jmp     .instr_end
.cmpi_instr:
GET_IMM8_ARG1   r9w, r10w, 0x6800       ; r9b = imm8
CHECK_ARG_CODE  r10w, r10               ; r10 = *arg1
        cmp     byte [r10], r9b         ; modyfikuje CF i ZF
SET_C                                   ; C = CF
SET_Z                                   ; Z = ZF
        jmp     .instr_end
.rcr_instr:
        cmp     r9b, 0x01
        jne     .instr_end
GET_ARG1        r9w, 0x7001
CHECK_ARG_CODE  r9w, r9                 ; r9 = *arg1
SET_CF                                  ; CF = C
        mov     r11b, byte [r9]         ; r11b = arg1
        rcr     r11b, 1                 ; rotacja w prawo o 1 bit przez CF
SET_C                                   ; C = CF
        mov     byte [r9], r11b         ; r9 = *arg1
        jmp     .instr_end
.clc_instr:
        lea     rax, [rel C]
        mov     byte [rax+rcx], 0       ; C = 0
        jmp     .instr_end
.stc_instr:
        lea     rax, [rel C]
        mov     byte [rax+rcx], 1       ; C = 1
        jmp     .instr_end
.jmp_instr:
GET_IMM8        r9w, 0xc000             ; r9b = imm8
.jump:
        lea     rax, [rel PC]
        add     byte [rax+rcx], r9b     ; PC += imm8
        jmp     .instr_end
.jnc_instr:
GET_IMM8        r9w, 0xc200             ; r9b = imm8
        lea     rax, [rel C]
        cmp     byte [rax+rcx], 0       ; jeśli C == 0, to wykonuję skok
        je      .jump
        jmp     .instr_end
.jc_instr:
GET_IMM8        r9w, 0xc300             ; r9b = imm8
        lea     rax, [rel C]
        cmp     byte [rax+rcx], 1       ; jeśli C == 1, to wykonuję skok
        je      .jump
        jmp     .instr_end
.jnz_instr:
GET_IMM8        r9w, 0xc400             ; r9b = imm8
        lea     rax, [rel Z]
        cmp     byte [rax+rcx], 0       ; jeśli Z == 0, to wykonuję skok
        je      .jump
        jmp     .instr_end
.jz_instr:
GET_IMM8        r9w, 0xc500             ; r9b = imm8
        lea     rax, [rel Z]
        cmp     byte [rax+rcx], 1       ; jeśli Z == 1, to wykonuję skok
        je      .jump
        jmp     .instr_end
.brk_instr:
        mov     r8, rdx
        dec     r8                      ; r8 = steps - 1
.instr_end:
        lea     rax, [rel PC]
        inc     byte [rax+rcx]          ; PC++
        inc     r8
        cmp     r8, rdx                 ; jeśli zwiększony licznik kroków < steps,
        jb      .next_step              ; to wykonuję kolejny
.exit:                                  ; wypełniam rax wartościami rejestrów w odpowiedniej kolejności
        lea     r11, [rel Z]
        mov     al, byte [r11+rcx]
        shl     rax, 8
        lea     r11, [rel C]
        mov     al, byte [r11+rcx]
        shl     rax, 16                 ; 16, bo miejsce na unused
        lea     r11, [rel PC]
        mov     al, byte [r11+rcx]
        shl     rax, 8
        lea     r11, [rel Y]
        mov     al, byte [r11+rcx]
        shl     rax, 8
        lea     r11, [rel X]
        mov     al, byte [r11+rcx]
        shl     rax, 8
        lea     r11, [rel D]
        mov     al, byte [r11+rcx]
        shl     rax, 8
        lea     r11, [rel A]
        mov     al, byte [r11+rcx]
        ret                             ; wychodzę z funkcji
