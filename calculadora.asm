; ============================================================
; Calculadora FreezeezyPeak - Clon de la calculadora de Windows
; Ensamblador FASM 32-bit Win32 API + MSVCRT (atof/sprintf)
; Estilo Windows Estandar: MC MR M+ M- MS / % CE C Back
;  1/x x^2 sqrt / / 7 8 9 X / 4 5 6 - / 1 2 3 + / +/- 0 , =
; Teclado completo + memoria + historial de expresion.
; Compilar con: compilar.bat (descarga FASM automaticamente)
; ============================================================

format PE GUI 4.0
entry start

include 'win32a.inc'

; ---------- IDs ----------
IDC_HIST = 100
IDC_MAIN = 101
IDC_MEMIND = 102

ID_MC   = 200
ID_MR   = 201
ID_MADD = 202
ID_MSUB = 203
ID_MS   = 204

ID_PCT   = 210
ID_CE    = 211
ID_C     = 212
ID_BACK  = 213

ID_RECIP = 214
ID_SQR   = 215
ID_SQRT  = 216
ID_DIV   = 217

ID_7 = 218
ID_8 = 219
ID_9 = 220
ID_MUL = 221

ID_4 = 222
ID_5 = 223
ID_6 = 224
ID_SUB = 225

ID_1 = 226
ID_2 = 227
ID_3 = 228
ID_ADD = 229

ID_NEG = 230
ID_0 = 231
ID_DOT = 232
ID_EQ = 233

; Operaciones internas: 1=+ 2=- 3=* 4=/
OP_ADD = 1
OP_SUB = 2
OP_MUL = 3
OP_DIV = 4

FIXED_STYLE = WS_OVERLAPPED+WS_CAPTION+WS_SYSMENU+WS_MINIMIZEBOX+WS_VISIBLE

; ============================================================
section '.text' code readable executable

start:
        invoke  GetModuleHandle,0
        mov     [hInst],eax
        invoke  LoadIcon,0,IDI_APPLICATION
        mov     [wc.hIcon],eax
        invoke  LoadCursor,0,IDC_ARROW
        mov     [wc.hCursor],eax
        mov     [wc.style],CS_HREDRAW+CS_VREDRAW
        mov     [wc.lpfnWndProc],WindowProc
        mov     [wc.cbClsExtra],0
        mov     [wc.cbWndExtra],0
        mov     eax,[hInst]
        mov     [wc.hInstance],eax
        mov     [wc.hbrBackground],COLOR_BTNFACE+1
        mov     [wc.lpszMenuName],0
        mov     [wc.lpszClassName],clsName
        invoke  RegisterClass,wc
        test    eax,eax
        jz      .error

        invoke  CreateWindowEx,0,clsName,titleText,FIXED_STYLE,\
                CW_USEDEFAULT,CW_USEDEFAULT,360,550,NULL,NULL,[hInst],NULL
        test    eax,eax
        jz      .error
        mov     [hMainWnd],eax

.msg_loop:
        invoke  GetMessage,msg,NULL,0,0
        cmp     eax,1
        jb      .end_loop
        jne     .msg_loop
        invoke  TranslateMessage,msg
        invoke  DispatchMessage,msg
        jmp     .msg_loop
.error:
        invoke  MessageBox,NULL,errStart,0,MB_ICONERROR+MB_OK
.end_loop:
        invoke  ExitProcess,[msg.wParam]

; ------------------------------------------------------------
; WindowProc
; ------------------------------------------------------------
proc WindowProc hwnd,wmsg,wparam,lparam
        push    ebx esi edi
        mov     eax,[wmsg]
        cmp     eax,WM_CREATE
        je      .wmcreate
        cmp     eax,WM_COMMAND
        je      .wmcommand
        cmp     eax,WM_CHAR
        je      .wmchar
        cmp     eax,WM_KEYDOWN
        je      .wmkeydown
        cmp     eax,WM_CLOSE
        je      .wmclose
        cmp     eax,WM_DESTROY
        je      .wmdestroy
.defwndproc:
        invoke  DefWindowProc,[hwnd],[wmsg],[wparam],[lparam]
        jmp     .finish
; ---------------- CREATE ----------------
.wmcreate:
        ; --- fuentes ---
        invoke  CreateFont,28,0,0,0,FW_BOLD,0,0,0,DEFAULT_CHARSET,\
                OUT_DEFAULT_PRECIS,CLIP_DEFAULT_PRECIS,DEFAULT_QUALITY,\
                DEFAULT_PITCH+FF_DONTCARE,0
        mov     [hFontMain],eax
        invoke  CreateFont,15,0,0,0,FW_NORMAL,0,0,0,DEFAULT_CHARSET,\
                OUT_DEFAULT_PRECIS,CLIP_DEFAULT_PRECIS,DEFAULT_QUALITY,\
                DEFAULT_PITCH+FF_DONTCARE,0
        mov     [hFontHist],eax
        invoke  CreateFont,17,0,0,0,FW_NORMAL,0,0,0,DEFAULT_CHARSET,\
                OUT_DEFAULT_PRECIS,CLIP_DEFAULT_PRECIS,DEFAULT_QUALITY,\
                DEFAULT_PITCH+FF_DONTCARE,0
        mov     [hFontBtn],eax

        mov     eax,[hwnd]
        mov     [hMainWnd],eax

        ; --- indicador M ---
        invoke  CreateWindowEx,0,clsStatic,emptyStr,\
                WS_CHILD+WS_VISIBLE+SS_LEFT,\
                12,100,20,20,[hwnd],IDC_MEMIND,[hInst],NULL
        mov     [hMemInd],eax
        cmp     eax,0
        je      .create_fail
        invoke  SendMessage,[hMemInd],WM_SETFONT,[hFontHist],0

        ; --- display historial (STATIC: SetWindowText interno funciona;
        ; --- EDIT falla en FASM por notificacion EN_CHANGE reentrante) ---
        invoke  CreateWindowEx,WS_EX_CLIENTEDGE,clsStatic,emptyStr,\
                WS_CHILD+WS_VISIBLE+SS_RIGHT+SS_CENTERIMAGE+SS_NOPREFIX,\
                12,12,320,28,[hwnd],IDC_HIST,[hInst],NULL
        mov     [hHist],eax
        cmp     eax,0
        je      .create_fail
        invoke  SendMessage,[hHist],WM_SETFONT,[hFontHist],0

        ; --- display principal ---
        invoke  CreateWindowEx,WS_EX_CLIENTEDGE,clsStatic,szZero,\
                WS_CHILD+WS_VISIBLE+SS_RIGHT+SS_CENTERIMAGE+SS_NOPREFIX,\
                12,42,320,58,[hwnd],IDC_MAIN,[hInst],NULL
        mov     [hMain],eax
        cmp     eax,0
        je      .create_fail
        invoke  SendMessage,[hMain],WM_SETFONT,[hFontMain],0

        ; --- fila memoria: 5 botones ---
        mov     ebx,0
