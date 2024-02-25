### 介绍
上一节在nanopi设备树的I2C节点下增加了一个MPU6050的子节点，并在sysfs中查看到了该节点已经被正确解析，这一节我们来修改之前的MPU6050驱动，使之能够匹配到我们的设备树节点，然后再分析设备树节点是如何加载到i2c总线上的。

### MPU6050驱动的变更
在之前的MPU6050驱动中，为了方便测试，我们是在模块的init函数中临时注册了一个i2c_client到i2c总线上，该i2c_client的信息由i2c_board_info指定，包括i2c_client的名称和从机地址。然后我们再注册了i2c_driver到i2c总线上，系统通过比较i2c_driver.id_table和i2c_client.name判断设备和驱动是否匹配，如果匹配那么执行probe函数，整个过程如下所示：

```cpp
static struct i2c_client *temp_client;
static int __init mpu6050_i2c_init(void)
{
    struct i2c_adapter *adapter;

    adapter = i2c_get_adapter(I2C_0);
    if (!adapter)
        printk(KERN_INFO "fail to get i2c-%d\n", I2C_0);
    
    // 临时注册一个i2c_client
    temp_client = i2c_new_device(adapter, &mpu6050_i2c_info);
    if (!temp_client)
        printk(KERN_INFO "fail to registe %s\n", mpu6050_i2c_info.type);

    pr_info(KERN_INFO "mpu6050 i2c init\n");
    return i2c_add_driver(&mpu6050_i2c_driver);
}

static void __exit mpu6050_i2c_exit(void)
{
    i2c_unregister_device(temp_client);
    i2c_del_driver(&mpu6050_i2c_driver);
}

```

而现在由于我们已经在设备树中添加了MPU6050子节点，系统已经正确解析，并且我们在`/sys/bus/i2c/device`目录下能够看到该节点的信息，这说明这个子节点已经作为了一个i2c_client被加载到了i2c总线上，我们只需要修改驱动使之能够匹配这个i2c_client即可。因此我先删除之前的i2c_client注册部分，只保留i2c驱动的注册。

```cpp
static int __init mpu6050_i2c_init(void)
{
    return i2c_add_driver(&mpu6050_i2c_driver);
}

static void __exit mpu6050_i2c_exit(void)
{
    i2c_del_driver(&mpu6050_i2c_driver);
}
```

然后在i2c_driver中加入对设备树节点的匹配

```cpp
static const struct of_device_id mpu6050_of_match[] = {
    { .compatible = "inv,mpu6050", },
    {  }
};

static struct i2c_driver mpu6050_i2c_driver = {
    .driver = {
        .name = "mpu6050",
        .owner = THIS_MODULE,
        .of_match_table = mpu6050_of_match,
    },
    .probe = mpu6050_i2c_probe,
    .remove = mpu6050_i2c_remove,
    .id_table = mpu6050_i2c_ids,
};
```

之前的id_table可以不用管，因为根据i2c总线的i2c_device_match()函数，如果设备树匹配上就不会进行id_table的匹配。**注意of_device_id中的compatible属性，系统通过这个字段来判断是否和已经注册的i2c_client.dev.of_node中的compatible字段匹配，如果匹配则执行probe函数。**

经过这两项修改，该驱动已经可以支持设备树了，测试方法和结果跟之前一致，我们能够正确地读取到传感器的值，这里就不截图了。

我们可以看到使用了设备树后驱动明显变简单了，并且更有条理性，驱动中可以增加多个of_device_id来匹配多个设备树节点，从而支持多个设备。而我们驱动的改动很小，这是因为操作系统帮我们做了大部分的事情。

到这里我们至少要提出两个问题：

1. 这个MPU6050的i2c_client是何时加入到i2c总线的？
2. 之前我们在i2c_board_info中明确指定了从机地址，这个设备树的从机地址是何时赋值到i2c_client中的？

### i2c_client注册的分析
首先说结论，**设备树中i2c节点下的子节点是在i2c_adapter注册的时候一同被注册到i2c总线的**，因为从驱动框架来看i2c_client是挂接到i2c_adapter上的，因此注册i2c_adapter时将总线上的i2c_client添加到系统合情合理。注册i2c_client时会找到子节点中的reg属性并赋值到i2c_client.addr中。具体分析见以下代码树（注意，对于不同的硬件平台，目录可能有差别）。

