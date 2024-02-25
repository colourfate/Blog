#### 1. 启动BIOS，准备实模式下的中断向量表和中断服务程序（ISR）
 - 按下电源键，处理器（IA-32）进入16位实模式，从`CS:IP=0xFFFF0`处开始运行。
 - BIOS程序在主板的一块ROM芯片中，该芯片无需初始化即可直接读取，被接在处理器的`0xFE000-0xFFFFF`地址处。
 - BIOS程序的入口地址被设计为`0xFFFF0`，因此上电过后处理器实际上运行的是BIOS程序。
 - BIOS程序将中断向量表放在内存的`0x00000`处，长度为1KB（`0x00000~0x003FF`，256个中断，每个中断向量为4B），在`0x00400~0x004FF`处放BIOS数据区，在57KB以后（0x0E05B）的位置放相应的中断服务程序（ISR），大小约8KB。

#### 2. 加载操作系统内核程序并为保护模式做准备
 - 触发BIOS中断`int 0x19`，在中断向量表中查询到该ISR的地址为`0x0E6F2`，处理器跳转到此处执行。
 - 该ISR将读取软盘第一个扇区（512B）的数据到内存`0x07C00`处，这个中断服务程序是由BIOS设计好的，与Linux操作系统无关。这个扇区中的程序由bootsect.s文件编译生成，这是Linux 0.11的第一个程序。
 - 中断退出后，CPU从0x07C00处开始执行。

**第一次拷贝软盘扇区1**
 - bootsect.s程序第一件事是拷贝`0x07C00`开始的内容到`0x90000`处，长度为512B，即: 将bootsect.s自身移动到0x90000处。这一步目的是按照自己的需求安排内存。
```	x86asm
	boot/bootsect.s
    ------------------------------------------------------
    mov	ax,#BOOTSEG
	mov	ds,ax			; ds=0x07C0
	mov	ax,#INITSEG
	mov	es,ax			; es=0x9000
	mov	cx,#256			; 循环次数256次
	sub	si,si			; si=0x0000
	sub	di,di			; di=0x0000
	rep
	movw				; 一次mov一个字，ds:si-->es:di
```

 - 拷贝完成后，0x07C00和0x90000处有了两份一样的代码，这里将IP=go的偏移量，CS=0x9000，处理器跳转到CS:IP=0x90000+go处执行。这里巧妙利用了`jmpi`指令。
```	x86asm
	boot/bootsect.s
    ------------------------------------------------------
	jmpi	go,INITSEG	; jmpi 为段间跳转指令，即跳转到go标号处，然后将cs=INITSEG
	go:	
	mov	ax,cs
```

 - 将DS, ES, SS都设置为0x9000，SP设置为0xFF00，此时栈地址为`SS:SP=0x9FF00`。设置栈地址后就可以使用PUSH和POP指令了。
```	x86asm
	boot/bootsect.s
    ------------------------------------------------------
    go: 
        mov	ax,cs
        mov	ds,ax
        mov	es,ax
    ! put stack at 0x9ff00.
        mov	ss,ax
        mov	sp,#0xFF00		! arbitrary value >>512
```

**第二次拷贝软盘扇区2~5**

 - 将软盘中第二个扇区开始的4个扇区(setup.s)拷贝到`0x90200`中，刚好紧挨bootsect的结尾。该拷贝使用int 0x13中断完成，该中断是软盘拷贝中断，可以根据ax,bx,cx,dx中的内容，拷贝软盘指定扇区到指定内存。
 - 此次拷贝，将软盘中setup.s这段程序拷贝到了0x90200开始的位置。
```	x86asm
    boot/bootsect.s
    ------------------------------------------------------
    load_setup:
        mov	dx,#0x0000		! drive 0, head 0
        mov	cx,#0x0002		! sector 2, track 0
        mov	bx,#0x0200		! address = 512, in INITSEG
        mov	ax,#0x0200+SETUPLEN	! service 2, nr of sectors
        int	0x13			! read it
        jnc	ok_load_setup		! ok - continue
        mov	dx,#0x0000
        mov	ax,#0x0000		! reset the diskette
        int	0x13
        j	load_setup
```

**第三次拷贝扇区6以后的240个扇区**

 - 将软盘中第六个扇区开始的240个扇区拷贝到`0x10000`往后的120KB的空间中，这120KB的内容就是内核程序，也就是system。该拷贝过程与第二扇区的拷贝基本相同。

 - 确认根设备号，并跳转到0x90200(setup.s)中执行。跳转仍然使用`jmpi`指令
