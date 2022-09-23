

;运行逻辑\
—\
—\
—\
—\
—\
—\
—\
—\
—












;reserve《保留》\
表示从当前位置保留指定数量的字节，不定义它们的值\
可用于保存已编译的内容或保留来自其他程序的数据\
如果编译器不填充数据，仅表示跳过指定字节数\
在空内存中且编译器未填充数据，《resb 1，resd 1》相当于《db 0,dd 0》

absolute 4096;低于此点的内存为 BIOS 和 MBR 保留\
跟 equ 有异曲同工之妙

轨道缓冲区 resb 8219;轨道缓冲区在这里
轨道缓冲区大小 equ $-轨道缓冲区;轨道缓冲区在 3000h 结束

;//////////
struc open_file_t
文件扇区 resd 1;扇区指针《0 =无结构》
剩余扇区数 resd 1
endstruc

;//////////
struc dir_t
目录开始 resd 1;LBA 目录 开始
字节长度 resd 1
簇长度 resb 1
endstruc

;//////////
最大打开文件数 equ 2;log2《最大打开文件数》
MAX_OPEN equ (1 << 最大打开文件数)
扇区大小_LG2 equ 11;2048 字节/扇区《El Torito 要求》
扇区大小 equ (1 << 扇区大小_LG2);SECTORSIZE_LG2

;//////////
absolute 20480;在这里，我们保留 BSS 的数据
驱动器号 resb 1;CD-ROM 的驱动器号
磁盘错误 resb 1;磁盘 I/O 的错误代码
重试次数 resb 1;用于磁盘访问重试
iso标志 resb 1;ISO 目录搜索的标志
根目录 resb dir_t_size
当前目录 resb dir_t_size
iso文件名 resb 64;ISO 文件名规范化缓冲区
iso文件名结束 equ $

;//////////
alignb open_file_t_size
文件 resb MAX_OPEN*open_file_t_size

;//////////
section .text
org 28672;7000h

;//////////
开始:;设置我们的堆栈和平面寻址模型
cli
xor ax,ax
mov ss,ax
mov sp,开始
mov ds,ax
mov es,ax
mov fs,ax
mov gs,ax
sti

;/////////\
清空屏幕
mov ax,3
int 16

;/////////\
把引导代码从 0000+7C00 位置拷贝到 0000+7000 位置，然后再运行
mov cx, 2048 >> 2
mov si,31744;从 0000+7C00
mov di,28672;到 0000+7000
rep movsd;复制程序
jmp 0:开机;跳转到重定位代码

;/////////\
BISO 给了我们一个引导驱动器号，如果没有问题，我们将使用那个\
不幸的是，周围有许多损坏的 BISO，所以 ISOLINUX 会尝试修复它们\
让我们在这里做同样的事情以获得最大的兼容性
开机:
mov si,欢迎
call 显示
;使用 int 13h 参数 4b01h《获取磁盘仿真状态》获取 El Torito Spec 数据包\
我们可以使用此信息来验证我们传递的引导驱动器号是否确实属于我们的 cd-rom
mov ds:[驱动器号],dl
mov ax,19201;获取磁盘仿真状态《4b01h》
mov dl,byte ds:[驱动器号]
mov si,规格包;《13h》
;call int13h;如果这个 int 13h 调用产生错误，我们可能是在一个损坏的 AWARD BIOS 上
int 13h
;jc 检查并修复
mov dl,byte ds:[驱动器号]
cmp byte ds:[色批驱动器],dl;应该包含驱动器号
;jne 规格查询失败


	mov	ah, 48h
	mov	dl, [驱动器号]
;//////////
找到驱动器:
;清除文件结构
mov di,文件
mov cx,(MAX_OPEN*open_file_t_size)/4
xor eax,eax
rep stosd;循环\
在扇区 16《32K》读取整个 2K 大小的 ISO9660 主卷描述符\
mkisofs 给了我们一个指向主卷描述符的指针\
此计算仅适用于单会话 ISO，但我们永远不会遇到其他任何情况，来自 PVD
mov eax,16;主卷描述符《扇区 16》
mov bx,轨道缓冲区
call 一个扇区

