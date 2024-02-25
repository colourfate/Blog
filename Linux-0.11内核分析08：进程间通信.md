#### 1. 管道机制
 - 管道文件的创建过程

```cpp
//创建管道实例
#include <stdio.h>
#include <unistd.h>

int main()
{
    int n, fd[2];
    pid_t pid;
    int i, j;
    char str1[1024];
    char str2[512];
    
    for(i=0; i<1024; i++){
        str1[i]='A';
    }
    if(pipe(fd) < 0){
        printf("pipe error\n");
        return -1;
    }
    if(pid = fork() < 0){
        printf("fork error\n");
        return -1;
    }else if(pid > 0){  // 父进程写数据
        close(fd[0]);
        for(i=0; i<10000; i++){
            write(fd[1], str1, strlen(str1));
        }
    }else{              // 子进程读数据
        close(fd[1]);
        for(i=0; i<20000; i++){
            read(fd[0], str2, strlen(str2));
        }
    }
    
    return 0;
}
```

```cpp
 fs --- pipe.c --- sys_pipe() --- 在file_table[64]中申请两个空闲项
     |                         |  分别为f[0]和f[1]
     |                         |- 在current的filp[20]中找到两个空闲项
     |                         |  filp[fd[0]]和filp[fd[1]]，分别指向
     |                         |  f[0]和f[1]
     |                         |- inode=get_pipe_inode()
     |                         |- f[0]->f_inode = f[1]->f_inode = inode
     |                         |  //指向同一个indoe
     |                         |- f[0]->f_mode = 1//读
     |                         |- f[1]->f_mode = 2//写
     |
     |- inode.c --- get_pipe_inode() --- inode = get_empty_inode()
                                      |- inode->i_size=get_free_page()
                                      |- inode->i_count = 2
                                      |- PIPE_HEAD(*inode) = PIPE_TAIL(*inode) = 0
                                      |- inode->i_pipe = 1
```

#### 管道的操作

 - 假设首先进行读进程，此时管道中还没有数据，size=0, 读进程会被挂起，切换到写进程中执行
 - 写进程执行，str1[1024]开始被写入管道。当写完一次后，说明此时管道中已经有数据可以供读取，此时唤醒读进程
 - 读进程虽然被唤醒，但是写进程还没有退出，所以写进程继续执行

```cpp
//尾指针用于读，头指针用于写
 fs --- pipe.c --- read_pipe() --- size=PIPE_SIZE(*inode)
                |               |  //size表示还有多少未读数据
                |               |- 若size=0表示全部读完，唤醒写进程，本进程休眠
                |               |- chars = PAGE_SIZE-PIPE_TAIL(*inode)
                |               |  //chars表示管道中还剩余的字节数
                |               |- if (chars > count)
                |               |      chars = count;
                |               |  //剩余字节数大于需读取的字节数
                |               |  //取需读取的字节数
                |               |- if (chars > size)
                |               |      chars = size;
                |               |  //要读的数据大于管道剩余未读的数据
                |               |  //取剩余未读数据
                |               |- count -= chars
                |               |- PIPE_TAIL(*inode) += chars
                |               |  //移动尾指针
                |               |- PIPE_TAIL(*inode) &= (PAGE_SIZE-1)
                |               |  //指针移动到4095以外，回滚到页首
                |               |- 拷贝内容到用户空间
                |               |- 唤醒写进程
                |- write_pipe() --- size=(PAGE_SIZE-1)-PIPE_SIZE(*inode) 
                                 |- //size表示管道中还有多少空间可供写入
                                 |- 若size=0表示管道中没有空间了，唤醒读进程，本进程休眠
                                 |- chars = PAGE_SIZE-PIPE_HEAD(*inode)
                                 |  //chars表示管道中还剩余的字节数
                                 |- if (chars > count)
                                 |      chars = count;
                                 |- if (chars > size)
                                 |      chars = size;
                                 |- count -= chars
                                 |- PIPE_HEAD(*inode) += chars
                                 |- PIPE_HEAD(*inode) &= (PAGE_SIZE-1)
                                 |- 将数据写入管道
                                 |- 唤醒读进程
```

 - 假设写管道的过程中发生了时钟中断，写进程的时间片会被削减，但是只要大于零，就不会退出。
 
```cpp
 kernel --- sched.c --- do_timer() --- if ((--current->counter)>0) return
                                    |- schedule()
```

 - 写进程一直写数据到管道中，直到管道写满，会挂起本进程，切换到读进程中执行

