## 1. 介绍
uboot加载内核时会从sd中读取内核镜像，和老版本的uboot不同，新版本的uboot支持文件系统，直接将内核镜像复制到sd卡中，然后uboot启动时就会访问sd卡的文件系统，找到内核镜像文件并加载。uboot支持什么文件系统是是由环境变量`loaduimage`决定的，这里我的环境变量为：
```bash
loaduimage=ext4load mmc ${mmcdev}:${mmcbootpart} 0x30007FC0 uImage
```
意思很明确，就是使用ext4格式访问sd卡指定分区的文件系统，然后从根目录找到`uImage`并加载到`0x30007FC0`这个地址。
那么我需要将SD卡格式化为ext4文件系统并挂载到操作系统中。

## 2. 分区、格式化、挂载
首先对sd卡分区，使用如下命令，其中sdx为sd卡的设备文件：
```bash
$ sudo fdisk /dev/sdx
```
进入fdisk命令行后，使用`p`查看所有分区：
```bash
Command (m for help): p
Disk /dev/sdc: 7.6 GiB, 8179941376 bytes, 15976448 sectors
Units: sectors of 1 * 512 = 512 bytes
Sector size (logical/physical): 512 bytes / 512 bytes
I/O size (minimum/optimal): 512 bytes / 512 bytes
Disklabel type: dos
Disk identifier: 0x726119ce

Device     Boot Start      End  Sectors  Size Id Type
/dev/sdc1       20480 15976447 15955968  7.6G 83 Linux
```
这里有一个我已经分好的区域，使用`d`删除这个分区：
```bash
Command (m for help): d
Selected partition 1
Partition 1 has been deleted.

```
然后输入指令`n`进行重新分区，然后输入`p`表示使用主分区，输入`1`表示使用盘符1，然后输入开始扇区，我这里因为要为uboot代码留一个空间，所以指定开始扇区是`20480`，也就是10MB的位置，结束扇区直接回车选择默认：
```bash
Command (m for help): n
Partition type
   p   primary (0 primary, 0 extended, 4 free)
   e   extended (container for logical partitions)
Select (default p): p
Partition number (1-4, default 1): 1
First sector (2048-15976447, default 2048): 20480
Last sector, +sectors or +size{K,M,G,T,P} (20480-15976447, default 15976447): 

Created a new partition 1 of type 'Linux' and of size 7.6 GiB.
Partition #1 contains a ext4 signature.

Do you want to remove the signature? [Y]es/[N]o: Y

The signature will be removed by a write command.
```
此时更改只是在内存中，使用`w`指令执行更改，此时sd卡才真正被分区，分区后使用：
```bash
$ ls /dev/sd*
```
可以看到多了一个`sdx1`文件，这个就是刚才建立的分区。
接下来开始格式化，使用如下指令，sdx替换为对应的盘符：
```bash
$ sudo mke2fs -t ext4 -O /dev/sdx1
mke2fs 1.43.4 (31-Jan-2017)
创建含有 1994496 个块（每块 4k）和 498736 个inode的文件系统
文件系统UUID：3f210d72-31d6-4754-bdee-4b4e4134588d
超级块的备份存储于下列块： 
	32768, 98304, 163840, 229376, 294912, 819200, 884736, 1605632

正在分配组表： 完成                            
正在写入inode表： 完成                            
写入超级块和文件系统账户统计信息： 已完成
```

格式化完成后就可以挂载了，使用如下指令：
```bash
sudo mount /dev/sdx1 <your dir>
```
> **注意：**
挂载时如显示以下错误：
>mount: wrong fs type, bad option, bad superblock on /dev/sdd1,
>       missing codepage or helper program, or other error
>       In some cases useful info is found in syslog - try
>      dmesg | tail or so.
> 建议更换SD卡，虽然**在格式化时**加`-O ^has_journal`选项，电脑能够成功挂载，但是uboot却不能正常读取。

成功挂载后可以在文件资源管理器中看到sd卡。
实际上是不需要手动挂载的，当再次插入sd卡后，系统识别到ext4文件系统会自动挂载到`/media/<usrname>/xxx`目录下。