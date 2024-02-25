## 介绍
 platform驱动框架是利用总线(bus_type)+驱动(driver)+设备(device)模型建立的驱动框架。这个模型中总线只有一条，而驱动和设备可以有多个，驱动和设备全都挂接到总线上，总线完成驱动和设备的匹配工作，一旦驱动和设备相匹配，则会执行驱动中的probe函数将驱动注册到系统。同时驱动还可以调用设备中写好的资源(resource)来区别不同的设备，该驱动框架的好处是：
 1. 设备可热插拔。 
 2. 多个设备可共用同一驱动。
下面给出platfom驱动框架的使用模板并且分析它在内核中的实现。

## platform驱动框架代码模板
#### 1. platform_driver
该驱动注册进系统后, 如果`platform_device`注册, 则执行`probe()`函数, 如果`platform_device`注销, 则执行`remove()`函数。设备和驱动的匹配只使用了名字进行匹配。
```cpp
struct xxx_dev {
	...
};

// platform_drvier和platform_device匹配时会调用此函数
static int xxx_probe(struct platform_device *pdev)
{
	struct xxx_dev *my_dev;
	// devm_xxx的函数会自动回收内存
	my_dev = devm_kzalloc(&pdev->dev, sizeof(*gl), GFP_KERNEL);
	...
	platform_set_drvdata(pdev, my_dev);
}

// platform_device从系统移除时会调用此函数
static int xxx_remove(struct platform_device *pdev)
{
	struct xxx_dev *my_dev = platform_get_drvdata(pdev);
	...
}

static struct platform_driver xxx_driver = {
	.driver = {
		.name = "xxx",				// device_driver中只定义了名字
		.owner = THIS_MODULE,
	},
	.probe = xxx_probe,
	.remove = xxx_remove,
};
// 注册platform driver到platform bus
module_platform_driver(xxx_driver);
```
#### 2. platform_device
这部分代码使用模块的形式完成`platform_device`的注册和注销

```cpp
static struct platform_device *xxx_pdev;

static int __init xxx_dev_init(void)
{
	int ret;
	// 注意此名字和platform_driver中的名字一致
	xxx_pdev = platform_device_alloc("xxx", -1);
	if (!xxx_pdev)
		return -ENOMEM;
	// 注册platform_device到系统
	ret = platform_device_add(xxx_pdev);
	if (ret) {
		platform_device_put(xxx_pdev);
		return ret;
	}

	return 0;
}
module_init(xxx_dev_init);

static void __exit xxx_dev_exit(void)
{
	// 从系统中注销platform_device
	platform_device_unregister(xxx_pdev);
}
module_exit(xxx_dev_exit);
```
将这两个驱动编译后分别插入系统，由于设备和驱动的名称一致，系统会自动将其相互匹配，从而执行`probe`函数。

## platform_driver的注册
#### 1. module_platform_driver宏
首先分析`platform_driver`的注册过程。模板中仅仅使用了一个宏就完成了注册，该宏就是`module_platform_driver`，其中包含了`module_init`和`module_exit`宏，展开后实际上是使用`platform_driver_register()`和`platform_driver_unregister()`函数对驱动进行注册和注销。
```cpp
// linux/include/linux/platform_device.h :
#define module_platform_driver(__platform_driver) \
	module_driver(__platform_driver, platform_driver_register, \
			platform_driver_unregister)

// linux/include/linux/device.h :
#define module_driver(__driver, __register, __unregister, ...) \
static int __init __driver##_init(void) \
{ \
	return __register(&(__driver) , ##__VA_ARGS__); \
} \
module_init(__driver##_init); \
static void __exit __driver##_exit(void) \
{ \
	__unregister(&(__driver) , ##__VA_ARGS__); \
} \
module_exit(__driver##_exit);
```
#### 2. platform_driver_register函数
从上面的分析可以看到，系统实际上是调用了`platform_driver_register()`函数进行注册，下面给出该函数的调用过程。这里只是给出了关键的函数调用，即便如此该调用过程仍然很复杂，我们一条一条来分析。
```cpp
--- include --- linux --- platform_device.h --- platform_driver_register(drv) --- __platform_driver_register(drv,THIS_MODULE)
 |
 |- drivers --- base --- platform.c --- __platform_driver_register(    --- drv->driver.bus = &platform_bus_type;
             |                   struct platform_driver *drv,  |- drv->driver.probe = platform_drv_probe
             |                   struct module *owner)         |- drv->driver.remove = platform_drv_remove
             |                                                 |- driver_register(&drv->driver)
             |
             |- driver.c --- driver_register(             --- driver_find(drv->name, drv->bus)
             |                 struct device_driver *drv)  |  //查找总线中是否已注册驱动, 若已注册直接退出
             |                                             |- bus_add_driver(drv)
             |- bus.c --- bus_add_driver(              --- struct driver_private *priv
                       |    struct device_driver *drv)  |- priv = kzalloc(sizeof(*priv), GFP_KERNEL)
                       |                                |- bus = bus_get(drv->bus)
                       |                                |- priv->driver = drv
                       |                                |- drv->p = priv
                       |                                |- klist_add_tail(&priv->knode_bus, &bus->p->klist_drivers)
                       |                                |  //driver添加到bus
                       |                                |- driver_attach(drv)
                       |                                |  //尝试绑定driver和device
                       |                                |- driver_create_file(drv, &driver_attr_uevent)
                       |                                |  //在sysfs中创建文件
                       |- bus_for_each_dev(       --- while ((dev = next_device(&i)) && !error)
                       |   struct bus_type *bus,  |      error = fn(dev, data)
                       |   struct device *start,  |  //遍历总线上的设备,执行fn函数
		               |   void *data,
                       |   int (*fn)(struct device *, void *))
                       |
                       |- dd.c --- driver_attach(             --- bus_for_each_dev(drv->bus, NULL, drv, __driver_attach)
                                |    struct device_driver *drv)
                                |- __driver_attach(      --- struct device_driver *drv = data
	                            |    struct device *dev,  |- driver_match_device(drv, dev)
                                |    void *data)          |  //查看driver和device是否匹配,若不匹配直接退出 
                                |                         |  //这里调用的是bus_type->match函数
                                |                         |- driver_probe_device(drv, dev)
                                |- driver_probe_device(       --- really_probe(dev, drv)
                                |    struct device_driver *drv, 
                                |    struct device *dev)
                                |- really_probe(               --- driver_sysfs_add(dev))//添加device到sysfs
                                |    struct device *dev,        |- if(dev->bus->probe)
                                |    struct device_driver *drv) |      dev->bus->probe(dev);
                                |                               |  else if(drv->probe)
                                |                               |      drv->probe(dev);
                                |                               |- driver_bound(dev)//设备和驱动绑定
                                |- driver_bound(         --- klist_add_tail(&dev->p->knode_driver,//把device添加到driver
                                     struct device *dev)  |                 &dev->driver->p->klist_devices);
```
`platform_driver`其实是`device_driver`的子类，这一点从它的结构可以看出，其中包含了`device_driver`这个结构体：