;读取根 目录《主卷描述符中的偏移量 156》的 LBA 地址《目录记录中的偏移量 2》
mov eax,dword ds:[轨道缓冲区+156+2]
mov dword ds:[根目录+目录开始],eax
mov dword ds:[当前目录+目录开始] ,eax

;读取根目录《主卷描述符中的偏移量 156》的数据长度《目录记录中的偏移量 10》
mov eax,dword ds:[轨道缓冲区+156+10]
mov dword ds:[根目录+字节长度],eax
mov dword ds:[当前目录+字节长度],eax

;计算簇的数量并将其写入我们的根目录和当前目录结构
add eax,扇区大小-1
shr eax,扇区大小_LG2
mov dword ds:[根目录+簇长度],eax
mov dword ds:[当前目录+簇长度],eax

;搜索“LOADER”目录《目录由AL =2 使用 搜索 iso 目录时》\
如果找到，使其成为当前目录而不是根目录目录
mov di,loader目录
mov al,2
call 搜索iso目录
jnz 找到目录
;找不到目录
mov si,没有loader目录
call 换行显示
jmp 关机

;/////////\
目录找到了，所以更新我们CurrentDir结构中的信息\
在进程中释放 SI 处的文件指针入口
找到目录:
mov dword ds:[当前目录+字节长度],eax
mov eax, dword ds:[si+剩余扇区数]
mov dword ds:[当前目录+簇长度],eax
xor eax,eax;释放此文件指针条目
xchg eax,dword ds:[si+文件扇区]
mov dword ds:[当前目录+目录开始],eax

;搜索“loader.bin”文件
mov di,装载机;di 指向 Isolinux 文件名
call 搜索目录
jnz 找到装载机
;找不到装载机
mov si,没有装载机
call 换行显示
jmp 关机

;/////////\
计算需要读取的 2K 扇区的四舍五入数
找到装载机:
mov di,si;保存文件指针
mov ecx,eax;计算扇区数
shr ecx,11;扇区转换
test eax,2047;7ffh
jz 加载装载机
inc ecx

;加载整个loader.bin
加载装载机:
mov bx,8000h;加载地址《8000h》
mov si,di;恢复文件指针
;mov es,bx
;xor ebx,ebx
mov cx,65535;加载整个文件《FFFFh》
call 读取簇;获取整个文件

mov si,加载程序读取完成
call 换行显示

;将两个参数传递给 loader\
dl =BIOS 驱动器号
;mov dl,byte ds:[驱动器号]
;将执行转移到引导加载程序
jmp 0:8000h;0+8000h

;/////被调用程序////\
某些版本的 AWARD BIOS 存在问题\
引导扇区将被正确加载和执行，但是，因为int 13 向量指向 BIOS 中的错误代码，每次尝试加载spec包会失败
oldint13 dd 0
Award_string db 184,1,2,187,0,124,185,6,0,186,128,1,156,154;0b8h,1,2,0bbh,0,7ch,0b9h,6,0,0bah,80h,1,09ch,09ah《改》


检查并修复:
mov si,a规格错误
call 换行显示
mov eax,dword ds:[13h*4]
mov dword ds:[oldint13],eax
push es
mov ax,61440;《0f000h》;es =BIOS Seg
mov es,ax
cld
xor dl,dl;开始于 es + di =f000 + 0

Award_loop:
push di;保存 di
mov si, Award_string;扫描 Award_string
mov cx,7;Award_string 的长度 =7dw
repz cmpsw;比 较
pop di;恢复 di
jcxz Award_found;如果找到则跳转
inc di;未找到，di + 1
jno Award_loop;循环

Award_failed:
pop es;不，不是这样的

Award_fail2:
mov eax,dword ds:[oldint13];恢复原来的中断
or eax,eax
jz 规格查询失败;尝试其他解决方法
mov dword ds:[19*4],eax
jmp 规格查询失败

