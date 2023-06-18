
;nasm 

;
; SYS_SIZE is the number of clicks (16 bytes) to be loaded.
; 0x3000 is 0x30000 bytes = 196kB, more than enough for current
; versions of linux
;
SYSSIZE EQU 0x3000

SETUPLEN EQU 4
BOOTSEG EQU 0x07c0
INITSEG EQU 0x9000
SYSSEG  EQU 0x1000			; system loaded at 0x10000 (65536).
ENDSEG	EQU SYSSEG + SYSSIZE	;这里使用段地址来计算sys大小


;----1. 复制启动扇区到0x9000:0-0x9020:0--------
start:
	; 源地址:	 ds:si 
	; 目标地址: es:di
	; cx: 递减
	; rep movsw
	mov ax, BOOTSEG
	mov ds, ax
	mov ax, INITSEG
	mov es, ax

	mov cx, 256
	
	;sub si, si 
	;xor si, si ;这两行在bochs中，无法把esi清0，所以手动
	mov esi, 0
	sub di, di

	rep movsw
;----------------------------------------------


;----2.跳转到0x9000:go 配置运行环境------------
; 配置好cs ds ss es相关环境寄存器
; cs = ds = es = ss = 0x9000
; ss:sp = 0x9ff00
	jmp INITSEG:go	;jmp 0x9000:go
	go:
		mov ax, cs
		mov ds, ax
		mov es, ax
		mov ss, ax
		mov sp, 0xff00
;----------------------------------------------


;----3.从硬盘加载setup程序到内存0x9020:0----
;	目前从硬盘加载程序到内存失败，可能是这种调试方法不能直接使用
; 参数:
; 	dx=0x0000: dh=0x00 磁头号0     dl=0x00 磁盘驱动器号0 
;	cx=0x0002: ch=0x00 柱面号0	 cl=0x02 扇区号2
; 	bx=0x0200: 起始地址es:0x0200, 0x9020:0 使用0x13中断，需要指定中断功能号（很关键）
; 	ax=0x0204: ah=0x02 读硬盘操作  al=0x04 读取扇区数量4
; 综上，dx,cx,bx,ax作为参数
; 执行BIOS 0x13号中断（读取磁盘操作）
; 结果：
; 0x9000:0-0x9020:0 启动扇区，硬盘第一个扇区
; 0x9020:0-0x90a0:0 硬盘第2-6个扇区
load_setup:
	mov dx, 0x0000
	mov ecx, 0x00000000
	mov cx, 0x0002
	mov bx, 0x0200
	mov ax, 0x0200+SETUPLEN
	jmp ok_load_setup
	;int 0x13
	
	; 执行成功,跳转
	jnc ok_load_setup	;jnc检查CF标志位为0，表示读取成功,这里跑飞

	; 读取失败则CF=1
	; 参数：
	;	dx=0x0000: 将磁头和磁道数清零
	;	ax=0x0000: 功能号0（Reset Disk System）来重置磁盘控制器 
	; 执行0x13中断(磁盘重置操作)
	mov dx, 0x0000
	mov ax, 0x0000
	int 0x13

	; 执行失败:重复load_setup
	jmp load_setup
;--------------------------------------------------------


;-----4.加载setup成功后，执行ok_load_setup---------------
; 功能：在屏幕上输出一些信息
ok_load_setup:
	;4.1 功能描述：读取驱动器扇区参数
	;入口参数：(参数只列出用到的)
	;	AH＝08H DL＝驱动器，00H~7FH：软盘；80H~0FFH：硬盘
	;出口参数：
	;	CL 的位 7-6＝柱面数的高2位
	;	CL 的位 5-0＝扇区数
	;	ES:DI＝磁盘驱动器参数表地址
	mov dl, 0x00
	mov ax, 0x0800
	int 0x13
	;seg cs	;指定当前sc地址，其实没变
	mov [sectors], cx	;结果存到sectors

	;由于es被作为出口参数，没用到，所以得恢复成原来的0x9000
	mov ax, INITSEG
	mov es, ax

	;4.2 功能描述：获取光标参数,用来显示内容
	; dx保存光标位置，为下面显示内容使用
	;调用显示中断
	mov ah, 0x03
	xor bh, bh
	int 0x10

	;功能描述：显示一些信息到屏幕
	; cx 字符长度（单位字节）
	mov cx, 24
	xor bx, 0x0007
	mov bp, msg1
	mov ax, 0x1301
	int 0x10
;----------------------------------------------


;-------------5. 继续加载system分区------------
	mov ax, SYSSEG
	mov es, ax
	call	read_it
	call	kill_motor


read_it:
	mov  ax, es		;ax=es=0x1000
	test ax, 0x0fff ;通过段寄存器判断起始地址位于64K地址边界

;如果不是64,死循环
die:
	jne die
	xor bx, bx		;?

rp_read:
	mov ax, es
	cmp ax, ENDSEG	;cmp SYSSEG(0x1000), ENDSEG(0x4000)
	jb ok1_read 	;如果ax<ENDSEG,则跳转到ok1_read,这里必跳转
	ret
;----------------------------------------------



sectors:
	dw 0
msg1:
	db 13,10
	db "Loading system ..."
	db 13,10,13,10

times 508-($-$$) db 0
ROOT_DEV EQU 0x0306
root_dev:
	dw ROOT_DEV
boot_flag:
	dw 0xAA55	