```cpp
struct platform_driver {
	int (*probe)(struct platform_device *);
	int (*remove)(struct platform_device *);
	void (*shutdown)(struct platform_device *);
	int (*suspend)(struct platform_device *, pm_message_t state);
	int (*resume)(struct platform_device *);
	struct device_driver driver;
};
```
 - 首先从`platform_driver_register()`函数开始，可以追到`__platform_driver_register()`函数，该函数中关键的一点是将驱动的总线类型设置为`platform_bus_type`，通过`driver_register(&drv->driver)`将`device_driver`注册进系统。
 - 再看`driver_register()`函数，该函数首先调用`driver_find()`函数在总线上搜索是否有同名的驱动，如果有说明该驱动已经注册，直接退出。如果没有接下来调用`bus_add_driver()`函数将驱动添加到总线。
 - 再进入`bus_add_driver()`函数，该函数中首先申请了一个`priv`结构，然后将`drv->p = priv`，最后通过`klist_add_tail()`函数`priv`添加`bus->p`的链表当中从而完成了驱动添加到总线的操作。接下来执行`driver_attach()`函数尝试绑定总线上的驱动和设备。
 - 接下来分析`driver_attach()`函数，将函数中的`bus_for_each_dev()`函数展开，可以看成该函数遍历总线上的所有设备dev，然后执行`__driver_attach(dev, drv)`。
 - 然后是`__driver_attach()`函数，该函数首先通过`driver_match_device()`函数判断驱动和设备是否匹配，若不匹配直接退出. 注意, 该函数的实现实际上就我们常说的`bus->match`函数:

```cpp
static inline int driver_match_device(struct device_driver *drv,
				      struct device *dev)
{
	return drv->bus->match ? drv->bus->match(dev, drv) : 1;
}
```

`bus->match`函数实际上绑定的是 `platform_match()`函数, 该函数的实现如下:

```cpp
static int platform_match(struct device *dev, struct device_driver *drv)
{
	struct platform_device *pdev = to_platform_device(dev);
	struct platform_driver *pdrv = to_platform_driver(drv);

	/* When driver_override is set, only bind to the matching driver */
	if (pdev->driver_override)
		return !strcmp(pdev->driver_override, drv->name);

	/* Attempt an OF style match first */
	// 匹配上之后直接返回，不进行下一步匹配
	if (of_driver_match_device(dev, drv))
		return 1;

	/* Then try ACPI style match */
	if (acpi_driver_match_device(dev, drv))
		return 1;

	/* Then try to match against the id table */
	if (pdrv->id_table)
		return platform_match_id(pdrv->id_table, pdev) != NULL;

	/* fall-back to driver name match */
	return (strcmp(pdev->name, drv->name) == 0);
}
```
从该函数可以看到先进行设备树匹配, 最后进行名字匹配. 

 - 接着分析`__driver_attach()`函数, 如果设备和驱动匹配, 则执行`driver_probe_device()`函数，该函数可以追到`really_probe()`函数。
 - 在`really_probe()`函数中可以看到执行了我们自己定义的probe函数，然后通过`driver_bound()`函数绑定设备和驱动。
 - 在`driver_bound()`函数中，和将驱动绑定到总线类似，同样调用了`klist_add_tail()`函数将设备加入了`driver->p`链表的尾部。

