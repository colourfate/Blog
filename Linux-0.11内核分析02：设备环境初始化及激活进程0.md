## 设备环境初始化及激活进程0
#### 1. 设置根设备、硬盘
```cpp
/*init/main.c
 --------------------------------------------------------------- */
#define DRIVE_INFO (*(struct drive_info *)0x90080)
#define ORIG_ROOT_DEV (*(unsigned short *)0x901FC)
...
void main(void)		/* This really IS void, no error here. */
{
	ROOT_DEV = ORIG_ROOT_DEV;
	drive_info = DRIVE_INFO;
    ...
}
```
setup.s通过BIOS中断将一些机器数据保存到了内存0x90000以后的地址，以覆盖bootsect.s。这里取出了其中的硬盘参数和根设备号。

#### 2. 设置缓冲区、虚拟盘、主内存在物理内存中的位置
```cpp
/* init/main.c
 --------------------------------------------------------------- */
#define EXT_MEM_K (*(unsigned short *)0x90002)
...
void main(void)		/* This really IS void, no error here. */
{
	...
    // 内存大小=1Mb + 扩展内存(k)*1024 byte
	memory_end = (1<<20) + (EXT_MEM_K<<10);
	memory_end &= 0xfffff000;
	if (memory_end > 16*1024*1024)
		memory_end = 16*1024*1024;
	if (memory_end > 12*1024*1024)
		buffer_memory_end = 4*1024*1024;
	else if (memory_end > 6*1024*1024)
		buffer_memory_end = 2*1024*1024;
	else
		buffer_memory_end = 1*1024*1024;
	main_memory_start = buffer_memory_end;
#ifdef RAMDISK
	main_memory_start += rd_init(main_memory_start, RAMDISK*1024);
#endif
    ...
}
```
这里内存大小为16MB，缓冲区大小为4MB位于`0~0x3FFFFF`，虚拟盘为2MB位于`0x400000~0x5FFFFF`，主内存为10MB位于`0x600000~0xFFFFFF`。

#### 3. 初始化虚拟盘
```cpp
/* init/main.c
 --------------------------------------------------------------- */
#define EXT_MEM_K (*(unsigned short *)0x90002)
...
void main(void)		/* This really IS void, no error here. */
{
	...
	main_memory_start += rd_init(main_memory_start, RAMDISK*1024);
    ...
}

/* kernel/blk_drv/ll_rw_blk.c
 --------------------------------------------------------------- */
struct blk_dev_struct blk_dev[NR_BLK_DEV] = {
	{ NULL, NULL },		/* no_dev */
	{ NULL, NULL },		/* dev mem */
	{ NULL, NULL },		/* dev fd */
	{ NULL, NULL },		/* dev hd */
	{ NULL, NULL },		/* dev ttyx */
	{ NULL, NULL },		/* dev tty */
	{ NULL, NULL }		/* dev lp */
};

/* kernel/ramdisk.c
 --------------------------------------------------------------- */
long rd_init(long mem_start, int length)
{
	int	i;
	char	*cp;

	blk_dev[MAJOR_NR].request_fn = DEVICE_REQUEST;
	rd_start = (char *) mem_start;
	rd_length = length;
	cp = rd_start;
	/* 将虚拟磁盘区清零 */
	for (i=0; i < length; i++)
		*cp++ = '\0';
	return(length);
}
```
这里`MAJOR_NR=1`，表示内存设备，将对应的`blk_dev[1].request_fn = DEVICE_REQUEST`，其中`DEVICE_REQUEST=do_rd_request`。然后将虚拟磁盘区清零。

