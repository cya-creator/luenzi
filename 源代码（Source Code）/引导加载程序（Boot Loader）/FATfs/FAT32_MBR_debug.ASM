;=======================================================================
;FAT32文件系统的引导扇区

;2022年9月12日16时12分~2022年11月21日9时34分\
;编写完成\
@cya

;2022年11月24日14时40分~2022年11月日时分\
;修复文件过多时检索错误，修改传递的参数\
@cya

;————————————————————————————————————
;内存布局
;7c00～7e00_boot.asm
org 7c00h;历史遗留的起始位置

;/
;bpb表不用修改，他只是用来占位而已
;12~?字节为BPB部分？
jmp short 初始化寄存器;略过下面的干扰去执行引导程序,3个字节
nop;别漏了这个
取个你喜欢的名字 db 'FrLdr1.0';8个字节
扇区大小 dw 512;默认512，2个字节 
每个簇占用的扇区数 db 0;默认8，8h×512b=4k，1个字节
保留扇区数 dw 32;2个字节
FAT表总数 db 2;默认2，1个字节
根目录可容纳目录数 dw 0;历史字段，FAT32不适用，2个字节
分区总扇区数 dw 0;小于32m，在这记录，大于32m，改totalsectors，2个字节
设备类型 db 0f8h;0xf8表示硬盘，1个字节
FAT表大小扇区数 dw 0;硬盘FAT32已经不使用了，2个字节
磁道扇区数 dw 0;每个磁道扇区数 s   >不同硬盘改动，一般为“3fh   00h”，2个字节
磁头数 dw 0;磁头数 h   >修改，一般为“ffh   00h”，即每个柱面有255个磁头，2个字节
FAT区前隐藏扇区数 dd 0;分区目前已使用 隐藏扇区数，4个字节
扇区总数 dd 73584;大于32m这里修改扇区数，对于大硬盘来说该处存放的是该分区占用的扇区数，4个字节
每个FAT表使用扇区数 dd 566;每个FAT表使用扇区数 ，4个字节
FAT表同步标识 dw 0;标记，2个字节;;最左端二进制位为零则所有FAT表是同步的，为1则有损坏的FAT表。低4位表示在用的FAT表编号，从零开始计
版本号 dw 0;文件系统格式版本号，2个字节
根目录起始簇号 dd 2;根目录簇号 4个字节 起始于数据区的 + 2个簇，4个字节
文件系统信息 dw 1;存放文件系统格式信息的扇区号，2个字节
引导备份 dw 6;备份引导扇区 位于文件系统的6号扇区，2个字节
未使用12字节 dd 0,0,0;预留未使用，你不用是吗 我用，，嗯。刚好够
驱动器号 db 159;硬盘为“80h”，一般软盘为“00h
未使用1字节 db 0;预留，1个字节
扩展引导标记 db 41;扩展引导标记，1个字节
磁盘序列号 dd 0;4个字节
磁盘标签 db 'NO NAME    ';windows显示硬盘的名字，如果没有卷标此处通常为字符串no   name，11个字节
文件系统 db 'FAT32   ',0;，文件系统标识，对于FAT32文件系统此处常为FAT32，8个字节

;//
初始化寄存器:;添加更多寄存器组合方式的注释
nop
nop
nop
mov ax,cs;代码段，cs：ip
mov ds,ax;数据段，ds：bx，si，di
mov ss,ax;堆栈段，ss：sp，bp
mov sp,7c00h; 堆栈基地址，一般情况，此时的堆栈只是临时的，到了加载模块时还要重新设置
;mov bp,sp;栈游标，ss：bp
mov ax,7e00h;用于读入位置赋值
mov es,ax;附加段，es：di
mov ax,2000h
mov fs,ax
cld;清空df并向前推进


;/
mov byte ds:[驱动器号],dl;先保存驱动器号
;清空屏幕
mov ax,3
int 10h

mov si,文件系统
call 显示