```	x86asm
	boot/bootsect.s
    ------------------------------------------------------
    	seg cs
        mov	ax,root_dev
        cmp	ax,#0
        jne	root_defined
        seg cs
        mov	bx,sectors
        mov	ax,#0x0208		! /dev/ps0 - 1.2Mb
        cmp	bx,#15
        je	root_defined
        mov	ax,#0x021c		! /dev/PS0 - 1.44Mb
        cmp	bx,#18
        je	root_defined
    undef_root:
        jmp undef_root
    root_defined:
        seg cs
        mov	root_dev,ax
    ; 跳转到0x90200，即setup.s
        jmpi	0,SETUPSEG
```

 - setup.s开始，此时中断向量表和ISR还在0x0开始地址，所以可以利用BIOS提供的ISR将一些机器系统数据存放到`0x90000-0x901FD`处，共占510B，刚好将bootsect.s程序覆盖，bootsect不再使用。以下省略了大部分代码。
```	x86asm
	boot/setup.s
    ------------------------------------------------------
    start:
        ; 保存光标位置
        mov	ax,#INITSEG	! this is done in bootsect already, but...
        mov	ds,ax
        mov	ah,#0x03	! read cursor pos
        xor	bh,bh
        int	0x10		! save it in known place, con_init fetches
        mov	[0],dx		! it from 0x90000.
        ; 保存外接内存大小
        mov	ah,#0x88
        int	0x15
        mov	[2],ax
        ...
```

#### 3. 开始向32位模式转变，为main函数的调用做准备
 - 关中断，将system从`0x10000`移动到`0x00000`地址处，此时一复制，实模式下的中断向量表和ISR就被覆盖了。下面这段代码实际上是将0x10000-0x90000的内容整体左移了0x10000
```x86asm
    boot/setup.s
    ------------------------------------------------------
        cli			! no interrupts allowed !
        mov	ax,#0x0000
        cld			! 'direction'=0, movs moves forward
    do_move:
        mov	es,ax		! destination segment
        add	ax,#0x1000
        cmp	ax,#0x9000
        jz	end_move
        mov	ds,ax		! source segment
        sub	di,di
        sub	si,si
        mov 	cx,#0x8000
        rep
        movsw			; 一次传送一个字
        jmp	do_move
```

 - 建立一个空的中断描述符表（IDT）放在0x0地址处，然后建立一个临时的全局描述符表（GDT）。这两个表可以由用户随意放在内存的合适位置，放置好后使用lidt和lgdt指令将其地址传给IDTR和GDTR寄存器，以后硬件就能够根据IDTR和GDTR的值来找到IDT和GDT。这两个寄存器都是48位的寄存器，其中高32位表示表的基地址，低16位表示限长。
```x86asm
	boot/setup.s
    -------------------------------------------------------------------
    end_move:
        mov	ax,#SETUPSEG	; right, forgot this at first. didn't work :-)
        mov	ds,ax
        lidt	idt_48		; load idt with 0,0
        lgdt	gdt_48		; load gdt with whatever appropriate
	...
    gdt:
        .word	0,0,0,0		; dummy

        .word	0x07FF		; 8Mb - limit=2047 (2048*4096=8Mb)
        .word	0x0000		; base address=0
        .word	0x9A00		; code read/exec
        .word	0x00C0		; granularity=4096, 386

        .word	0x07FF		; 8Mb - limit=2047 (2048*4096=8Mb)
        .word	0x0000		; base address=0
        .word	0x9200		; data read/write
        .word	0x00C0		; granularity=4096, 386

    idt_48:
        .word	0			; idt limit=0
        .word	0,0			; idt base=0L

    gdt_48:
        .word	0x800		; gdt limit=2048, 256 GDT entries
        .word	512+gdt,0x9	; gdt base = 0X9xxxx
	; 这里 0x9是段地址，512+gdt是偏移量，加起来就是0x90200+gdt刚好是前面gdt标号的地址
```

 - 打开A20，关闭回滚机制。A20是通过键盘控制器8042打开的。16位实模式下访问0x100000以上的地址，会回滚到`0x00000~0xFFFFF`之间，但是打开A20后就关闭了该回滚机制。
```x86asm
	boot/setup.s
    -------------------------------------------------------------------
	; A20打开后，可以访问0x100000-0x10FFEF的地址，不会回滚
	call	empty_8042
	mov	al,#0xD1		; command write
	out	#0x64,al	 	; 访问键盘控制器，打开A20
	call	empty_8042
	mov	al,#0xDF		; A20 on
	out	#0x60,al
	call	empty_8042
```

 - 对中断控制器8259进行重新编程，目的是空出int 0x00~0x1F做内部使用（P23）。
 - 配置CR0，打开32位保护模式，并跳转到内核文件的head.s执行。