#### 3. 内存管理结构mem_map初始化
系统通过`mem_map[]`对1MB以上的内存进行分页管理（一页为4KB），记录每一页的使用次数。初始化完成后`1~6MB`的页面被标记为`USED`，`6~16MB`的页面被清零，表示没有使用
```cpp
/* init/main.c
 --------------------------------------------------------------- */
#define EXT_MEM_K (*(unsigned short *)0x90002)
...
void main(void)		/* This really IS void, no error here. */
{
	...
	mem_init(main_memory_start,memory_end);
    ...
}

/* kernel/blk_drv/ll_rw_blk.c
 --------------------------------------------------------------- */

#define LOW_MEM 0x100000					// 内存低端(1MB)
#define PAGING_MEMORY (15*1024*1024)		// 分页内存15 MB，主内存区最多15M.
#define PAGING_PAGES (PAGING_MEMORY>>12)	// 分页后的物理内存页面数（3840）
#define MAP_NR(addr) (((addr)-LOW_MEM)>>12)	// 指定地址映射为页号
#define USED 100							// 页面被占用标志.
void mem_init(long start_mem, long end_mem)
{
	int i;
    // 1. 首先将1~16MB内存对应的页面设置为已占用状态
	HIGH_MEMORY = end_mem;                  // 设置内存最高端(16MB)
	for (i=0 ; i<PAGING_PAGES ; i++)
		mem_map[i] = USED;

	i = MAP_NR(start_mem);      // 主内存区起始位置处页面号
	end_mem -= start_mem;
	end_mem >>= 12;             // 主内存区中的总页面数
    // 2. 主内存区（6~16MB）页面对应字节值清零
	while (end_mem-->0)
		mem_map[i++]=0;
	/* 3. 最后1~6MB的页面被标记为USED，6~16MB的页面被清零，表示没有使用 */
}
```

#### 4. 异常处理类中断服务程序挂接
首先设置`0~16`号中断，然后将`17~47`号中断设置为保留
```cpp
/* init/main.c
 --------------------------------------------------------------- */
...
void main(void)		/* This really IS void, no error here. */
{
	...
	trap_init();
    ...
}

/* kernel/traps.c
 --------------------------------------------------------------- */
void trap_init(void)
{
	int i;

	set_trap_gate(0,&divide_error);
	set_trap_gate(1,&debug);
    ...
}

#define _set_gate(gate_addr,type,dpl,addr) \
__asm__ ("movw %%dx,%%ax\n\t" \	// eax=0x00080000 | divide_error低16位
	"movw %0,%%dx\n\t" \	// edx=divide_error高16位 | 0x8000+(dpl<<13)+(type<<8)
							// edx:eax构成了中断描述符
	"movl %%eax,%1\n\t" \					// eax给低4字节地址
	"movl %%edx,%2" \						// edx给高4字节地址
	: \
	: "i" ((short) (0x8000+(dpl<<13)+(type<<8))), \		// 输入的第0个参数
	"o" (*((char *) (gate_addr))), \   // 第1个参数，中断描述符的低4字节地址
	"o" (*(4+(char *) (gate_addr))), \ // 第2个参数，中断描述符的高4字节地址
	"d" ((char *) (addr)),"a" (0x00080000))	// "d"对应edx，"a"对应eax

#define set_trap_gate(n,addr) \
	_set_gate(&idt[n],15,0,addr)
```
这里设置ISR的方法是通过`&idt[n]`找到对应的中断描述符，然后将ISR地址写入其中。

#### 5. 初始化块设备请求项结构
初始化请求项管理结构request[32]，全部设置为空闲，互不挂接。
```cpp
/* init/main.c
 --------------------------------------------------------------- */
void main(void)		/* This really IS void, no error here. */
{
	...
	blk_dev_init();
    ...
}

/* kernel/blk_dev/blk.h
 --------------------------------------------------------------- */
#define NR_REQUEST	32
struct request {
	int dev;		/* -1 if no request */
	int cmd;		/* READ or WRITE */
	int errors;
	unsigned long sector;
	unsigned long nr_sectors;
	char * buffer;
	struct task_struct * waiting;
	struct buffer_head * bh;
	struct request * next;
};

/* kernel/blk_dev/ll_rw_block.c
 --------------------------------------------------------------- */
void blk_dev_init(void)
{
	int i;

	for (i=0 ; i<NR_REQUEST ; i++) {
		request[i].dev = -1;
		request[i].next = NULL;
	}
```
进程想要与块设备进行沟通，必须经过主机内存中的缓冲区。请求项管理结构request[32]就是操作系统管理缓冲区中的缓冲块和块设备上逻辑块之间读写关系的数据结构。

