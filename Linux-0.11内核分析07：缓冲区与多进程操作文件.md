#### 1. 缓冲块的进程等待队列
 - A为一个读盘进程，目的是将hello.txt中的100字节读入buffer[100]中
 - B为一个读盘进程，目的是将hello.txt中的200字节读入buffer[200]中
 - C为一个写盘进程，目的是将hello.txt写入字符串"ABCDE"
 - 三个进程执行顺序为A-->B-->C，进程间没有父子关系

```cpp
// 进程A打开文件
--- fs --- open.c --- sys_open() --- (current->filp[fd]=f)->f_count++
                                  |- open_namei(inode)
                                  |- f->f_count=1
                                  |- f->f_inode=inode
// 进程A读取文件
--- fs --- read_write.c --- sys_read() --- file_read()
 |      |
 |      |- file_dev.c --- file_read() --- nr=bmap((filp->f_pos)/BLOCK_SIZE)
 |      |                              |- bh=bread(nr)
 |      |                              |- 将数据拷贝到用户空间
 |      |
 |      |- buffer.c --- bread() --- bh=getblk()
 |                   |           |  //假设有空闲缓冲区
 |                   |           |- ll_rw_block(READ,bh)
 |                   |           |  //缓冲区加锁，开始读硬盘
 |                   |           |- wait_on_buffer(bh)//等待读盘完成
 |                   |- wait_on_buffer() --- while (bh->b_lock)
 |                                        |       sleep_on(&bh->b_wait);
 |
 |- kernel --- sched.c --- sleep_on(p) --- tmp = *p
            |                           |  //备份上一个task_struct，这里为空//备份进程B
            |                           |- *p = current//bh->b_wait=A
            |                           |- current->state = 1
            |                           |- schedule()//调度到进程B//调度到进程0
            |                           |- if (tmp)//唤醒上一个进程这里为空//唤醒进程B
            |                           |      tmp->state=0;
            |- blk_drv --- ll_rw_block.c --- ll_rw_block() --- make_request(bh)
                                          |- make_request() --- lock_buffer(bh)
                                          |- lock_buffer() --- while (bh->b_lock)//未上锁
                                                            |      sleep_on(&bh->b_wait);
                                                            |- bh->b_lock=1//上锁
//进程A消耗时间片，调度到进程B
```

```cpp
// 进程B打开文件
--- fs --- open.c --- sys_open() --- (current->filp[fd]=f)->f_count++
        |                         |  //f与进程A中的f指向不同的file_table[]
        |                         |- open_namei(inode)
        |                         |  //与进程A得到的是同一个inode节点
        |                         |- f->f_count=1
        |                         |- f->f_inode=inode
        |
        |- namei.c --- open_namei() --- inode=iget(dev,inr)
                    |                |  //返回已有的inode节点，没有则重新创建
                    |- iget() --- 遍历整个inode_table[32]
                               |    如果dev和inode号不等则continue
                               |    inode->i_count++;
                               |    返回inode
                                  
// 进程B读取文件
--- fs --- read_write.c --- sys_read() --- file_read()
 |      |
 |      |- file_dev.c --- file_read() --- nr=bmap((filp->f_pos)/BLOCK_SIZE)
 |      |                              |- bh=bread(nr)
 |      |                              |- 将数据读入进程空间
 |      |
 |      |- buffer.c --- bread() --- bh=getblk()
 |                   |           |  //得到进程A申请的同一个缓冲块
 |                   |           |- ll_rw_block(READ,bh)
 |                   |           |  //开始读硬盘，缓冲块被锁，挂起
 |                   |           |- wait_on_buffer(bh)//等待读盘完成
 |                   |- wait_on_buffer() --- while (bh->b_lock)//已上锁
 |                   |                    |       sleep_on(&bh->b_wait);
 |                   |- getblk() --- if ((bh = get_hash_table(dev,block)))
 |                                |     return bh;
 |
 |- kernel --- sched.c --- sleep_on(p) --- tmp = *p//备份进程A的task_struct //备份进程C // 备份进程B
            |                           |- *p = current//bh->b_wait=B
            |                           |- current->state = 1
            |                           |- schedule()//调度到进程C //调度到进程A // 调度到进程C
            |                           |- if (tmp)//唤醒进程A //唤醒进程C //重复唤醒进程B
            |                           |      tmp->state=0;
            |- blk_drv --- ll_rw_block.c --- ll_rw_block() --- make_request(bh)
                                          |- make_request() --- lock_buffer(bh)
                                          |- lock_buffer() --- while (bh->b_lock)//进程A已上锁
                                                            |      sleep_on(&bh->b_wait);
                                                            |- bh->b_lock=1
//进程B消耗时间片，切换到进程0
```

