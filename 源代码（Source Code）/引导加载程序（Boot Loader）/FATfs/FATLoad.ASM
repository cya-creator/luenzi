;=======================================================================
;FAT文件系统的通用装载

;2022年11月29日22时8分~2022年12月16日时分\
;成功进入长模式\
@cya@https://wiki.osdev.org/Talk:Entering_Long_Mode_Directly

;2022年12月27日22时56分~2022年月日时分\


;————————————————————————————————————
;内存布局
;7e00～ffff_loader.asm
org 7e00h;，我最终向jmp指令妥协了删除这尘封已久的注释


描述符表起始:
call 自定位;确保加载到任何地方都能运行
自定位:
pop bx
sub bx,3;减去call指令占的位置
;shr bx,4;退回被推进的一位
mov ax,cs;代码段，ip：cs
add ax,bx;ip：ffff+cs:ffff,00 =当前地址，无论cs是几都要在ip后添两个零

cld;清空df并向前推进
cmp ax,7e0h;真的已经加载到要求的位置吗

jz 等于则跳转
mov ds,ax;此程序起始位置
mov cx,结束;代码的结束
sub cx,ax;你得到了本程序的长度
shr cx,2;除以4，复制次数
mov ax,7e0h;处理器将自动左移一位
mov es,ax;复制到的位置

xor si,si
xor di,di
rep movsd;以dword，4复制，最大化效率
jmp 0:等于则跳转;现在必然是了：)


等于则跳转:
xor ax,ax
mov ds,ax;数据段，ds：bx，si，di
mov es,ax;附加段，es：di
mov ss,ax;堆栈段，ss：sp，bp
mov sp,0ffffh;在我们的头顶建立堆栈 

mov di,描述符表起始;将在此处定义我们的数据。注意这是一个六十四位的gdt
mov ax,di
shl eax,16;将数据移动到高位eax
stosd;dq，空描述符
xor eax,eax
stosd;我们不能使用rax寄存器

stosd;dq，代码段
mov eax,209800h
stosd;>可读不可写可执行

xor eax,eax
stosd;dq，数据段
mov eax,9000h
stosd;>可读写

sub di,描述符表起始-1;描述符长度，为啥减一俺也不知道
mov word ds:[描述符表起始],di;gdt起始，利用空描述符存储gdt长度和起始
lgdt [描述符表起始];数据已写入gdtr寄存器





   xor bx,bx
   mov es,bx

   mov di,0xa000

   mov ax,0xb00f
   stosw;把AX中的数据装入ES:DI指向的存储单元，然后根据DF标志增减DI

   xor ax,ax
   mov cx,0x07ff
   rep stosw

   mov ax,0xc00f
   stosw

   xor ax,ax
   mov cx,0x07ff
   rep stosw

   mov ax,0x018f
   stosw

   xor ax,ax
   mov cx,0x07ff
   rep stosw


in al,0eeh;在没进入保护模式之前也能开启a20，有些人用这种方式传递内核这很无奈
;out al,0eeh;读这个端口就会关闭a20


;进入长模式    
   mov eax,10100000b				;设置PAE和PGE
   mov cr4,eax

   mov edx, 0x0000a000				;将 CR3 指向 PML4
   mov cr3,edx

   mov ecx,0xC0000080				;指定 EFER MSR

   rdmsr						;启用长模式
   or eax,0x00000100
   wrmsr

   mov ebx,cr0					;激活长模式
   or ebx,0x80000001				;通过同时启用分页和保护
   mov cr0,ebx					;完全跳过保护模式


cli;关中断
jmp 8:	amd64


bits 64
amd64:
call 更新堆栈

更新堆栈:
pop rsp


mov rsi,pp
call 显示字符

jmp $


pp db 'a',10'abbbcccdddeeeefff',0,0


显示字符:
;将会修改ax,dx寄存器
;首先获取当前光标位置
mov dx,03d4h
mov al,0eh
out dx,al
mov dx,03d5h

in al,dx;高8位 
mov ah,al

mov dx,03d4h
mov al,0fh
out dx,al
mov dx,03d5h

in al,dx;低8位 
shl ax,1;×2，我们获得了光标对应的字符位置
push ax





下一个:
mov dl,[rsi]
cmp dl,0;判断[]中的字符值是否 =0
jz 退退退
inc rsi

push ax
call Lllllll
pop ax
add ax,2;推进到下一个字符
jmp short 下一个

退退退:

ret



Lllllll:
cmp bl,10h
jnz 不换行;跳过这段
add ax,0a0h;增加一整行
cmp ax,0f9eh;这是最后一个字符，3998~4000的两个是属性
jb 不滚屏;小于则跳转
call 滚屏

不滚屏:
jmp short 刷新光标


不换行:
cmp bl,13h
jnz 不回车
mov bl,0a0h
div bl
xor ah,ah;清空余数
shr ax,8
jmp short 刷新光标

不回车:
push ax

add eax,0b8000h
mov [eax],dl

pop ax
jmp short 刷新光标





;将会修改eax，dx寄存器
;输入
;bx >字符位置
;输出
;>刷新光标位置
刷新光标:;单纯的反过来而已，注意
shr ax,1;÷2，我们获得了字符对应的光标位置

shl eax,8;把ah挪高两个零
mov dx,03d4h
mov al,0fh
out dx,al
mov dx,03d5h

mov al,ah;低位被挪到了高位我们将它搬回来
out dx,al;低8位 

mov dx,03d4h
mov al,0eh
out dx,al
mov dx,03d5h

shr eax,16;先还原前面操作shl8，然后shl8，把高位ah挪到低位al
out dx,al;写入高8位 

ret



滚屏:
mov rcx,490;感谢群友帮助计算

mov rsi,0b80a0h;从第二行开始
mov rdi,0b8000h;复制到第一行
rep movsq

ret;你获得了最底下的一行


bits 16
结束: