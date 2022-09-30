
; ======================================================
; ------------ Copyright (C) B.S.K.T 2022 -------------- 
; ======================================================

_Init_Start_MBR:
    ORG 0x7c00                          ; 程序起始加载位置

    cLoader_Base         EQU 0x920      ; Loader 16位 段地址
    cLoader_Offset       EQU 0           ; Loader 16位 偏移地址
    cStack_Base          EQU 0x7c00      ; 栈底

    cRoot_Fst_Sec        EQU 19          ; 根目录起始扇区号
    cRoot_Length_Sec     EQU 14          ; 根目录占用的扇区数

    JMP _Entry_MBR_Code                       ; BS_JMP2Boot
    NOP                                       ; Empty Cmd

; ==== FAT_12 File System BPB(BIOS Paramter Block) Informations ====
    Code_Of_BPB:

    BS_OEM_Name:       DB "B.S.K.T."           ; 8 Bytes      生产厂商名

    BPB_BytesPerSec:   DW 512                  ; 2 Bytes      每个扇区的字节大小
    BPB_SecPerClus:    DB 1                    ; 1 Bytes      描述每个簇的扇区数
    BPB_RsvdSecCnt:    DW 1                    ; 2 Bytes      保留扇区的数量，FAT12必须是1，FAT表从第二个扇区开始
    BPB_NumFATs:       DB 2                    ; 1 Bytes      指定文件系统中FAT表的份数

    BPB_RootEntCnt:    DW 224                  ; 2 Bytes      根目录容纳的子目录个数 This * 32 = 2n（BPB_BytesPerSec）
    BPB_TotSec16:      DW 2880                 ; 2 Bytes      总扇区数量（或BPB_TotSec32），包括保留扇区、FAT表、根目录区、数据区占用的扇区数
    BPB_Media:         DB 0xf0                 ; 1 Bytes      介质描述符（标准值0xf8，可移动0xf0），必须与FAT[0]的低字节保持一致
    BPB_FATSz16:       DW 9                    ; 2 Bytes      每个FAT表的扇区数

    BPB_SecPerTrk:     DW 18                   ; 2 Bytes      每磁道扇区数
    BPB_NumHeads:      DW 2                    ; 2 Bytes      磁头数
    BPB_HiddSec:       DD 0                    ; 4 Bytes      隐藏扇区数
    BPB_TotSec32:      DD 0                    ; 4 Bytes      如果扇区数TotSec16为0，则由此记录扇区数

    BS_DrvNum:         DB 0                    ; 1 Bytes      INT13H使用的驱动号
    BS_Reserved1:      DB 0                    ; 1 Bytes      保留位
    BS_BootSig:        DB 0x29                 ; 1 Bytes      扩展引导标记
    BS_VolID:          DD 0                    ; 4 Bytes      卷序列号

    BS_VolLab:         DB "NOSNAMELOAD"        ;11 Bytes      卷标
    BS_FileSysType:    DB "FAT12   "           ; 8 Bytes      文件系统类型，非鉴别文件系统用

; ============ End Of BPB ================ 59 Bytes intotal ==========