;///
;计算参数，必要
;乘法
;al×bl =ax，被乘数×被乘数 =积
;eax×ebx =edx高：低eax
;首先计算根目录扫描次数
movzx ax,byte ds:[每个簇占用的扇区数]
mul word ds:[扇区大小];ax×内存单元 =dx高：低ax
mov bp,ax;使用持久寄存器保存值

xor eax,eax
mov [未使用12字节],eax;初始化缓冲区状态

;然后计算fat起始
mov ax,[保留扇区数];没有 movzx eax，字...需要
add eax,dword ds:[FAT区前隐藏扇区数]
mov dword ds:[未使用12字节+4],eax;第一个 FAT 扇区
mov dword ds:[未使用12字节+8],eax;数据区起始，仅值的第一部分

;最后计数数据区起始
mov eax,dword ds:[FAT表总数];不需要 movzx ...字节，bsFATs db 之后的 2 dw 根据 FAT32 定义为 0 :-)
mul dword ds:[每个FAT表使用扇区数]
add dword ds:[未使用12字节+8],eax;第一个数据扇区，全部值


;/
;在根目录中检索文件，必要
;输入
;>根目录起始簇号
;bp >查找次数
;输出
;ax >目标文件的第一个簇号
mov eax,dword ds:[根目录起始簇号]
查下一个簇:
 push eax;保存目前的簇号
 call 簇转LBA;簇号转换为绝对扇区号，返回值中EcX是每个簇的扇区数，EAX是扇区号 
 jc 簇找完了;簇转LBA时发现簇查完了

 ;bx;根目录只占用一个扇区吗，还是簇占用的扇区数
 mov dx,es;读取到的段地址，使用es的值以便配合di
 xor bx,bx
 call 读盘
 ;jmp 7e00h:0;测试通过

    xor di,di;es:di，文件名目标地址
    下一个目录项:;在这里循环的寻找目标文件
     mov si,要搜索的文件名;文件名源地址
     mov cx,11;文件名长度，也是比较的次数，正确一个就减1

     push di;保存di以免被repe破坏
     repe cmpsb;比较si，di，重复cx次数
     pop di;覆盖推动过的di
     jcxz 找到了文件;cx是零则跳转
 
     ;and di,0ffe0h;FFE0h（1111 1111 1110 0000）用于使DI对齐
     add di,32;20h，DI指向下一个文件条目的32字节结构体开头处
     cmp di,bp;查完了吗？
    jb 下一个目录项;小于则跳转

 pop eax;推进到下一个簇号
 call 计算下一个簇号
jmp short 查下一个簇


;/
找到了文件:
mov si,找到文件
call 换行显示
mov si,要搜索的文件名
call 显示

push word es:[di+14h];获取簇号 HI
push word es:[di+1ah];获取簇号 LO
pop eax;转换为 32位


继续读取:
 push eax
 call 簇转LBA;EcX 是簇中的扇区，EAX 是扇区
 jc 载入完成

 mov dx,es;会被计算下一个簇号破坏的段地址所以用es弄回去
 call 读盘
 mov  di,cx;转完簇后再添加读入的扇区数
 add di,bp;还记得吗？这是我们一开始计算的簇占用扇区数

 pop eax
 call 计算下一个簇号

 mov cx,di;增加读取的偏移量即可，希望不会遇到64k段问题
jmp short 继续读取

载入完成:
mov dl,byte ds:[驱动器号];传递一些参数
jmp 7e00h:0;我的同行抖机灵只读一个簇就跳转过去了，让他解析表项自己读完自己，这样好吗？这样不好


;/
簇找完了:
mov si,没有文件
call 换行显示
mov si,要搜索的文件名
call 显示
jmp $;先停在这里


;/
;按任意键即往下执行
MOV AH,00H
INT 16H;键盘中断

;关机禁用ACPI，就会失效
MOV AX,5307H;高级电源管理功能,设置电源状态 
MOV BX,0001H;设备ID,1:所有设备 
MOV CX,0003H;状态,3:表示关机 
INT 15H

jmp $;停


