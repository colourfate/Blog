## 概述
上一章讲到`210.bin`是`u-boot.bin`的前16KB程序，也就是BL1，根据s5pv210的启动流程，这段程序的作用是初始化DRAM，然后将BL2载入DRAM当中，最后跳转到DRAM运行。要分析这段程序，就要了解uboot的启动过程以及源码构成。

## 从上电到进入_main函数之前
uboot启动总的来说可以分为两个大的阶段，第一个是从上电到进入`_main()`之前，这部分代码是在对芯片运行所必须的硬件进行初始化（如：DRAM、串口、时钟等）和完成==重定位==，主要由汇编实现；第二个是`_main()`之后一直到`run_main_loop()`，这部分是在对uboot运行所必须的数据结构、驱动等进行初始化，主要由C语言实现。这里先来看看uboot的第一阶段。
要分析第一阶段首先就要分析链接脚本，ARM架构的链接脚本都是通用的，位置在`arch/arm/cpu/u-boot.lds`，注意其中代码段的构成：
```bash
.text :
	{
		*(.__image_copy_start)
		*(.vectors)
		CPUDIR/start.o (.text*)
		*(.text*)
	}
```
可以看到，首先是`__image_copy_start`标号，然后是中断向量表`vectors`，接着是`CPUDIR/start.o`文件，最后是其他文件。
先来看看`__image_copy_start`，我们可以在`arch/arm/lib/sections.c`文件中看到如下定义：
```cpp
char __image_copy_start[0] __attribute__((section(".__image_copy_start")));
```
这是一个==长度为0的数组==，0长度的数组是不会占用内存的，但是在编译时仍然会保留数组名这个标号，我们知道数组名实际上是数组的地址，因此`__image_copy_start`标号就代表了`__image_copy_start[0]`这个数组的地址，而这个数组是第一个被链接的文件，因此`__image_copy_start`实际上是代表了==整个代码段的被载入到内存的首地址==，该地址在后来uboot重定位时具有重要作用。
接下来是`vectors`，这部分代码在`arch/arm/lib/vectors.S`文件中，主要是建立中断向量表，这个文件只用关注开头部分即可：
```cpp
.globl _start

	.section ".vectors", "ax"
	
_start:

#ifdef CONFIG_SYS_DV_NOR_BOOT_CFG
	.word	CONFIG_SYS_DV_NOR_BOOT_CFG
#endif

	b	reset
	ldr	pc, _undefined_instruction
	ldr	pc, _software_interrupt
	ldr	pc, _prefetch_abort
	ldr	pc, _data_abort
	ldr	pc, _not_used
	ldr	pc, _irq
	ldr	pc, _fiq
```
首先注意到`_start`被声明为一个==全局标号==，意味着在uboot整个阶段都可以跳回到此处。然后可以看到该部分被被编译为`vectors`段，也就是链接脚本中的指定的`.vectors`，然后进入`_start`函数，开始执行CPU的第一个指令，该指令是`b reset`，也就是跳转到`reset`运行。

