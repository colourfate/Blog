## 文件操作
#### 1. 安装文件系统
```cpp
// 示例
mount /dev/hd1 /mnt
// 对应操作
--- fs --- super.c --- sys_mount() --- dev_i=namei("/dev/hd1")//获得hd1的inode
                    |               |- dev = dev_i->i_zone[0]//获取hd1的设备号
                    |               |- dir_i=namei("/mnt")//获得mnt的inode
                    |               |- sb=read_super(dev)//读取hd1超级块
                    |               |- sb->s_imount=dir_i//将inode挂载在超级块上
                    |
                    |- read_super(dev) --- 检查超级块是否已经读入super_block[8]
                                     |- 从super_block[8]中找到没有使用的一项
                                     |- bh = bread(dev,1)//读超级块
                                     |- s = bh->b_data
                                     |- s->s_imap[i]=bread(dev,block)
                                     |  //读外设节点位图并挂接
                                     |- s->s_zmap[i]=bread(dev,block)
                                     |  //读外设逻辑位图并挂接
```

#### 2. 打开文件

```cpp
// 示例
char buffer[12000];
int fd = open("/mnt/user/user1/user2/hello.txt", O_RDWR, 0644);
int size = read(fd, buffer, sizeof(buffer));
```

```cpp
--- fs --- open.c --- sys_open() --- 在当前进程的filp[20]中
        |                         |  找到一个空闲项filp[fd]
        |                         |- 在file_table[64]中找到一个空闲项f
        |                         |- current->filp[fd]=f
        |                         |- open_namei(&inode)//获取文件节点
        |                         |- f->f_inode = inode//挂接到f上
        |
        |- namei.c --- open_namei() --- dir=dir_namei(pathname,&namelen,&basename)
        |           |                |  //获取文件枝梢节点、文件名及其长度
        |           |                |- bh=find_entry(&dir,basename,namelen,&de)
        |           |                |  //从枝梢节点读取对应的目录项de
        |           |                |- inr=de->inode;dev=dir->i_dev
        |           |                |  //获取文件inode号
        |           |                |- inode=iget(dev,inr)
        |           |- dir_namei() --- dir = get_dir(pathname)
        |           |               |- 获得文件名，计算其长度
        |           |- get_dir() --- inode设置为根节点，pathname指向'mnt'
        |           |             |- 遍历路径名字符串
        |           |             |- thisname=pathname
        |           |             |- namelen=pathname长度
        |           |             |- pathname指向下一个目录名
        |           |             |- 字符串到末尾了吗 --- Yes --- 返回inode
        |           |             |- find_entry(&inode,thisname,namelen,&de)
        |           |             |  //找到这个目录中名为thisname的目录项de
        |           |             |- inr=de->inode;idev=inode->i_dev
        |           |             |- inode=iget(idev,inr)
        |           |             |- 返回遍历
        |           |- find_entry() --- block=(*dir)->i_zone[0])
        |                            |- bh = bread((*dir)->i_dev,block)
        |                            |  //读取文件的第一个数据块
        |                            |- de=bh->b_data//de指向数据块头
        |                            |- de迭代遍历数据块，查找名字为name
        |                            |  长度为namelen的目录项
        |                            |- 找到返回bh，否则返回NULL
        | 
        |- inode.c --- iget(dev,nr) --- empty=get_empty_inode()
                    |                |- 遍历inode_table[32]
                    |                 |- 设备号=dev且节点号=nr吗 --- No --- 返回遍历
                    |                |- inode挂载了文件系统吗 --- No --- 返回inode
                    |                |- 查找对应超级块super_block[i]
                    |                |- dev=super_block[i].s_dev
                    |                |- nr=1
                    |                |- inode = inode_table
                    |                |- 返回遍历
                    |                |- 遍历结束，没有找到inode
                    |                |- inode=empty
                    |                |- inode->i_dev=dev
                    |                |- inode->i_num=nr
                    |                |- read_inode(inode)//从硬盘上读取节点
                    |                |- 返回inode
                    |- read_inode() --- sb=get_super(inode->i_dev)
                                     |- 由超级块中的节点位图和inode号
                                     |  计算出文件所在块号block
                                     |- bh=bread(inode->i_dev,block)
                                     |- 由inode号计算出块内偏移量
                                     |- 根据偏移量拷贝bh->b_data到inode
```

