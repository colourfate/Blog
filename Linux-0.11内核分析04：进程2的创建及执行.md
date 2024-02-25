## 进程2的创建及执行

### 代码树

```cpp
--- init --- main.c --- sched_init()
 |                   |- init() --- setup() --- int 0x80
 |                              |- open("/dev/tty0") --- int 0x80//根文件系统挂载完毕，打开tty设备
 |                              |- dup(0) --- int 0x80//建立标准输出文件
 |                              |- dup(0) --- int 0x80//标准错误文件
 |                              |- pid=fork() --- int 0x80  //创建进程2
 |                              |- if(!pid) {         //进程2进入
 |                              |      close(0);      //关闭tty0
 |                              |      open("/etc/rc",O_RDONLY,0);       //打开rc文件
 |                              |      execve("/bin/sh",argv_rc,envp_rc);//执行shell程序，读取rc文件
 |                              |      _exit(2);      //进程2退出
 |                              |  }
 |                              |- if (pid>0)
 |                              |      while (pid != wait(&i))//调度到进程2，等待其退出
 |                              |- while (1) {
 |                              |      pid=fork();    //创建进程4
 |                              |      if (!pid) {    //进程4进入
 |                              |          close(0);close(1);close(2);//关闭rc文件
 |                              |          setsid();
 |                              |          (void) open("/dev/tty0",O_RDWR,0);//打开tty0
 |                              |          (void) dup(0);
 |                              |          (void) dup(0);
 |                              |          _exit(execve("/bin/sh",argv,envp));//执行shell程序，读取tty0
 |                              |      }
 |                              |      while (1)
 |                              |          if (pid == wait(&i))//调度到进程4
 |                              |              break;
 |                              |      sync();          //同步硬盘数据
 |                              |  }
 |
 |- kernel --- sched.c --- sched_init() --- set_system_gate(0x80,&system_call)
 |          |
 |          |- system_call.s --- system_call() --- sys_call_table(,%eax,4)
 |          |                 |- sys_execve() --- eax指向堆栈中eip指针处
 |          |                                  |- do_execve()
 |          |
 |          |- exit.c --- sys_waitpid --- 找到current的子进程*p，也就是进程2
 |                     |               |- p处于僵死态，则返回(*p)->pid
 |                     |               |  否则继续运行  
 |                     |               |- 设置current->state为等待状态
 |                     |               |- schedule()//切换到进程2
 |                     |               |- 检测到SIGCHLD信号量,返回第1条执行
 |                     |- sys_exit() --- do_exit()
 |                     |- do_exit() --- 释放shell进程所占据的内存页面
 |                                   |- 将update的父进程设置为进程1
 |                                   |- 关闭当前进程打开着的所有文件
 |                                   |- 把当前进程置为僵死状态
 |                                   |- tell_father()//通知父进程
 |                                   |- schedule()//发现进程1收到信号,切换到进程1
 |
 |- include --- linux --- sys_call_table[] --- sys_open()
 |                                          |- sys_dup(0)
 |                                          |- sys_fork()//复制父进程
 |                                          |- sys_waitpid()
 |                                          |- sys_close()
 |                                          |- sys_read()
 |                                          |- sys_exit()
 |
 |- fs --- open.c --- sys_open(pathname) --- 找到current中空闲filp[fd]
 |      |          |                      |- 在file_table[64]中获取空闲项的地址f
 |      |          |                      |- filp[fd]=f
 |      |          |                      |- 文件引用计数加1
 |      |          |                      |- open_namei(pathname,&inode)
 |      |          |                      |- current->tty = MINOR(inode->i_zone[0])
 |      |          |                      |- f->f_inode = inode//设置file_table[0]
 |      |          |- sys_close() --- filp = current->filp[fd]
 |      |                          |- current->filp[fd] = NULL
 |      |                          |- filp->f_count减1  
 |      |
 |      |- namei.c --- open_namei() --- dir=get_dir(pathname,&namelen,&namebase)
 |      |           |                |  //获取dev目录inode,以及'tty0'的长度和首地址
 |      |           |                |- find_entry(&dir,namebase,namelen,&de)
 |      |           |                |  //根据上面的信息得，从dev目录得到tty0的目录项de
 |      |           |                |- inr=de->inode; dev=dir->i_dev
 |      |           |                |- 保存inr和dev在table_inode[32]中
 |      |           |                |- inode=iget(inr,dev)//得到tty0的i节点
 |      |           |- get_dir() --- inode = current->root
 |      |                         |- pathname指向'd'
 |      |                         |- thisname = pathname
 |      |                         |- 获取thisname的长度namelen
 |      |                         |- pathname指向下一个目录
 |      |                         |- pathname是最后一个目录则返回inode
 |      |                         |- find_entry(&inode,thisname,namelen,&de)
 |      |                         |  //根据上面的信息得到目录项de
 |      |                         |- inr=de->inode; dev=dir->i_dev
 |      |                         |- iput(inode)
 |      |                         |- inode=iget(idev,inr)
 |      |                         |- 返回3执行
 |      |
 |      |- fcntl.c --- sys_dup() --- dupfd(0,0)
 |      |           |- dupfd() --- 在进程1的filp[20]中寻找空闲项filp[arg]
 |      |                       |- filp[arg]指向目标文件
 |      |
 |      |- exec.c --- do_execve() --- inode=namei(filename)
 |      |                          |- bh = bread(inode->i_dev,inode->i_zone[0])
 |      |                          |- ex = *((struct exec *) bh->b_data)
 |      |                          |- eip[0] = ex.a_entry//eip指向shell程序
 |      |                             //由于该线性空间对应的程序内容未加载，因此会触发 page_fault
 |      |
 |      |- read_write.c --- sys_read() --- 如果是普通文件,读取完成后返回-ERROR
 |
 |- mm --- page.s --- page_fault() --- do_no_page()
        |- memery.c --- do_no_page() --- page = get_free_page()
                     |                |- bread_page(page,current->executable->i_dev,nr)
                     |                |- put_page(page)//建立页表映射关系,之后shell程序开始执行
                     |                   //中断退出后,shell程序执行
                     |- put_page() --- page_table = (address>>20) & 0xffc
                                    |- page_table[(address>>12) & 0x3ff] = page | 7   


--- bin --- sh --- 读取/etc/rc文件，并执行
 |
 |- etc --- rc --- /etc/update &//创建update程序，挂起后返回进程2
                |- echo "/dev/hd1 /" > /etc/mtab --- read() --- int 0x80  
                |- 返回错误则执行exit() --- int 0x80                
```