```cpp
 fs --- pipe.c --- read_pipe() --- size=PIPE_SIZE(*inode)
                                |- while(!size){
                                |       wake_up(&inode->i_wait);
                                |       sleep_on(&inode->i_wait);
                                |  }
```

 - 读进程执行，读出一次管道数据后，管道中有空间可供写入，唤醒写进程
 - 写进程虽被唤醒，但是读进程还没发生调度，因此读进程继续读取数据。
 - 假设期间发送时钟中断，会削减读进程时间片，时间片削减为0后切换到写进程中执行。
 - 写进程的尾指针调度之前指向4095的位置，此时唤醒后仍然为4095，进入下一次循环，由于尾指针的位置变了，因此size不为0，chars=1, HEAD=4096, 此时与上4095，HEAD=0, 回滚到页首，重新开始写入。
 - 写进程一直写数据，直到管道再次被写满，重新挂起，切换到读进程。
 - 此时读进程时间片为0，因此，进入schedule()函数后会重新分配时间片。

```cpp
 --- kernel --- sched.c --- schedule() --- for(p = &LAST_TASK ; p > &FIRST_TASK ; --p)
                                        |       if (*p)
                                        |           (*p)->counter = ((*p)->counter >> 1) +
                                        |               (*p)->priority;
```

 - 读进程继续执行，直到头指针和尾指针重合，再次切换到写进程。
 - 写进程和读进程轮流执行，直到数据交互完毕。
 
 
 #### 2. 信号机制

 - 示例进程processsig

```cpp

#include <stdio.h>
#include <signal.h>

void sig_usr(int signo)
{
    if(signo == SIGUSR1){
        printf("received SIGUSER1\n");
    }else{
        printf("NOT SIGUSER1\n");
    }
    signal(SIGUSR1, sig_usr);
}

int main(int argc, char **argv)
{
    signal(SIGUSR1, sig_usr); // 绑定信号处理函数
    while(1){
        pause();
    }
    return 0;
}
```
 - 示例进程sendsig
 
```cpp
#include <stdio.h>

int main(int argc, char **argv)
{
    int pid, ret, signo;
    int i;
    
    if(argc != 3){
        printf("Usage <signo> <pid>\n");
        return -1;
    }
    signo = atoi(argv[1]);
    pid = atoi(argv[2]);
    
    ret = kill(pid, signo);
    for(i=0; i<1000000; i++){
        if(ret != 0){
            printf("send signal error\n");
        }
    }
    
    return 0;
}
```

 - 首先执行进程processsig进程，然后执行`./sendsig 10 160`给processsig发送信号
 - processsig进程执行，其中restorer()函数由内核指定

```cpp
 --- kernel --- signal.c --- sys_signal() --- tmp.sa_handler = handler//设置信号处理函数
                                           |- tmp.sa_restorer = restorer//设置恢复现场函数
                                           |- current->sigaction[signum-1] = tmp
                                           |  //设置当前进程的信号
```

 - processsig进程进入可中断等待状态，切换到sendsig中执行

```cpp
 --- kernel --- sched.c --- sys_pause() --- current->state = TASK_INTERRUPTIBLE
                                         |- schedule()
```

 - sendsig会执行`ret=kill(pid, signo)`这一行代码，对应`sys_kill()`函数

```cpp
--- kernel --- exit.c --- sys_kill() --- 找到需要kill的进程p
                      |              |- send_sig(sig,*p,0)//发送信号0
                      |- send_sig() --- p->signal |= (1<<(sig-1))//设置信号位图
```

 - 发送完成后，sendsig进程退出，进入进程0，进程0中执行schedule()函数，发现processsig进程接收到信号，于是唤醒processsig进程
 
```cpp
--- kernel --- sched.c --- schedule() --- for(p = &LAST_TASK ; p > &FIRST_TASK ; --p)
                                       |      if (((*p)->signal & ~(_BLOCKABLE & (*p)->blocked)) &&
                                       |      (*p)->state==TASK_INTERRUPTIBLE)
                                       |            (*p)->state=TASK_RUNNING;
                                       |- 再次遍历task_struct[32]，发现只有processsig处于就绪态
                                       |- switch_to(next)
```

 - processsig进程开始执行，会继续在循环中执行pause()函数，这是一个系统调用，当系统调用返回时，会执行ret_form_sys_call标号处，最终会调用do_signal()函数

```cpp
 --- kernel --- system_call.s --- ret_from_sys_call --- do_signal()
             |
             |- signal.c --- do_signal() --- old_eip=eip
                                          |  //备份eip
                                          |  sa = current->sigaction + signr - 1
                                          |  //获取接收到的信号
                                          |- sa_handler = (unsigned long) sa->sa_handler
                                          |  //获取信号处理函数
                                          |- *(&eip) = sa_handler
                                          |  //返回后跳转到处理函数执行
                                          |- old_eip，eflags，edx，ecx，eax，
                                          |  signr，sa->sa_restorer依次压到用户栈
                                          |- 返回，跳转到sa_handler处执行
```

 - 信号处理函数结束后，会执行ret指令，该指令会将栈顶的内容放到eip中，最终跳转到eip执行，此时栈顶是sa->sa_restorer，因此跳转到restorer处执行。
 - restorer会依次将eax, ecx, edx和eflags恢复，然后执行ret，此时栈顶是old_eip，因此跳转回到processsig函数继续执行
 