```cpp
--- drivers --- i2c --- busses --- i2c-mv64xxx.c --- mv64xxx_i2c_probe(            --- drv_data = devm_kzalloc();
                     |                                 struct platform_device *pd)  |- drv_data->adapter.algo = &mv64xxx_i2c_algo
                     |                                                              |- drv_data->adapter.class = I2C_CLASS_DEPRECATED
                     |                                                              |- drv_data->adapter.nr = pd->id
                     |                                                              |* drv_data->adapter.dev.of_node = pd->dev.of_node
                     |                                                              |- i2c_add_numbered_adapter(&drv_data->adapter))
                     |
                     |- i2c_core.c --- i2c_add_numbered_adapter(   --- __i2c_add_numbered_adapter(adap)
                                    |    struct i2c_adapter *adap)
                                    |- __i2c_add_numbered_adapter( --- i2c_register_adapter(adap)
                                    |    struct i2c_adapter *adap)
                                    |- i2c_register_adapter(      --- *of_i2c_register_devices(adap)//添加设备树子节点上的设备
                                    |    struct i2c_adapter *adap)
                                    |- of_i2c_register_devices(    --- struct device_node *bus
                                    |    struct i2c_adapter *adap)  |- struct i2c_client *client
                                    |                               |- bus = of_node_get(adap->dev.of_node)
                                    |                               |- for_each_available_child_of_node(bus, node)
                                    |                               |*     client = of_i2c_register_device(adap, node)
                                    |- of_i2c_register_device(     --- struct i2c_board_info info = {};
                                         struct i2c_adapter *adap,  |- addr_be = of_get_property(node, "reg", &len)//获取reg属性
                                         struct device_node *node)  |- addr = be32_to_cpup(addr_be)
                                                                    |- info.addr = addr
                                                                    |- info.of_node = of_node_get(node)
                                                                    |* i2c_new_device(adap, &info)
```

`i2c-mv64xxx.c`是针对nanopi的全志H3平台的i2c_adapter的初始化，对于不同的平台，初始化过程也不相同，所以需要找到所使用平台的`i2c-xxx.c`文件再分析。
该驱动是一个platform驱动，i2c_adapter是platform_device，它通过设备树添加到系统的platform总线上，注册platform_driver时只要compatible匹配就会执行这里的`mv64xxx_i2c_probe`函数。至于系统是如何将i2c_adapter注册到platform总线的，我们下来再分析，这里只看注册i2c适配器时是如何将子节点作为i2c_client添加到i2c总线上的。

以上加了星号的是重点，这个过程总结起来就是先将I2C适配器的设备树节点放到i2c_adapter.dev.of_node中，然后注册这个i2c_adapter，注册时，遍历了该节点下的子节点，对所有子节点执行`of_i2c_register_device(adap, node)`，这个函数中，先对子节点进行解析，获取其reg属性的值，然后填充i2c_board_info结构体，最后用`i2c_new_device`将其注册到i2c总线。

### i2c_adapter注册的分析
上面提到，这里的i2c_adapter是一个platform_device，通过与platform_driver的匹配来执行probe函数，这个platform_driver定义如下：

```cpp
static const struct of_device_id mv64xxx_i2c_of_match_table[] = {
    { .compatible = "allwinner,sun4i-a10-i2c", .data = &mv64xxx_i2c_regs_sun4i},
    { .compatible = "allwinner,sun6i-a31-i2c", .data = &mv64xxx_i2c_regs_sun4i},
    { .compatible = "marvell,mv64xxx-i2c", .data = &mv64xxx_i2c_regs_mv64xxx},
    { .compatible = "marvell,mv78230-i2c", .data = &mv64xxx_i2c_regs_mv64xxx},
    { .compatible = "marvell,mv78230-a0-i2c", .data = &mv64xxx_i2c_regs_mv64xxx},
    {}
};

static struct platform_driver mv64xxx_i2c_driver = {
    .probe  = mv64xxx_i2c_probe,
    .remove = mv64xxx_i2c_remove,
    .driver = {
        .name   = MV64XXX_I2C_CTLR_NAME,
        .pm     = mv64xxx_i2c_pm_ops,
        .of_match_table = mv64xxx_i2c_of_match_table,
    },
};
```

设备树中的i2c_adapter定义如下，这个节点将来会被系统作为一个platform_device注册到系统

```
i2c0: i2c@01c2ac00 {
    compatible = "allwinner,sun6i-a31-i2c";
    reg = <0x01c2ac00 0x400>;
    interrupts = <GIC_SPI 6 IRQ_TYPE_LEVEL_HIGH>;
    clocks = <&ccu CLK_BUS_I2C0>;
    resets = <&ccu RST_BUS_I2C0>;
    pinctrl-names = "default";
    pinctrl-0 = <&i2c0_pins>;
    status = "disabled";
    #address-cells = <1>;
    #size-cells = <0>;
};
```

全志H3芯片有三个i2c控制器，这里只列出其中的一个节点。可以看到该节点的`compatible = "allwinner,sun6i-a31-i2c"`，再看platform_driver中也有"allwinner,sun6i-a31-i2c"这个compatible，因此它们可以匹配。

为什么这个i2c_adapter会被系统识别为platform_device呢？因为这个i2c控制器节点是`soc`的子节点，而`soc`的`compatible = "simple_bus"`，这就是上一节提到过的：**内核在解析设备树时遇到"simple-bus"时，会继续解析这个节点的子节点，并将各个子节点注册为一个`platform_device`放到`platform_bus_type`中。**我们来看具体代码是如何写的。