Award_found:
mov eax,dword ds:[di+14];加载可能的 int 13h 地址
pop es;恢复 es
cmp eax,dword es:[oldint13];如果这是
jz Award_failed;活动 int 13h 向量
mov dword ds:[19*4],eax;否则更改 0:13h×4
mov ax,19201;尝试读取规范数据包
mov dl,byte ds:[驱动器号];现在它不应该失败
mov si,规格包;不再是
int 19
jc Award_fail2
jmp 找到驱动器

;/////////\
int 13h, ax =4b01h, dl =<传入值>失败\
尝试从末尾开始扫描整个 80h ~ ffh
规格查询失败:
;一些代码移到了 Broken Award_Hack
mov si,a规格错误
call 换行显示

mov dl,255;ffh

测试循环:
pusha
mov ax,19201;4b01h
mov si,规格包
mov byte ds:[si],13;缓冲区大小
int 19
;call int13h
popa
jc 还是坏了
mov si,a发现奇怪的东西
call 换行显示
mov al,dl
cmp byte ds:[色批驱动器],dl
jne 可能坏了
;好的，足够好 了
mov si,好消息
call 换行显示

找到驱动器0:
mov byte ds:[驱动器号],dl

没坏:
jmp 找到驱动器

;授予 BIOS 4.51 显然在 sp_drive 中传递了垃圾\
但如果这是最初在 dl 中传递的驱动器号，那么认为它“足够好”
可能坏了:
cmp byte ds:[驱动器号],dl
;mov al,byte ds:[驱动器号]
;cmp al,dl;对比驱动器号
je 没坏

;带有 Adaptec 1542CP BIOS 1.02 的 Intel Classic R+ 计算机\
在 sp_drive 中传递垃圾，而最初在 dl 中传递的驱动器号没有设置 80h 位
or al,80h
cmp al,dl
je 找到驱动器0

还是坏了:
dec dx;dx减一
cmp dl,128;80h
jnb 测试循环

;任何地方都没有规范数据包，一些特别可悲的 bios 甚至没有实现函数\
4b01h，所以无论如何我们都无法查询规范数据包\
什么。如果我们在 dl 中得到一个驱动器号，然后尝试\
使用它，如果它有效，那么好吧
mov dl,byte ds:[驱动器号]
cmp dl,81h;应该是 81 ~ ff
jb 彻底坏了;如果没有，那就没希望了

;写一个警告，我们现在处于非常危险的状态
mov si,bios严重损坏
call 换行显示
mov al,dl
jmp 没坏;少女祈祷中《pray that this works》

彻底坏了:;fatal error
mov si,光盘飞了
call 显示
jmp 关机

;on entry：\
ds + di =文件名\
如果成功：\
zf 清除\
si =文件指针\
eax =文件长度[以字节为单位]\
如果不成功：\
设置 zf\
假设 CS == DS == ES，并丢弃 BX 和 CX\
searchdir_iso 是一个仅适用于 ISOLINUX 的特殊入口点\
除了上述之外，searchdir_iso 在 AL 中传递一个文件标志掩码\
这对于搜索 目录很有用
分配失败:
xor ax,ax;zf <- 1
ret

搜索目录:
xor al,al

搜索iso目录:
mov byte ds:[iso标志],al
call 分配文件;目录的临时文件结构
jnz 分配失败
push es
push ds
pop es;es =ds
mov si,当前目录
cmp byte ds:[di],'\';如果文件名以斜杠开头
jne 没有根目录
inc di;跳过前导斜杠
mov si,根目录;改为引用根目录

没有根目录:
mov eax,dword ds:[si+簇长度]
mov dword ds:[bx+剩余扇区数],eax
shl eax,11
mov dword ds:[bx+4],eax
mov eax,dword ds:[si+目录开始]
mov dword ds:[bx+文件扇区],eax
mov edx,dword ds:[si+字节长度]

查找斜杠:
mov ax,di