#### 6. 初始化终端设备
主要包括串口、显示器和键盘的初始化。
```cpp
/* init/main.c
 --------------------------------------------------------------- */
void main(void)		/* This really IS void, no error here. */
{
	...
	tty_init();
    ...
}

/* kernel/chr_dev/tty_io.c
 --------------------------------------------------------------- */
void tty_init(void)
{
	rs_init();			// kernel/chr_dev/serial.c
	con_init();			// kernel/chr_dev/console.c
}
```
`rs_init`函数对串口进行初始化，`con_init`对显示器和键盘进行初始化。

#### 7. 开机启动时间设置
这里主要设置开机时间
```cpp
/* init/main.c
 --------------------------------------------------------------- */
void main(void)		/* This really IS void, no error here. */
{
	...
	time_init();
    ...
}

static void time_init(void)
{
	struct tm time;

    // CMOS的访问速度很慢，为了减少时间误差，在读取了下面循环中的所有数值后，如果此时
    // CMOS中秒值发生了变化，那么就重新读取所有值。这样内核就能把与CMOS时间误差控制在1秒之内。
	do {
		time.tm_sec = CMOS_READ(0);
		time.tm_min = CMOS_READ(2);
		time.tm_hour = CMOS_READ(4);
		time.tm_mday = CMOS_READ(7);
		time.tm_mon = CMOS_READ(8);
		time.tm_year = CMOS_READ(9);
	} while (time.tm_sec != CMOS_READ(0));
	BCD_TO_BIN(time.tm_sec);
	BCD_TO_BIN(time.tm_min);
	BCD_TO_BIN(time.tm_hour);
	BCD_TO_BIN(time.tm_mday);
	BCD_TO_BIN(time.tm_mon);
	BCD_TO_BIN(time.tm_year);
	time.tm_mon--;                              // tm_mon中月份的范围是0-11
	/* 设定开机时间，从1970年1月1日0时开始计算 */
	startup_time = kernel_mktime(&time);        // 计算开机时间。kernel/mktime.c文件
}
```

#### 8. 初始化进程0*
 - 首先在全局变量中初始化了一个`task_union`联合体，然后用`INIT_TASK`初始化其中的`task_struct`结构体，这个结构体叫`init_task.task`。
 - 将`task[0]`设置为`init_task.task`的地址。
 - `tss_struct tss`是`task_struct`的一个成员，它表示当前进程的状态，在初始化好的结构体中，这个成员叫做`init_task.task.tss`。
 - 找到`gdt[4]`，将`init_task.task.tss`的地址放入其中。
 - 同样`desc_struct ldt[3]`也是`task_struct`的一个成员，它表示当前进程的段描述符表，叫做`init_task.task.ldt`。
 - 找到`gdt[5]`，将`init_task.task.ldt`的地址放入其中。
 - 将`task[0]`以后全部设置为`NULL`，然后将`gdt[5]`以后全部设置为0。
 - 将`TR`寄存器的值设置为4，表示TSS在GDT的第4项；将`LDTR`寄存器的值设置为5，表示LDT在GDT的第5项。
 - 对时钟中断进行设置，每10ms中断一次。
 - 将`system_call`与IDT相挂接，int 0x80设置为系统调用中断入口。