; ============ MBR 主程序执行区 =======================================
_Entry_MBR_Code:                                    ; 进入程序
   
    MOV AX , CS                                     ; CS寄存器的初始值 0x0000
    MOV BX , AX
    MOV CX , AX
    MOV DS , AX
    MOV ES , AX
    MOV SS , AX
    MOV BP , AX
    MOV SP , cStack_Base                            ; 初始化寄存器

    CALL Func_Clean_Screen                          ; 清理屏幕
    CALL Func_Reset_Floppy                          ; 在读取之前初始化软盘状态

    MOV WORD[vSec_Order_Num]  , cRoot_Fst_Sec         ; 从BPB取得要读的扇区号
    MOV WORD[vSec_toRead_Num] , cRoot_Length_Sec      ; 从BPB取得共要读扇区数

    _Search:
        CMP WORD[vSec_toRead_Num] , 0
        JZ _No_Loader
        DEC WORD[vSec_toRead_Num]

        MOV AX , cLoader_Base
        MOV ES , AX
        MOV BX , cLoader_Offset

        MOV AX , cRoot_Fst_Sec           ; 从根目录起始扇区号开始读起
        MOV CL , 1                      ; 连续读取的扇区数
        CALL Func_Read_Sec              ; 调用函数，读取一个扇区到内存缓冲区

        MOV SI , vName_Loader
        MOV DI , cLoader_Offset
        CLD

        MOV DX , 0x10                   ; 要对比文件名的文件的个数（递减）
        ;一个扇区（512）内存放的文件目录条目（32）可以有512 / 32 = 16个，即0x10

        _Search_CMP_Ready:
            CMP DX , 0
            JZ _Search_Next_Sec
            DEC DX
            MOV CX , 11
            JMP _Search_CMP

            _Search_Next_Sec:                   ; 该扇区搜索完毕，没有发现目标，转向下一个扇区
                ADD WORD[vSec_Order_Num] , 1
                JMP _Search

            _Search_CMP:
                CMP CX , 0
                JZ _Found_Loader
                DEC CX

                LODSB                   ; 把SI指向存储单元的内容读入累加器

                CMP AL , BYTE[ES:DI]
                JZ _Search_CMP_GOON
                JMP _Not_to_Find 

            _Search_CMP_GOON:
                INC DI                  ; 使DI指向读入文件名的下一个字符
                JMP _Search_CMP         ; 继续对比

            _Not_to_Find:                       ; 对比的文件名不是要找的文件
                AND DI , 0xFFE0                 ; 0xFFE0（1111 1111 1110 0000）用于使DI对齐
                ADD DI , 0x20                   ; 0x20 (32)，DI指向下一个文件条目的32字节结构体开头处
                MOV SI , vName_Loader           ; 使SI重新指向目标文件名的开头
                JMP _Search_CMP_Ready           ; 跳转并继续，开始对比下一个读入的文件

    _Found_Loader:
        MOV AX , cRoot_Length_Sec
        AND DI , 0xFFE0
        ADD DI , 0x1a

        MOV CX , WORD[ES:DI]
        PUSH CX
        ADD CX , AX
        ADD CX , (cRoot_Fst_Sec - 2)

        MOV AX , cLoader_Base
        MOV ES , AX
        MOV BX , cLoader_Offset
        MOV AX , CX
        G_LOADING:
            PUSH AX
            PUSH BX
            MOV AH , 0x0e
            MOV AL , '*'
            MOV BL , 0x0f
            INT 0x10
            POP BX
            POP AX

            MOV CL , 1 
            CALL Func_Read_Sec
            POP AX
            CALL Func_Get_Next_FAT
            CMP AX , 0x0ff8
            JAE _LOADED
            PUSH AX
            MOV DX , cRoot_Length_Sec
            ADD AX , DX
            ADD AX , (cRoot_Fst_Sec - 2)
            ADD BX , [BPB_BytesPerSec]
            JMP G_LOADING

    _LOADED:
        MOV BP , vLoad_MSG
        CALL Func_Disp
        JMP cLoader_Base:cLoader_Offset

    _No_Loader:
        MOV BP , vNo_Loader_MSG
        CALL Func_Disp
        JMP _HLT

    _HLT:
        HLT
        JMP _HLT







; =================== 函数模块定义区 Functions ============================
Func_Reset_Floppy:                  ; 复位软盘，初始化AX和DX
    XOR AX , AX
    XOR DX , DX
    INT 0x13
    RET

