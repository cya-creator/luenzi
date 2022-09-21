;FAT32文件系统的引导扇区/////////////////////////////////////////////////////////////////////////\
\
|2022年9月12日16时12分~年月日时分\
编写完成\
@cya\
\
\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\

;/////内存布局////\
7c00～7e00_boot.asm 512字节\
8000～？_loader.asm
org 7c00h;历史遗留的起始位置

;/////BPB/////\
bpb表不用修改，他只是用来占位而已\
12~?字节为BPB部分？
jmp 初始化寄存器;略过下面的干扰去执行引导程序,3个字节
取个你喜欢的名字 db "lunzi os";8个字节
扇区大小 dw 512;默认512，2个字节 
每个簇占用的扇区数量 db 1;默认8，8h×512b=4k，1个字节
保留扇区数 dw 32;2个字节
;16字节

FAT表总数 db 2;默认2，1个字节
根目录可容纳目录数 dw 0;历史字段，FAT32不适用，2个字节
分区总扇区数 dw 0;小于32m，在这记录，大于32m，改totalsectors，2个字节
设备类型 db 248;0xf8表示硬盘，1个字节
FAT表大小扇区数 dw 0;硬盘FAT32已经不使用了，2个字节
磁道扇区数 dw 63;每个磁道扇区数 s   >不同硬盘改动，一般为“3fh   00h”，2个字节
磁头数 dw 16;磁头数 h   >修改，一般为“ffh   00h”，即每个柱面有255个磁头，2个字节
FAT区前隐藏扇区数 dd 0;分区目前已使用 隐藏扇区数，4个字节
;16字节

扇区总数 dd 73584;大于32m这里修改扇区数，对于大硬盘来说该处存放的是该分区占用的扇区数，4个字节
每个FAT表使用扇区数 dd 566;每个FAT表使用扇区数 ，4个字节
FAT表同步标识 dw 0;标记，2个字节;;最左端二进制位为零则所有FAT表是同步的，为1则有损坏的FAT表。低4位表示在用的FAT表编号，从零开始计
版本号 dw 0;文件系统格式版本号，2个字节
根目录起始簇号 dd 2;根目录簇号 4个字节 起始于数据区的 + 2个簇，4个字节
;16字节

文件系统信息 dw 1;存放文件系统格式信息的扇区号，2个字节
引导备份 dw 6;备份引导扇区 位于文件系统的6号扇区，2个字节
未使用12字节 db 0;预留，12字节未使用
;以上共16字节

驱动器号 db 159;硬盘为“80h”，一般软盘为“00h
未使用1字节 db 0;预留，1个字节
扩展引导标记 db 41;扩展引导标记，1个字节
磁盘序列号 dd 0;4个字节
磁盘标签 db "no     name";windows显示硬盘的名字，如果没有卷标此处通常为字符串no   name，11个字节
文件系统 db "FAT   32";，文件系统标识，对于FAT32文件系统此处常为FAT32，8个字节
;以上共30字节

;//////////
初始化寄存器:;添加更多寄存器组合方式的注释
mov ax,cs;代码段，cs：ip
mov ds,ax;数据段，ds：si
mov es,ax;附加段，es：di
mov ss,ax;堆栈段，ss：sp
mov bp,ax;栈游标，ss：bp
mov sp,ax;栈顶，不可随意触动

;/////前奏/////
mov byte ds:[驱动器号],dl;先保存驱动器号
;清空屏幕
mov ax,3
int 10h
mov si,欢迎;指向要显示的字符,柚子厨狂喜
call 显示

;/////计算起始数据/////
xor eax,eax
mov [fat_sector],eax

mov ax,[保留扇区数];没有 movzx eax，字...需要
add eax,[FAT区前隐藏扇区数]
mov [fat_start],eax;第一个 FAT 扇区
mov [data_start],eax;（仅值的第一部分）
;接下来，找到data_start：
mov eax,[FAT表总数];不需要 movzx ...字节
;bsFATs db 之后的 2 dw 根据 FAT32 定义为 0 :-)
imul dword[每个FAT表使用扇区数];（也改变edx）
add [data_start],eax;第一个 DATA 扇区
;（添加 RAM 更短！）
;最后，找到 fat_secshift
mov ax,512;默认扇区大小（表示默认移位）