#### 3. 信号对可中断等待状态的影响

```cpp
 --- kernel --- exit.c --- do_exit() --- current->state = TASK_ZOMBIE
             |          |             |- tell_father(current->father)
             |          |             |- schedule()//这里不返回了
             |          |- tell_father() --- 找到pid相符的进程task[i]
             |          |                 |- task[i]->signal |= (1<<(SIGCHLD-1)
             |          |                 |  //发送子进程退出信号
             |          |- sys_waitpid() --- 检测当前进程的子进程的状态
             |                            |  如果处于僵死态
             |                            |- release(*p)//释放子进程
             |
             |- sched.c --- schedule() --- for(p = &LAST_TASK ; p > &FIRST_TASK ; --p)
                                        |      if (((*p)->signal & ~(_BLOCKABLE & (*p)->blocked)) &&
                                        |      (*p)->state==TASK_INTERRUPTIBLE)
                                        |            (*p)->state=TASK_RUNNING;
                                        |            //找到接收到信号的进程，设置为就绪态
                                        |- 第二次遍历，只有shell为就绪态，切换到shell进程执行
```

#### 4. 信号对不可中断等待状态的影响

 - 假设系统中有三个进程A,B,C，都处于就绪状态。进程B是进程A的子进程，进程A正在运行
 
```cpp
//进程A和B
void main(void)
{
    char buffer[12000];
    int pid, i;
    int fd = open("/mnt/user/hello.txt", O_RDWR, 0644);
    read(fd, buffer, sizeof(buffer));
    if(!(pid = fork())){
        exit();             //子进程B退出
    }
    if(pid < 0){
        while(pid != wait($i));
    }
    close(fd);
    return;
}

//进程C
void main(void)
{
    int i, j;
    for(i=0; i<1000000; i++)
        for(i=0; i<1000000; i++);
}
```

 - 进程A执行read()系统调用，最终会执行到bread()读取缓冲块

```cpp
 --- fs --- buffer.c --- bread() --- ll_rw_block()//向硬盘发送读指令
  |                   |           |- wait_on_buffer()//等待硬盘读写完成
  |                   |- wait_on_buffer() --- while(bh->b_lock)
  |                                        |      sleep_on(&bh->b_wait)
  |      
  |- sched.c --- sleep_on() --- current->state = TASK_UNINTERRUPTIBLE
                             |  //设置为不可中断等待状态
```

 - 进程A等待硬盘读取，从而切换到B执行，进程B进入后直接退出

```cpp
 --- kernel --- exit.c --- do_exit() --- current->state = TASK_ZOMBIE
                        |             |- tell_father(current->father)
                        |             |- schedule()//这里不返回了
                        |- tell_father() --- 找到pid相符的进程task[i]
                        |                 |- task[i]->signal |= (1<<(SIGCHLD-1)
                        |                 |  //发送子进程退出信号
```

 - 进入schedule()函数后，虽然进程A收到了信号，但是由于处于不可中断等待状态，所以不会被设置为就绪态

```cpp
--- kernel --- sched.c --- schedule() --- for(p = &LAST_TASK ; p > &FIRST_TASK ; --p)
                                       |      if (((*p)->signal & ~(_BLOCKABLE & (*p)->blocked)) &&
                                       |      (*p)->state==TASK_INTERRUPTIBLE)
                                       |            (*p)->state=TASK_RUNNING;
                                       |            //这里不会把进程A设置为就绪态
                                       |- 再次遍历task_struct[32]，发现只有进程C处于就绪态
                                       |- switch_to(next)
```
 - 进程C执行一段时间后，硬盘读取完毕，产生硬盘中断，唤醒进程A

```cpp
 --- kernel --- blk_dev --- blk.h --- end_request() --- unlock_buffer(CURRENT->bh)
                                   |- unlock_buffer() --- wake_up(&bh->b_wait)

```

 - 进程A唤醒后，进程C继续执行，等待时间片耗尽后，切换到进程A
 - 进程A将数据从缓冲区拷贝到进程空间，然后sys_read()返回，又会执行到do_signal()函数检测信号。
 - 由于之前进程B退出向进程A发送了子进程退出信号，因此这里能够检测到，进而进行子进程的退出工作