扫描:
mov cl,byte ds:[di]
inc di
and cl,cl
jz 是文件
cmp cl,'\'
jne 扫描
mov byte ds:[di-1],0;终止于目录名
mov cl,2;搜索 目录
xchg cl,byte ds:[iso标志]
;保存这些
push di
push cx
;创建递归堆栈帧
push word 恢复;“返回”到哪里
push es

是文件:
xchg ax,di

;获取目录的一部分\
这取决于 ISOLINUX 不会改变 si
读取目录:
mov si,轨道缓冲区
pushad
xchg bx,si
mov cx,1;《改》mov cx,word ds:[BufSafe]
call 读取簇
popad

比较:
movzx eax,byte ds:[si];目录条目长度
cmp al,33
jb 下一个扇区
mov cl,byte ds:[si+25]
	xor	cl, [iso标志]
;mov cl,byte ds:[iso标志]
test cl,142;《8eh》不需要的文件属性
jnz 不是文件
pusha
movzx cx,byte ds:[si+32];文件标识符长度
add si,byte 33;文件标识符偏移量
call iso比较名称
popa
je 成功

不是文件:
sub edx,eax;减少剩余字节数
jbe 失败
add si,ax;推进指针

;检查溢出:\
我们是否完成了缓冲区
cmp si,轨道缓冲区+轨道缓冲区大小
jb 比较 ;没有，继续
jmp short 读取目录;获取更多目录

下一个扇区:;前进到下一个扇 区的开头
lea ax,[si+扇区大小-1]
and ax,~(扇区大小-1)
sub ax,si
jmp short 不是文件;我们还需要做长度检查

失败:
xor eax,eax;zf =1
mov dword ds:[bx+文件扇区],eax
pop es
ret

成功:
mov eax,dword ds:[si+2];范围的位置
mov dword ds:[bx+文件扇区],eax
mov eax,dword ds:[si+10];数据长度
;mov dword ds:[bx+],eax
push eax
add eax,扇区大小-1
shr eax,扇区大小_LG2
mov dword ds:[bx+剩余扇区数],eax
pop eax
mov edx,eax
shr edx,16
;jz 失败;空文件
and bx,bx;zf =0
mov si,bx
pop es
ret

;如果我们只是进行部分查找，我们会到达这里\
这取决于 .成功，返回 bx ==si
恢复:
xchg edx,eax;edx中的目录长度
pop cx;旧 ISO 标志
pop di;下一个文件名指针
mov byte ds:[di-1],'\' ;恢复文件名中的反斜杠
mov byte ds:[iso标志],cl;恢复标志
jz 失败;我们失败了吗？如果是真的失败了！
jmp 查找斜杠;否则，下一级

; allocate_file：分配文件结构\
如果成功\
zf 置1\
bx =文件指针\
不成功\
zf 清除
分配文件:
push cx
mov bx,文件
mov cx,MAX_OPEN

检查:
cmp dword ds:[bx],byte 0
je 发现
add bx,open_file_t_size;zf =0
loop 检查

发现:;zf =0,则退出循环
pop cx
ret

;比 较名称 DS:SI 和 DS:DI 并报告它们是否相等\
ISO 9660视角。SI 是来自\
文件系统的名称；CX 表示它的长度，';' 终止\
DI 应该以 null 结尾\
注意：clobbers AX, CX, SI, DI; 假设 DS == ES == 基本段
iso比较名称:;首先，终止并规范化输入文件名
push di
mov di,iso文件名

规范循环:
jcxz 规范结束
lodsb
dec cx
cmp al,';'
je 规范结束
and al,al
je 规范结束
stosb
cmp di,iso文件名结束-1;防止缓冲区溢出
jb 规范循环

规范结束:
cmp di,iso文件名
jbe 规范完成
cmp byte ds:[di-1],'.';删除终端点
jne 规范完成
dec di
jmp short 规范结束

规范完成:
mov byte ds:[di],0;空终止字符串
pop di
mov si,iso文件名

比较2:
lodsb
mov ah,byte ds:[di]
inc di
and ax,ax
jz 成功2;两者的字符串末尾
and al,al;是字符串的一端吗
jz 失败2;如果是，则失败
and ah,ah
jz 失败2
or ax,8224;《2020h》转换为小写
cmp al,ah
je 比较2

