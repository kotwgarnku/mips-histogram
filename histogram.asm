# Author: Filip Konieczny
# Exercise: 6 < contrast change | stretching histogram >

# constants
.eqv FILENAME_LENGTH 32
.eqv BUFFER_SIZE 256

# macros
#---------- STRING RELATED ----------#

.macro load_str (%buffer, %size)
    li $v0, 8        # procedura wczytujaca string
    la $a0, %buffer  # zaladowanie adresu bufora, gdzie ma byc zapisany tekst
    la $a1, %size    # wczytanie rozmiaru bufora
    syscall
.end_macro

.macro print_str (%str)
    .data
    text: .asciiz %str
    .text
    li $v0, 4         # procedura wyswietlajaca string
    la $a0, text      # zaladowanie adresu tekstu
    syscall
.end_macro

.macro remove_newline (%string)
    la $v0, %string
    remove_newline:
        lb $a3, ($v0)             # zaladowanie aktualnego znaku
        addi $v0, $v0, 1          # przejscie do nastepnego indexu
        bnez $a3, remove_newline  # petla, az do napotkania konca tekstu - \0
        beq $a1, $v0, skip        # jesli wczytalismy max znakow, nie ma \n
        subiu $v0, $v0, 2         # jest znak \n, cofamy sie do niego
        sb $0, ($v0)              # zamieniamy \n na \0
    skip:
.end_macro

#---------- FILE RELATED ----------#

.macro open_file (%filename, %flag)
    li $v0, 13        # procedura otwierajaca plik
    la $a0, %filename # wczytanie nazwy pliku
    li $a1, %flag     # flaga, 0 - read
    li $a2, 0         # tryb (nieuzywany)
    syscall
.end_macro

.macro close_file (%descriptor)
    li $v0, 16                # procedura zamykajaca plik
    move $a0, %descriptor     # wczytanie deskryptora pliku
    syscall
.end_macro

.macro read_bytes_from_file (%buffer, %bytes)
    li $v0, 14        # procedura czytajaca plik
    move $a0, $t0     # zaladowanie deskryptora pliku do $a0
    la $a1, %buffer   # wczytanie adresu pod ktory wczytac bajty
    li $a2, %bytes    # wczytanie liczby bajtow do odczytania
    syscall
.end_macro

#---------- FIXED-POINT RELATED ----------#

.macro int_to_fixed (%source)
    sll %source, %source, 16
.end_macro

.macro fixed_to_int (%source)
    sra %source, %source, 16
.end_macro

.macro fixed_mul (%dest, %first, %second)
    # HI: | significant | LO: | fraction |, do mult = (HI << 16) | (LO >> 16)
    multu %first, %second
    mflo %dest
    srl %dest, %dest, 16    # 16 bits for fraction
    mfhi $v0
    sll $v0, $v0, 16        # 16 bits for significant
    or %dest, %dest, $v0
.end_macro

.macro fixed_div (%dest, %first, %second)
    sll %dest, %first, 8
    addu $v0, $zero, %second
    sra $v0, $v0, 8
    div %dest, $v0
    mflo %dest
.end_macro

.data
input_file:  .space FILENAME_LENGTH
output_file: .space FILENAME_LENGTH
buffer:      .space BUFFER_SIZE
size:        .space 4
offset:      .space 4
width:       .space 4
height:      .space 4
begin:       .space 4
multiplier:  .float 65536.0

# friendly registers' names
.eqv r_input_descriptor  $t0
.eqv r_output_descriptor $t1
.eqv r_bytes_done        $t2
.eqv r_bytes_number      $t3
.eqv r_colour_value      $t4
.eqv r_padding           $t5

.eqv r_size              $s0
# current byte           $s1
.eqv r_width             $s2
.eqv r_height            $s3
# offset                 $s4
.eqv r_factor            $s5

.text
read_file:
    print_str ("Wpisz nazwe pliku .bmp, ktory chcesz modyfikowac:\n")
    load_str (input_file, FILENAME_LENGTH)
    remove_newline (input_file)

    print_str ("Podaj wspolczynnik kontrastu: \n")
    li $v0, 6
    syscall

    # konwersja float do fixed-point 16:16
    # fixed = (int)(float * 2^16)
    l.s $f2, multiplier
    mul.s $f0, $f0, $f2
    cvt.w.s $f0, $f0
    mfc1 r_factor, $f0

    print_str ("Wpisz nazwe pliku pod jaka chcesz zapisac obraz po modyfikacji:\n")
    load_str (output_file, FILENAME_LENGTH)
    remove_newline (output_file)

    # TODO:
    # rozciaganie histogramu + wybor opcji programu:
    # * rozciaganie histogramu - padding bardzo komplikuje
    # * zmiana kontrastu

    open_file (input_file, 0)
    move r_input_descriptor, $v0               # wczytanie deskryptora pliku do $t0
    bltz r_input_descriptor, file_exception    # jesli jest mniejszy od zera - blad

    read_bytes_from_file (buffer, 2) # odczytanie 2 bajtow 'BM'
    read_bytes_from_file (size, 4)   # odczytanie 4 bajtow okreslajacych rozmiar pliku
    lw r_size, size                  # zapisanie rozmiaru w $s0

    read_bytes_from_file (buffer, 4) # odczytanie 4 bajtow zarezerwowanych
    read_bytes_from_file (offset, 4) # odczytanie 4 bajtow offsetu
    read_bytes_from_file (buffer, 4) # odczytanie 4 bajtow naglowka

    read_bytes_from_file (width, 4)  # odczytanie 4 bajtow szerokosci obrazka
    lw r_width, width                # zaladowanie szerokosci do $s2

    read_bytes_from_file (height, 4) # odczytanie 4 bajtow wysokosci obrazka
    lw r_height, height              # zaladowanie wysokosci do $s3
    abs r_height, r_height

    close_file (r_input_descriptor)