```cpp
// 进程C打开文件
--- fs --- open.c --- sys_open() --- (current->filp[fd]=f)->f_count++
                                  |  //f与进程B中的f指向不同的file_table[]
                                  |- open_namei(inode)
                                  |  //与进程B得到的是同一个inode节点
                                  |- f->f_count=1
                                  |- f->f_inode=inode
                                  
// 进程C写入文件
--- fs --- read_write.c --- sys_write() --- file_write()
 |      |
 |      |- file_dev.c --- file_write() --- block = create_block(pos/BLOCK_SIZE)
 |      |                               |- bh=bread(block)
 |      |                               |- 将数据写入bh
 |      |                                  
 |      |
 |      |- buffer.c --- bread() --- bh=getblk()
 |                   |           |  //得到进程A申请的同一个缓冲块
 |                   |           |- ll_rw_block(READ,bh)
 |                   |           |  //开始读硬盘，缓冲块被锁，挂起
 |                   |           |- wait_on_buffer(bh)//等待读盘完成
 |                   |- wait_on_buffer() --- while (bh->b_lock)//已上锁
 |                   |                    |       sleep_on(&bh->b_wait);
 |                   |- getblk() --- if ((bh = get_hash_table(dev,block)))
 |                                |     return bh;
 |
 |- kernel --- sched.c --- sleep_on(p) --- tmp = *p
            |                           |  //备份进程B的task_struct //备份进程C
            |                           |- *p = current//bh->b_wait=C
            |                           |- current->state = 1
            |                           |- schedule()//调度到进程0 //调度到进程B
            |                           |- if (tmp)//唤醒进程B //重复唤醒进程C
            |                           |      tmp->state=0;
            |- blk_drv --- ll_rw_block.c --- ll_rw_block() --- make_request(bh)
                                          |- make_request() --- lock_buffer(bh)
                                          |- lock_buffer() --- while (bh->b_lock)//进程A已上锁
                                                            |      sleep_on(&bh->b_wait);
                                                            |- bh->b_lock=1//再次上锁
//进程C消耗时间片，消耗完毕后进入进程0执行
```

```cpp
//进程A读盘完毕，发生硬盘中断
--- kernel --- blk_drv --- hd.c --- write_intr() --- end_request(1)
            |           |
            |           |- blk.h --- end_request() --- unlock_buffer()
            |                     |- unlock_buffer() --- bh->b_lock=0//bh解锁
            |                                         |- wake_up(&bh->b_wait)
            |- sched.c --- wake_up(p) --- (**p).state=0//唤醒进程C
```

```cpp
//进程C读盘完毕，发生硬盘中断
--- kernel --- blk_drv --- hd.c --- write_intr() --- end_request(1)
            |           |
            |           |- blk.h --- end_request() --- unlock_buffer()
            |                     |- unlock_buffer() --- bh->b_lock=0//bh解锁
            |                                         |- wake_up(&bh->b_wait)
            |- sched.c --- wake_up(p) --- (**p).state=0//唤醒进程A
```

