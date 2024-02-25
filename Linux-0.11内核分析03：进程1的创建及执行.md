## 进程1的创建及执行

### 1. 进程0创建进程1

```cpp
 --- init --- main.c --- sched_init()
  |                   |- hd_init()
  |                   |- fork() --- int 0x80//系统调度中断
  |                   |- init() --- setup() --- int 0x80
  |                   |- pause() --- int 0x80
  |
  |- kernel --- sched.c --- sched_init() --- set_system_gate(0x80,&system_call)//注册中断
  |          |           |- sys_pause() --- schedule()
  |          |           |- schedule() --- switch_to()
  |          |           |- sleep_on() --- *p = current//p=&bh->b_wait
  |          |           |              |- schedule()
  |          |           |- wake_up() --- (**p).state=0//p=&bh->b_wait,进程1就绪
  |          |
  |          |- sched.h --- switch_to()//进程1切换到进程0后在sys_pause中循环
  |          |
  |          |- system_call.s --- system_call() --- sys_call_table(,%eax,4)
  |          |                 |- sys_fork() --- find_empty_process()//找到空闲任务结构task[nr]
  |          |                 |              |- copy_process()//复制父进程任务结构和页表
  |          |                 |- hd_interrupt() --- do_hd()
  |          |
  |          |- fork.c --- find_empty_process() --- 返回进程号nr，
  |          |          |                        |  并且找到最小的pid值赋值给last_pid
  |          |          |- copy_process() --- p=get_free_page()//开辟新的一页内存用于存放子进程任务结构
  |          |          |                  |- *p=*current//复制父进程任务结构给子进程
  |          |          |                  |- p->tss.eip=eip
  |          |          |                  |- p->tss.eax=0//这是子进程执行时，fork函数的返回值
  |          |          |                  |- copy_mem(p)//建立页表映射，并复制父进程页表
  |          |          |                  |- f->f_count++
  |          |          |                  |- set_tss_desc()//将task[nr]的tss和ldt地址填入GDT
  |          |          |                  |- set_ldt_desc()
  |          |          |                  |- p->state = TASK_RUNNING//子进程改为就绪态
  |          |          |- copy_mem() --- set_base(p->ldt[1]...)//子进程ldt，数据段和代码段基地址
  |          |                         |- set_base(p->ldt[2]...)//赋值为0x4000000*nr
  |          |                         |- copy_page_tables()//建立页表映射，并复制父进程页表
  |          |
  |          |- blk_drv --- hd.c --- sys_setup() --- hd_info[2]赋值
  |                      |        |               |- hd[0]和hd[5]赋值
  |                      |        |               |- bh=bread()
  |                      |        |               |- 判断硬盘信息有效
  |                      |        |               |- 根据硬盘中的分区信息设置hd[1]~hd[4]
  |                      |        |               |- brelse(bh)
  |                      |        |               |- rd_load()//用软盘格式化虚拟盘
  |                      |        |               |- mount_root()//加载根文件系统
  |                      |        |- hd_init() --- blk_dev[3].request_fn = do_hd_request
  |                      |        |             |- set_intr_gate(0x2E,&hd_interrupt);
  |                      |        |- do_hd_request() --- INIT_REQUEST//CURRENT==NULL时返回
  |                      |        |                   |- hd_out(...,&read_intr) --- 控制硬盘开始读写,
  |                      |        |                                              |  完成后引发中断
  |                      |        |                                              |- do_hd=read
  |                      |        |- read_intr() --- port_read(...CURRENT->buffer)
  |                      |                        |  //CURRENT=blk_dev[3].current_request
  |                      |                        |  //CURRENT->buffer=bh->b_data
  |                      |                        |- end_request(1)//读取完成后执行到这里
  |                      |                        |- do_hd_request()
  |                      |
  |                      |- ll_rw_block.c --- ll_rw_block() --- major=MAJOR(bh->b_dev)
  |                      |                 |                 |- make_request(major,bh)
  |                      |                 |- make_request() --- lock_buffer(bh)
  |                      |                 |                  |- 找到空闲请求req
  |                      |                 |                  |- req->buffer=bh->b_data
  |                      |                 |                  |- req->next=NULL
  |                      |                 |                  |- add_request(blk_dev[major],req)
  |                      |                 |- add_request() --- blk_dev[3]->current_request=req
  |                      |                                   |- blk_dev[3]->request_fn
  |                      |
  |                      |- blk.h --- end_request() --- CURRENT->bh->b_uptodate = 1
  |                      |         |                  |- unlock_buffer(CURRENT->bh)
  |                      |         |                  |- CURRENT = CURRENT->next//CURRENT=NULL
  |                      |         |- unlock_buffer() --- bh->b_lock=0 
  |                      |                             |- wake_up(&bh->b_wait)
  |                      |
  |                      |- ramdisk.c --- rd_load() --- bh=breada()
  |                                                  |- 拷贝bh->b_data到s//s为超级块
  |                                                  |- brelse(bh)
  |                                                  |- 计算虚拟块数
  |                                                  |- 将软盘文件系统复制到虚拟盘
  |                                                  |- ROOT_DEV=0x0101//虚拟盘设置为根设备
  |
  |- include --- linux --- sys_call_table[] --- sys_fork()
  |                                          |- sys_pause()
  |                                          |- sys_setup()
  |
  |- mm --- memery.c --- copy_page_tables() --- from和to分别为父进程和子进程线性地址
  |                                          |- from_dir=(from>>20) & 0xffc //取出页目录偏移，然后乘上4
  |                                          |- to_dir=(to>>20) & 0xffc     //等于在页目录中实际的地址
  |                                          |- size = (size+0x3fffff)) >> 22
  |                                          |  //一个页表管理4MB内存，">>22"相当于"/4MB"
  |                                          |  //也就是将要拷贝的字节数转为要拷贝的页表数
  |                                          |- for( ; size-->0 ; from_dir++,to_dir++) {
  |                                          |      from_page_table=0xfffff000 & *from_dir;
  |                                          |      //取出父进程页表地址
  |                                          |      to_page_table=get_free_page();
  |                                          |      //申请一个页面作为子进程页表
  |                                          |      *to_dir = to_page_table | 7;
  |                                          |      //将该页面放入子进程的页目录表
  |                                          |      nr = (from==0)?0xA0:1024;
  |                                          |      for(;nr-->0;from_page_table++,to_page_table++) {
  |                                          |          this_page = *from_page_table;
  |                                          |          //取出父进程的页地址
  |                                          |          this_page &= ~2;//设置为只读
  |                                          |          *to_page_table = this_page;
  |                                          |          //放入子进程页表
  |                                          |          处理mem_map[]
  |                                          |      }
  |                                          |  }
  |                                          |- invalidate()//刷新CR3页高速缓存
  |
  |- fs --- buffer.c --- bread() --- bh=getblk()
         |            |           |- ll_rw_block(bh)
         |            |           |- wait_on_buffer(bh)
         |            |           |- if(bh->b_uptodate)//返回bh
         |            |- getblk() --- get_hash_table()
         |            |            |- 遍历free_list,找到空闲bh
         |            |            |- remove_from_queues(bh)
         |            |            |- bh->b_dev=dev
         |            |            |  bh->b_blocknr=block
         |            |            |- insert_into_queues(bh)
         |            |- get_hash_table() --- find_buffer()
         |            |- find_buffer()
         |            |- remove_from_queues(bh)
         |            |- insert_into_queues(bh) --- hash(...) = bh
         |            |- wait_on_buffer() --- sleep_on(&bh->b_wait)
         |                                    //等待读盘完成b_wait=NULL
         |
         |- super.c --- mount_root() --- 初始化super_block[8]
                     |                |- p=read_super(ROOT_DEV)//读取超级块
					 |                |- mi=iget(ROOT_DEV,ROOT_INO)//读取根节点
					 |                |- p->s_isup = p->s_imount = mi//挂接i节点
                     |                |- current->pwd = mi
                     |                |- current->root = mi
					 |- read_super() --- 从super_block[8]中申请一项
					 |                |- s->s_dev = dev
                     |                |- lock_super(s)
                     |                |- bh = bread(dev,1)
                     |                |- 拷贝bh->b_data到s//s前半部分被填充
                     |                |- s->s_imap[i]=bread()
                     |                |- s->s_zmap[i]=bread()
                     |- iget() --- empty = get_empty_inode()
                     |          |- inode=empty
                     |          |- inode->i_dev = dev
                     |          |- inode->i_num = nr
                     |          |- read_inode(inode)
                     |- read_inode() --- sb=get_super(inode->i_dev)
                                      |- bh=bread(inode->i_dev,block)
                                      |- 拷贝bh->b_data到inode//inode前半部分被填充
```

