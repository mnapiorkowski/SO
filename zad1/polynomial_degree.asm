; SO 2021/22 - zadanie 1
; Michał Napiórkowski
; 429573

; Funkcja int polynomial_degree(int const *y, size_t n)
; parametry: y -> rdi, n -> rsi
; wynik: rax
; modyfikowane rejestry: rax, rcx, rdx, rsp (przywracam), rbp (przywracam), rsi, rdi, r8 - r11

; Streszczenie działania funkcji:
; Odejmuję od siebie sąsiadujące liczby i wynikiem zastępuję pierwszą z nich.
; Gdy w końcu otrzymam tablicę postaci [x, 0, 0,...0, 0], to odpowiada to wielomianowi
; stopnia 0 (lub -1 jeśli x == 0).
; Zliczając liczbę iteracji tych odejmowań mogę wtedy odpowiedzieć jaki był
; początkowy stopień wielomianu.
; Za każdą iteracją wykonuję o 1 odejmowanie mniej, a ostatnią liczbę zastępuję zerem.
; W związku z tym wykonam co najwyżej n-1 iteracji.
; Liczba zer po każdej iteracji to #(zera uzyskane przez odejmowanie w tej iteracji) + nr iteracji.

; Biginty:
; W skrajnym przypadku możemy otrzymać początkowy n-elementowy
; ciąg postaci [MAX_INT, MIN_INT, MAX_INT,..., MIN_INT].
; MAX_INT jest liczbą 32-bitową, a przy odejmowaniach sąsiednich elementów takiego ciągu
; na zapisanie wyniku potrzebujemy o 1 bit więcej w każdej iteracji.
; Zatem potrzebujemy 32 + (n-1) == n + 31 bitów, aby móc zapisać każdą liczbę, jaką potencjalnie
; możemy otrzymać. Biginta będę przechowywał w "tablicy" double-word'ów.
; Dla n == 1 wystarczy 1 dword, ale już dla n == 2, 3,...,33 potrzebujemy dwóch.
; Stąd wzór #dwords = (n+62)/32 (dzielenie z zaokrągleniem w dół)
; #bytes = 4 * #dwords
; W początkowej pętli wpisuję inty z danej tablicy do najmniej znaczących dword'ów w bigintach.
; Resztę wypełniam samymi zerami jeśli int był nieujemny, wpp. samymi jedynkami
; (biginty są w systemie U2). Biginty wrzucam na stos od ostatniego do pierwszego,
; a dword'y od najbardziej do najmniej znaczących. Dzięki temu mogę się do nich w miarę
; naturalnie odwoływać względem rsp.
; Odpowiadające sobie dword'y kolejnych bigintów odejmuję za pomocą sbb,
; bo może być potrzebna pożyczka z wyższego dword'a.

global polynomial_degree

polynomial_degree:
        push    rbp                     ; zachowuję stary rbp
        mov     rbp, rsp                ; inicjalizacja stosu
        push    rdi                     ; [rbp-8] = y
        push    rsi                     ; [rbp-16] = n
        add     rsi, 62
        shr     rsi, 5                  ; (n+62)/32 -> tyle dword'ów na jednego biginta
        push    rsi                     ; [rbp-24] = #dwords
        shl     rsi, 2                  ; mnożę przez 4 -> tyle bajtów na jednego biginta
        push    rsi                     ; [rbp-32] = #bytes
        mov     rdx, [rbp-16]           ; licznik pętli po bigintach
        dec     rdx                     ; rdx = n-1 (wrzucam inty na stos od ostatniego do pierwszego)
        xor     r8, r8                  ; pod r8 będę trzymał aktualną liczbę zerowych bigintów