Func_Read_Sec:                      ; 调用该函数的参数：CL（要读的扇区数）AX(要读的起始扇区号),改变了DL的值
    Read_Sec_Ready:                 ; 初始值：SP = BP = 0x7c00，SS = 0
    PUSH    BP                      ; 备份BP的值以便之后恢复
    MOV     BP  , SP                ; 将SP的值存入BP，栈从这里开始

    SUB     ESP , 2                 ; Push和Pop指令先更改栈指针ESP的值再存入或取出站中的数据，所以存入BX时栈中CL的值不会被BH覆盖
    MOV     BYTE[BP - 2], CL        ; 在栈中存入CL(存放要读的扇区数)的值，但不移动栈指针

    PUSH    BX                      ; 备份数据缓冲区地址。备份数据缓冲区地址，以便使用BL寄存器。
    MOV     BL  , [BPB_SecPerTrk]   ; BL用于存放除数（每个磁道的扇区数），被除数在AX中
    DIV     BL                      ; 被除数AX必须是LBA扇区号，执行除法运算，商在AL中，余数在AH中
    INC     AH                      ; 余数+1得该柱面起始扇区号

    MOV     CL  , AH                ; · CL 作为INT 0x13的参数，读盘的起始扇区号
    MOV     DH  , AL                ; 除法运算的商按位与1得到C/H/S磁头号
    AND     DH  , 1                 ; · DH 作为INT 0x13的参数，读盘的磁头号

    SHR     AL  , 1                 ; 除法运算的商右移一位得到C/H/S柱面号
    MOV     CH  , AL                ; · CH 作为INT 0x13的参数，读盘的C/H/S柱面号
                                    ; · BX 作为INT 0x13的参数，[ES:BX] 是读盘的数据缓冲区
    POP     BX                      ; 从栈中将缓冲区偏移地址取回
    MOV     DL  , [BS_DrvNum]       ; · DL 作为INT 0x13的参数，存放驱动器号

    ; ---------以上代码通过公式计算得到起 始扇区，磁头号，柱面号。以及参数BX，DL-------------
    
    Read_Sec_Go:                    ; 以下代码传入AH(0x02)和AL(要读取的扇区数)
    MOV     AH  , 0x02              ; INT 0x13读盘功能号
    MOV     AL  , BYTE[BP-2]        ; 将函数开头存入的要读取的扇区数的值取回AL,与Read_Sec_Ready开头的栈操作首尾呼应

    INT     0x13                    ; 执行中断，读取磁盘，如果失败则CF标志位被设置为1，否则为0
    JC      Read_Sec_Go             ; 由于软盘质量问题，读取失败只能重来，直到读取成功,实际虚拟机模拟过程中应该不会出现失败的情况

    ADD     ESP , 2                 ; 这两句用于在执行完从Read_Sec_Ready到INT 0x13后
    POP     BP                      ; 将栈、栈底、栈顶指针恢复原状
    
    RET                             ; 函数执行完毕。整个读盘函数实现了从LBA扇区号转换为C/H/S并将指定扇区数读取到ES:BX为首地址的内存缓冲区中

Func_Clean_Screen:                  ; 清空屏幕
	MOV AX ,	0x0600
	MOV BX ,	0x0700
	MOV CX ,    0
	MOV DX ,	0x184f
	INT 0x10
    XOR DX , DX
    RET

Func_Get_Next_FAT:
    PUSH ES
    PUSH BX
    PUSH AX                         ; 保存FAT表项号

    MOV AX , 0x00
    MOV ES , AX                     ; 将ES赋值为0

    POP AX

    MOV BYTE[ODD] , 0               ; 奇数标志，置为0

    MOV BX , 3                      ; 
    MUL BX
    MOV BX , 2
    DIV BX
    CMP DX , 0
    JZ _Even_Num

    MOV BYTE[ODD] , 1

    _Even_Num:
        XOR DX , DX 
        MOV BX , [BPB_BytesPerSec]
        DIV BX
        PUSH DX
        MOV BX , 0x8000
        ADD AX , 1
        MOV CL , 2
        CALL Func_Read_Sec

        POP DX
        ADD BX , DX
        MOV AX , [ES:BX]
        CMP BYTE[ODD] , 1
        JNZ _Even_Then
        SHR AX , 4

        _Even_Then:
            AND AX , 0x0FFF
            POP BX
            POP ES
            RET

Func_Disp:
    PUSH AX
    PUSH BX
    PUSH CX
    PUSH DX
    PUSH ES
    MOV AX , 0x1301
    MOV BX , 0x000c
    MOV CX , 6
    XOR DX , DX
    MOV ES , DX
    INT 0x10
    POP ES
    POP DX
    POP CX
    POP BX
    POP AX
    RET

; =================== 变量声明区域 ========================================

vSec_toRead_Num:                    ; 剩余多少个待读取扇区
    DW 0

vSec_Order_Num:                     ; 要读的扇区的LBA扇区号
    DW 0

vLoad_MSG:
    DB "LOADED"
    DB 0x0a , 0x0a
          ; 字符串结尾
    MSG.length.Load:         DB ($ - vLoad_MSG)

vNo_Loader_MSG:
    DB "Error."
    DB 0x0a , 0x0a
          ; 字符串结尾
    MSG.length.No_Loader:    DB ($ - vNo_Loader_MSG)

vName_Loader:
    DB "LOADER  BIN" , 0        ;字符串结尾
    
ODD:
    DB 0

_End_MBR:
    TIMES 0x1fe - ($ - $$) DB 0         ; 填充剩余部分为 0
    DW 0xAA55                      ; MBR 引导扇区结束标志