```cpp
/* init/main.c
 --------------------------------------------------------------- */
void main(void)		/* This really IS void, no error here. */
{
    ...
    sched_init();
    ...
}

/* kernel/sched.c
 --------------------------------------------------------------- */
...
union task_union {
	struct task_struct task;
	char stack[PAGE_SIZE];
};
static union task_union init_task = {INIT_TASK,};
...
struct task_struct * task[NR_TASKS] = {&(init_task.task), };
long user_stack [ PAGE_SIZE>>2 ] ;		// 用户栈
...

void sched_init(void)
{
	int i;
	struct desc_struct * p;                 // 描述符表结构指针
    
    // 调试用
	if (sizeof(struct sigaction) != 16)         // sigaction 是存放有关信号状态的结构
		panic("Struct sigaction MUST be 16 bytes");
        
    /* 1.1 将TSS的地址传入gdt[4]，TSS已经在INIT_TASK中被初始化好 */
	set_tss_desc(gdt+FIRST_TSS_ENTRY,&(init_task.task.tss));
	/* 1.2 将LDT的地址传入gdt[5]，LDT已经在INIT_TASK中被初始化好 */
	set_ldt_desc(gdt+FIRST_LDT_ENTRY,&(init_task.task.ldt));
    /* 2. 将task[1]和gdt[5]以后的项清零 */
	p = gdt+2+FIRST_TSS_ENTRY;
	for(i=1;i<NR_TASKS;i++) {
		task[i] = NULL;
		p->a=p->b=0;
		p++;
		p->a=p->b=0;
		p++;
	}
	/* Clear NT, so that we won't have troubles with that later on */
	__asm__("pushfl ; andl $0xffffbfff,(%esp) ; popfl");        // 复位NT标志
	/* 3.1 将TR设置为4，这样cpu就能够通过gdt[4]找到TSS的地址，从而找到TSS */
	ltr(0);
	/* 3.2 将LDTR设置为5，cpu能够通过gdt[5]找到LDT的地址，从而找到LDT */
	lldt(0);
    /* 4. 设置定时器中断，10ms触发一次。但是由于此时总中断是关的，因此CPU不响应 */
	outb_p(0x36,0x43);		/* binary, mode 3, LSB/MSB, ch 0 */
	outb_p(LATCH & 0xff , 0x40);	/* LSB */
	outb(LATCH >> 8 , 0x40);	/* MSB */
	set_intr_gate(0x20,&timer_interrupt);
	outb(inb_p(0x21)&~0x01,0x21);
	/* 5. 设置系统调用总入口 */
	set_system_gate(0x80,&system_call);
}

/* include/linux/sched.h
 --------------------------------------------------------------- */
struct tss_struct {
	long	back_link;	/* 16 high bits zero */
	long	esp0;
	long	ss0;		/* 16 high bits zero */
	long	esp1;
	long	ss1;		/* 16 high bits zero */
	long	esp2;
	long	ss2;		/* 16 high bits zero */
	long	cr3;
	long	eip;
	long	eflags;
	long	eax,ecx,edx,ebx;
	long	esp;
	long	ebp;
	long	esi;
	long	edi;
	long	es;		/* 16 high bits zero */
	long	cs;		/* 16 high bits zero */
	long	ss;		/* 16 high bits zero */
	long	ds;		/* 16 high bits zero */
	long	fs;		/* 16 high bits zero */
	long	gs;		/* 16 high bits zero */
	long	ldt;		/* 16 high bits zero */
	long	trace_bitmap;	/* bits: trace 0, bitmap 16-31 */
	struct i387_struct i387;
};

struct task_struct {
/* these are hardcoded - don't touch */
	long state;	/* -1 unrunnable, 0 runnable, >0 stopped */
	long counter;
	long priority;
	long signal;
	struct sigaction sigaction[32];
	long blocked;	/* bitmap of masked signals */
/* various fields */
	int exit_code;
	unsigned long start_code,end_code,end_data,brk,start_stack;
	long pid,father,pgrp,session,leader;
	unsigned short uid,euid,suid;
	unsigned short gid,egid,sgid;
	long alarm;
	long utime,stime,cutime,cstime,start_time;
	unsigned short used_math;
/* file system info */
	int tty;		/* -1 if no tty, so it must be signed */
	unsigned short umask;
	struct m_inode * pwd;
	struct m_inode * root;
	struct m_inode * executable;
	unsigned long close_on_exec;
	struct file * filp[NR_OPEN];
/* ldt for this task 0 - zero 1 - cs 2 - ds&ss */
	struct desc_struct ldt[3];
/* tss for this task */
	struct tss_struct tss;
};
/*
 *  INIT_TASK is used to set up the first task table, touch at
 * your own risk!. Base=0, limit=0x9ffff (=640kB)
 */
#define INIT_TASK \
/* state etc */	{ 0,15,15, \
/* signals */	0,{{},},0, \
/* ec,brk... */	0,0,0,0,0,0, \
/* pid etc.. */	0,-1,0,0,0, \
/* uid etc */	0,0,0,0,0,0, \
/* alarm */	0,0,0,0,0,0, \
/* math */	0, \
/* fs info */	-1,0022,NULL,NULL,NULL,0, \
/* filp */	{NULL,}, \
	{ \
		{0,0}, \
/* ldt */	{0x9f,0xc0fa00}, \
		{0x9f,0xc0f200}, \
	}, \
/*tss*/	{0,PAGE_SIZE+(long)&init_task,0x10,0,0,0,0,(long)&pg_dir,\
	 0,0,0,0,0,0,0,0, \
	 0,0,0x17,0x17,0x17,0x17,0x17,0x17, \
	 _LDT(0),0x80000000, \
		{} \
	}, \
}
...
#define FIRST_TSS_ENTRY 4
#define FIRST_LDT_ENTRY (FIRST_TSS_ENTRY+1)
#define _TSS(n) ((((unsigned long) n)<<4)+(FIRST_TSS_ENTRY<<3))
#define _LDT(n) ((((unsigned long) n)<<4)+(FIRST_LDT_ENTRY<<3))
#define ltr(n) __asm__("ltr %%ax"::"a" (_TSS(n)))
#define lldt(n) __asm__("lldt %%ax"::"a" (_LDT(n)))

/* include/asm/system.h
 --------------------------------------------------------------- */
#define _set_tssldt_desc(n,addr,type) \
__asm__ ("movw $104,%1\n\t" \
	"movw %%ax,%2\n\t" \
	"rorl $16,%%eax\n\t" \
	"movb %%al,%3\n\t" \
	"movb $" type ",%4\n\t" \
	"movb $0x00,%5\n\t" \
	"movb %%ah,%6\n\t" \					// 这里构造段描述符，见P69, P70
	"rorl $16,%%eax" \
	::"a" (addr), "m" (*(n)), "m" (*(n+2)), "m" (*(n+4)), \
	 "m" (*(n+5)), "m" (*(n+6)), "m" (*(n+7)) \
	)

#define set_tss_desc(n,addr) _set_tssldt_desc(((char *) (n)),((int)(addr)),"0x89")
#define set_ldt_desc(n,addr) _set_tssldt_desc(((char *) (n)),((int)(addr)),"0x82")

```