.mem_loop:
        cmp     ebx,5
        jge     .grid_init
        mov     esi,ebx
        shl     esi,2
        mov     eax,[memIDs+esi]
        mov     [tmpID],eax
        mov     eax,[memTexts+esi]
        mov     [tmpTxt],eax
        ; x = 12 + ebx*64, y=108, w=60, h=30
        mov     eax,ebx
        imul    eax,64
        add     eax,12
        mov     [tmpX],eax
        invoke  CreateWindowEx,0,clsButton,[tmpTxt],\
                WS_CHILD+WS_VISIBLE+BS_PUSHBUTTON,\
                [tmpX],108,60,30,[hwnd],[tmpID],[hInst],NULL
        test    eax,eax
        jz      .create_fail
        invoke  SendMessage,eax,WM_SETFONT,[hFontBtn],0
        inc     ebx
        jmp     .mem_loop

.grid_init:
        mov     [gridRow],0
.grid_row_loop:
        cmp     dword [gridRow],6
        jge     .grid_done
        mov     [gridCol],0
.grid_col_loop:
        cmp     dword [gridCol],4
        jge     .next_row
        ; idx = row*4+col
        mov     eax,[gridRow]
        shl     eax,2
        add     eax,[gridCol]
        mov     esi,eax
        shl     esi,2
        mov     eax,[gridIDs+esi]
        mov     [tmpID],eax
        mov     eax,[gridTexts+esi]
        mov     [tmpTxt],eax
        ; x = 12 + col*80 ; y = 144 + row*54
        mov     eax,[gridCol]
        imul    eax,80
        add     eax,12
        mov     [tmpX],eax
        mov     eax,[gridRow]
        imul    eax,54
        add     eax,144
        mov     [tmpY],eax
        invoke  CreateWindowEx,0,clsButton,[tmpTxt],\
                WS_CHILD+WS_VISIBLE+BS_PUSHBUTTON,\
                [tmpX],[tmpY],75,48,[hwnd],[tmpID],[hInst],NULL
        test    eax,eax
        jz      .create_fail
        invoke  SendMessage,eax,WM_SETFONT,[hFontBtn],0
        inc     dword [gridCol]
        jmp     .grid_col_loop
.next_row:
        inc     dword [gridRow]
        jmp     .grid_row_loop
.grid_done:
        stdcall DoClear
        invoke  SetFocus,[hwnd]
        xor     eax,eax
        jmp     .finish
.create_fail:
        or      eax,-1
        jmp     .finish
; ---------------- COMMAND (botones) ----------------
.wmcommand:
        mov     eax,[wparam]
        movzx   ebx,ax            ; id
        shr     eax,16            ; notif
        ; solo pulsaciones (0 = BN_CLICKED)
        cmp     eax,0
        jne     .finish_cmd0
        cmp     ebx,ID_0
        je      .b0
        cmp     ebx,ID_1
        je      .b1
        cmp     ebx,ID_2
        je      .b2
        cmp     ebx,ID_3
        je      .b3
        cmp     ebx,ID_4
        je      .b4
        cmp     ebx,ID_5
        je      .b5
        cmp     ebx,ID_6
        je      .b6
        cmp     ebx,ID_7
        je      .b7
        cmp     ebx,ID_8
        je      .b8
        cmp     ebx,ID_9
        je      .b9
        cmp     ebx,ID_DOT
        je      .bdot
        cmp     ebx,ID_ADD
        je      .badd
        cmp     ebx,ID_SUB
        je      .bsub
        cmp     ebx,ID_MUL
        je      .bmul
        cmp     ebx,ID_DIV
        je      .bdiv
        cmp     ebx,ID_EQ
        je      .beq
        cmp     ebx,ID_C
        je      .bc
        cmp     ebx,ID_CE
        je      .bce
        cmp     ebx,ID_BACK
        je      .bback
        cmp     ebx,ID_NEG
        je      .bneg
        cmp     ebx,ID_PCT
        je      .bpct
        cmp     ebx,ID_RECIP
        je      .brecip
        cmp     ebx,ID_SQR
        je      .bsqr
        cmp     ebx,ID_SQRT
        je      .bsqrt
        cmp     ebx,ID_MC
        je      .bmc
        cmp     ebx,ID_MR
        je      .bmr
        cmp     ebx,ID_MADD
        je      .bmadd
        cmp     ebx,ID_MSUB
        je      .bmsub
        cmp     ebx,ID_MS
        je      .bms
        jmp     .finish_cmd0
.b0:    stdcall AppendDigit,'0'
        jmp     .finish_cmd
.b1:    stdcall AppendDigit,'1'
        jmp     .finish_cmd
.b2:    stdcall AppendDigit,'2'
        jmp     .finish_cmd
.b3:    stdcall AppendDigit,'3'
        jmp     .finish_cmd
.b4:    stdcall AppendDigit,'4'
        jmp     .finish_cmd
.b5:    stdcall AppendDigit,'5'
        jmp     .finish_cmd
.b6:    stdcall AppendDigit,'6'
        jmp     .finish_cmd
.b7:    stdcall AppendDigit,'7'
        jmp     .finish_cmd
.b8:    stdcall AppendDigit,'8'
        jmp     .finish_cmd
.b9:    stdcall AppendDigit,'9'
        jmp     .finish_cmd
.bdot:  stdcall AppendDot
        jmp     .finish_cmd
.badd:  stdcall DoOperator,OP_ADD
        jmp     .finish_cmd
.bsub:  stdcall DoOperator,OP_SUB
        jmp     .finish_cmd
