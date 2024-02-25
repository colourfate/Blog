## 介绍
手上有一块nanopi，想在上面测试写好的驱动，但是开发环境在主机上，为了方便测试，需要使用NFS服务器将开发板文件夹挂载到主机上，这个文件夹相当于一个共享文件夹，只需将写好的驱动复制到该文件夹中，在开发板中就可以看到复制进去的文件了。
注意：这里是在nanopi上搭建NFS服务器，而不是在主机中搭建，好处是任意一台主机（即使没有安装NFS服务器）都可以挂载nanopi的文件夹，坏处是如果开发板不是运行的linux发行版（我的nanopi装的Ubuntu），搭建NFS服务器不是一件容易的事情。
这里选择在nanopi上搭建NFS服务器，还有一点原因是我的主机虚拟机不能ping通开发板，但是开发板却能ping通主机。

## 在开发板上搭建NFS服务器
注意，这里需要开发板安装的是发行版Linux
#### 1. 安装
```bash
$ sudo apt-get install nfs-kernel-server
$ sudo apt-get install nfs-common
```
#### 2. 配置/etc/exports
首先创建一个目录用于主机挂载，这里使用的是：`/home/pi/nfs`，然后执行`$ sudo vi /etc/exports`，在文本末尾添加：

```bash
/home/pi/nfs *(insecure,rw,sync,no_root_squash,no_subtree_check)
```

**(注意这里添加`insecure`选项目的是允许使用1024以上的端口号)**

接下来执行`$ chmod 777 -R /home/pi/nfs`更改文件夹的权限，然后执行`$ sudo exportfs -r`更新`/etc/exports`的变更。
最后执行`$ sudo showmount localhost -e`查看在本机中允许NFS挂载的文件夹，此时应该显示（xxx是开发板的ip地址）：
```
Export list for xxx.xxx.xxx.xxx
/home/pi/nfs *
```
如果显示了以上内容，则可以执行`$ sudo /etc/init.d/nfs-kernel-server restart`重启NFS服务器。
#### 3. 测试挂载
将刚才的NFS文件夹挂载到本机的/mnt文件夹下：
```bash
$ sudo mount -t nfs -o nolock localhost:/home/pi/nfs /mnt
```
然后进入`/mnt`文件夹即可查看到`/home/pi/nfs`文件夹下的内容，说明挂载成功。
使用以下命令取消挂载
```bash
$ sudo umount /mnt
```

## 在主机中挂载开发板的NFS文件夹
首先需要保证主机能够ping通开发板
```bash
ping xxx.xxx.xxx.xxx
```
然后执行`$ sudo showmount xxx.xxx.xxx.xxx -e`查看对应ip地址下允许NFS挂载的文件夹，此时应该输出：
```
Export list for xxx.xxx.xxx.xxx
/home/pi/nfs *
```
然后主机执行
```bash
$ sudo mount -t nfs -o nolock xxx.xxx.xxx.xxx:/home/pi/nfs /mnt
```
即可将开发板的`/home/pi/nfs`挂载到主机的`/mnt`文件夹下。
如果出现：
```
mount.nfs: access denied by server while mounting xxx.xxx.xxx.xxx:/home/pi/nfs
```
说明开发板的`/home/pi/nfs`文件夹权限没有改为777，或者`/etc/exports`文件配置中没有加`inssecure`选项。