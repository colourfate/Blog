## 介绍
因为块设备驱动和网络设备驱动实际中用得较少，所以只给出驱动模板，我也没有具体测试，等到实际用到是再研究吧，溜了溜了。

---------

## 块设备驱动模板

```cpp
struct xxx_dev {
    int size; 
    struct request_queue *queue;    /* The device request queue */
    struct gendisk *gd;             /* The gendisk structure */
    spinlock_t lock;                // 如果使用请求队列需要自旋锁
}

static int xxx_major;
module_param(xxx_major, int, 0);// 主设备号为0, 动态获取
#define HARDSECT_SIZE xxx       // HARDSECT_SIZE为硬盘的块大小, 一般为512字节
#define NSECTORS xxx            // 硬盘总的扇区数
#define xxx_MINORS              // 次设备号最大数目, 一个分区对应一个次设备号

/* 
 * 这里是具体的硬件操作
 * @sector: 要写/读硬盘的那个扇区
 * @nsect: 要写/读的扇区数目
 */
static void xxx_disk_transfer(struct vmem_disk_dev *dev, unsigned long sector,
		unsigned long nsect, char *buffer, int write)
{
	unsigned long offset = sector*KERNEL_SECTOR_SIZE;
	unsigned long nbytes = nsect*KERNEL_SECTOR_SIZE;

	if ((offset + nbytes) > dev->size) {
		printk (KERN_NOTICE "Beyond-end write (%ld %ld)\n", offset, nbytes);
		return;
	}
	if (write)
		...
	else
		...
}

// 这个是通用的
static int gen_xfer_bio(struct xxx_dev *dev, struct bio *bio)
{
    struct bio_vec bvec;
    struct bvec_iter iter;
    sector_t sector = bio->bi_iter.bi_sector;   // 要写的扇区号
    // 遍历一个bio的所有bio_vec, __bio_kmap_atomic()将一段内存映射到
    // 要操作的内存页, 然后返回首地址. bio_cur_bytes(bio)获取当前bio_vec.bv_len
	bio_for_each_segment(bvec, bio, iter) {
		char *buffer = __bio_kmap_atomic(bio, iter);
		xxx_disk_transfer(dev, sector, bio_cur_bytes(bio) >> 9,
			buffer, bio_data_dir(bio) == WRITE);
		sector += bio_cur_bytes(bio) >> 9;
		__bio_kunmap_atomic(buffer);
	}
	return 0;
}

// 不使用请求队列绑定该函数
static void xxx_make_request(struct request_queue *q, struct bio *bio)
{
	struct xxx_dev *dev = q->queuedata;
	int status;

	status = gen_xfer_bio(dev, bio);
#if LINUX_VERSION_CODE >= KERNEL_VERSION(4,3,0)
        bio->bi_error = status;
        bio_endio(bio);
#else
        bio_endio(bio, status);
#endif
}

// 使用请求队列绑定该函数
static void vmem_disk_request(struct request_queue *q)
{
	struct request *req;
	struct bio *bio;
    // 1. 从请求队列中拿出一个请求
	while ((req = blk_peek_request(q)) != NULL) {
		struct xxx_dev *dev = req->rq_disk->private_data;
		if (req->cmd_type != REQ_TYPE_FS) {
			printk (KERN_NOTICE "Skip non-fs request\n");
			blk_start_request(req);
			__blk_end_request_all(req, -EIO);
			continue;
		}

		blk_start_request(req);
        // 2. 遍历请求中每一个bio
		__rq_for_each_bio(bio, req)
			gen_xfer_bio(dev, bio);
		__blk_end_request_all(req, 0);
	}
}


// 1. 申请主设备号
xxx_major = register_blkdev(xxx_major, "vmem_disk");

// 2. 记录硬盘大小
struct xxx_dev *dev = kzalloc(NSECTORS*sizeof(struct xxx_dev), GFP_KERNEL);
dev->size = NSECTORS*HARDSECT_SIZE;

// 3.1 不使用请求队列, 绑定xxx_make_request()函数
dev->queue = blk_alloc_queue(GFP_KERNEL);
blk_queue_make_request(dev->queue, xxx_make_request);

// 3.2 使用请求队列, 绑定xxx_request()函数
dev->queue = blk_init_queue(xxx_request, &dev->lock);

// 4. 设置请求队列的逻辑块大小, 将私有数据xxx绑定到队列中
blk_queue_logical_block_size(dev->queue, HARDSECT_SIZE);
dev->queue->queuedata = dev;

// 5. 申请gendisk(相当于cdev)并赋值, 然后添加到系统
dev->gd = alloc_disk(xxx_MINORS);

// 6. 给gendisk赋值, 然后添加到系统
dev->gd->major = xxx_major;
dev->gd->first_minor = 0;
dev->gd->fops = &xxx_ops;           // 绑定block_device_operations
dev->gd->queue = dev->queue;
dev->gd->private_data = dev;        // xxx绑定到了gendisk中
set_capacity(dev->gd, NSECTORS*(HARDSECT_SIZE/KERNEL_SECTOR_SIZE));
add_disk(dev->gd);
```