.bmul:  stdcall DoOperator,OP_MUL
        jmp     .finish_cmd
.bdiv:  stdcall DoOperator,OP_DIV
        jmp     .finish_cmd
.beq:   stdcall DoEquals
        jmp     .finish_cmd
.bc:    stdcall DoClear
        jmp     .finish_cmd
.bce:   stdcall DoClearEntry
        jmp     .finish_cmd
.bback: stdcall DoBack
        jmp     .finish_cmd
.bneg:  stdcall DoNegate
        jmp     .finish_cmd
.bpct:  stdcall DoPercent
        jmp     .finish_cmd
.brecip: stdcall DoRecip
        jmp     .finish_cmd
.bsqr:  stdcall DoSquare
        jmp     .finish_cmd
.bsqrt: stdcall DoSqrt
        jmp     .finish_cmd
.bmc:   stdcall DoMemory,0
        jmp     .finish_cmd
.bmr:   stdcall DoMemory,1
        jmp     .finish_cmd
.bmadd: stdcall DoMemory,2
        jmp     .finish_cmd
.bmsub: stdcall DoMemory,3
        jmp     .finish_cmd
.bms:   stdcall DoMemory,4
        jmp     .finish_cmd
.finish_cmd:
        invoke  SetFocus,[hMainWnd]
.finish_cmd0:
        xor     eax,eax
        jmp     .finish
; ---------------- TECLADO ASCII ----------------
.wmchar:
        mov     eax,[wparam]
        and     eax,0FFh
        cmp     eax,'0'
        jb      .char2
        cmp     eax,'9'
        jbe     .chdigit
.char2:
        cmp     eax,'.'
        je      .chdot
        cmp     eax,','
        je      .chdot
        cmp     eax,'+'
        je      .chadd
        cmp     eax,'-'
        je      .chsub
        cmp     eax,'*'
        je      .chmul
        cmp     eax,'/'
        je      .chdiv
        cmp     eax,'%'
        je      .chpct
        cmp     eax,'='
        je      .cheq
        cmp     eax,13          ; Enter
        je      .cheq
        cmp     eax,8           ; Backspace
        je      .chback
        cmp     eax,27          ; Esc
        je      .chc
        cmp     eax,'c'
        je      .chc
        cmp     eax,'C'
        je      .chc
        cmp     eax,'e'
        je      .chce
        cmp     eax,'E'
        je      .chce
        jmp     .defwndproc
.chdigit:
        stdcall AppendDigit,eax
        xor     eax,eax
        jmp     .finish
.chdot: stdcall AppendDot
        xor     eax,eax
        jmp     .finish
.chadd: stdcall DoOperator,OP_ADD
        xor     eax,eax
        jmp     .finish
.chsub: stdcall DoOperator,OP_SUB
        xor     eax,eax
        jmp     .finish
.chmul: stdcall DoOperator,OP_MUL
        xor     eax,eax
        jmp     .finish
.chdiv: stdcall DoOperator,OP_DIV
        xor     eax,eax
        jmp     .finish
.chpct: stdcall DoPercent
        xor     eax,eax
        jmp     .finish
.cheq:  stdcall DoEquals
        xor     eax,eax
        jmp     .finish
.chback: stdcall DoBack
        xor     eax,eax
        jmp     .finish
.chc:   stdcall DoClear
        xor     eax,eax
        jmp     .finish
.chce:  stdcall DoClearEntry
        xor     eax,eax
        jmp     .finish
; ---------------- TECLAS VIRTUALES (numpad, suprimir) ----------------
.wmkeydown:
        mov     eax,[wparam]
        cmp     eax,VK_RETURN
        je      .k_eq
        cmp     eax,VK_ESCAPE
        je      .k_c
        cmp     eax,VK_BACK
        je      .k_back
        cmp     eax,VK_DELETE
        je      .k_ce
        cmp     eax,VK_ADD
        je      .k_add
        cmp     eax,VK_SUBTRACT
        je      .k_sub
        cmp     eax,VK_MULTIPLY
        je      .k_mul
        cmp     eax,VK_DIVIDE
        je      .k_div
        cmp     eax,VK_DECIMAL
        je      .k_dot
        cmp     eax,VK_NUMPAD0
        jb      .defwndproc
        cmp     eax,VK_NUMPAD9
        jbe     .k_num
        jmp     .defwndproc
.k_num: sub     eax,VK_NUMPAD0
        add     eax,'0'
        stdcall AppendDigit,eax
        xor     eax,eax
        jmp     .finish
.k_dot: stdcall AppendDot
        xor     eax,eax
        jmp     .finish
.k_add: stdcall DoOperator,OP_ADD
        xor     eax,eax
        jmp     .finish
.k_sub: stdcall DoOperator,OP_SUB
        xor     eax,eax
        jmp     .finish
.k_mul: stdcall DoOperator,OP_MUL
        xor     eax,eax
        jmp     .finish
.k_div: stdcall DoOperator,OP_DIV
        xor     eax,eax
        jmp     .finish
.k_eq:  stdcall DoEquals
        xor     eax,eax
        jmp     .finish
.k_c:   stdcall DoClear
        xor     eax,eax
        jmp     .finish
.k_ce:  stdcall DoClearEntry
        xor     eax,eax
        jmp     .finish
.k_back: stdcall DoBack
        xor     eax,eax
        jmp     .finish
; ---------------- CERRAR ----------------
.wmclose:
        invoke  DestroyWindow,[hwnd]
        xor     eax,eax
        jmp     .finish
.wmdestroy:
        invoke  DeleteObject,[hFontMain]
        invoke  DeleteObject,[hFontHist]
        invoke  DeleteObject,[hFontBtn]
        invoke  PostQuitMessage,0
        xor     eax,eax
.finish:
        pop     edi esi ebx
        ret
endp

; ============================================================
; Utilidades de cadena (ANSI, terminadas en 0)
; ============================================================
proc StrLen pStr
        push    esi
        mov     esi,[pStr]
        xor     eax,eax
.len_loop:
        cmp     byte [esi+eax],0
        je      .len_done
        inc     eax
        jmp     .len_loop
.len_done:
        pop     esi
        ret
endp

proc StrCopy pDst,pSrc
        push    esi edi
        mov     edi,[pDst]
        mov     esi,[pSrc]