尝试其他扇区大小:
 cmp ax,[扇区大小]
 jz 确定大小
 inc word[fat_secshift];最初是 9-2（字节！）
jmp short 尝试其他扇区大小

确定大小:
mov eax,ds:[根目录起始簇号]
; mov al,byte[FAT表总数];mul乘法指令，一个数放在a某寄存器，完事后结果也放在a某寄存器
; mul word[每个FAT表使用扇区数];× FAT表个数=#
; add ax,word[保留扇区数];+#
; mov word[数据扇区],ax;数据区 起始位置
;下面的可能错误了
;(根目录可容纳的目录项数×32 + 每个扇区字节数 - 1) / 每个扇区字节数 =根目录占用扇区数
;(224 * 32 + 512 - 1) / 512 =14
;/////////\
乘法\
al×bl =ax，被乘数×被乘数 =积\
ax×bx =dx高：低ax\
（根目录可容纳目录数×每个目录条目长32）÷扇区大小 =根目录占用区扇区数;fat32不再使用以后会跳过的
; mov ax,32
; mul word ds:[根目录可容纳目录数];ax×内存单元 =dx高：低ax
; xor dx,dx;清空高位
; div word ds:[扇区大小];dx高：ax低÷内存单元 =ax……dx
; mov bx,ax;这是根目录占用的扇区数
;/////检索文件/////
查下一个簇:
 push eax;保存目前的簇号
 call 簇转LBA;把簇号转换为lba
 jc 簇找完了;簇转LBA时发现簇查完了
    查下一个扇区:
     mov bx,8000h
     ;mov es,bx
     ;les bx,[loadsegoff_60];高位放入es，低位放入你指定的寄存器
     call 读盘
     xor di,di;es:di，文件名目标地址

        查下一个目录项:;在这里循环的寻找目标文件
         mov si,要搜索的文件名;文件名源地址
         mov cx,11;文件名长度，必须是11
         repe cmpsb;比较si，di，重复cx次数
         jcxz 找到了文件;cx是零则跳转，注意 di 现在是+11
         add di,byte 32;每个目录项的尺寸，其结构如上所示?
         and di,byte -20h;0ffe0h
         cmp di,[扇区大小];这个扇区查完了吗？
        jnc 查下一个目录项;没有就继续本扇区的

     dec dx;簇中的下一个扇区==============注意读盘参数
    jnz 查下一个扇区;好吧dx还没减到零

 pop eax;推进到下一个簇号
 call 计算下一个簇号
jmp 查下一个簇

;/////载入文件/////
找到了文件:
mov si,找到文件
call 换行显示
mov si,要搜索的文件名
call 显示

push word [es:di+14h-11];获取簇号 HI
push word [es:di+1ah-11];获取簇号 LO
pop eax;转换为 32位
sub bx,bx;ES 指向 加载段，（内核-> ES:BX）

read_kernel:
 push eax
 call 簇转LBA
 jc 载入完成;EDX 是簇中的扇区，EAX 是扇区

    rk_in_cluster:
     call 读盘
     dec dx
    jnz rk_in_cluster

 pop eax
 call 计算下一个簇号
jmp read_kernel

载入完成:
mov dl,byte ds:[驱动器号];传递一些参数
jmp  0:8000;远眺至目标far

;//////////
簇找完了:
mov si,没有文件
call 换行显示
mov si,要搜索的文件名
call 显示
jmp $;先停在这里

;//////////
;按任意键即往下执行
MOV AH,00H
INT 16H;键盘中断

;关机\
禁用ACPI，就会失效
MOV AX,5307H;高级电源管理功能,设置电源状态 
MOV BX,0001H;设备ID,1:所有设备 
MOV CX,0003H;状态,3:表示关机 
INT 15H

jmp $;停

;/////////\
给定一个簇编号，找出下一个簇的编号\
FAT 链表需要 fat_secshift 和 fat_start\
输入\
eax >簇号\
输出\
eax >下一个簇号
计算下一个簇号:
push es
push di
push bx

mov di,ax
shl di,2;32位 fat

push ax
mov ax,[扇区大小]
dec ax
and di,ax;屏蔽扇区大小
pop ax
shr eax,7;例如 9-2 代表 512 by/sect

fat_afterss:
add eax,[fat_start]
mov bx,2000;FATSEG
mov es,bx
sub bx,bx