## platform_device的注册
了解了`platform_driver`的注册过程，分析`platform_device`的注册过程就很简单了，因为有很多地方都是相似的。`platform_device`的注册过程主要包括两个函数：
```cpp
// 申请一个platform_device结构
platform_device_alloc()
// 向系统添加设备
platform_device_add()
```
#### 1. platform_device_alloc()函数的调用过程

```cpp
struct platform_object {
	struct platform_device pdev;
	char name[];
};

drivers --- base --- platform.c --- platform_device_alloc( --- struct platform_object *pa
                                      const char *name,     |- pa = kzalloc(sizeof(*pa)+strlen(name)+1, GFP_KERNEL)
                                      int id)               |- strcpy(pa->name, name)
                                                            |- pa->pdev.name = pa->name
                                                            |- pa->pdev.id = id
                                                            |- device_initialize(&pa->pdev.dev)
```
之前提到`platform_driver`是`driver`的子类，这里的情况和其类似，`platform_device`也是`device`的子类：

```cpp
struct platform_device {
	const char	* name;
	int		id;
	struct device	dev;
	u32		num_resources;
	struct resource	* resource;
	struct platform_device_id	*id_entry;
	struct pdev_archdata	archdata;
};
```

这里重要一点就是调用`device_initialize()`函数给`platform_device.dev`进行了初始化


#### 2. platform_device_add()函数的调用过程

```cpp
drivers --- base --- platform.c --- platform_device_add(            --- pdev->dev.bus = &platform_bus_type
                  |                   struct platform_device *pdev)  |- dev_set_name(&pdev->dev, "%s", pdev->name)
                  |                                                  |- device_add(&pdev->dev)
                  |
                  |- core.c --- device_add(           --- kobject_add(&dev->kobj, dev->kobj.parent, NULL)
                  |               struct device *dev)  |- device_create_file(dev, &dev_attr_uevent)
                  |                                    |  //sysfs中创建文件
                  |                                    |- bus_add_device(dev)
                  |                                    |  //添加设备到总线
                  |                                    |- bus_probe_device(dev)
                  |                                    |  //执行probe函数
                  |
                  |- bus.c --- bus_add_device(       --- struct bus_type *bus = bus_get(dev->bus)
                  |         |    struct device *dev)  |- klist_add_tail(&dev->p->knode_bus, &bus->p->klist_devices)
                  |         |                            //添加设备到总线
                  |         |- bus_probe_device(     --- struct bus_type *bus = dev->bus
                  |         |    struct device *dev)  |- device_attach(dev)
                  |         |- bus_for_each_drv(               --- while ((drv = next_driver(&i)) && !error)
                  |              struct bus_type *bus,          |-     error = fn(drv, data);
                  |              struct device_driver *start,   |  //遍历总线上的设备,执行fn
		          |              void *data, 
                  |              int (*fn)(struct device_driver *, void *))
                  |
                  |- dd.c --- device_attach(        --- if (dev->driver) 
                           |    struct device *dev)  |      device_bind_driver(dev);
                           |                         |  else
                           |                         |      bus_for_each_drv(dev->bus, NULL, dev, __device_attach);
                           |
                           |- __device_attach(             --- if (!driver_match_device(drv, dev))
                                struct device_driver *drv,  |      return 0;
                                void *data)                 |  return driver_probe_device(drv, dev);
                                                            |  //这里的两个函数和注册驱动时的两个函数一致

```
 - 申请到的`platform_device`由这个函数添加到系统，该函数进入后，首先是将`pdev->dev.bus`设置为`platform_bus_type`，这意味着该设备会挂载到platform_bus上。然后执行`device_add()`函数向系统添加设备。
 - `device_add()`函数进入后，使用`bus_add_device()`函数向总线添加设备，然后使用`bus_probe_device()`函数调用我们的probe函数。
 - 在`bus_add_device()`函数中，也是调用了`klist_add_tail()`将设备添加到系统链表当中，完成设备和总线绑定的操作。
 - `bus_probe_device()`函数中，最终调用`device_attach()`函数尝试绑定同一总线上的驱动和设备。
 - `device_attach()`函数中，首先判断`dev->driver`是否已经指定了驱动，否则在总线中搜索所有驱动，找到和设备匹配的那一个，遍历总线驱动使用的是`bus_for_each_drv()`函数，可以看到最终调用的是`__device_attach()`来尝试绑定设备和驱动。
 - 以上程序流程和驱动的注册如出一辙，接下来进入`__device_attach()`调用的就是和驱动中完全相同的函数了：使用`driver_match_device()`判断设备和驱动是否匹配，然后调用`driver_probe_device()`调用我们的probe函数。