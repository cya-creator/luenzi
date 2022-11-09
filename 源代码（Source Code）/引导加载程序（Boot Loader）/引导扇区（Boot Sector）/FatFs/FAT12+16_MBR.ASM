;/////////////////////////////////////////////////////////////////////////////////////////
;FAT12或16文件系统的引导扇区
;将根目录数据区读取到7e00h，逐一检查每一个目录项以检索文件直到查完
;读取fat链表至7e00h
;压栈保存第一个簇号，如果是fat12先乘以3再除以2，fat16就直接乘以2便可以得到下一个簇号
;簇号+根目录占用扇区数+根目录起始扇区号-2 =cx
;将簇号弹栈减2再加数据区起始扇区号就是lba号了

;2022年8月13日13时8分~2022年10月30日17时32分
;编写完成\
@cya\
;\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\

;内存布局
;7c00～7e00_boot.asm 512字节
;7e00～？_loader.asm
;bits 16;编译成16位
org 7c00h;历史遗留的起始位置


;/////
;bpb表不用修改，他只是用来占位而已，另外我也会占用一些位置
;12~?字节为BPB部分？
jmp short 初始化寄存器;略过下面的干扰去执行引导程序,2个字节
nop ;空指令;1个字节

取个你喜欢名字 db 'B.S.K.T.';8个字节
扇区大小 dw 512;默认512，2个字节 
每个簇占用的扇区数 db 1;默认1，8h×512b=4k，1个字节
保留扇区数 dw 1;默认1，2个字节
FAT表个数 db 2;默认2，1个字节
根目录可容纳目录数 dw 224;默认224，2个字节
分区总扇区数 dw 2880;2个字节
设备类型 db 0fh;f0表示软盘，1个字节
FAT表占用扇区数 dw 9;2个字节
每磁道扇区数 dw 18;每个磁道扇区数 s   >不同硬盘改动，一般为“3fh   00h”，2个字节
磁头数 dw 2;磁头数 h   >修改，一般为“ffh   00h”，即每个柱面有255个磁头，2个字节
FAT区前隐藏扇区数 dd 0;分区目前已使用 隐藏扇区数，4个字节
扇区总数 dd 0;大于32m这里修改扇区数，对于大硬盘来说该处存放的是该分区占用的扇区数，4个字节
驱动器号 db 0;驱动器号，该处为磁盘bios信息，第一块硬盘为80，一般软盘为0，1个字节
未使用12字节 db 0;预留，12字节未使用，既然你们不用我就拿去用咯
扩展引导标记 db 29h;扩展引导标记，1个字节
磁盘序列号 dd 0;4个字节
磁盘标签 db 'NO NAME    ';windows显示硬盘的名字，如果没有卷标此处通常为字符串no   name，11个字节
文件系统 db 'FAT26   ',10,13,'[]';文件系统标识，待会就显示他，8个字节

找文件 db 'Find',0

;//
初始化寄存器:;添加更多寄存器组合方式的注释
mov ax,cs;代码段，cs：ip
mov ds,ax;数据段，ds：bx，si，di
mov ss,ax;堆栈段，ss：sp，bp
mov sp,7c00h; 堆栈基地址，一般情况，此时的堆栈只是临时的，到了加载模块时还要重新设置
;mov bp,sp;栈游标，ss：bp
mov ax,7e00h
mov es,ax;附加段，es：di
cld;清空df并向前推进

;/
mov byte ds:[驱动器号],dl;先保存驱动器号
;清空屏幕
mov ax,3
int 10h

mov si,文件系统;指向要显示的字符
call 显示


;///
;计算参数，必要
;输出
;cx >根目录占用区扇区数，用于控制循环次数
;ax >根目录起始扇区号
;乘法
;al×bl =ax，被乘数×被乘数 =积
;ax×bx =dx高：低ax
;（每个目录条目长32×根目录可容纳目录数）÷扇区大小 =根目录占用区扇区数
mov ax,32
mul word ds:[根目录可容纳目录数];ax×内存单元 =dx高：低ax
;xor dx,dx;清空高位
div word ds:[扇区大小];dx高：ax低÷内存单元 =ax……dx
mov cx,ax;这是根目录占用的扇区数
mov word ds:[取个你喜欢名字],ax;这个是要留给簇用的

;FAT表大小扇区数×FAT表个数+保留扇区数+FAT区前隐藏扇区数 =根目录起始扇区号
xor ax,ax;需要这样做吗
mov al,byte ds:[FAT表占用扇区数]
mul byte ds:[FAT表个数];al×bl =ax
add ax,word ds:[保留扇区数]
add ax,word ds:[FAT区前隐藏扇区数];根目录起始扇区号
add word ds:[取个你喜欢名字],ax;数据区起始扇区号

mov word ds:[未使用12字节],ax;根目录起始扇区号
mov word ds:[未使用12字节+2],cx;根目录占用的扇区数
call Q读盘


;////
;检索目标文件，必要
xor di,di;es:di，文件名目标地址

下一个目录项:
 mov si,要搜索的文件名;文件名源地址
 mov cx,11;文件名长度，也是比较的次数，正确一个就减1

 push di;保存di以免被repe破坏
 repe cmpsb;比较si，di，重复cx次数
 pop di;覆盖推动过的di
 jcxz 找到了文件;cx是零则跳转
 
 ;and di,0ffe0h;FFE0h（1111 1111 1110 0000）用于使DI对齐
 add di,32;20h，DI指向下一个文件条目的32字节结构体开头处
 cmp byte es:[di],0;查完了吗？
jnz 下一个目录项

mov si,失败
mov dx,找文件
call 状态显示
mov si,没有文件
call 换行显示
jmp 停机


