## 概述
这一章开始讲解如何使s5pv210载入BL1。上一章讲到芯片启动时首先会执行==iROM==中固化的一段代码，然后依次检查SD0和SD2的存储器中是否有代码。SD0是芯片的SD卡通道0，上面接的是一片4GB的iNand，SD2是连接到一个SD卡插槽上，我在这里插上了一个16GB的SD卡。iNand是开发板上的一块芯片，我们自然是没有办法将代码烧写到上面的，所以这里我们只能将代码烧写到SD卡上，然后芯片在SD卡上找到代码就能载入执行。

## 构建BL1
首先下载我的[BSP](https://github.com/colourfate/x210_bsp)。
配置好环境后，执行`/.build.sh`会编译所有文件，然后进入`output/`目录，其中的`210.bin`文件就是BL1（暂且这么称呼，实际上是BL1+校验和）。那么这个文件是如何构建的呢？让我们看看`build.sh`这个文件uboot编译的部分：
```bash
    echo -e "\n------------------------uboot------------------------\n
    cd $UBOOTDIR
    make x210_defconfig $MFLAG
    make $MFLAG
    cd sd_fusing/
    make
    ./mkx210 ../u-boot.bin 210.bin
    cd $BASEPATH
    cp $UBOOTDIR/u-boot.bin $UBOOTDIR/sd_fusing/210.bin output/
```
注意第7行，可以看到`210.bin`是由`mkx210`程序根据`u-boot.bin`文件生成的。而这里的`u-boot.bin`就是uboot的二进制文件，继续往下追，看`mkx210`是个什么程序，打开`u-boot-2017.09/sd_fusing/`目录下的`Makefile`可以看到：
```bash
$(CC) $(CFLAGS) mkx210 mkv210_image.c
```
说明`mkx210`是由`mkv210_image.c`文件编译出来的，要分析`mkv210_image.c`所做的事情，就要先讲SD卡校验和。

## SD卡校验和
s5pv210芯片能够从iNand或SD卡上找到代码依靠的是SD卡校验和。我们知道，我们最终要执行的BL1实际上是编译得到的二进制文件，将二进制文件的每一个字节相加，我们会得到一个非常大的数字，这个数字就是校验和。由于这个数字非常大不利于存储，所以我们一般取这个数字的最后几位来代表校验和。
上一章说到，芯片探测到SD卡上有代码时，会载入SD卡的==前16KB==数据到SRAM，这个==探测代码的过程就是计算校验和的过程==。芯片首先会依次读取SD上前16KB的数据，计算其校验和，然后将这个校验和与SD卡的==前16字节==进行比较，如果相等就说明这个SD卡上是有代码的，然后就会载入这16KB的代码到SRAM运行。
根据上面所述，只要我们将BL1前面加上BL1的校验和，然后将其烧写到SD卡中，芯片就能够载入BL1正常运行。这个数据结构大概如下所示：
![在这里插入图片描述](res/ARM+Linux嵌入式开发02：【uboot-2017移植】s5pv210载入BL1_1.png)
这个数据结构就是上面提到的`210.bin`，所以这里的`mkv210_image.c`做的其中一件事情是==计算BL1的校验和，然后将其添加到BL1前面==，从而生成`210.bin`。
前面提到BL1大小是16KB，这是因为芯片启动时固定会将SD卡前16KB的数据载入到SRAM中运行，那么如何保证BL1的大小刚好是16KB呢？这就是`mkv210_image.c`做的另一件事情。
通过分析上面脚本，我们可以知道`210.bin`是通过`u-boot.bin`生成的，查看`u-boot.bin`的大小有320KB：
```bash
$ du u-boot.bin 
320	u-boot.bin
```
这显然对于BL1来说太大了，我们要做的就是找到`u-boot.bin`前16KB的数据，然后将其复制下来从而生成BL1。
> **总结210.bin的生成过程：**
>  1. 编译uboot，生成u-boot.bin
>  2. 获取u-boot.bin的前16KB数据，得到BL1
>  3. 计算BL1的校验和，然后添加到BL1前面，从而生成210.bin

## 验证
我们最后来看看210.bin的构成，在`u-boot-2017.09/sd_fusing/`目录下执行：
```bash
$ du 210.bin 
16	210.bin
```
可以看到`210.bin`的大小刚好为16KB，然后执行：
```bash
$ xxd 210.bin > 210.xxd
```
打开`210.xxd`可以看到如下内容：
```bash
00000000: 2a2a 2a2a 2a2a 2a2a 271a 1c00 2a2a 2a2a  ********'...****
00000010: be00 00ea 14f0 9fe5 14f0 9fe5 14f0 9fe5  ................
00000020: 14f0 9fe5 14f0 9fe5 14f0 9fe5 14f0 9fe5  ................
```
退回到`u-boot-2017.09\`目录，执行：
```bash
$ xxd u-boot.bin > u-boot.xxd
```
打开`u-boot.xxd`可以看到如下内容：
```bash
00000000: be00 00ea 14f0 9fe5 14f0 9fe5 14f0 9fe5  ................
00000010: 14f0 9fe5 14f0 9fe5 14f0 9fe5 14f0 9fe5  ................
```
可以看到，在`210.bin`的`0x10~0x2F`与`u-boot.bin`的`0x00~0x1F`的内容是相同的，而`210.bin`多出的`0x00~0x0F`的内容就是SD卡校验和（其中`0x2a`是占位符，实际起作用的是`0x271a1c00`）。

## 烧写到SD卡
在BSP根目录执行（将`sdx`替换为SD卡的设备号）：
```bash
$ sudo ./build.sh upload /dev/sdx
```
可以将u-boot烧写到SD卡，然后将kernel镜像和rootfs复制到SD卡文件系统。我们看看`210.bin`的烧写过程：
```bash
dd iflag=dsync oflag=dsync if=210.bin of=$SDDEV seek=$BL1POS
```
其中`$BL1POS=1`，也就是从SD卡的第一个扇区开始烧写`210.bin`。

> **注意：**
> 以上过程是老的uboot生成BL1过程，可以看到是比较原始的，依靠一个外部的程序强行分割u-boot.bin生成BL1，而新的uboot已经原生支持了这个功能，这就是uboot spl，SPL是Secondary Program Loader的简称，即：第二阶段程序加载器。对于一些SOC来说，它的内部SRAM可能会比较小，小到无法装载下一个完整的uboot镜像，那么就需要spl，它主要负责初始化外部RAM和环境，并加载真正的uboot镜像到外部RAM中来执行^[https://blog.csdn.net/rikeyone/article/details/51646200]。
> 但是博主在移植这个uboot时并不知道什么是SPL(　ﾟ∀ﾟ) 。