.copy_loop:
        mov     al,[esi]
        mov     [edi],al
        inc     esi
        inc     edi
        test    al,al
        jnz     .copy_loop
        pop     edi esi
        ret
endp

proc StrCat pDst,pSrc
        push    esi edi
        mov     edi,[pDst]
        mov     esi,[pSrc]
.find_end:
        cmp     byte [edi],0
        je      .do_copy
        inc     edi
        jmp     .find_end
.do_copy:
.copy_loop:
        mov     al,[esi]
        mov     [edi],al
        inc     esi
        inc     edi
        test    al,al
        jnz     .copy_loop
        pop     edi esi
        ret
endp

; Comprueba si entryBuf contiene ','
proc HasComma
        push    esi
        mov     esi,entryBuf
.check:
        mov     al,[esi]
        test    al,al
        jz      .no
        cmp     al,','
        je      .yes
        inc     esi
        jmp     .check
.yes:   mov     eax,1
        pop     esi
        ret
.no:    xor     eax,eax
        pop     esi
        ret
endp

; ============================================================
; Conversion numero <-> texto (usa MSVCRT atof/sprintf)
; entryBuf usa ',' como separador (estilo espanol).
; ============================================================
; Parsea entryBuf -> [curVal] (double). Convierte ','->'.'
proc ParseEntry
        push    esi edi ebx
        mov     esi,entryBuf
        mov     edi,tmpParse
.conv_loop:
        mov     al,[esi]
        test    al,al
        jz      .conv_done
        cmp     al,','
        jne     .store
        mov     al,'.'
.store:
        mov     [edi],al
        inc     esi
        inc     edi
        jmp     .conv_loop
.conv_done:
        mov     byte [edi],0
        push    tmpParse
        call    [atof]
        add     esp,4
        fstp    qword [curVal]
        pop     ebx edi esi
        ret
endp

; Formatea [curVal] -> entryBuf (convierte '.'->',')
; Detecta INF/NAN -> pone "Error" y errState=1. Devuelve eax=1 si error.
proc FormatCurVal
        push    esi edi ebx
        push    dword [curVal+4]
        push    dword [curVal]
        push    fmtG
        push    tmpFormat
        call    [sprintf]
        add     esp,16
        ; detectar letras salvo E/e (INF/NAN)
        mov     esi,tmpFormat
.scan:
        mov     al,[esi]
        test    al,al
        jz      .scan_ok
        cmp     al,'E'
        je      .next_c
        cmp     al,'e'
        je      .next_c
        cmp     al,'+'
        je      .next_c
        cmp     al,'-'
        je      .next_c
        cmp     al,'.'
        je      .next_c
        cmp     al,','
        je      .next_c
        cmp     al,'0'
        jb      .bad
        cmp     al,'9'
        jbe     .next_c
.bad:
        ; letra invalida -> overflow/error
        stdcall StrCopy,entryBuf,errOverflow
        mov     byte [errState],1
        mov     eax,1
        pop     ebx edi esi
        ret
.next_c:
        inc     esi
        jmp     .scan
.scan_ok:
        ; convertir '.' -> ',' y copiar a entryBuf
        mov     esi,tmpFormat
        mov     edi,entryBuf
.copy_loop:
        mov     al,[esi]
        test    al,al
        jz      .copy_done
        cmp     al,'.'
        jne     .st
        mov     al,','
.st:
        mov     [edi],al
        inc     esi
        inc     edi
        jmp     .copy_loop
.copy_done:
        mov     byte [edi],0
        ; "-0" -> "0" (evita menos cero)
        cmp     byte [entryBuf],'-'
        jne     .ok
        cmp     byte [entryBuf+1],'0'
        jne     .ok
        mov     al,[entryBuf+2]
        test    al,al
        jz      .fix_neg
        cmp     al,','
        jne     .ok
        ; "-0,..." -> quitar '-'
        stdcall StrCopy,tmpFormat,entryBuf+1
        stdcall StrCopy,entryBuf,tmpFormat
        jmp     .ok
.fix_neg:
        mov     byte [entryBuf], '0'
        mov     byte [entryBuf+1], 0
.ok:
        xor     eax,eax
        pop     ebx edi esi
        ret
endp

; ============================================================
proc UpdateDisplay
        push    ebx
        invoke  SetWindowText,[hMain],entryBuf
        invoke  SetWindowText,[hHist],exprBuf
        pop     ebx
        ret
endp

proc UpdateMemInd
        push    ebx
        fld     qword [memVal]
        fldz
        fcompp
        fstsw   ax
        sahf
        jne     .has
        invoke  SetWindowText,[hMemInd],emptyStr
        pop     ebx
        ret
.has:
        invoke  SetWindowText,[hMemInd],szM
        pop     ebx
        ret
endp

; ============================================================
proc DoClear
        push    ebx
        stdcall StrCopy,entryBuf,szZero
        mov     byte [exprBuf],0
        fldz
        fstp    qword [stored]
        mov     byte [pendingOp],0
        mov     byte [newEntry],1
        mov     byte [errState],0
        mov     byte [justEquals],0
        stdcall UpdateDisplay
        pop     ebx
        ret
endp

proc DoClearEntry
        push    ebx
        cmp     byte [errState],1
        jne     .nerr
        stdcall DoClear
        pop     ebx
        ret
.nerr:
        stdcall StrCopy,entryBuf,szZero
        mov     byte [newEntry],1
        stdcall UpdateDisplay
        pop     ebx
        ret
endp

proc DoBack
        push    ebx esi edi
        cmp     byte [errState],1
        je      .clr
        cmp     byte [newEntry],1
        je      .done
        cmp     byte [justEquals],1
        je      .done
        stdcall StrLen,entryBuf
        ; eax = len
        cmp     eax,1
        jbe     .to_zero
        cmp     eax,2
        jne     .trunc
        ; len==2: si es "-x" -> "0"
        cmp     byte [entryBuf],'-'
        jne     .trunc
        jmp     .to_zero
.trunc:
        dec     eax
        mov     esi,entryBuf
        mov     byte [esi+eax],0
        ; si queda "-" o "" -> "0"
        cmp     byte [esi],'-'
        jne     .upd
        cmp     byte [esi+1],0
        jne     .upd
        jmp     .to_zero