;/
;把fat表读入运存并设置环境，必要
;参数
;ax >初始簇号
找到了文件:;//////////
mov si,成功
mov dx,找文件
call 状态显示

mov si,Q簇项
call 换行显示


mov di,es:[di+26];我们取到了簇号，26是1ah
mov ax,word ds:[保留扇区数]
add ax,word ds:[FAT区前隐藏扇区数];你获得了fat表起始扇区号
mov cx,[FAT表占用扇区数];把fat表全部读入运存9或12
call Q读盘;读取FAT表项至7e00h

mov ax,di;恢复第一个簇号
xor cx,cx;用于读出簇的扇区计数

mov bp,sp;栈内寻址


;///
;查找并保存簇号，必要
;传递参数
;cx >loop计数，内部
;ax >压栈，内部
下一个簇:
 push ax;保存第一次簇号 =storw
 inc cx;loop循环加1
 mov bx,ax;备份用于乘3

 mov di,ax;簇号给di
 add di,di;乘以2，这里是通用处理部分

 mov ax,es:[di];先准备fat16的目录项
 cmp byte ds:[文件系统+4],'6';你应该不是fat16
 jz 是fat16;如果是的话就不用处理了

 add di,bx;si+si=2+bx =3，将簇数乘以3
 shr di,1;移动一位就是除以2
 mov ax,es:[di];把di指向的值读入ax寄存器，你将会获得一个目录项
 ;如果簇数是偶数，则簇值现在在AX 的 0-11位
 ;如果簇号是奇数，则簇值在 4-15位，必须右移 4位
 ;如果数字是奇数，CF 设置在最后一个移位指令中
 jnc 奇数
 shr ax,4;除以8

 奇数:
 and ah,0fh;屏蔽最高4位
 cmp ax,0ff8h;大于或等于ff8h就是最后一个簇了，你不用理其他的值
 jae 读入簇;大于或等于则跳转，fat16不会来到这里

 是fat16:
 cmp ax,0fff8h
jb 下一个簇;小于则跳转，fat12跌落到这里一定不会大于fff8


;//
;把文件读入运存，必要
;将会修改bx寄存器
;输入
;di >栈底保存的簇号，内部
;si >转存循环次数，内部
;es:bx >读入位置
;输出
;es:bx >缓冲区
读入簇:;//////////

mov si,成功
mov dx,簇项
call 状态显示

mov si,载入
call 换行显示



xor bx,bx;bx是读取到的起始位置
读入下一个簇:
 mov si,cx;保存循环次数
 dec bp;堆栈是反过来的
 dec bp

 mov ax,ss:[bp];弄出上面保存的lba号
 ;（簇号-2）×每个簇占用的扇区数+数据区起始扇区号 =簇的lba号
 dec ax
 dec ax;簇号减2
 mov cl,byte ds:[每个簇占用的扇区数]
 xor ch,ch
 ;and cx,0ffh;
 mul cx;ax×每个集群的扇区，;ax×内存单元 =dx高：低ax
 add ax,word ds:[取个你喜欢名字];+数据区起始扇区号，40

 mov cx,1;读一个扇区
 call 读盘
 mov cx,si;弹出保存的循环次数看看还有没有得读
loop 读入下一个簇


mov si,成功
mov dx,载入
call 状态显示


mov dl,byte ds:[驱动器号];传递参数
mov dh,byte ds:[文件系统+4]
mov bx,word ds:[取个你喜欢名字];数据区起始扇区号
mov cx,word ds:[未使用12字节]
mov dx,word ds:[未使用12字节+2]

jmp 7e00h:0;我的同行抖机灵只读一个簇就跳转过去了，让他解析表项自己读完自己，这样好吗？这样不好



;////
;用chs读取，必要
;将会修改ax，bx，cx，dx寄存器
;输入
;ax >LBA
;cx >要读取的扇区数
;bx >读入位置
;输出
;es:bx0 >缓冲区
;除法
;ax÷bl =al……ah，被除数÷除数 =商……余数
;dx高：ax低÷bx =ax……dx
Q读盘:
xor bx,bx

读盘:
 push ax
 push cx

 div byte ds:[每磁道扇区数];ax÷内存单元 =al……ah
 inc ah;lba从0开始所以，扇区号+1
 mov cl,ah;扇区

 xor ah,ah;清除余数
 div byte ds:[磁头数]
 mov dh,ah;磁头
 mov ch, al;柱面

 mov al,1;要读取的扇区数，最多能读72个扇区
 mov dl,byte ds:[驱动器号]
 mov ah,2;功能号2，将扇区读入内存
 int 13h
 jc 读盘错误;如果读取失败则中止

 add bx,word ds:[扇区大小];我将推进段而不是偏移
 pop cx;循环计数
 pop ax;恢复被迫害的lba号
 inc ax;推进lba号以便读取下一个扇区
loop 读盘;我读取多个扇区时遇到问题所以更改了读取方式

ret

读盘错误:
mov si,你读盘失败了捏
call 换行显示


;/
停机:
cli
hlt


;///
;显示字符，可删
;将会修改ax，bx，si寄存器
;输入
;ds：si >字符地址
;输出
;自行查看显示器
状态显示:
call 显示
mov si,dx;显示目标
jmp short 显示

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
没有文件 db 'None ';没有找到loader，0是判断数
要搜索的文件名 db 'LOADER  BIN',0;在 fat文件系统 里所有保存的文件名都是大写，0用于显示

Q簇项 db '[]'
簇项 db'Tuft',0

Q载入 db '[]'
载入 db 'Load',0

你读盘失败了捏 db 'Dre',0

换行 db 10,13,0;10是换行,13是退格
成功 db 13,'[ok]',0
失败 db 13,'[on]',0


times 510-($-$$) db 0
dw 0xaa55
;学到更多\
你应该改进和创新而不是复制粘贴