用户每进行一次对硬盘的操作, 都会被操作系统处理成一个请求, 然后放入相应的请求队列中(该请求队列由驱动定义), 一个请求包含若干个bio, 一个bio又包含若干个bio_vec

bio_vec指向用户需要写入硬盘的数据, 它由如下三个参数组成: 
```cpp
 struct bio_vec {
     struct page *bv_page;      // 数据所在页面的首地址
     unsigned int bv_len;       // 数据长度
     unsigned int bv_offset;    // 页面偏移量
 }
```
 
 一个bio还包含一个bvec_iter, 它由如下4个参数组成:
```cpp
 struct bvec_iter {
	sector_t        bi_sector;	    // 要操作的扇区号
	unsigned int    bi_size;	    // 剩余的bio_vec数目
	unsigned int	bi_idx;		    // 当前的bio_vec的索引号
	unsigned int    bi_bvec_done;	// 当前bio_vec中已完成的字节数
};
```
通过bio, 再结合其中的bio_iter就可以找到当前的bio_vec.

用户可能发出若干对硬盘的操作, 也就对应着若干个bio, 操作系统能够按照一定的算法将这些操作重新组合成一个请求, 硬盘执行这个请求就能够以最高的效率将数据读取/写入.

以上操作仅适用于机械硬盘, 因为机械硬盘按照扇区顺序读写能够达到最高效率. 对于RAMDISK, ZRAM等可以随机访问的设备, 请求队列是没有必要的, 因此不需要请求队列.

------

## 网络设备驱动模板

```cpp
static void xxx_rx (struct net_device *dev)
{
    struct xxx_priv *priv = netdev_priv(dev);
    struct sk_buff *skb;
    int length;

    length = get_rev_len(...); // 获取要接收数据的长度
    skb = dev_alloc_skb(length + 2);

    // 对齐
    skb_reserve(skb, 2);
    skb->dev = dev;

    // 硬件读取数据到skb
    ...

    // 获取上层协议类型
    skb->protocol = eth_type_trans(skb, dev);

    // 把数据交给上层
    netif_rx(skb);

    // 记录接收时间
    dev->last_rx = jiffies;
    ...
}

// 中断接收
static void xxx_interrupt(int irq, void *dev_id)
{
    struct net_device *dev = dev_id;
    status = ior(...); // 从硬件寄存器获取中断状态
    switch (status) {
    case IRQ_RECEIVER_ENENT:    // 接收中断
        xxx_rx(dev);
        break;
    ...
    }
}

static void xxx_timeout (struct net_device *dev)
{
    netif_stop_queue(dev);
    ...
    netif_wake_queue(dev);
}
// 数据发送
static xxx_start_xmit (struct sk_buf *skb, struct net_device *dev)
{
    int len;
    char *data, shortpkt[ETH_ZLEN];
    // 发送队列未满, 可以发送
    if (xxx_send_available()) {
        data = skb->data;
        len = skb->len;
        // 帧长度小于最小长度, 后面补0
        if (len < ETH_ZLEN) {
            memset(shortpkt, 0, ETH_ZLEN);
            memcpy(shortpkt, skb->data, skb->len);
            len = ETH_ZLEN;
            data = shortpkt;
        }
    }
    // 记录时间戳
    dev->trans_start = jiffies;
    
    if (...) {
        // 满足一定添加使用硬件发送数据
        xxx_hw_tx(data, len, dev);
    } else {
        // 否则停止队列
        netif_stop_queue(dev);
        ...
    }
}

static int xxx_open(struct net_device *dev)
{
    ...
    // 申请端口, IRQ等
    ret = request_irq(dev->irq, &xxx_interrupt, 0, dev->name, dev);
    ...
    // 打开发送队列
    netif_start_queue(dev);
    ...
}

static const struct net_device_ops xxx_netdev_ops = {
    .ndo_open = xxx_open,
    .ndo_stop = xxx_stop,
    .ndo_start_xmit = xxx_start_xmit,
    .ndo_tx_timeout = xxx_timeout,
    .ndo_do_ioctl = xxx_ioctl,
    ...
}

// 1. 给net_device结构体分配内存, xxx_priv为私有数据
// 私有数据是和net_device绑定到一起的
struct net_device *ndev;
struct xxx_priv *priv;
ndev = alloc_etherdev(sizeof(struct xxx_priv));

// 2. 硬件初始化, 并将net_device_ops和ethtool_ops与ndev绑定
xxx_hw_init();
ndev->netdev_ops = &xxx_netdev_ops;
ndev->ethtool_ops = &xxx_ethtool_ops;
ndev->watchdog_timeo = timeout; 

// 3. 获取私有数据地址, 为私有数据赋值
priv = netdev_priv(ndev);
...

// 4. 注册ndev
register_netdev(ndev);

// 5. 注销ndev
unregister_netdev(ndev);
free_netdev(ndev);

```