.upd:
        cmp     byte [esi],0
        jne     .refresh
.to_zero:
        stdcall StrCopy,entryBuf,szZero
.refresh:
        stdcall UpdateDisplay
.done:
        pop     edi esi ebx
        ret
.clr:
        stdcall DoClear
        pop     edi esi ebx
        ret
endp

proc AppendDigit dig
        push    ebx esi edi
        cmp     byte [errState],1
        jne     .noerr
        stdcall DoClear
.noerr:
        cmp     byte [justEquals],1
        jne     .nojust
        ; empezar calculo nuevo tras '='
        mov     byte [exprBuf],0
        mov     byte [pendingOp],0
        fldz
        fstp    qword [stored]
        mov     byte [justEquals],0
        mov     byte [newEntry],1
.nojust:
        mov     eax,[dig]
        and     eax,0FFh
        mov     bl,al              ; digito
        cmp     byte [newEntry],1
        je      .fresh
        ; --- anexar ---
        stdcall StrLen,entryBuf
        cmp     eax,16
        jae     .done
        ; caso "0" -> reemplazar
        cmp     eax,1
        jne     .chk_neg0
        cmp     byte [entryBuf],'0'
        jne     .append
        cmp     bl,'0'
        je      .done              ; evita "00"
        mov     [entryBuf],bl
        jmp     .refresh
.chk_neg0:
        cmp     eax,2
        jne     .append
        cmp     byte [entryBuf],'-'
        jne     .append
        cmp     byte [entryBuf+1],'0'
        jne     .append
        cmp     bl,'0'
        je      .done
        mov     [entryBuf+1],bl
        jmp     .refresh
.append:
        mov     esi,entryBuf
        add     esi,eax
        mov     [esi],bl
        mov     byte [esi+1],0
        jmp     .refresh
.fresh:
        cmp     bl,'0'
        je      .fresh0
        mov     [entryBuf],bl
        mov     byte [entryBuf+1],0
        mov     byte [newEntry],0
        jmp     .refresh
.fresh0:
        stdcall StrCopy,entryBuf,szZero
        mov     byte [newEntry],0
.refresh:
        stdcall UpdateDisplay
.done:
        pop     edi esi ebx
        ret
endp

proc AppendDot
        push    ebx
        cmp     byte [errState],1
        jne     .noerr
        stdcall DoClear
.noerr:
        cmp     byte [justEquals],1
        jne     .nojust
        mov     byte [exprBuf],0
        mov     byte [pendingOp],0
        fldz
        fstp    qword [stored]
        mov     byte [justEquals],0
        mov     byte [newEntry],1
.nojust:
        cmp     byte [newEntry],1
        je      .fresh
        stdcall HasComma
        test    eax,eax
        jnz     .done
        stdcall StrLen,entryBuf
        cmp     eax,15
        jae     .done
        stdcall StrCat,entryBuf,szComma
        stdcall UpdateDisplay
.done:
        pop     ebx
        ret
.fresh:
        stdcall StrCopy,entryBuf,szZeroComma
        mov     byte [newEntry],0
        stdcall UpdateDisplay
        pop     ebx
        ret
endp

proc DoNegate
        push    ebx esi
        cmp     byte [errState],1
        je      .done
        ; si es "0" no hacer nada
        cmp     byte [entryBuf],'0'
        jne     .toggle
        cmp     byte [entryBuf+1],0
        je      .done
.toggle:
        cmp     byte [entryBuf],'-'
        je      .remove
        ; anadir '-'
        stdcall StrLen,entryBuf
        cmp     eax,16
        jae     .done
        mov     esi,entryBuf
        ; desplazar a la derecha
        mov     ecx,eax
        inc     ecx                ; incluye 0 final
.shift:
        mov     al,[esi+ecx-1]
        mov     [esi+ecx],al
        dec     ecx
        jnz     .shift
        mov     byte [esi],'-'
        stdcall UpdateDisplay
        jmp     .done
.remove:
        stdcall StrCopy,entryBuf,entryBuf+1
        stdcall UpdateDisplay
.done:
        pop     esi ebx
        ret
endp

; Devuelve en eax el caracter op para pendingOp dado (por pila o variable)
proc OpCharFor op
        push    ebx
        mov     eax,[op]
        cmp     eax,OP_ADD
        je      .add
        cmp     eax,OP_SUB
        je      .sub
        cmp     eax,OP_MUL
        je      .mul
        cmp     eax,OP_DIV
        je      .div
        mov     eax,'?'
        pop     ebx
        ret
.add:   mov     eax,'+'
        pop     ebx
        ret
.sub:   mov     eax,'-'
        pop     ebx
        ret
.mul:   mov     eax,'*'
        pop     ebx
        ret
.div:   mov     eax,'/'
        pop     ebx
        ret
endp

; Calcula stored (op) curVal -> curVal. eax=0 ok, 1=div0, 2=error.
; Usa FPU. No toca entryBuf.
proc ComputeStoredOpCur
        push    ebx
        mov     al,[pendingOp]
        cmp     al,OP_ADD
        je      .do_add
        cmp     al,OP_SUB
        je      .do_sub
        cmp     al,OP_MUL
        je      .do_mul
        cmp     al,OP_DIV
        je      .do_div
        mov     eax,2
        pop     ebx
        ret
.do_add:
        fld     qword [stored]
        fld     qword [curVal]
        faddp   st1,st0
        fstp    qword [curVal]
        xor     eax,eax
        pop     ebx
        ret
.do_sub:
        fld     qword [stored]
        fld     qword [curVal]
        fsubp   st1,st0
        fstp    qword [curVal]
        xor     eax,eax
        pop     ebx
        ret
.do_mul:
        fld     qword [stored]
        fld     qword [curVal]
        fmulp   st1,st0
        fstp    qword [curVal]
        xor     eax,eax
        pop     ebx
        ret
.do_div:
        ; comprobar divisor cero
        fld     qword [curVal]
        fldz
        fcompp
        fstsw   ax
        sahf
        je      .div0
        fld     qword [stored]
        fld     qword [curVal]
        fdivp   st1,st0
        fstp    qword [curVal]
        xor     eax,eax
        pop     ebx
        ret