cmp eax,[fat_sector];已经缓冲了？
jz cn_buffered
mov [fat_sector],eax;缓冲扇区数
call 读盘

cn_buffered:
and byte[es：di+3],0fh;屏蔽前4位
mov eax,[es：di];读取下一个簇号

pop bx
pop di
pop es
ret


;//////////
;某簇起始LAB逻辑扇区号 = 保留扇区数 + 每个FAT表大小扇区数 × FAT表个数 + (该簇簇号 - 2) × 每簇扇 区数
;计算 起始数据簇 的位置 放入寄存器 ax
;/////簇号转换////\
将会修改ax寄存器\
或者如果 EndOfChain 则返回进位！需要 data_start\
输入\
eax >目标集群\
输出\
eax >绝对扇区
; EDX - [bsSectPerClust]（字节）
; 随身携带
; （如果进位设置，EAX/EDX 不变，链结束）
簇转LBA:
cmp eax,00ffffff8h;如果链表结束
jnb 链表末端

dec eax
dec eax

movzx edx,byte [每个簇占用的扇区数量]
push edx
mul edx
pop edx
add eax,[data_start]
ret;此时进位未设置（除非参数错误）

链表末端:
stc;通过进位表示参数错误
ret

;/////显示字符////\
将会修改ax，bx，si寄存器\
输入\
ds：si >字符地址\
输出\
自行查看显示器
换行显示:
push si;保存原来的字符
mov si,换行
call 显示
pop si;现在可以显示原来的字符了
call 显示
ret

显示:
 xor bx,bx
 mov ah,14;BIOS中断参数：中断模式
 int 10h
 lodsb;加载下一个字符
 or al,al;判断[di]中的字符值是否 =0
jne 显示
ret

;/////读取硬盘////\
将会修改ax，bx，dx，si寄存器\
从硬盘读取一个扇区数据\
输入\
eax >lba 低 32 位\
es：bx >缓冲区段\
ds：si >磁盘地址包\
输出\
es：bx >目标位置
读盘:;读硬盘调用+增加dpa包 是加扇区
mov word [DAP+2],1;计数
mov word [DAP+4],dx;抵消
mov word [DAP+6],ax;段
mov word [DAP+8],eax;lba低32位
mov dword [DAP+12],0;lba高32位

xor bx,bx
mov si,DAP;参数被保存在堆栈里
mov dl,byte ds:[驱动器号]
mov ah,42h;扩展调用
int 13h
ret

;/////////\
这里可能会产生未知错误
; pop cx;恢复cx=要读几个扇区
; pop bx;恢复bx=要写出扇区到内存的地址
; pop ax;恢复ax=簇起始LBA逻辑扇区
; add bx,word[扇区大小]; bx += 扇区字节数 指向下一个要写出的地址
; inc ax; ax += 1  逻辑扇区 +1 下一个被读取扇区
; loop 读取扇区 ; cx -1 循环读取一个扇区
; ret

; 簇转LBA:
; sub ax,2
; xor cx,cx
; mov cl,byte[每个簇占用的扇区数量]
; mul cx
; add ax,word[数据扇区]
; ret

;/////被调用的参数/////
根目录起始扇区号 dw 0000h
根目录占用扇区数 db 00
目标文件名长度 equ 11
要搜索的文件名 db 'LOADER  BIN';在 fat文件系统 里所有保存的文件名都是大写
换行 db 13,10,0 

DAP:;磁盘地址数据包
db 10h;[0]：数据包大小，以字节
db 0;[1]：保留，必须为 0 
db 0;[2]:要传输的块 (0~127) 
db 0;[3]：保留，必须为 0 
dw 0;[4]:buf 地址（偏移量） DWORD >传输缓冲区
dw 0;[6]:buf 地址(段) 
dd 0;[8]：lba低32位
dd 0;[12]：lba高32位

fat_sector dd 0
fat_start dd 0
data_start dd 0
fat_secshift equ fat_afterss-1

;/////显 示的字符/////
欢迎 db "Ciallo~(L",249,"w<)^*",13,10,0;249 是一个点
没有文件 db 'Nw',0;没有找到loader，0是判断数
找到文件 db 'Tu',0;
times 510-($-$$) db 0
dw 0xaa55
;注意\
我们不能在引导扇区耽误太多时间