`reset`函数在`arch/arm/cpu/armv7/start.S`文件中，也就是链接脚本中的第三个对象，该函数如下所示：
```cpp
reset:
/////////////////////////////////////////
	/* Allow the board to save important registers */
	b	save_boot_params
save_boot_params_ret:
#ifdef CONFIG_ARMV7_LPAE
/*
 * check for Hypervisor support
 */
	mrc	p15, 0, r0, c0, c1, 1		@ read ID_PFR1
	and	r0, r0, #CPUID_ARM_VIRT_MASK	@ mask virtualization bits
	cmp	r0, #(1 << CPUID_ARM_VIRT_SHIFT)
	beq	switch_to_hypervisor
switch_to_hypervisor_ret:
#endif
	/*
	 * disable interrupts (FIQ and IRQ), also set the cpu to SVC32 mode,
	 * except if in HYP mode already
	 */
	mrs	r0, cpsr
	and	r1, r0, #0x1f		@ mask mode bits
	teq	r1, #0x1a		@ test for HYP mode
	bicne	r0, r0, #0x1f		@ clear all mode bits
	orrne	r0, r0, #0x13		@ set SVC mode
	orr	r0, r0, #0xc0		@ disable FIQ and IRQ
	msr	cpsr,r0

/*
 * Setup vector:
 * (OMAP4 spl TEXT_BASE is not 32 byte aligned.
 * Continue to use ROM code vector only in OMAP4 spl)
 */
#if !(defined(CONFIG_OMAP44XX) && defined(CONFIG_SPL_BUILD))
	/* Set V=0 in CP15 SCTLR register - for VBAR to point to vector */
	mrc	p15, 0, r0, c1, c0, 0	@ Read CP15 SCTLR Register
	bic	r0, #CR_V		@ V = 0
	mcr	p15, 0, r0, c1, c0, 0	@ Write CP15 SCTLR Register

	/* Set vector address in CP15 VBAR register */
	ldr	r0, =_start
	mcr	p15, 0, r0, c12, c0, 0	@Set VBAR
#endif

	/* the mask ROM code should have PLL and others stable */
#ifndef CONFIG_SKIP_LOWLEVEL_INIT
	bl	cpu_init_cp15
#ifndef CONFIG_SKIP_LOWLEVEL_INIT_ONLY
	bl	cpu_init_crit
#endif
#endif

	bl	_main
```
首先保存参数，关闭中断，然后跳转到`cpu_init_cp15()`对cp15进行一些配置，接着执行`cpu_init_crit()`函数，最后跳转到`_main`函数，==第一阶段启动结束==。
这个函数中都是对armv7架构的一些通用配置，除了`cpu_init_crit()`函数：
```cpp
ENTRY(cpu_init_crit)
	/*
	 * Jump to board specific initialization...
	 * The Mask ROM will have already initialized
	 * basic memory. Go here to bump up clock rate and handle
	 * wake up conditions.
	 */
	b	lowlevel_init		@ go setup pll,mux,memory
ENDPROC(cpu_init_crit)
```
在该函数中执行了一个至关重要的函数：`lowlevel_init()`，这也是前期uboot移植的大部分工作量所在，`lowlevel_init()`函数位于`board\samsung\x210\lowlevel_init.S`文件中，下一章将对这个文件进行具体介绍。

 ## 总结：
uboot启动第一阶段涉及到的文件和函数如下（函数调用树）： 
```c
--- arch --- arm  --- lib --- vectors.S --- _start() --- b reset
 |                 |
 |                 |- cpu --- armv7 --- start.S --- reset() --- 设置SVC模式
 |                                               |           |- 关中断
 |                                               |           |- 设置cp15
 |                                               |           |- bl cpu_init_crit
 |                                               |           |- bl _main
 |                                               |- cpu_init_crit() --- b lowlevel_init
 |- board --- samsung --- x210 --- lowlevel_init.S --- lowlevel_init()
```