```x86asm
	boot/setup.s
    -------------------------------------------------------------------
    ! 切换到保护模式，保护模式下，CS不是代码段基地址，而是代码段选择符
	mov	ax,#0x0001	; protected mode (PE) bit
	lmsw	ax		; This is it!
	jmpi	0,8		; jmp offset 0 of segment 8 (cs)
```
这里执行jmpi后，IP=0，CS=8，由于在**保护模式下CS的值表示段选择符**，CS=8=0b1000，其中低两位00表示内核特权级，第三位0表示GDT，最高位1表示第1项。
查看GDT的第1项：
0x 00C0             9A00             0000             07FF
0b 0000000011000000 1001101000000000 0000000000000000 0000011111111111
表示：段基址0x00000000，内核特权级，代码段，段限长0x7FF*4KB=8MB（详细解释在P28），所以这里实际上是跳转到了0x0处执行
之前将0x10000开始的内容复制到了0x00000处，而原来0x10000处又是从软盘第6扇区开始复制过来的内容，第6扇区是head.s，因此这里跳转到head.s执行，head.s程序在内核中占25KB+184B的空间。

**head.s创建了内核的分页机制，即在0x000000的位置创建了页目录表、页表、缓冲区、GDT、IDT，并将head程序已经执行过的代码覆盖。**
 - head.s开始，首先设置页基地址`pg_dir`，然后设置DS、ES、FS和GS =0x10，表示保护模式下的**段选择符**
```x86asm
	boot/head.s
    -------------------------------------------------------------------
    .text
    .globl idt,gdt,pg_dir,tmp_floppy_area
    pg_dir:		# 该标号表示分页机制完成后内核的起始地址
    .globl startup_32
    startup_32:
        movl $0x10,%eax
        mov %ax,%ds		# 将ds, es, fs, gs设置为保护模式下的段选择符
        mov %ax,%es		# 0x10=0b10000，和cs=8意义类似
        mov %ax,%fs		# 最后两位00表示内核特权级，第三位0表示GDT
        mov %ax,%gs		# 最高两位10表示第2项
        ...
```
此处的0x10和之前的CS=8类似，0x10=0b10000，最后两位表示内核特权级，第三位0表示GDT，最高两位10表示表的第二项。
查看GDT第二项：0x00C0 9200 0000 07FF
表示段基址0x0，内核级，数据段，段限长8MB

 - 设置SS为段选择符0x10，同时设置ESP=0x1E25C。
```x86asm
	boot/head.s
    -------------------------------------------------------------------
		lss stack_start,%esp
```
lss指令是80386以后才有的指令，目的是同时设置SS和ESP。这里stack_start为48位的结构体，其中低32位为栈地址，高16位为0x10，定义如下：
```cpp
struct {
	long * a;
	short b;
	} stack_start = { & user_stack [PAGE_SIZE>>2] , 0x10 };
```
这里user_stack是一个long数组，长度为PAGE_SIZE>>2（1024），是一个全局变量，因此这里是将esp=user_stack的最后一个元素的地址(0x1E25C)，然后将ss=0x10。0x10的分析方法和上面类似，是同一个段选择符。

 - 循环填充IDT，长度为256，填充内容是：`ignore_int的高16位 | 0x8E00 | 0x0008 | ignore_int的低16位`（中断描述符的详细构造在P31），然后将IDTR设置为当前IDT地址。注意此时的IDT实际放到了0x5000以后的位置
```x86asm
	boot/head.s
    -------------------------------------------------------------------
    	call setup_idt
    	...
    setup_idt:
        lea ignore_int,%edx
        movl $0x00080000,%eax
        movw %dx,%ax		/* selector = 0x0008 = cs */
        movw $0x8E00,%dx	/* interrupt gate - dpl=0, present */
        /* eax= 0x0008<<16 | ignore_int的低16位
         * edx= ignore_int的高16位<<16 | 0x8E00
         * 中断描述符见P31，表示中断服务程序偏移地址为ignore_int，段选择符
         * 为0x8，P(段存在标志)=1，DPL(特权等级)=00，TYPE(段描述符类型)=0111
         */
        lea idt,%edi
        mov $256,%ecx
        /* 将256个中断描述符全部设置为以上内容，即全部指向ignore_int */
    rp_sidt:
        movl %eax,(%edi)
        movl %edx,4(%edi)	# 表示[edi+4]
        addl $8,%edi
        dec %ecx
        jne rp_sidt
        lidt idt_descr		# 设置IDTR寄存器（48位）的值
        ret
        ...
    ignore_int:
        pushl %eax
        pushl %ecx
        pushl %edx
        ...
	.org 0x5000		# 放到了0x5000以后
    ...
    .align 2
    .word 0
    idt_descr:
        .word 256*8-1		# idt contains 256 entries
        .long idt
    idt:	.fill 256,8,0		# idt is uninitialized
				# 在内存中创建256个8字节长区域，初始化为0
```

 - 重新构建GDT，将第一项和第二项的限长该为0xFFF,也就是16MB，然后给后面的250多项真正的分配了内存空间。GDT实际也在0x5000之后的地址