### 总结
**进程0创建进程1**
1. `fork()`函数执行，触发0x80中断，系统由特权级3转换为特权级0，跳转到sys_fork执行。
2. sys_fork中首先使用`find_empty_process()`函数找到空闲的进程号nr，和最小的pid值，然后调用`copy_process()`函数复制父进程任务结构到给子进程。
3. `copy_process()`函数先将task[nr]指向新的一页内存，然后将父进程任务结构复制到task[nr]指向的内存；然后修改task[nr]的tss.eip=当前eip，tss.eax=0，tss.ldt = _LDT(nr)；最后调用`copy_mem()`函数复制父进程页表到子进程。
4. `copy_mem()`函数中，设置新的数据段和代码段基址为nr*0x4000000，再将其填入当前进程的LDT[1]和LDT[2]，然后调用`copy_page_tables()`函数开始复制页表。
5. `copy_page_tables()`函数**建立的新的映射关系**，并复制父进程的页表到子进程。首先申请一页内存作为子进程的页表，将页表首地址填入页目录表，然后将父进程的页表复制到子进程的页表中，最后写CR3寄存器，刷新MMU，这样父进程和子进程就共享同样的内存了。映射建立完后就可以直接使用线性地址寻址了。
6. 返回`copy_process()`函数，将填充好的task[nr]的tss和ldt的地址填充到GDT中相应的位置。
7. 将进程1改为状态改为就绪态，最终中断返回，fork返回子进程pid值。
8. 死循环中执行pause()，将当前进程（进程0）改为可中断等待状态，然后调用`schedule()`函数。
9. `schedule()`函数找到task[]中就绪态的进程只有进程1，于是切换到进程1。
10. 系统自动载入tss中的寄存器值到各寄存器，其中eip为进程0调用0x80中断后地址，exa=0，代码段基址在LDT[1]中，为0x4000000，这个线性地址是和进程0共享同一段内存的，因此代码段的物理地址是相同，因此跳转到进程0的eip的位置执行，也就是system_call函数的iret的位置。
11. 同样fork函数返回，返回值为exa，也就是0，执行`init()`函数。