.div0:
        mov     eax,1
        pop     ebx
        ret
endp

proc ShowDiv0
        push    ebx
        stdcall StrCopy,entryBuf,errDiv0
        mov     byte [errState],1
        mov     byte [newEntry],1
        stdcall UpdateDisplay
        pop     ebx
        ret
endp

proc ShowInvalid
        push    ebx
        stdcall StrCopy,entryBuf,errInvalid
        mov     byte [errState],1
        mov     byte [newEntry],1
        stdcall UpdateDisplay
        pop     ebx
        ret
endp

; ---------------- Operaciones unarias ----------------
proc DoPercent
        push    ebx
        cmp     byte [errState],1
        je      .done
        stdcall ParseEntry          ; -> curVal
        mov     al,[pendingOp]
        cmp     al,OP_ADD
        je      .addsub
        cmp     al,OP_SUB
        je      .addsub
        cmp     al,OP_MUL
        je      .muldiv
        cmp     al,OP_DIV
        je      .muldiv
        ; sin pendiente: /100
        fld     qword [curVal]
        fld     qword [hundred]
        fdivp   st1,st0
        fstp    qword [curVal]
        jmp     .fmt
.addsub:
        ; stored * cur / 100
        fld     qword [stored]
        fld     qword [curVal]
        fmulp   st1,st0
        fld     qword [hundred]
        fdivp   st1,st0
        fstp    qword [curVal]
        jmp     .fmt
.muldiv:
        fld     qword [curVal]
        fld     qword [hundred]
        fdivp   st1,st0
        fstp    qword [curVal]
.fmt:
        stdcall FormatCurVal
        test    eax,eax
        jnz     .upd_err
        mov     byte [newEntry],1
        stdcall UpdateDisplay
.done:
        pop     ebx
        ret
.upd_err:
        stdcall UpdateDisplay
        pop     ebx
        ret
endp

proc DoRecip
        push    ebx esi
        cmp     byte [errState],1
        je      .done
        ; guardar texto viejo
        stdcall StrCopy,tmpOld,entryBuf
        stdcall ParseEntry
        ; cero?
        fld     qword [curVal]
        fldz
        fcompp
        fstsw   ax
        sahf
        je      .div0
        fld1
        fld     qword [curVal]
        fdivp   st1,st0
        fstp    qword [curVal]
        stdcall FormatCurVal
        test    eax,eax
        jnz     .upd
        ; expr = "1/(viejo)"
        stdcall StrCopy,exprBuf,szRecipPre
        stdcall StrCat,exprBuf,tmpOld
        stdcall StrCat,exprBuf,szParen
        mov     byte [newEntry],1
        stdcall UpdateDisplay
.done:
        pop     esi ebx
        ret
.div0:
        stdcall ShowDiv0
        pop     esi ebx
        ret
.upd:
        stdcall UpdateDisplay
        pop     esi ebx
        ret
endp

proc DoSquare
        push    ebx
        cmp     byte [errState],1
        je      .done
        stdcall StrCopy,tmpOld,entryBuf
        stdcall ParseEntry
        fld     qword [curVal]
        fld     qword [curVal]
        fmulp   st1,st0
        fstp    qword [curVal]
        stdcall FormatCurVal
        test    eax,eax
        jnz     .upd
        stdcall StrCopy,exprBuf,szSqrPre
        stdcall StrCat,exprBuf,tmpOld
        stdcall StrCat,exprBuf,szParen
        mov     byte [newEntry],1
        stdcall UpdateDisplay
.done:
        pop     ebx
        ret
.upd:
        stdcall UpdateDisplay
        pop     ebx
        ret
endp

proc DoSqrt
        push    ebx
        cmp     byte [errState],1
        je      .done
        stdcall StrCopy,tmpOld,entryBuf
        stdcall ParseEntry
        ; negativo? comparar curVal < 0  (ST0=curVal, ST1=0 -> JB si cur<0)
        fldz
        fld     qword [curVal]
        fcompp
        fstsw   ax
        sahf
        jb      .invalid
        fld     qword [curVal]
        fsqrt
        fstp    qword [curVal]
        stdcall FormatCurVal
        test    eax,eax
        jnz     .upd
        stdcall StrCopy,exprBuf,szSqrtPre
        stdcall StrCat,exprBuf,tmpOld
        stdcall StrCat,exprBuf,szParen
        mov     byte [newEntry],1
        stdcall UpdateDisplay
.done:
        pop     ebx
        ret
.invalid:
        stdcall ShowInvalid
        pop     ebx
        ret
.upd:
        stdcall UpdateDisplay
        pop     ebx
        ret
endp

; ---------------- Operador binario ----------------
proc DoOperator op
        push    ebx esi edi
        cmp     byte [errState],1
        je      .done
        mov     eax,[op]
        mov     bl,al               ; nuevo op
        ; cambio de operador consecutivo: newEntry=1 y hay pendiente y no es "="
        cmp     byte [newEntry],1
        jne     .compute_or_first
        cmp     byte [pendingOp],0
        je      .compute_or_first
        cmp     byte [justEquals],1
        je      .compute_or_first
        ; reemplazar ultimo char del expr
        mov     bl,al
        stdcall OpCharFor,ebx
        ; eax = char
        stdcall StrLen,exprBuf
        test    eax,eax
        jz      .compute_or_first
        dec     eax
        mov     esi,exprBuf
        mov     [esi+eax],al
        mov     eax,[op]
        mov     [pendingOp],al
        stdcall UpdateDisplay
        jmp     .done
.compute_or_first:
        cmp     byte [pendingOp],0
        je      .first
        cmp     byte [justEquals],1
        je      .first_after_eq
        cmp     byte [newEntry],1
        je      .first_after_eq
        ; hay pendiente y numero nuevo -> encadenar
        stdcall ParseEntry          ; curVal = actual
        stdcall ComputeStoredOpCur
        cmp     eax,1
        je      .div0
        cmp     eax,0
        jne     .invalid
        ; curVal = resultado -> stored
        fld     qword [curVal]
        fstp    qword [stored]
        stdcall FormatCurVal
        test    eax,eax
        jnz     .upd
        jmp     .build_expr
.first:
        stdcall ParseEntry
        fld     qword [curVal]
        fstp    qword [stored]
        jmp     .build_expr