#### 9. 初始化缓冲区管理结构*

缓冲区管理结构是一个双向链表，每一个链表节点指向一个缓冲区块的首地址，一个缓冲区块大小为1KB，所有的缓冲区块构成一段连续分布的内存。

这里缓冲区大小是0~4MB，实际大小是从内核代码末尾到4MB，该部分内存前半部分是缓冲区管理结构的链表，后半部分是缓冲区块本身。缓冲区的初始化如下：

```cpp
void buffer_init(long buffer_end)
{
	struct buffer_head * h = start_buffer;
	void * b;
	int i;

    //从640KB - 1MB被显示内存和BIOS占用，所以实际可用缓冲区内存高端位置应该是
    //640KB
	if (buffer_end == 1<<20)
		b = (void *) (640*1024);
	else
		b = (void *) buffer_end;
    /* 这里缓冲区大小为4MB，因此b=0x3FFFFF，h=内核代码末尾。
     * 这里将缓冲区分为了两个部分，一部分是缓冲区管理结构，一部分是缓冲区数据块。
     * 其中第一部分是一个双向链表（初始化时在内存中连续分布），通过一个节点，
     * 可以找到一个缓冲区块。第二部分是一系列连续分布的缓冲区块，一个块大小为1KB。
     * 这里构造缓冲区及其管理结构的流程如下：
     * 首先h指向缓冲区头，b指向缓冲区尾，然后在h处初始化一个管理结构（buffer_head）
     * 将其中的b_data指针指向b（最后一个缓冲区块），前向指针指向h-1，后向指针指向h+1
     * 然后h++，再初始化一个buffer_head，将其中的b_data指向b-1024，同样赋值前后项指针
     * ......
     * 当b和h之间不足一个缓冲区块时停止。
     * void *b; b+1对应地址加1，所以b-1024
     * buffer_head *h; h+1对应地址加sizeof(buffer_head)，所有h+1即可 */
	while ( (b -= BLOCK_SIZE) >= ((void *) (h+1)) ) {
		h->b_dev = 0;                       // 使用该缓冲块的设备号
		h->b_dirt = 0;                      // 脏标志，即缓冲块修改标志
		h->b_count = 0;                     // 缓冲块引用计数
		h->b_lock = 0;                      // 缓冲块锁定标志
		h->b_uptodate = 0;                  // 缓冲块更新标志(或称数据有效标志)
		h->b_wait = NULL;                   // 指向等待该缓冲块解锁的进程
		h->b_next = NULL;                   // 指向具有相同hash值的下一个缓冲头
		h->b_prev = NULL;                   // 指向具有相同hash值的前一个缓冲头
		h->b_data = (char *) b;             // 指向对应缓冲块数据块（1024字节）
		h->b_prev_free = h-1;               // 指向链表中前一项
		h->b_next_free = h+1;               // 指向连表中后一项
		h++;                                // h指向下一新缓冲头位置
		NR_BUFFERS++;                       // 缓冲区块数累加
		if (b == (void *) 0x100000)         // 若b递减到等于1MB，则跳过384KB
			b = (void *) 0xA0000;           // 让b指向地址0xA0000(640KB)处
	}
	h--;                                    // 让h指向最后一个有效缓冲块头
	free_list = start_buffer;               // 让空闲链表头指向头一个缓冲快
	/* 修正第一项前向指针，将其指向最后一项，同时将最后一项后向指针指向第一项 */
	free_list->b_prev_free = h;             // 链表头的b_prev_free指向前一项(即最后一项)。
	h->b_next_free = free_list;             // h的下一项指针指向第一项，形成一个环链
    /* 最后清空hash表 */
	for (i=0;i<NR_HASH;i++)
		hash_table[i]=NULL;
}
```