#### 3. 读取文件
```cpp
--- fs --- read_write.c --- sys_read() --- 若是管道文件，则执行read_pipe()返回
        |                               |- 若是字符设备文件，则执行rw_char()返回
        |                               |- 若是块设备文件，则执行block_read()返回
        |                               |- 若是目录或普通文件，则执行file_read()返回
        |
        |- file_dev.c --- file_read() --- 剩余字节数不为0时循环
        |                              |- nr = bmap((filp->f_pos)/BLOCK_SIZE))
        |                              |  //确定要读的部分在哪个块上
        |                              |- bh=bread(inode->i_dev,nr)
        |                              |- 计算剩余字节数
        |                              |- 复制数据到指定用户空间
        |
        |- inode.c --- bmap(block) --- _bmap(block,0)
                    |- _bmap(block,create) --- 若block<7,返回i_zone[block]
                                            |- block -= 7
                                            |- 若block<512
                                            |--- 若create=1且i_zone[7]不存在
                                            |----- i_zone[7]=new_block()
                                            |--- i_zone[7]=new_block()
                                            |--- i=(bh->b_data)[block]
                                            |    //求出块号
                                            |--- 若create=1且i=0
                                            |----- i=new_block
                                            |--- 返回i
                                            |- block-=512
                                            |- 若create=1且i_zone[8]不存在
                                            |--- i_zone[8]=new_block()
                                            |- bh=bread(i_zone[8])//读一级索引块
                                            |- i = (bh->b_data)[block/512]
                                            |  //i为二级索引块块号
                                            |- 若create=1且i=0
                                            |--- i=new_block()
                                            |- bh=bread(i)//读二级索引块
                                            |- i = (bh->b_data)[block%512]
                                            |- 若create=1且i=0
                                            |--- i=new_block()
                                            |- 返回i
```

#### 4. 新建文件

```cpp
char str1[]="Hello, world";
int fd = creat("/mnt/user/user1/user2/hello.txt", 0644);
int size = write(fd, str1, strlen(str1));
```

```cpp
--- fs --- open.c --- sys_creat() --- sys_open(O_CREAT | O_TRUNC)
        |          |- sys_open() --- 在当前进程的filp[20]中
        |                         |  找到一个空闲项filp[fd]
        |                         |- 在file_table[64]中找到一个空闲项f
        |                         |- current->filp[fd]=f
        |                         |- open_namei(&inode)//获取文件节点
        |                         |- f->f_inode = inode//挂接到f上
        |
        |- namei.c --- open_namei() --- dir=dir_namei(pathname,&namelen,&basename)
        |           |                |  //获取文件枝梢节点、文件名及其长度
        |           |                |- bh=find_entry(&dir,basename,namelen,&de)
        |           |                |  //从枝梢节点读取对应的目录项de
        |           |                |- 若bh=NULL
        |           |                |--- inode = new_inode()
        |           |                |--- inode->i_dirt = 1
        |           |                |--- bh = add_entry(dir,basename,namelen,&de)
        |           |                |    //在dir中新建一个目录项,名字为basename,返回到de中
        |           |                |--- de->inode = inode->i_num
        |           |                |--- bh->b_dirt = 1
        |           |                |--- 返回0
        |           |- add_entry() --- block = dir->i_zone[0]
        |                           |- bh = bread(dir->i_dev,block)//读取文件第一个块
        |                           |- de = bh->b_data//de指向第一个目录项
        |                           |- 开始遍历
        |                           |--- 如果该数据块中没有空闲目录项
        |                           |----- block = create_block(i/DIR_ENTRIES_PER_BLOCK)
        |                           |      //当前第i个目录项,参数是i_zone号
        |                           |----- bh = bread(dir->i_dev,block)
        |                           |----- de = bh->b_data
        |                           |----- 返回遍历
        |                           |--- 如果已达到inode末尾，没有找到空闲项
        |                           |----- de->inode=0//在inode末尾添加一个空闲项
        |                           |--- 如果de->inode为0//已找到空闲项
        |                           |----- 给de->name赋值
        |                           |----- bh->b_dirt = 1
        |                           |----- 返回bh
        |                           |--- de++
        |                           |- 返回NULL
        |
        |- bitmap.c --- new_inode() --- inode=get_empty_inode()
        |                            |- sb = get_super(dev)
        |                            |- 找到bit为0的节点位图所在的缓冲区bh
        |                            |- 由于新建了inode，将bh中对应bit位置1
        |                            |- bh->b_dirt = 1
        |                            |- 对inode属性进行设置
        |
        |- inode.c --- create_block() --- _bmap(1)
```

#### 5. 写文件
 - 将数据写到缓冲区

