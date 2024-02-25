###0. 概述
这里是简单介绍什么是busybox，busybox的移植步骤，以及其中遇到的一些问题，然后介绍了其中一些文件夹的作用。移植完成后再将交叉编译工具链中的动态链接库拷贝到构建好的根文件系统当中，并且使用hello world程序对动态链接库进行测试。
### 1. 什么是busybox
（1）busybox是一个C语言写出来的项目，里面包含了很多.c文件和.h文件。
（2）busybox这个程序开发出来就是为了在嵌入式环境下构建根文件系统（以下简称rootfs）使用的，也就是说他就是专门开发的init进程应用程序。
（3）busybox为当前系统提供了一整套的shell命令程序集。譬如vi、cd、mkdir、ls等。在桌面版的linux发行版（譬如ubuntu、redhat、centOS等）中vi、cd、ls等都是一个一个的单独的应用程序。但是在嵌入式linux中，为了省事我们把vi、cd等所有常用的shell命令集合到一起构成了一个shell命令包，起名叫busybox。
### 2. 最小rootfs所需要的文件夹
（1）dev目录。在linux中一切皆是文件，因此一个硬件设备也被虚拟化成一个设备文件来访问，在linux系统中/dev/xxx就表示一个硬件设备
（2）sys和proc目录。该目录在最小rootfs中也是不可省略的，但是这两个只要创建了空文件夹即可，属于linux中的虚拟文件系统。
（3）usr目录。该目录是系统的用户所有的一些文件的存放地，这个东西将来busybox安装时会自动生成。
（4）etc目录。这是很关键很重要的一个目录，目录中的所有文件全部都是运行时配置文件。
（5）lib目录。这是rootfs中很关键的一个，不能省略的一个。lib目录下放的是当前操作系统中的动态和静态链接

###3. busybox移植实验
（1）登录官网下载busybox-1.26.2，解压后先在Makefile中添加架构信息和交叉编译工具链：
```Makefile
	ARCH = arm
	CROSS_COMPILE = /usr/local/arm/arm2009q3/bin//arm-none-linux-gnueabi-
```
（2）在make menuconfig 中进行必要的配置，配置方法见"busybox menuconfig配置"。
（3）报错'MTD_FILE_MODE_RAW' undeclared ，因为我们没有使用 nandfalsh ，所以把这个文件去掉。在 menuconfig 中搜索 nandwrite 取消即可。
（4）报错'BLKSECDISCARD' undeclared，这是写SD卡的程序，不能直接去掉。BLKSECDISCARD 定义在 /usr/include/linux/fs.h 文件中，进入报错文件 util-linux/blkdiscard.c 中，将注释掉原来的#include "linux/fs.h"，加上 #include "/usr/include/linux/fs.h" 即可。
（5）报错 undefined reference to 'setns'，在 menuconfig 中去掉 nsenter 的定义。
（6）报错 undefined reference to 'syncfs'，在 menuconfig 中去掉 sync 的定义。
（7）在menuconfig 中的修改安装路径
（8）make install
（启动后根文件系统挂载成功，但是一直在报错：can't open /dev/tty2: No such file or directory）

###4. 添加文件 etc/inittab 
该文件属于一个运行时配置文件实际工作的时候 busybox 会（按照一定的格式）解析这个 inittab 文本文件，然后根据解析的内容来决定要怎么工作。 inittab 的格式在 busybox 中定义的，网上可以搜索到详细的格式说明，具体去参考即可
（启动后正常进入命令行，但是提示没有找到/etc/init.d/rsC ，可以执行ls、cd、pwd等命令）
###5. rcS文件
（1）rcS文件是系统的初始化文件，被etc/inittab 
所调用，其中的内容是一些脚本信息。
（2）PATH 这个环境变量是 linux 系统内部定义的一个环境变量，含义是操作系统去执行程序时会默认到 PATH 指定的各个目录下去寻找。
（3）runlevel=S表示将系统设置为单用户模式
（4）umask值决定当前用户在创建文件时的默认权限
（5）mount -a是挂载所有的应该被挂载的文件系统，在busybox中 mount -a 时 busybox 会去查找一个文件 /etc/fstab 文件，这个文件按照一定的格式列出来所有应该被挂载的文件系统（包括了虚拟文件系统）
（6）mdev 是 udev 的嵌入式简化版本， udev/mdev 是用来配合 linux 驱动工作的一个应用层的软件， udev/mdev 的工作就是配合 linux 驱动生成相应的/dev目录下的设备文件。
（7）hostname是linux中的一个shell命令。命令（hostname xxx）执行后可以用来设置当前系统的主机名为xxx，直接hostname不加参数可以显示当前系统的主机名。
###6. 解决没有找到rsC问题
（1）复制 rcS 文件到 /etc/init.d 文件夹中，开机仍然提示文件不存在，原因是 windows 中的换行符和 Linux 不一样。
（2）SecureCRT中 vi rcS 删除其中的^M，开机提示找不到 /etc/fstab ,将其添加，并且在根目录创建 proc, dev, var, sys, tmp 目录中的所有文件全部都是运行时配置文件。
（3）重新开机，没有提示错误，进入 proc，sys，其中有文件
###7. profile文件
（1）添加 /etc/profile 文件，之后的实验现象：命令行提示符前面显示：[@my210 ]#
（2）my210 定义在 /etc/sysconfig/HOSTNAME 文件中，但是 @ 前面是用户名称，这里还没有登录程序，所以没有显示
###8. 添加登录程序
（1）在 inittab 中添加 
```Makefile
s3c2410_serial2::respawn:/sbin/getty -L s3c2410_serial2 115200 vt100 
```
表示开机的时候使用 /sbin/getty 登录程序
（2）添加 /etc/passwd 文件和 /etc/shadow 文件，指定用户名和密码，passwd 文件中需要把 /etc/bash 改为 /etc/sh ，shadow需要将密码删除
（3）重新启动即可使用 root 登录，登录后使用 passwd root 命令添加用户密码
###9. 动态链接库的拷贝
（1）先在 /root 目录下创建 hello_world.c 文件，使用 arm-linux-gcc  交叉编译工具链编译，使用动态链接，生成可执行文件
（2）
```sh
cp /usr/local/arm/arm-2009q3/arm-none-linux-gnueabi/libc/lib/*so* . -rdf 
```
拷贝动态链接库，*so*是过滤掉非动态链接库的文件，-rdf是保证符号链接仍是符号链接
（3）使用 arm-linux-strip 去掉链接库中的符号信息，缩小库的体积
（4）在 开发板上能够执行hello_world 程序