#### 10. 初始化硬盘
将硬盘请求项服务程序`do_hd_request()`与`blk_dev`控制结构相挂接，然后将硬盘ISR`hd_interrupt()`与IDT相挂接。
```cpp
/* init/main.c
 --------------------------------------------------------------- */
void main(void)		/* This really IS void, no error here. */
{
    ...
    hd_init();
    ...
}

/* kernel/blk_dev/hd.c
 --------------------------------------------------------------- */
void hd_init(void)
{
	blk_dev[MAJOR_NR].request_fn = DEVICE_REQUEST;      // MAJOR_NR=3, do_hd_request()
	set_intr_gate(0x2E,&hd_interrupt);
	outb_p(inb_p(0x21)&0xfb,0x21);                      // 复位接联的主8259A int2的屏蔽位
	outb(inb_p(0xA1)&0xbf,0xA1);                        // 复位硬盘中断请求屏蔽位(在从片上)
}
```

#### 11. 初始化软盘
挂接`do_fd_request()`，初始化软盘中断
```cpp
/* init/main.c
 --------------------------------------------------------------- */
void main(void)		/* This really IS void, no error here. */
{
    ...
    floppy_init();
    ...
}

/* kernel/floppy.c
 --------------------------------------------------------------- */
void floppy_init(void)
{
	blk_dev[MAJOR_NR].request_fn = DEVICE_REQUEST;      //MAJOR_NR=2, do_fd_request()
	set_trap_gate(0x26,&floppy_interrupt);              // 设置陷阱门描述符
	outb(inb_p(0x21)&~0x40,0x21);                       // 复位软盘中断请求屏蔽位
}
```
#### 12. 开启中断*
```cpp
/* init/main.c
 --------------------------------------------------------------- */
void main(void)		/* This really IS void, no error here. */
{
    ...
    sti();
    ...
}
```