**读取硬盘信息**
1. `init()`函数中执行`setup()`系统调用，触发0x80中断，系统转换到特权级0，执行`sys_setup()`函数。
2. `sys_setup()`函数中调用`bread()`读取硬盘信息到缓冲区bh，硬盘设备号是0x300和0x305，从0开始读取。
3. `bread()`函数中，首先使用`getblk()`函数在缓冲区中找到空闲的缓冲块。
4. `getblk()`函数遍历缓冲区数据结构，找到空闲的缓冲块，然后将缓冲块bh->b_dev=dev，返回缓冲区管理结构。
5. 返回`bread()`函数，调用`ll_rw_block()`函数从硬盘中读取数据到缓冲块。其中
```cpp
major=MAJOR(bh->b_dev)=MAJOR(0x300)=3
blk_dev[major].request_fn=blk_dev[3].request_fn=do_hd_request
```
决定了硬盘该请求是硬盘读写请求。
6. `bread()`函数继续执行`wait_on_buffer()`函数等待硬盘读取完成，完成后返回bh
7. 返回`sys_setup()`函数，判断刚才读取的硬盘引导区内容是否有效，然后根据硬盘中的分区信息设置虚拟分区。

**挂载根文件系统**
1. `sys_setup()`函数中，继续调用`rd_load()`函数，读取软盘内容到内存的虚拟盘(4-6MB)中，并将根设备设置为虚拟盘（0x0101）。然后调用`mount_root()`函数挂载文件系统。
2. `mount_root()`函数中，先初始化file_table[64]，然后初始化super_block[8]，然后读取根文件系统（虚拟盘）的超级块到p，调用`iget()`函数读取根文件系统的根节点到mi。
3. `iget()`函数中，先在inode_table[32]中申请一个空闲的inode节点，然后将`inode->i_dev = dev; inode->i_num = nr`，nr为inode号，这里为1。然后调用`read_inode()`函数读取该节点。
4. `read_inode()`函数中首先读取inode->i_dev的超级块，然后和根据超级块的信息确定inode->i_num对应的块，最后使用`bread()`函数读取对应inode节点。
5. 最终返回`iget()`函数，将`p->s_isup = p->s_imount = mi`完成根文件系统的挂载。
6. 中断返回，最终返回`sys_setup()`函数。