```cpp
const struct of_device_id of_default_bus_match_table[] = {
    { .compatible = "simple-bus", },
    { .compatible = "simple-mfd", },
    { .compatible = "isa", },
#ifdef CONFIG_ARM_AMBA
    { .compatible = "arm,amba-bus", },
#endif /* CONFIG_ARM_AMBA */
    {} /* Empty terminated list */
};

of_platform_populate(NULL, of_default_bus_match_table, NULL, NULL) 

    --- drivers --- of --- platform.c --- of_platform_populate(                 --- struct device_node *child
                                    |    struct device_node *root,            |- root = root ? of_node_get(root) : 
                                    |    const struct of_device_id *matches,  |                of_find_node_by_path("/");
                                    |    const struct of_dev_auxdata *lookup, |- for_each_child_of_node(root, child) 
                                    |    struct device *parent)               |      of_platform_bus_create(child, matches,
                                    |                                         |              lookup, parent, true)
                                    |- of_platform_bus_create(               --- struct platform_device *dev
                                    |    struct device_node *bus,             |- void *platform_data = NULL
                                    |    const struct of_device_id *matches,  |- const char *bus_id = NULL
                                    |    const struct of_dev_auxdata *lookup, |- dev = of_platform_device_create_pdata(
                                    |    struct device *parent, bool strict)  |-             bus, bus_id, platform_data, parent)
                                    |                                         |  // 对该节点创建platform_device 
                                    |                                         |- if (!dev || !of_match_node(matches, bus))
                                    |                                         |      return 0;
                                    |                                         |- for_each_child_of_node(bus, child)
                                    |                                         |       of_platform_bus_create(child, matches, 
                                    |                                         |              lookup, &dev->dev, strict);
                                    |                                         |  // 如果该节点.compatible = "simple-bus"
                                    |                                         |  // 遍历子节点，递归调用，继续注册子节点
                                    |- of_platform_device_create_pdata( --- struct platform_device *dev
                                    |    struct device_node *np,         |- dev = of_device_alloc(np, bus_id, parent)
                                    |    const char *bus_id,             |- dev->dev.bus = &platform_bus_type
                                    |    void *platform_data,            |- dev->dev.platform_data = platform_data
                                    |    struct device *parent)          |- of_device_add(dev) 
                                    |- of_device_alloc(           --- struct platform_device *dev
                                    |     struct device_node *np,  |- dev = platform_device_alloc("", -1)
                                    |     const char *bus_id,      |- dev->dev.of_node = of_node_get(np)
                                    |     struct device *parent)   |- dev->dev.parent = parent ? : &platform_bus
                                    |                              |- return dev
                                    |- of_device_add(                   --- device_add(&ofdev->dev)
                                         struct platform_device *ofdev)
```

系统通过调用`of_platform_populate`函数解析整个设备树，该函数在`customize_machine`中通过`machine_desc->init_machine()`间接调用。

```cpp
static int __init customize_machine(void)
{
	/*
	 * customizes platform devices, or adds new ones
	 * On DT based machines, we fall back to populating the
	 * machine from the device tree, if no callback is provided,
	 * otherwise we would always need an init_machine callback.
	 */
	if (machine_desc->init_machine)
		machine_desc->init_machine();

	return 0;
}
arch_initcall(customize_machine);
```
`machine_desc`是一个全局变量，在`setup_arch()`函数中被赋值，`init_machine()`由平台定义，其中会调用`of_platform_populate`函数将根节点下的设备树节点注册为platform_devcie。值得注意的是`of_platform_bus_create`函数，它首先将节点自身注册为platform_device，然后执行`of_match_node(matches, bus)`判断该节点是否和matches匹配，这里的matches就是`of_default_bus_match_table`，其中有一个字段是`.compatible = "simple-bus"`，就是说如果该节点的`.compatible = "simple-bus"`，那么就不会返回，接下来遍历该节点下的子节点，递归调用`of_platform_bus_create`，将所有子节点都注册为platform_device，这样i2c-0的设备树节点就被注册为了一个platform_device，后面的platform_driver的匹配就得以运行。

### 疑问
在sunxi的板级文件中，我始终没有找到对init_machine的赋值，这里的machine_desc定义如下：
```cpp
static const char * const sun8i_board_dt_compat[] = {
	"allwinner,sun8i-a23",
	"allwinner,sun8i-a33",
	"allwinner,sun8i-a83t",
	"allwinner,sun8i-h2-plus",
	"allwinner,sun8i-h3",
	"allwinner,sun8i-v3s",
	NULL,
};

DT_MACHINE_START(SUN8I_DT, "sun8i")
	.init_time	= sun6i_timer_init,
	.dt_compat	= sun8i_board_dt_compat,
MACHINE_END
```
其中没有对init_machine属性的赋值，如果这个属性是空，那么就不会执行of_platform_populate函数，也不会将设备树下的节点注册为platform_device，但是实际上肯定是注册了的，要不然无法使用cpu上所有的外设资源。这里留下一个疑问，等学了内核调试方法再在实际的调试中解决该问题