```x86asm
    boot/head.s
    -------------------------------------------------------------------
    	call setup_gdt
    	...
    setup_gdt:
        lgdt gdt_descr
        ret
        ...
    .align 2
    .word 0
    gdt_descr:
        .word 256*8-1		; so does gdt (not that that's any
        .long gdt		; magic number, but it works for me :^)
    ...
    gdt:	
    	.quad 0x0000000000000000	/* NULL descriptor */
		.quad 0x00c09a0000000fff	/* 16Mb */
		.quad 0x00c0920000000fff	/* 16Mb */
		.quad 0x0000000000000000	/* TEMPORARY - don't use */
		.fill 252,8,0			/* space for LDT's and TSS's etc */
```

 - 重新设置DS、ES、FS、GS和SS = 0x10。
```x86asm
	boot/head.s
    -------------------------------------------------------------------
        movl $0x10,%eax		# reload all the segment registers
        mov %ax,%ds		# after changing gdt. CS was already
        mov %ax,%es		# reloaded in 'setup_gdt'
        mov %ax,%fs
        mov %ax,%gs
        lss stack_start,%esp
```

 - 通过向0x000000写一个数，然后和0x10000比较是否相等来判断A20是否打开。
```x86asm
	boot/head.s
    -------------------------------------------------------------------
    	xorl %eax,%eax
    1:	incl %eax		; check that A20 really IS enabled
        movl %eax,0x000000	; loop forever if it isn't
        cmpl %eax,0x100000
		je 1b
```

 - 检测x87协处理器是否存在。
```x86asm
	boot/head.s
    -------------------------------------------------------------------
		movl %cr0,%eax		# check math chip
        andl $0x80000011,%eax	# Save PG,PE,ET
    /* "orl $0x10020,%eax" here for 486 might be good */
        orl $2,%eax		# set MP
        movl %eax,%cr0
        call check_x87
        jmp after_page_tables
```

 - 将L6标号和main函数压栈，然后跳转到setup_paging函数。此时栈顶为main函数地址，目的是head程序执行完返回后，以立即执行main函数，main函数不应该跳出，若跳出则接着执行L6
```x86asm
    boot/head.s
    -------------------------------------------------------------------
    after_page_tables:
        pushl $0		# These are the parameters to main :-)
        pushl $0
        pushl $0
        pushl $L6		# return address for main, if it decides to.
        pushl $main
        jmp setup_paging
    L6:
        jmp L6
```

 - 开始建立页目录和页表。将0x0开始的5KB内存清零，`0x0000~0x1000`为页目录，`0x1000~0x1FFF`为第1页，`0x2000~0x2FFF`为第2页，`0x3000~0x3FFF`为第3页，`0x4000~0x4FFF`为第4页。将页目录的前4项分别指向4个页表，然后在`0x4FFB`中存储`0xFFF007`，在`0x4FF7`中存储`0xFFE007`......直到将所有的页表填满，此时页表建立完毕，将16MB的内存分为了4K页，每页4KB，使用页目录可查询到各页表，使用各页表可以查询到各页。**这四个页表是内核的专属页表。**