失败2:
and ax,ax;zf =0，至少有一个非零

成功2:
ret

;给定文件指针，从一个文件中获取多个簇\
进入时\
es:bx >缓冲区\
si >文件指针\
cx >簇计数，FFFFh = 直到文件末尾\
退出时\
si >文件指针《或 eof 上为 0》\
cf =1 >命中 eof \
ecx >实际读取的字节数
读取簇:
;push ds
;push cs
;pop ds;相当于mov ds,cs
;movzx ecx,cx
cmp ecx,dword ds:[si+剩余扇区数]
jna 确定大小
mov ecx,dword ds:[si+剩余扇区数]

确定大小:
;pushad
mov bp,cx
push cx
push si
mov eax,dword ds:[si+文件扇区]
mov bp,cx
call getlinsec
xor ecx,ecx
pop si
pop cx
;popad

;ecx [31：16] =0 这里
add dword ds:[si+文件扇区],ecx
sub dword ds:[si+剩余扇区数],ecx
;shl ecx,扇区转换;转换为字节
;cmp ecx,dword ds:[si+]
ja 文件未结束;不是全部，cf =0
;mov ecx,dword ds:[si+]

;不是全部:
;sub dword  ds:[si+],ecx
;jnz 返回;CF =0在这种情况下
;push eax
xor eax,eax
mov dword ds:[si+文件扇区],eax;标记为未使用
;mov si,ax
;pop eax
xor si,si
;stc

文件未结束:
;pop ds
ret

;/////////\
ds：si处显 示字符\
显 示一个字符，si = 字符串文本地址
换行显示:
push si
mov si,换行
call 显示
pop si
call 显示
ret

显示:
mov al,ds:[si];将[di]指向的内存单元的一个字节放入AL
inc si;di+1指向下一个字节
or al,al;判断[di]中的字符值是否=0
jz 完毕;=0显 示完毕
mov ah,14;BIOS中断参数：中断模式
mov bx,7;BIOS中断参数：指定字符颜色？
int 16
jmp 显示

完毕:
ret

;int 13h: 保存所有段寄存器并调用 int 13h\
一些 CD-ROM BIOS 被发现会损坏段寄存器\
和/或禁用中断
; int13h:
; pushf
; push bp
; push ds
; push es
; push fs
; push gs
; int 13h
; mov bp,sp
; setc byte ds:[bp+10];将cf传播给调用者
; pop gs
; pop fs
; pop es
; pop ds
; pop bp
; popf
; ret

;获取一个扇 区，方便的入口点
一个扇区:
mov bp,1
;获取线性扇区 - EBIOS LBA 寻址，2048 字节扇区\
请注意，我们不能总是将其作为单个请求来执行，因为至少\
Phoenix BIOS 有 127 个扇区的限制。 为了安全起见，坚持\
每个请求最多 32 个扇区 (64K)\
输入\
EAX - 线性扇区号\
ES:BX - 目标缓冲区\
BP - 扇区数
getlinsec:
mov si,dapa;加载 DAPA
mov word ds:[si+4],bx
mov bx,es
mov word ds:[si+6],bx
mov dword ds:[si+8],eax

循环:
push bp;剩余扇区 
cmp bp,word ds:[最大传输量]
jbe bp正常
mov bp,word ds:[最大传输量]

bp正常:
mov word ds:[si+2],bp
push si
mov dl,byte ds:[驱动器号]
mov ah,66;扩展读取《42h》
call xint13h
pop si
pop bp
movzx eax,word ds:[si+2]
add dword ds:[si+8],eax;推进扇区指针
sub bp,ax;剩余扇区
shl ax,扇区大小_LG2-4;2048 字节扇区 ->段
add word ds:[si+6],ax;推进缓冲区指针
and bp,bp
jnz 循环
mov eax, dword ds:[si+8];下一个扇 区
ret

;INT 13h 重试
xint13h:
mov byte ds:[重试次数],6;尝 试6次