```cpp
//进程B读盘完毕，发生硬盘中断
--- kernel --- blk_drv --- hd.c --- write_intr() --- end_request(1)
            |           |
            |           |- blk.h --- end_request() --- unlock_buffer()
            |                     |- unlock_buffer() --- bh->b_lock=0//bh解锁
            |                                         |- wake_up(&bh->b_wait)
            |- sched.c --- wake_up(p) --- (**p).state=0//唤醒进程B
```

 - 总体执行顺序
 ```cpp
 进程A: bh->b_lock=1 --- 设置硬盘中断 --- tmp=NULL --- bh->b_wait=A --- A.state=1 --- 切换到进程B --- tmp=B --- bh->b_wait=A --- A.state=1 --- 切换到进程0 --- tmp->state=0 --- 将bh数据读入进程空间 --- 等待时间片耗尽，切换到进程B
 
 进程B: tmp=A --- bh->b_wait=B --- B.state=1 --- 切换到进程C --- tmp.state=0 --- tmp=C --- bh->b_wait=B --- B.state=1 --- 切换到进程A --- tmp.state=0 --- bh->b_lock=1 --- 设置硬盘中断 --- tmp=A --- bh->b_wait=B --- B.state=1 --- 切换到进程C --- tmp.state=0 --- 将bh数据读入进程空间 --- 等待时间片耗尽，切换到进程A
 
 进程C: tmp=B --- bh->b_wait=C --- C.state=1 --- 切换到进程0 --- tmp.state=0 --- bh->b_lock=1 --- 设置硬盘中断 --- tmp=C --- bh->b_wait=C --- C.state=1 --- 切换到进程B --- tmp.state=0 --- tmp=B --- bh->b_wait=C --- C.state=1 --- 切换到进程0 --- tmp.state=0 --- 将数据写入bh --- 等待时间片耗尽，切换到进程B
 
 硬盘中断：bh->b_lock=0 --- C.state=0 --- 切换到进程C --- bh->b_lock=0 --- A.state=0 --- 切换到进程A --- bh->b_lock=0 --- C.state=0 --- 切换到进程C
 ```
 
#### 2. 多进程操作文件综合实例
 - 进程A是一个写盘进程，目的是往hello1.txt文件中写入"ABCDE"
 - 进程B是一个写盘进程，目的是往hello2.txt文件中写入"ABCDE"
 - 进程C是一个读盘进程，目的是从hello3.txt文件中读20000字节到buffer中
 - 三个进程执行顺序为A-->B-->C，进程间没有父子关系
 - 假设进程A执行时，所有空闲的缓冲块都是脏的，且没加锁

```cpp
//进程A
--- fs --- buffer.c --- bread() --- bh=getblk()
 |                   |           |  
 |                   |           |- ll_rw_block(READ,bh)
 |                   |           |  
 |                   |           |- wait_on_buffer(bh)
 |                   |- wait_on_buffer() --- while (bh->b_lock)
 |                   |                    |       sleep_on(&bh->b_wait);
 |                   |- getblk() --- 找到空闲，无锁，脏的缓冲区bh
 |                   |            |- while(bh->b_dirt){
 |                   |            |      sync_dev(bh->b_dev);
 |                   |            |      wait_on_buffer(bh);
 |                   |            |  }
 |                   |            |- 
 |                   |
 |                   |- sync_dev(dev) --- 遍历所有缓冲块，如果对应设备缓冲块是脏的
 |                                     |      ll_rw_block(WRITE,bh);
 |                                        //将所有脏的缓冲块都放入请求队列，直到请求队列满
 |
 |- kernel --- blk_drv --- ll_rw_block.c --- ll_rw_block() --- make_request(bh)
                                          |- make_request() --- lock_buffer(bh)
                                          |                  |- 在request[32]中找到空闲请求项req
                                          |                  |- 如果没有空闲请求项
                                          |                  |      sleep_on(&wait_for_request)
                                          |                  |      //切换到进程B
                                          |                  |      返回1，重新查找
                                          |                  |- req->bh=bh
                                          |                  |- add_request(req)
                                          |- lock_buffer() --- while (bh->b_lock)
                                          |                 |      sleep_on(&bh->b_wait);
                                          |                 |- bh->b_lock=1
                                          |- add_request() --- if (req->bh)
                                                            |       req->bh->b_dirt=0;
                                                            |  //去除脏的标志
                                                            |- if (!(tmp = dev->current_request)){
                                                            |       dev->current_request = req;
                                                            |       (dev->request_fn)();
                                                            |        return;
                                                            |  }
                                                            |  //当前设备没有执行请求时，执行新请求
                                                            |- req->next=tmp->next;
                                                            |- tmp->next=req;
                                                            |  //否则将新请求插入请求队列
                                                               //这里将刚刚释放的请求项加入队列
```