.initial_loop:                          ; pętla przepisująca zawartość tablicy y[] na biginty
        sub     rsp, [rbp-32]           ; robię miejsce na stosie na jednego biginta
        mov     rcx, 0x1                ; licznik wewnętrznej pętli (po dword'ach)
        mov     r9d, [rdi+rdx*4]        ; kopiuję y[rdx]
        mov     [rsp], r9d              ; pierwszy dword w każdym bigincie to skopiowany int z y[]
        cmp     qword [rbp-24], 0x1     ; jeśli tylko jeden dword był do wypełnienia,
        je      .filling_end            ; to przechodzę do następnego biginta
        cmp     r9d, 0x0                ; w przeciwnym przypadku sprawdzam znak inta
        jg      .fill_with_zeroes       ; liczba dodatnia
        jl      .fill_with_ones         ; liczba ujemna
        cmp     rdx, 0x0                ; zero
        je      .fill_with_zeroes       ; jeśli licznik pętli jest > 0,
        inc     r8                      ; to zwiększam liczbę zerowych bigintów
.fill_with_zeroes:                      ; jeśli int był nieujemny, to pozostałe dword'y
                                        ; odpowiadającego mu biginta wypełniam zerami
        mov     [rsp+rcx*4], dword 0x0
        inc     rcx                     ; j++
        cmp     rcx, [rbp-24]           ; czy j == #dwords?
        jne     .fill_with_zeroes       ; jeśli nie, to wracam na początek pętli
        jmp     .filling_end            ; jeśli tak, to kończę wypełnianie zerami
.fill_with_ones:                        ; jeśli int był ujemny, to pozostałe dword'y
                                        ; odpowiadającego mu biginta wypełniam jedynkami
        mov     [rsp+rcx*4], dword 0xffffffff
        inc     rcx                     ; j++
        cmp     rcx, [rbp-24]           ; czy j == #dwords?
        jne     .fill_with_ones         ; jeśli nie, to wracam na początek pętli
.filling_end:                           ; skończyłem wypełniać biginta
        dec     rdx                     ; i--
        cmp     rdx, 0x0                ; czy i < 0?
        jge     .initial_loop           ; jeśli nie, to wracamy na początek pętli

        xor     rax, rax                ; rax = liczba iteracji
        mov     r9, [rbp-16]
        dec     r9                      ; r9 = n-1
        cmp     r8, r9                  ; jeśli biginty od 1 do n-1 są zerowe,
        je      .check_first_bigint     ; to nie wchodzimy do pętli
.main_loop:                             ; iteracje aż do osiągnięcia wielomianu stopnia 0 lub -1
        inc     rax                     ; iteration++
        xor     r8, r8                  ; zeroes = 0
        xor     rdx, rdx                ; licznik pętli po bigintach
        mov     r11, rsp                ; r11 będzie adresem aktualnego dword'a -> rsp + (rdx * #bytes) + (rcx * 4)
.subtract_bigints:                      ; pętla wykonująca bigint[rdx] -= bigint[rdx+1]
        xor     rcx, rcx                ; licznik wewnętrznej pętli (po dword'ach)
        xor     rsi, rsi                ; licznik niezerowych dword'ów
        xor     r9b, r9b                ; 1 -> przy odejmowaniu została podniesiona flaga CF, 0 -> wpp.
.subtract_dwords:                       ; pętla odejmująca odpowiadające sobie dword'y aktualnych bigintów
        mov     r10, r11
        add     r10, [rbp-32]           ; adres początku biginta[rdx+1]
        mov     edi, [r10+rcx*4]        ; wartość aktualnego dworda
        cmp     r9b, 0x0                ; jeśli poprzednie odejmowanie nie podniosło flagi CF
        je      .subtract               ; to odejmuję bez pożyczki (CF została wyzerowana w poprzednim wierszu)
        stc                             ; wpp. ponownie podnoszę CF i odejmuję z pożyczką
.subtract:
        sbb     [r11+rcx*4], edi        ; dword[rdx][rcx] -= dword[rdx+1][rcx]
        setc    r9b                     ; zachowuję flagę CF
        cmp     [r11+rcx*4], dword 0x0  ; jeśli wynikowy dword nie jest zerem
        je      .subtract_dwords_end
        inc     rsi                     ; to zwiększam licznik niezerowych dword'ów
.subtract_dwords_end:
        inc     rcx                     ; j++
        cmp     rcx, [rbp-24]           ; czy j == #dwords?
        jne     .subtract_dwords        ; jeśli nie, to wracam na początek pętli

        cmp     rdx, 0x0                ; jeśli aktualny jest bigint[0],
        je      .subtract_bigints_end   ; to nie sprawdzam, czy jest zerem
        cmp     rsi, 0x0                ; jeśli wszystkie dwordy były zerowe,
        jne     .subtract_bigints_end
        inc     r8                      ; to zwiększam liczbę zerowych bigintów w aktualnej iteracji
.subtract_bigints_end:
        add     r11, [rbp-32]           ; adres początku kolejnego biginta
        inc     rdx                     ; i++
        mov     r10, [rbp-16]
        sub     r10, rax                ; r10 = n - iteration
        cmp     rdx, r10                ; czy i == n - iteration?
        jne     .subtract_bigints       ; jeśli nie, to wracam na początek pętli

        add     r8, rax                 ; zeroes += iteration
        mov     r9, [rbp-16]
        dec     r9                      ; r9 = n-1
        cmp     r8, r9                  ; jeśli zeroes < n-1,
        jb      .main_loop              ; to wracam na początek pętli

.check_first_bigint:                    ; sprawdzam, czy bigint[0] jest zerowy
        mov     rcx, [rbp-24]           ; licznik pętli po dword'ach
        mov     r11, rsp                ; adres początku biginta[0]
.is_dword_zero:
        cmp     [r11], dword 0x0        ; jeśli dword nie jest zerem,
        jne     .exit                   ; to wychodzę
        lea     r11, [r11+4]            ; wpp. sprawdzam kolejny dword
        loop    .is_dword_zero
        dec     rax                     ; jeśli wszystkie dword'y były zerowe, to zmniejszam wynik o 1
.exit:
        mov     rsp, rbp                ; przywracam stary rsp
        pop     rbp                     ; przywracam stary rbp
        ret                             ; wychodzę z funkcji