```cpp
	boot/head.s
    -------------------------------------------------------------------
    .org 0x1000
    pg0:

    .org 0x2000
    pg1:

    .org 0x3000
    pg2:

    .org 0x4000
    pg3:
    
    .org 0x5000
    ...
    .align 2
    setup_paging:
        movl $1024*5,%ecx		/* 5 pages - pg_dir+4 page tables */
        xorl %eax,%eax
        xorl %edi,%edi			/* pg_dir is at 0x000 */
        cld;rep;stosl			/* 清空0x0开始的5K*4B的空间 */
        /* 将后4个页表地址填写到页目录中 */
        movl $pg0+7,pg_dir		/* set present bit/user r/w */
        movl $pg1+7,pg_dir+4		/*  --------- " " --------- */
        movl $pg2+7,pg_dir+8		/*  --------- " " --------- */
        movl $pg3+7,pg_dir+12		/*  --------- " " --------- */
        /* 
         * 16MB内存被分为4K页，每页为4KB
         * 这里填充pg3的最后一个页表项，指向16MB内存的最后一页(0xfff000) 
         * 为了按4字节对齐，这里只取0xfff007的高12位，最低位的7(0x111)
         * 表示用户、读写、存在p，若是0(0x000)表示内核，只读，不存在p 
         */
        movl $pg3+4092,%edi
        movl $0xfff007,%eax		/*  16Mb - 4096 + 7 (r/w user,p) */
        std
    1:	stosl			/* fill pages backwards - more efficient :-) */
        /* 开始循环填充，注意这里的pg0存的是0x0，pg0+4存的是0x1000 */
        subl $0x1000,%eax
        jge 1b
```
这里页表中存的各页的起始地址，因为要4KB对齐，所以看其中的高12位，低12位表示权限，如这里的`0xFFF007`，高12位是最后一页的地址，即`0xFFF000`，低12位的`0x7=0b111`表示用户、读写、存在p。建立页表的程序被分配在了**0x5000以后，因此不会被页表覆盖**。

 - 将CR3指向页目录表，打开CR0的分页机制开关。
```cpp
	boot/head.s
    -------------------------------------------------------------------
	/* 将CR3置零，其中的高20位表示页目录基地址，即pg_dir=0x0为也目录的基地址 */
	xorl %eax,%eax		/* pg_dir is at 0x0000 */
	movl %eax,%cr3		/* cr3 - page directory start */
	/* 将CR0的最高位置1，打开分页机制 */
	movl %cr0,%eax
	orl $0x80000000,%eax
	movl %eax,%cr0		/* set paging (PG) bit */
```

 - 跳转到main函数执行
```cpp
	boot/head.s
    -------------------------------------------------------------------
    ret
```
由于前面已经将main函数的地址压到了栈中，因此只需`ret`即可将main地址弹出给EIP，处理器跳到main函数执行。**此时仍处于关中断的状态**。

### 总结
**BIOS**
1. 开机时，CPU处于16位实模式，从0xFFFF0地址处开始执行，这个地址接了个ROM芯片，里面存储着BIOS程序，因此BIOS程序开始执行。
2. BIOS程序对硬件进行检测，然后将中断向量表放到`0x00000~0x003FF`的地址，供256个中断，然后将中断服务程序放到0x400开始的地址。
3. BIOS程序触发0x19中断，该中断将软盘中第一个扇区（512B）的内容拷贝到0x07C00处，然后跳转到此处执行。

**bootsect.s**
4. 软盘中第一个扇区的内容是bootsect.s，该程序进入后做的第一件事是将之前拷贝到0x07C00的内容（512B）重新拷贝到0x90000处，然后跳转到0x90000+go的地址继续执行。
5. 接下来bootsect.s利用0x13中断，将软盘中2~5扇区的内容拷贝到0x90200地址处，并将6扇区以后的240个扇区的内容拷贝到0x10000处。拷贝完成后，跳转到0x90200处执行。

**setup.s**
6. 0x90200是setup.s的内容，该程序开始先利用BIOS中断将硬件信息放到0x90000处，覆盖了bootsect.s的内容。然后**关闭中断，并将0x10000开始的内容拷贝到0x00000处，覆盖了原先的中断向量表。**
7. 之后建立了临时的GDT和IDT，其中IDT是空的。目的是为打开32位保护模式做准备。
8. 打开A20关闭回滚机制，**配置CR0，打开32位保护模式**。然后在32位模式下，利用新的GDT，跳转到0x00000处执行。

**head.s**
9. 0x00000现在是head.s的内容，该文件首先设置了数据段地址，堆地址，然后使用重新设置了IDT和GDT在0x5000之后的位置。
10. 之后在0x0000-0x5000之间建立了页目录表和页表，将之后的内存分页，然后把它们的首地址填入第1~4页表中，这是内核页表。注意：建立页表的代码在0x5000之后，因此不会在建立页表时被清空和覆盖。
11. **建立完页表后，将页目录表的首地址（0x00000）填入CR3寄存器，然后将CR0最高位置1打开分页机制（MMU）**。注意，打开分页机制后，所有的寻址都要通过线性地址到物理地址的转换。这一步由MMU完成。
12. 线性地址0x00000000-0x00FFFFFF属于内核空间，也就是0-16MB的范围，该范围内线性地址等于物理地址。该线性地址范围，只有内核允许访问，用户不能够访问。
13. 跳转到main.c函数进行执行。