## 第一阶段在BL1中的位置
从链接脚本可以看到，第一阶段的两个重要文件：`vectors.S`和`start.S`是被指定了位置的，而`lowlevel_init.S`以及其中被调用的其他文件是没有指定位置的，没有指定位置的文件会按照编译顺序来排放，如果这些文件被安排到了16KB以后，那么运行时PC指针就会指向一个没有代码的内存区域，最终造成系统死机。那么我们能够保证这些文件刚好被安排到uboot的前16KB吗？
因为我们分割BL1的过程是由一个外部程序实现的，本身不受uboot支持，因此uboot是没有特意指定这些文件被编译到16KB以内的，但是所幸的是这些文件由于是启动代码，在编译uboot时都比较靠前，因此刚好在16KB的范围内。
我们如何验证这一点呢？可以将`u-boot`反汇编得到整个镜像的汇编文件。uboot编译完成后会生成`u-boot`可执行文件，该文件保留了源代码中所有的符号信息，因此是比较适合反汇编的，进入`u-boot-2017.09`目录，执行：
```bash
arm-linux-objdump -S u-boot > u-boot.dmp
```
可以生成反汇编文件，首先截取文件最开始的一段代码：
```cpp
Disassembly of section .text:

33e00000 <__image_copy_start>:

#ifdef CONFIG_SYS_DV_NOR_BOOT_CFG
	.word	CONFIG_SYS_DV_NOR_BOOT_CFG
#endif

	b	reset
33e00000:	be 00 00 ea 14 f0 9f e5 14 f0 9f e5 14 f0 9f e5     ................
	ldr	pc, _undefined_instruction
	ldr	pc, _software_interrupt
	ldr	pc, _prefetch_abort
	ldr	pc, _data_abort
```
这里==链接地址==是`0x33E00000`，这是我手动指定的。从这里可以看到首先是`__image_copy_start`标号，然后是`b	reset`跳转到`start.S`中：
```cpp
33e00300 <reset>:
#endif

reset:
/////////////////////////////////////////
	/* Allow the board to save important registers */
	b	save_boot_params
33e00300:	ea000012 	b	33e00350 <save_boot_params>

33e00304 <save_boot_params_ret>:
#endif
	/*
	 * disable interrupts (FIQ and IRQ), also set the cpu to SVC32 mode,
	 * except if in HYP mode already
	 */
	mrs	r0, cpsr
33e00304:	e10f0000 	mrs	r0, CPSR
	and	r1, r0, #0x1f		@ mask mode bits
33e00308:	e200101f 	and	r1, r0, #31
	teq	r1, #0x1a		@ test for HYP mode
33e0030c:	e331001a 	teq	r1, #26
	bicne	r0, r0, #0x1f		@ clear all mode bits
33e00310:	13c0001f 	bicne	r0, r0, #31
	orrne	r0, r0, #0x13		@ set SVC mode
33e00314:	13800013 	orrne	r0, r0, #19
	orr	r0, r0, #0xc0		@ disable FIQ and IRQ
33e00318:	e38000c0 	orr	r0, r0, #192	; 0xc0
	msr	cpsr,r0
33e0031c:	e129f000 	msr	CPSR_fc, r0
 * (OMAP4 spl TEXT_BASE is not 32 byte aligned.
 * Continue to use ROM code vector only in OMAP4 spl)
 */
#if !(defined(CONFIG_OMAP44XX) && defined(CONFIG_SPL_BUILD))
	/* Set V=0 in CP15 SCTLR register - for VBAR to point to vector */
	mrc	p15, 0, r0, c1, c0, 0	@ Read CP15 SCTLR Register
33e00320:	ee110f10 	mrc	15, 0, r0, cr1, cr0, {0}
	bic	r0, #CR_V		@ V = 0
33e00324:	e3c00a02 	bic	r0, r0, #8192	; 0x2000
	mcr	p15, 0, r0, c1, c0, 0	@ Write CP15 SCTLR Register
33e00328:	ee010f10 	mcr	15, 0, r0, cr1, cr0, {0}

	/* Set vector address in CP15 VBAR register */
	ldr	r0, =_start
33e0032c:	e59f0078 	ldr	r0, [pc, #120]	; 33e003ac <cpu_init_crit+0x4>
	mcr	p15, 0, r0, c12, c0, 0	@Set VBAR
33e00330:	ee0c0f10 	mcr	15, 0, r0, cr12, cr0, {0}
#endif

	/* the mask ROM code should have PLL and others stable */
#ifndef CONFIG_SKIP_LOWLEVEL_INIT
	bl	cpu_init_cp15
33e00334:	eb000006 	bl	33e00354 <cpu_init_cp15>
#ifndef CONFIG_SKIP_LOWLEVEL_INIT_ONLY
	bl	cpu_init_crit
33e00338:	eb00001a 	bl	33e003a8 <cpu_init_crit>
#endif
#endif

	bl	_main
33e0033c:	eb00025f 	bl	33e00cc0 <_main>
```
从第一行就可以看到`reset`在`0x33E00300`的位置，我们重点看看`lowlevel_init()`的位置：
```cpp
33e003a8 <cpu_init_crit>:
	 * Jump to board specific initialization...
	 * The Mask ROM will have already initialized
	 * basic memory. Go here to bump up clock rate and handle
	 * wake up conditions.
	 */
	b	lowlevel_init		@ go setup pll,mux,memory
33e003a8:	ea000714 	b	33e02000 <lowlevel_init>
```
这里`lowlevel_init()`的地址在`0x33E02000`，与uboot起始地址的偏移量为`0x2000 = 8KB`，在16KB的范围内。
用同样的方法可以确定`lowlevel_init()`中调用的各个函数都是在16KB范围内的，这里就不一一验证了。