clone_header:
    open_file (input_file, 0)

    move r_input_descriptor, $v0

    # alokacja pamieci o rozmiarze naglowka pliku (czyli offsetu)
    lw $a0, offset
    li $v0, 9
    syscall

    # przekazanie adresu zaalokowanej pamieci do $s1
    move $s1, $v0
    sw $s1, begin

    li $v0, 14
    move $a0, r_input_descriptor
    la $a1, ($s1)
    lw $a2, offset    # wczytanie tylu bajtow, jaki jest rozmiar naglowka
    syscall

    open_file (output_file, 1)
    move r_output_descriptor, $v0
    bltz r_output_descriptor, file_exception

    lw $s1, begin
    lw $s4, offset

    # sklonowanie naglowka do nowego pliku
    move $a0, r_output_descriptor
    la $a1, ($s1)
    la $a2, ($s4)
    li $v0, 15
    syscall

# File Pointer znajduje sie teraz na tablicy pixeli
# odczytujemy w kawalkach o wielkosci BUFFER_SIZE pixele
# zmieniamy kontrast pixeli i zapisujemy do wyjsciowego pliku

calculate_padding:
    mul r_width, r_width, 3                       # szerokosc w bajtach
    rem r_padding, r_width, 4

initialize_variables:
    li r_bytes_done, 0                            # licznik ustawiony na 0
    add r_bytes_number, r_width, r_padding        # bytes_number = 3*width + padding
    mul r_bytes_number, r_bytes_number, r_height  # bytes_number = (3*width + padding)*height
    div $s6, r_bytes_number, BUFFER_SIZE          # n_times = (3*width + padding)*height / BUFFER_SIZE

adjust_contrast:
    beqz $s6, remainder
    read_bytes_from_file (buffer, BUFFER_SIZE)
    la $s1, buffer

loop:
    beq r_bytes_done, BUFFER_SIZE, store_chunk
    lbu r_colour_value, ($s1)

calculate_contrast:
    addi r_colour_value, r_colour_value, -128              # (R/G/B) - 128
    int_to_fixed (r_colour_value)
    fixed_mul (r_colour_value, r_colour_value, r_factor)   # f * ((R/G/B) - 128)
    fixed_to_int (r_colour_value)                          # truncate[ f * ((R/G/B) - 128) ]
    addi r_colour_value, r_colour_value, 128               # truncate[ f * ((R/G/B) - 128) + 128 ]
    bgt r_colour_value, 255, set_to_max
    bltz r_colour_value, set_to_min
    b dont_set
set_to_max:
    li r_colour_value, 255
    b dont_set
set_to_min:
    li r_colour_value, 0
dont_set:
    sb r_colour_value, ($s1)               # nadpisanie skladowej nowa wartoscia

    addi $s1, $s1, 1                       # przejscie o kolejny bajt
    addi r_bytes_done, r_bytes_done, 1     # przejscie o kolejny bajt
    b loop

next_chunk:
    addi $s6, $s6, -1
    li r_bytes_done, 0
    b adjust_contrast

store_chunk:
    move $a0, r_output_descriptor
    la $a1, buffer
    li $a2, BUFFER_SIZE
    li $v0, 15
    syscall

    b next_chunk

remainder:
    rem $s6, r_bytes_number, BUFFER_SIZE
    beqz $s6, clone_rest_of_file
    li $v0, 14
    move $a0, r_input_descriptor
    la $a1, buffer
    move $a2, $s6
    syscall
    la $s1, buffer

    li r_bytes_done, 0
remainder_loop:
    beq r_bytes_done, $s6, store_remainder
    lbu r_colour_value, ($s1)

remainder_calculate_contrast:
    addi r_colour_value, r_colour_value, -128              # (R/G/B) - 128
    int_to_fixed (r_colour_value)
    fixed_mul (r_colour_value, r_colour_value, r_factor)   # f * ((R/G/B) - 128)
    fixed_to_int (r_colour_value)                          # truncate[ f * ((R/G/B) - 128) ]
    addi r_colour_value, r_colour_value, 128               # truncate[ f * ((R/G/B) - 128) + 128 ]
    bgt r_colour_value, 255, remainder_set_to_max
    bltz r_colour_value, remainder_set_to_min
    b remainder_dont_set
remainder_set_to_max:
    li r_colour_value, 255
    b remainder_dont_set
remainder_set_to_min:
    li r_colour_value, 0
remainder_dont_set:
    sb r_colour_value, ($s1)             # nadpisanie skladowej nowa wartoscia

    addi $s1, $s1, 1                     # przejscie o kolejny bajt
    addi r_bytes_done, r_bytes_done, 1   # przejscie o kolejny bajt
    b remainder_loop

store_remainder:
    move $a0, r_output_descriptor
    la $a1, buffer
    move $a2, $s6
    li $v0, 15
    syscall

clone_rest_of_file:
    read_bytes_from_file (buffer, BUFFER_SIZE)
    beqz $v0, exit

    move $a0, r_output_descriptor
    la $a1, buffer
    move $a2, $v0
    li $v0, 15
    syscall

    b clone_rest_of_file

file_exception:
    print_str ("Nie udalo sie otworzyc pliku.")

exit:
    close_file (r_input_descriptor)
    close_file (r_output_descriptor)
    li $v0, 10
    syscall