```cpp
//进程B
--- fs --- buffer.c --- bread() --- bh=getblk()
 |                   |           |  
 |                   |           |- ll_rw_block(READ,bh)
 |                   |           |  
 |                   |           |- wait_on_buffer(bh)
 |                   |- wait_on_buffer() --- while (bh->b_lock)
 |                   |                    |       sleep_on(&bh->b_wait);
 |                   |                    |       //切换到进程C//切换到进程A
 |                   |- getblk() --- 找到空闲，有锁，干净的缓冲区bh
 |                   |            |  //该缓冲区是刚刚由进程A上锁并设置为干净的
 |                   |            |- wait_on_buffer(bh)//等待解锁//重新等待解锁
 |                   |            |- 检测到bh非空闲，返回0执行
 |                   |            |  
 |
 |- kernel --- blk_drv --- ll_rw_block.c --- ll_rw_block() --- make_request(bh)
                                          |- make_request() --- lock_buffer(bh)
                                          |                  |- 在request[32]中找到空闲请求项req
                                          |                  |- 如果没有空闲请求项
                                          |                  |      sleep_on(&wait_for_request)
                                          |                  |      //切换到进程B
                                          |                  |      返回1，重新查找
                                          |                  |- req->bh=bh
                                          |                  |- add_request(req)
                                          |- lock_buffer() --- while (bh->b_lock)
                                          |                 |      sleep_on(&bh->b_wait);
                                          |                 |- bh->b_lock=1
                                          |- add_request() --- if (req->bh)
                                                            |       req->bh->b_dirt=0;
                                                            |  //去除脏的标志
                                                            |- if (!(tmp = dev->current_request)){
                                                            |       dev->current_request = req;
                                                            |       (dev->request_fn)();
                                                            |        return;
                                                            |  }
                                                            |  //当前设备没有执行请求时，执行新请求
                                                            |- req->next=tmp->next;
                                                            |- tmp->next=req;
                                                            |  //否则将新请求插入请求队列
```

```cpp
//进程C
--- fs --- buffer.c --- bread() --- bh=getblk()
 |                   |           |  
 |                   |           |- ll_rw_block(READ,bh)
 |                   |           |  //将读盘请求加入请求队列中
 |                   |           |- wait_on_buffer(bh)
 |                   |- wait_on_buffer() --- while (bh->b_lock)
 |                   |                    |       sleep_on(&bh->b_wait);
 |                   |                    |       //切换到进程0//切换到进程B
 |                   |- getblk() --- 找到空闲，有锁，干净的缓冲区bh
 |                   |            |  //该缓冲区和进程B获取的是同一个 
 |                   |            |- wait_on_buffer(bh)//等待解锁
 |                   |            |- bh->b_count=1  
 |                   |            |  //bh变为非空闲缓冲块
 |                   |            |- bh->b_dirt=0//干净的
 |
 |- kernel --- blk_drv --- ll_rw_block.c --- ll_rw_block() --- make_request(bh)
                                          |- make_request() --- lock_buffer(bh)
                                          |                  |- 在request[32]中找到空闲请求项req
                                          |                  |- 如果没有空闲请求项
                                          |                  |      sleep_on(&wait_for_request)
                                          |                  |      //切换到进程B
                                          |                  |      返回1，重新查找
                                          |                  |  //从反向查找，第一个请求可以用于读
                                          |                  |- req->bh=bh
                                          |                  |- add_request(req)
                                          |- lock_buffer() --- while (bh->b_lock)
                                          |                 |      sleep_on(&bh->b_wait);
                                          |                 |- bh->b_lock=1
                                          |- add_request() --- if (req->bh)
                                                            |       req->bh->b_dirt=0;
                                                            |  //去除脏的标志
                                                            |- if (!(tmp = dev->current_request)){
                                                            |       dev->current_request = req;
                                                            |       (dev->request_fn)();
                                                            |        return;
                                                            |  }
                                                            |  //硬盘还在读，插入请求队列
                                                            |- req->next=tmp->next;
                                                            |- tmp->next=req;
```

```cpp
//硬盘中断
--- kernel --- blk_drv --- hd.c --- write_intr() --- end_request(1)
            |           |
            |           |- blk.h --- end_request() --- unlock_buffer()
            |                     |                 |- wake_up(&wait_for_request)
            |                     |                 |  //唤醒进程A
            |                     |                 |- CURRENT->dev = -1
            |                     |                    //释放请求项
            |                     |- unlock_buffer() --- bh->b_lock=0//bh解锁
            |                                         |- wake_up(&bh->b_wait)
            |                                            //唤醒进程C
            |- sched.c --- wake_up(p) --- (**p).state=0
```
 - 由于进程C的时间片多于进程A，因此切换到进程C执行
 
#### 缓冲区的设计指导思想是让数据在缓冲区中停留的时间尽可能长