.first_after_eq:
        ; stored ya es el resultado, solo construir expr con entry actual
        jmp     .build_expr
.build_expr:
        ; expr = entryBuf + " " + opChar
        stdcall StrCopy,exprBuf,entryBuf
        stdcall OpCharFor,ebx
        mov     [tmpOpCh],al
        mov     byte [tmpOpStr], ' '
        mov     cl,[tmpOpCh]
        mov     [tmpOpStr+1],cl
        mov     byte [tmpOpStr+2],0
        stdcall StrCat,exprBuf,tmpOpStr
        mov     eax,[op]
        mov     [pendingOp],al
        mov     byte [newEntry],1
        mov     byte [justEquals],0
        stdcall UpdateDisplay
        jmp     .done
.div0:
        stdcall ShowDiv0
        jmp     .done
.invalid:
        stdcall ShowInvalid
        jmp     .done
.upd:
        stdcall UpdateDisplay
.done:
        pop     edi esi ebx
        ret
endp

; ---------------- Igual =================
proc DoEquals
        push    ebx esi edi
        cmp     byte [errState],1
        je      .done
        cmp     byte [pendingOp],0
        je      .no_pending
        cmp     byte [justEquals],0
        je      .first_eq
        ; --- repetir ultimo = : resultado (op) lastOperand ---
        stdcall StrCopy,tmpOld,entryBuf
        stdcall ParseEntry          ; curVal = resultado actual
        fld     qword [curVal]
        fstp    qword [stored]
        fld     qword [lastOperand]
        fstp    qword [curVal]
        mov     al,[lastOp]
        mov     [pendingOp],al
        stdcall ComputeStoredOpCur
        cmp     eax,1
        je      .div0
        cmp     eax,0
        jne     .invalid
        fld     qword [curVal]
        fstp    qword [stored]
        ; guardar operando str
        fld     qword [lastOperand]
        fstp    qword [curVal]
        stdcall FormatCurVal
        stdcall StrCopy,tmpCur,entryBuf
        ; resultado
        fld     qword [stored]
        fstp    qword [curVal]
        stdcall FormatCurVal
        test    eax,eax
        jnz     .upd
        ; expr = tmpOld + op + tmpCur + " ="
        stdcall OpCharFor,ebx       ; ebx? necesita lastOp
        jmp     .build_repeat
.first_eq:
        ; guardar cur actual (segundo operando)
        stdcall StrCopy,tmpCur,entryBuf
        stdcall ParseEntry
        fld     qword [curVal]
        fstp    qword [lastOperand]
        mov     al,[pendingOp]
        mov     [lastOp],al
        mov     bl,al
        ; formatear stored para expr
        fld     qword [stored]
        fstp    qword [curVal]
        stdcall FormatCurVal
        stdcall StrCopy,tmpStored,entryBuf
        ; restaurar cur = lastOperand para calcular
        fld     qword [lastOperand]
        fstp    qword [curVal]
        stdcall ComputeStoredOpCur
        cmp     eax,1
        je      .div0
        cmp     eax,0
        jne     .invalid
        fld     qword [curVal]
        fstp    qword [stored]
        stdcall FormatCurVal
        test    eax,eax
        jnz     .upd
        ; expr = tmpStored + op + tmpCur + " ="
        stdcall StrCopy,exprBuf,tmpStored
        stdcall OpCharFor,ebx
        mov     [tmpOpCh],al
        mov     byte [tmpOpStr], ' '
        mov     cl,[tmpOpCh]
        mov     [tmpOpStr+1],cl
        mov     byte [tmpOpStr+2],0
        stdcall StrCat,exprBuf,tmpOpStr
        mov     byte [tmpSp],' '
        mov     byte [tmpSp+1],0
        stdcall StrCat,exprBuf,tmpSp
        stdcall StrCat,exprBuf,tmpCur
        stdcall StrCat,exprBuf,szEqEnd
        mov     byte [newEntry],1
        mov     byte [justEquals],1
        stdcall UpdateDisplay
        jmp     .done
.no_pending:
        ; sin operacion: "N ="
        stdcall StrCopy,exprBuf,entryBuf
        stdcall StrCat,exprBuf,szEqEnd2
        mov     byte [newEntry],1
        mov     byte [justEquals],1
        stdcall UpdateDisplay
        jmp     .done
.build_repeat:
        ; ebx debe ser lastOp -> recargar
        mov     bl,[lastOp]
        stdcall StrCopy,exprBuf,tmpOld
        stdcall OpCharFor,ebx
        mov     [tmpOpCh],al
        mov     byte [tmpOpStr], ' '
        mov     cl,[tmpOpCh]
        mov     [tmpOpStr+1],cl
        mov     byte [tmpOpStr+2],0
        stdcall StrCat,exprBuf,tmpOpStr
        mov     byte [tmpSp],' '
        mov     byte [tmpSp+1],0
        stdcall StrCat,exprBuf,tmpSp
        stdcall StrCat,exprBuf,tmpCur
        stdcall StrCat,exprBuf,szEqEnd
        mov     byte [newEntry],1
        mov     byte [justEquals],1
        ; restaurar pending para futuras repeticiones
        mov     al,[lastOp]
        mov     [pendingOp],al
        stdcall UpdateDisplay
        jmp     .done
.div0:
        stdcall ShowDiv0
        jmp     .done
.invalid:
        stdcall ShowInvalid
        jmp     .done
.upd:
        stdcall UpdateDisplay
.done:
        pop     edi esi ebx
        ret
endp

; ---------------- Memoria: 0=MC 1=MR 2=M+ 3=M- 4=MS ----------------
proc DoMemory mop
        push    ebx
        mov     eax,[mop]
        cmp     eax,0
        je      .mc
        cmp     eax,1
        je      .mr
        cmp     eax,2
        je      .madd
        cmp     eax,3
        je      .msub
        cmp     eax,4
        je      .ms
        pop     ebx
        ret
.mc:
        fldz
        fstp    qword [memVal]
        stdcall UpdateMemInd
        pop     ebx
        ret
.mr:
        cmp     byte [errState],1
        jne     .mr_ok
        stdcall DoClear