;/
;给定一个簇编号，找出下一个簇的编号
;FAT 链表需要 fat_secshift 和 fat_start
;输入
;eax >簇号
;输出
;eax >下一个簇号
;((簇-2)*每个集群的扇区数)+保留扇区+隐藏扇区 =起始扇区号
计算下一个簇号:
mov si,ax;未使用Eax的高字节
shl si,2;* 4（因为 FAT32 条目是 4 个字节）

push ax
mov ax,word ds:[扇区大小]
dec ax;扇区大小减1
and si,ax;屏蔽扇区大小，扇区内的 FAT 偏移 = ECX % BytesPerSector 
pop ax

shr eax,7;例如 9-2 代表 512 by/sect
add eax,dword ds:[未使用12字节+4];你得到了lba号

cmp eax,dword ds:[未使用12字节];已经缓冲了？
jz 读取簇号
mov dword ds:[未使用12字节],eax;使用lba号进行标记
mov dx,fs;将簇读取到，2000：0000h
xor bx,bx
movzx cx,byte ds:[每个簇占用的扇区数]
call 读盘

读取簇号:
and byte fs:[si+3],0fh;屏蔽前4位
mov eax,dword fs:[si];读取下一个群集编号

ret


;/
;将会修改ax寄存器
;输入
;eax >目标簇号
;输出
;eax >lba号
;如果链表末端则进位设置，eax/edx 不变，链表结束
;乘法
;al×bl =ax，被乘数×被乘数 =积
;eax×edx =edx高：低eax
簇转LBA:
cmp eax,0ffffff8h;如果链表结束
jnb 链表末端;需要在这里拦截否则会出现乘法错误

;（簇号-2）×每个簇占用的扇区数+数据区起始扇区号 =簇的lba号
dec eax
dec eax

movzx ecx,byte ds:[每个簇占用的扇区数]
mul ecx

add eax,dword ds:[未使用12字节+8];数据区起始扇区号
ret;此时进位未设置，除非参数错误

链表末端:
stc;通过进位表示参数错误
ret


;///
;显示字符，可删
;将会修改ax，bx，si寄存器
;输入
;ds：si >字符地址
;输出
;自行查看显示器
换行显示:
push si;保存原来的字符
mov si,换行
call 显示
pop si;现在可以显示原来的字符了

显示:;每个指令都很重要确保他们被正确执行
 lodsb;将ds：si指向的内容放入al然后si+1
 or al,al;判断[al]中的字符值是否 =0
 jz 是零
 xor bx,bx
 mov ah,14;BIOS中断参数：中断模式
 int 10h
jmp short 显示

是零:
ret


;//
;将会修改ax，bx，dx，si寄存器
;从硬盘读取一个扇区数据
;输入
;eax >lba 低 32 位
;bx >段地址
;cx >读入扇区数
;dx >偏移地址
;si >磁盘地址包
;输出
;dx：bx >目标位置
读盘:;读硬盘调用+增加dpa包 是加扇区
push dword 0;[12]lba高32位
push eax;[8]lba低32位
push dx;[6]段地址
push bx;[4]偏移地址
;byte[3]保留，必须为0，注意堆栈只能压word
push cx;[2]要传输的块数0~127
;byte[1]保留，必须为0，cx的高位就是这里的值应当清空ch寄存器，堆栈只能压word
push byte 16;[0]参数块大小

mov si,sp;注意堆栈是反过来的
;mov byte ds:[si+2],cl
mov dl,byte ds:[驱动器号]
mov ah,42h;扩展调用
int 13h
add sp,16;从堆栈中删除参数块
jc 读盘错误;如果读取失败则中止
ret

读盘错误:
mov si,没有文件
call 换行显示

jmp 簇找完了


;/
要搜索的文件名 db 'KERNEL  SYS';在 fat文件系统 里所有保存的文件名都是大写
换行 db 13,10,0 

没有文件 db 'hooo',0;没有找到loader，0是判断数
找到文件 db 'Tu ',0;

times 510-($-$$) db 0
dw 0xaa55
;注意\
我们不能在引导扇区耽误太多时间