尝试:
pushad
;call int13h
int 13h
jc 光盘错误
add sp,byte 8*4;清理堆栈
ret

光盘错误:
mov byte ds:[磁盘错误],ah;保存错误码
popad
;mov word ds:[磁盘系统],ax;保存系统调用号
dec byte ds:[重试次数]
jz 真实错误
push ax
mov al,byte ds:[重试次数]
mov ah,byte ds:[dapa+2];扇区传输计数
cmp al,2;只剩下 2 次尝试
ja 没有危险
mov ah,1;将传输大小降低到 1
jmp short 设置大小

没有危险:
cmp al,6-2;尝试4次
ja 再次;第一次，再试一次
shr ah,1;否则，尝试减少
adc ah,0;最大 传输大小，但不是 0

设置大小:
mov byte ds:[最大传输量],ah
mov byte ds:[dapa+2],ah

再次:
pop ax
jmp 尝试

真实错误:
mov si,磁盘出错
call 换行显示

;//////////
关机:
;显 示失败信息
mov si,提示关机
call 换行显示
;按任意键向下
mov ah,00h
int 16h;键盘中断
;关机\
禁用acpi，它将失败
mov ax,5307h;高级电源管理功能,设置电源状态
mov bx,1h;设备id，1所有设备
mov cx,3h;状态3，表示关机
int 15h
;试试这个
MOV AX,2001h
MOV DX,1004h
OUT DX,AX
;好像失败了
mov si,手动关机
call 换行显示
;//////////
停机:
cli
hlt
jmp short 停机

;/////显 示的字符/////
欢迎 db "Ciallo~(L",249,"w<)^*",13,10,0;249 是一个点
没有loader目录 db 'LOADER directory not found',0
没有装载机 db 'LOADER.BIN not found',0
a规格错误 db 'could not load spec package trying to fix',0

a发现奇怪的东西 db 'something was found in the drive',0
bios严重损坏 db 'Seriously corrupted BIOS detected, last attempt to use drive',0
好消息 db 'looks normal continue',0

光盘飞了 db 'boot fails with cd-rom device error',0
加载程序读取完成 db 'go to loader',0
磁盘出错 db 'disk error',0
提示关机 db 'unable to boot press any key to shutdown',0
手动关机 db 'the shutdown fails you can manually turn off the power',0

;/////被调用的参数/////
loader目录 db '\LOADER',0
装载机 db 'loader.bin',0
;缓冲区安全 dw  0
换行 db 13,10,0


;/////El Torito规格数据包/////
align 8,db 0
规格包 db 19;数据包大小
媒体类型 dw 0
色批驱动器 db 0;驱动器号
控制器索引 db 0
模拟LBA dd 0;用于模拟磁盘映像的 LBA
开发规范 dw 0;IDE/SCSI 信息
用户提供的缓冲区 dw 0
负载段 dw 0
扇区数 dw 0
CSH db 0,0,0;模拟 CHS 几何
dummy db 0;划痕，可安全覆盖

;/////EBIOS驱动参数包/////
align 8, db 0
驱动参数 dw 30;缓冲区大小
信息标志 dw 0
物理柱面 dd 0
物理磁头 dd 0
物理扇区—轨道 dd 0
扇面总数 dd 0,0
每个扇区的字节数 dw 0
设备参数表 dd 0
BEDDh dw 0;如果剩余有效
DPIlen db 0
db 0
dw 0
主机总线类型 times 4 db 0
接口类型 times 8 db 0
接口路径 dd 0,0
设备路径 dd 0,0
db 0
DPI信息的校验 db 0

;/////EBIOS 磁盘地址包/////
align 8,db 0
dapa dw 16;数据包大小
区块计数 dw 0
缓冲区偏移 dw 0
缓冲区段 dw 0
LBA dd 0;LBA《LSW》
dd 0;LBA《MSW》

alignb 4,db 0
最大传输量 dw 2;32 每次传输的最大扇区数

times 2046-($-$$) db 0
dw 0aa55h
;事件\
从loader开始我将没有代码可以抄了@ReactOS