### 总结
**打开tty0**
1. 进程1在init()函数中，执行open("/dev/tty0",O_RDWR,0)打开tty设备，系统触发0x80中断，跳转到sys_open()函数中执行。
2. 在sys_open()函数中，首先在进程1的任务结构的filp[20]找到一个空闲的项filp[fd]，然后在file[64]中找到一个空闲项，其地址存在f中，然后将filp[fd]=f。接着调用open_namei()函数读取tty设备文件的inode。
3. 在open_namei()函数中，调用dir_namei()函数获取枝梢节点，然后使用find_entry()函数在枝梢节点中找到名字匹配的目录项，最后根据目录项中的设备号和inode号，调用iget()函数读取文件的inode，读取完成后，返回inode号
 3.1. 在dir_namei()函数中，调用get_dir()函数得到枝梢节点
 3.2. 在get_dir()函数中，获取下一个目录的名称，然后调用find_entry()在目录文件中找到名称相同的目录项，然后根据目录项中的设备号和inode号，调用iget()函数读取文件的inode。
 3.3. 循环3.2过程，直到读取到枝梢节点为止，然后返回inode号。
4. 回到sys_open()函数，将f指向的文件结构中绑定该tty0的inode号。函数返回。
5. 回到init()函数中，调用dup(0)两次将当前进程的filp[20]中再找到两个空闲项，给它们filp[0]的值。

**进程1创建进程2**
1. 继续执行init()函数，接着执行fork()函数创建进程2，然后wait()函数切换到进程2执行。
2. 在wait()系统调用最终执行sys_waitpid()函数，该函数中遍历所有任务结构，若没有任何进程处于僵死态或停止态，则将当前进程置为可中断等待状态，然后调用schedule()函数，切换到进程2。
3. 切换到进程2，仍然在init()函数中执行，首先执行close(0)关闭进程1打开的tty0，然后调用open("/etc/rc",O_RDONLY,0)打开rc文件，最后调用execve("/bin/sh",argv_rc,envp_rc)执行脚本
4. execve()函数触发0x80中断，最终调用do_execve()函数。该函数中首先调用namei()函数获取shell文件所在的文件节点，然后将shell文件头读取到缓冲区，接着将current->executable置为shell文件的inode，释放掉进程2已经建立好的页表，并将环境变量放入数据段当中，最后设置脚本文件的入口地址和栈指针（栈指针指向数据段末尾）到栈中，调用ret即可跳转到脚本的入口地址运行。
5. 由于shell文件并没有读入代码段，所以会触发缺页中断，最终跳转到do_no_page()函数执行。
6. do_no_page()函数中，首先新申请一页新的内存，然后根据current->executable读取shell文件的一页数据到新的内存页中，最后调用put_page()将这页内存写入到页表和页目录。返回执行shell程序。
7. shell程序从filp[0]中读取命令并执行，filp[0]现在是rc文件，文件中重要的一点是执行了`/etc/update &`，该命令创建了一个新的update进程，也就是进程3。update进程用于将缓冲区的数据和硬盘进行同步。

**进程2退出，重建新的shell进程**
1. shell程序执行完rc文件后退出，调用do_exit()函数。
2. do_exit()函数首先释放当前进程的代码段和数据段，然后检测当前进程是否有子进程，若有子进程，将子进程的父进程置为进程1，接着将当前进程设置为僵死态，然后调用tell_father()函数给父进程（进程1）发送信号，最后调用schedule()函数进行调度。
3. schedule()函数中，遍历所有进程，找到接收到信号的进程（进程1）并将其置为就绪态，然后查找所有就绪态的进程，找到最合适的那一个，切换到那个进程。
4. 进程1在sys_waitpid()函数中切换到进程2，现在返回进程1，仍然从sys_waitpid()函数继续执行。
5. 在sys_waitpid()函数中，发现当前进程收到了SIGCHLD信号，返回sys_waitpid()函数头重新执行一次。遍历所有任务结构，找到僵死态进程（进程2），对进程2进行释放，返回释放的进程号（2）.
6. 回到init()函数继续执行，进程1创建调用fork()函数创建一个新进程（进程4），然后再次调用wait()系统调用，切换到进程4中。
7. 进程4首先关闭了filp[0],filp[1]和filp[2]，然后重新打开/dev/tty0，并重新执行/bin/sh程序。这次，因为进程4打开的文件是tty0，而非rc，因此shell程序开始执行后不会退出。