.mr_ok:
        fld     qword [memVal]
        fstp    qword [curVal]
        stdcall FormatCurVal
        mov     byte [newEntry],1
        stdcall UpdateDisplay
        pop     ebx
        ret
.ms:
        cmp     byte [errState],1
        je      .done
        stdcall ParseEntry
        fld     qword [curVal]
        fstp    qword [memVal]
        mov     byte [newEntry],1
        stdcall UpdateMemInd
.done:
        pop     ebx
        ret
.madd:
        cmp     byte [errState],1
        je      .done2
        stdcall ParseEntry
        fld     qword [memVal]
        fld     qword [curVal]
        faddp   st1,st0
        fstp    qword [memVal]
        mov     byte [newEntry],1
        stdcall UpdateMemInd
.done2:
        pop     ebx
        ret
.msub:
        cmp     byte [errState],1
        je      .done3
        stdcall ParseEntry
        fld     qword [memVal]
        fld     qword [curVal]
        fsubp   st1,st0
        fstp    qword [memVal]
        mov     byte [newEntry],1
        stdcall UpdateMemInd
.done3:
        pop     ebx
        ret
endp

; ============================================================
section '.data' data readable writeable

  hInst       dd ?
  hMainWnd    dd ?
  hMain       dd ?
  hHist       dd ?
  hMemInd     dd ?
  hFontMain   dd ?
  hFontHist   dd ?
  hFontBtn    dd ?

  tmpID       dd ?
  tmpTxt      dd ?
  tmpX        dd ?
  tmpY        dd ?
  gridRow     dd ?
  gridCol     dd ?

  ; estado calculadora
  stored      dq 0.0
  curVal      dq 0.0
  memVal      dq 0.0
  lastOperand dq 0.0
  lastOp      db 0
  pendingOp   db 0
  newEntry    db 1
  errState    db 0
  justEquals  db 0
  tmpOpCh     db 0

  hundred     dq 100.0

  entryBuf    rb 64
  exprBuf     rb 256
  tmpParse    rb 64
  tmpFormat   rb 64
  tmpOld      rb 64
  tmpCur      rb 64
  tmpStored   rb 64
  tmpOpStr    rb 8
  tmpSp       rb 4

  msg MSG
  wc WNDCLASS

  clsName     db 'FreezeezyCalc',0
  titleText   db 'Calculadora FreezeezyPeak',0
  clsButton   db 'BUTTON',0
  clsEdit     db 'EDIT',0
  clsStatic   db 'STATIC',0
  emptyStr    db 0
  errStart    db 'Error al iniciar la calculadora.',0
  errDiv0     db 'No se puede dividir entre cero',0
  errInvalid  db 'Entrada no v',0xA1,'lida',0
  errOverflow db 'Desbordamiento',0
  fmtG        db '%.12G',0
  szZero      db '0',0
  szComma     db ',',0
  szZeroComma db '0,',0
  szM         db 'M',0
  szRecipPre  db '1/(',0
  szSqrPre    db 'sqr(',0
  szSqrtPre   db 'sqrt(',0
  szParen     db ')',0
  szEqEnd     db ' =',0
  szEqEnd2    db ' =',0

  ; textos botones
  txtMC    db 'MC',0
  txtMR    db 'MR',0
  txtMPlus db 'M+',0
  txtMMinus db 'M-',0
  txtMS    db 'MS',0

  txtPct   db '%',0
  txtCE    db 'CE',0
  txtC     db 'C',0
  txtBack  db 'Back',0
  txtRecip db '1/x',0
  txtSquare db 'x^2',0
  txtSqrt  db 'sqrt',0
  txtDiv   db '/',0
  txt7     db '7',0
  txt8     db '8',0
  txt9     db '9',0
  txtMul   db 'X',0
  txt4     db '4',0
  txt5     db '5',0
  txt6     db '6',0
  txtSub   db '-',0
  txt1     db '1',0
  txt2     db '2',0
  txt3     db '3',0
  txtAdd   db '+',0
  txtNeg   db '+/-',0
  txt0     db '0',0
  txtDot   db ',',0
  txtEq    db '=',0

  memTexts dd txtMC,txtMR,txtMPlus,txtMMinus,txtMS
  memIDs   dd ID_MC,ID_MR,ID_MADD,ID_MSUB,ID_MS

  gridTexts dd txtPct,txtCE,txtC,txtBack,\
               txtRecip,txtSquare,txtSqrt,txtDiv,\
               txt7,txt8,txt9,txtMul,\
               txt4,txt5,txt6,txtSub,\
               txt1,txt2,txt3,txtAdd,\
               txtNeg,txt0,txtDot,txtEq
  gridIDs   dd ID_PCT,ID_CE,ID_C,ID_BACK,\
               ID_RECIP,ID_SQR,ID_SQRT,ID_DIV,\
               ID_7,ID_8,ID_9,ID_MUL,\
               ID_4,ID_5,ID_6,ID_SUB,\
               ID_1,ID_2,ID_3,ID_ADD,\
               ID_NEG,ID_0,ID_DOT,ID_EQ

; ============================================================
section '.idata' import data readable writeable

  library kernel,'KERNEL32.DLL',\
          user,'USER32.DLL',\
          gdi,'GDI32.DLL',\
          msvcrt,'MSVCRT.DLL'

  import kernel,\
         GetModuleHandle,'GetModuleHandleA',\
         ExitProcess,'ExitProcess'

  import user,\
         RegisterClass,'RegisterClassA',\
         CreateWindowEx,'CreateWindowExA',\
         DefWindowProc,'DefWindowProcA',\
         GetMessage,'GetMessageA',\
         TranslateMessage,'TranslateMessage',\
         DispatchMessage,'DispatchMessageA',\
         SendMessage,'SendMessageA',\
         LoadCursor,'LoadCursorA',\
         LoadIcon,'LoadIconA',\
         SetWindowText,'SetWindowTextA',\
         GetDlgItem,'GetDlgItemA',\
         SetFocus,'SetFocus',\
         MessageBox,'MessageBoxA',\
         DestroyWindow,'DestroyWindow',\
         PostQuitMessage,'PostQuitMessage'

  import gdi,\
         CreateFont,'CreateFontA',\
         DeleteObject,'DeleteObject'

  import msvcrt,\
         sprintf,'sprintf',\
         atof,'atof'