#### 13. 进程0由0特权级翻转到3特权级*
 - 分别将0x17，当前ESP，当前EFLAGS，0x0f，标号1压入栈中。
 - 然后调用`iret`指令，CPU开始出栈，此时`SS=0x17`，ESP、EFLAGS不变，`CS=0x0f`，EIP为标号1的地址。
 - 然后将`ds, es, fs, gs`也设置为`0x17`。

```cpp
/* init/main.c
 --------------------------------------------------------------- */
void main(void)		/* This really IS void, no error here. */
{
    ...
    move_to_user_mode();
    ...
}

/* include/system.h
 --------------------------------------------------------------- */
#define move_to_user_mode() \
__asm__ ("movl %%esp,%%eax\n\t" \	// 手工入栈
	"pushl $0x17\n\t" \				// SS
	"pushl %%eax\n\t" \				// ESP
	"pushfl\n\t" \					// EFLAGS
	"pushl $0x0f\n\t" \				// CS, 3特权级，LDT，代码段
	"pushl $1f\n\t" \				// EIP
	"iret\n" \						// 出栈恢复现场
	"1:\tmovl $0x17,%%eax\n\t" \
	"movw %%ax,%%ds\n\t" \
	"movw %%ax,%%es\n\t" \
	"movw %%ax,%%fs\n\t" \
	"movw %%ax,%%gs" \
	:::"ax")

#define sti() __asm__ ("sti"::)
```
这里CS的段选政府为`0x0f=0b01111`，表示3特权级，LDT第1项。LDT在`INIT_TASK`中初始化，其中第1项等于`0x00C0 F200 0000 009F`，查看段描述符的定义（P69）可看出：
基地址为0，粒度G为1，段限长为`0x9F*4096=636KB`，DPL为3，TPYE为2。
由于DPL为3，因此是用户特权级3。
SS的段选择符为`0x17=0b10111`，表示3特权级，LDT第2项。LDT第二项等于0x00C0 FA00 0000 009F，除了TPYE为0xA，其他与CS段类似。然后让DS=ES=FS=GS=SS
这样就把特权级从0翻转到了3。

### 总结
1. head.s将硬件信息存到了0x90000以后的地址，现从中取出根设备，驱动信息。
2. 将16MB内存划分为缓冲区（0-4MB），虚拟盘（4-6MB）和主内存（6-16MB）。
3. 挂接虚拟盘的块设备请求项，将虚拟盘区域清零。
4. 初始化内存管理结构，该结构管理1-16MB的物理内存，每一页对应一个管理结构。其中将1-6MB的内存标记为USED，将6-16MB的内存标记为0。
5. 填充IDT，这里的IDT仍然是head.s中创建的0x5000以后的那个IDT。
6. 初始化块设备请求，填充request[32]数据结构。
7. 初始化tty设备，设置开机启动时间。
8. **初始化进程0**，一个进程对应一个task_struct，这里在预设了一个task_strutc作为进程0的管理结构，然后将任务管理结构的tss和ldt填入了GDT[4]和GDT[5]，并且将TR=4，LDTR=5，这样CPU就知道tss在GDT[4]，而LDT在GDT[5]了，最后设置了定时器中断和系统调用中断。
9. 初始化缓冲区管理结构。缓冲区实际范围是从内核代码末尾到4MB，其中包括前半部分的缓冲区管理结构链表和后半部分的缓冲区块，一个块大小为1KB。
10. 初始化硬盘和软盘，设置他们的块设备请求项。
11. **开启中断。**
12. **通过压栈和iret指令，从0特权级翻转到3特权级。**