```cpp
--- fs --- open.c --- sys_write() --- file_write()
        |
        |- file_dev.c --- file_write() --- 已写入字节小于count循环
        |                               |--- block=create_block(pos/BLOCK_SIZE)
        |                               |    //找到需要写入的块号
        |                               |--- bh=bread(inode->i_dev,block)
        |                               |--- 计算
        |                               |--- 拷贝buf到缓冲区
        |                               |- 返回写入字节数
        |
        |- inode.c --- create_block(block) --- _bmap(block,1)
        |           |- _bmap(block,create) --- 若block<7,返回i_zone[block]
        |                                   |- block -= 7
        |                                   |- 若block<512
        |                                   |--- 若create=1且i_zone[7]不存在
        |                                   |----- i_zone[7]=new_block()
        |                                   |--- i_zone[7]=new_block()
        |                                   |--- i=(bh->b_data)[block]
        |                                   |    //求出块号
        |                                   |--- 若create=1且i=0
        |                                   |----- i=new_block
        |                                   |--- 返回i
        |                                   |- block-=512
        |                                   |- 若create=1且i_zone[8]不存在
        |                                   |--- i_zone[8]=new_block()
        |                                   |- bh=bread(i_zone[8])//读一级索引块
        |                                   |- i = (bh->b_data)[block/512]
        |                                   |  //i为二级索引块块号
        |                                   |- 若create=1且i=0
        |                                   |--- i=new_block()
        |                                   |- bh=bread(i)//读二级索引块
        |                                   |- i = (bh->b_data)[block%512]
        |                                   |- 若create=1且i=0
        |                                   |--- i=new_block()
        |                                   |- 返回i
        |
        |- bitmap.c --- new_block() --- sb = get_super(dev)
                                     |- 找到bit为0的逻辑位图所在的缓冲区bh
                                     |- 由于要新建块，将bh中逻辑位图对应bit位置1
                                     |- 由位图的信息计算逻辑块号j
                                     |- bh=getblk(dev,j)
                                     |- clear_block(bh->b_data)
                                     |- bh->b_dirt = 1
                                     |- 返回j
```

 - 从缓冲区同步到外设，sys_sync()在update进程中，一定时间运行一次

```cpp
--- fs --- buffer.c --- sys_sync() --- sync_inodes()
        |                           |- 遍历缓冲区，若bh->b_dirt=1
        |                           |--- ll_rw_block(bh)
        |
        |- inode.c --- sync_inodes() --- 遍历inode_table，若inode->i_dirt=1
                    |                 |--- write_inode()
                    |- write_inode() --- sb=get_super(inode->i_dev)
                                      |- 根据inode号计算其所在块号
                                      |- bh=bread(inode->i_dev,block)
                                      |- 将inode写入bh缓冲区
                                      |- bh->b_dirt=1
                                      |- inode->i_dirt=0
```

#### 6. 关闭文件

```cpp
//示例
close(fd);
unlink("/mnt/user/user1/user2/hello.txt");
```

```cpp
--- fs --- open.c --- sys_close() --- filp = current->filp[fd])
        |                          |- current->filp[fd]=NULL//当前进程fd置空
        |                          |- --filp->f_count//file_table项引用计数减1
        |                          |- iput(filp->f_inode)//inode引用计数减1
        |
        |- inode.c --- iput(inode) --- 循环开始
                                    |- 如果inode->i_count>1
                                    |--- inode->i_count--
                                    |--- 返回
                                    |- 如果inode->i_nlinks=0
                                    |--- truncate(inode)
                                    |--- free_inode(inode)
                                    |--- 返回
                                    |- 如果inode->i_dirt=1
                                    |--- write_inode(inode)
                                    |--- 返回循环
                                    |- inode->i_count--
                                    |- 返回
```

#### 7. 删除文件

```cpp
--- fs --- namei.c --- sys_unlink() --- dir=dir_namei(name,&namelen,&basename)
        |                            |  //找到要删除文件的枝梢节点
        |                            |- bh = find_entry(&dir,basename,namelen,&de)
        |                            |  //读取枝梢节点对应目录项
        |                            |- inode = iget(dir->i_dev, de->inode)
        |                            |  //获得文件i节点
        |                            |- de->inode = 0//该目录项设置为空闲项
        |                            |- bh->b_dirt = 1
        |                            |- inode->i_nlinks--
        |                            |- inode->i_dirt = 1
        |                            |- iput(inode)
        |                            |- iput(dir)
        |
        |- inode.c --- iput(inode) --- 循环开始
        |                           |- 如果inode->i_count>1
        |                           |--- inode->i_count--
        |                           |--- 返回
        |                           |- 如果inode->i_nlinks=0
        |                           |--- truncate(inode)
        |                           |--- free_inode(inode)
        |                           |--- 返回
        |                           |- 如果inode->i_dirt=1
        |                           |--- write_inode(inode)
        |                           |--- 返回循环
        |                           |- inode->i_count--
        |                           |- 返回
        |
        |- truncate.c --- truncate() --- 将i_zone[0]到i_zone[6]置0
        |                             |- 释放一级索引块
        |                             |- 释放二级索引块
        |                             |- 将i_zone[7]和i_zone[8]置0
        |                             |- inode->i_size = 0
        |                             |- inode->i_dirt = 1
        |
        |- bitmap.c --- free_inode() --- sb = get_super(inode->i_dev)
                                      |- bh=sb->s_imap[inode->i_num/8192]
                                      |  //得到inode所在缓冲区
                                      |- clear_bit(inode->i_num%8191,bh->b_data)
                                      |  //清除缓冲区中对应节点位图bit位
                                      |- bh->b_dirt = 1
                                      |- memset(inode,0,sizeof(*inode))
                                         //对应i节点清零
```