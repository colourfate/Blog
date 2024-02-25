##问题
在高版本的Linux内核中使用了设备树进行传参，之前购买一块nanopi的板子使用的是linux 4.11.2版本的内核（使用的友善之臂的Mainline linux）就是这种情况，并且使用设备树传参过后，原来硬编码在mach-xxx.c文件中的platform device全部都放入了设备树中，而原来使用name进行platform device和driver进行匹配的方式也发生了变化。
以nanopi中PWM驱动为例，这是它的platform driver：
```c
static struct platform_driver sun4i_pwm_driver = {
	.driver = {
		.name = "sun4i-pwm",
		.of_match_table = sun4i_pwm_dt_ids,
	},
	.probe = sun4i_pwm_probe,
	.remove = sun4i_pwm_remove,
};
```
在没有设备树传参时，platform device和driver的匹配是通过名字来匹配的，也就是比较platform_driver.device_driver.name和platform_device.name，而在这里整个工程中是找不到"sun4i-pwm"的字符串的，也就是说匹配方式发生了变化。

##设备树的加载
设备树文件的后缀名为.dts，一般放在 /arch/arm/boot/dts 文件夹中，对内核进行编译的时候可以使用make指令将设备树编译成二进制文件.dtb，该文件在内核启动的时候会被加载到内核当中。以我的nanopi的板子为例，要求将SD卡分为boot分区和rootfs分区，编译的.dtb文件只需放入boot分区即可，uboot在环境变量中指定该.dtb文件的名字，那么内核在加载的时候就会加载相应的设备树。内核加载设备树的过程如下：

```
b	start_kernel							-->arch/arm/kernel/head-common.S
	start_kernel							-->init/main.c
		setup_arch							-->arch/arm/kernel/setup.c
			setup_machine_fdt				-->arch/arm/kernel/devtree.c
				early_init_dt_scan_nodes	-->drivers/of/fdt.c
					of_scan_flat_dt(early_init_dt_scan_chosen, boot_command_line);	-->(1)
					of_scan_flat_dt(early_init_dt_scan_root, NULL);  -->(2)
					of_scan_flat_dt(early_init_dt_scan_memory, NULL);  -->(3)	
				__machine_arch_type = mdesc->nr;	-->(4)
		unflatten_device_tree				-->drivers/of/fdt.c, (5)
			__unflatten_device_tree
				unflatten_dt_nodes			// 对设备树进行展开
```
以下解释引用自http://blog.csdn.net/lichengtongxiazai/article/details/38941913

> （1）扫描 /chosen node，保存运行时参数（bootargs） 到boot_command_line ，此外，还处理initrd相关的property ，并保存在initrd_start 和initrd_end 这两个全局变量中
（2）扫描根节点，获取 {size,address}-cells信息，并保存在dt_root_size_cells和dt_root_addr_cells全局变量中
（3）扫描DTB中的memory node，并把相关信息保存在meminfo中，全局变量meminfo保存了系统内存相关的信息
（4）Change machine number to match the mdesc we're using
（5）unflattens a device-tree, creating the tree of struct device_node.

##device和driver的匹配
以上文章还提到
> 系统应该会根据Device tree来动态的增加系统中的platform_device(这个过程并非只发生在platform bus上，也可能发生在其他的非即插即用的bus上，例如AMBA总线、PCI总线)。 如果要并入linux kernel的设备驱动模型，那么就需要根据device_node的树状结构（root是of_allnodes）将一个个的device node挂入到相应的总线device链表中。只要做到这一点，总线机制就会安排device和driver的约会。当然，也不是所有的device node都会挂入bus上的设备链表，比如cpus node，memory node，choose node等。

可以看到，一些设备树的device_node最终是会变为device挂载到总线上的，而这时就可以和driver进行配对了。在platform 总线中也是如此，要知道device和driver是如何配对的，就要看platform 总线的定义了，platform_bus_type定义如下：

```c
struct bus_type platform_bus_type = {
	.name		= "platform",
	.dev_groups	= platform_dev_groups,
	.match		= platform_match,
	.uevent		= platform_uevent,
	.pm		= &platform_dev_pm_ops,
};
```

因此要看device和driver是如何配对的需要看platform_match函数是如何匹配的，platform_match函数如下：

```c
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

可以看到和2.6版本的platform_match函数不同了，该函数在最后一步才进行pdev->name, drv->name名字的匹配，而如果在之前的if中匹配上了是直接返回1，而不会进行下一步匹配的。其中第二个if就是在设备树中进行匹配，我们追进去可以看到这个函数实际做的工作：
```
platform_match
	of_driver_match_device		// 利用设备树的节点进行匹配
		of_match_device				--> driver/of/device.c
			of_match_node			--> driver/of/base.c
				__of_match_node
```
在__of_match_node函数中才进行的真正的device和driver的匹配：
```c
static
const struct of_device_id *__of_match_node(const struct of_device_id *matches,
					   const struct device_node *node)
{
	const struct of_device_id *best_match = NULL;
	int score, best_score = 0;

	if (!matches)
		return NULL;
	// 这里和设备树的进行匹配
	for (; matches->name[0] || matches->type[0] || matches->compatible[0]; matches++) {
		score = __of_device_is_compatible(node, matches->compatible,
						  matches->type, matches->name);
		if (score > best_score) {
			best_match = matches;
			best_score = score;
		}
	}

	return best_match;
}
```
这里匹配的是什么呢？在这个内核内核中匹配的是matches->compatible，为了方便说明，还是以nanopi的PWM驱动为例，这里再贴一遍它的platform_driver：
```c
static struct platform_driver sun4i_pwm_driver = {
	.driver = {
		.name = "sun4i-pwm",
		.of_match_table = sun4i_pwm_dt_ids,
	},
	.probe = sun4i_pwm_probe,
	.remove = sun4i_pwm_remove,
};
```
这里匹配的就是platform_driver.driver_driver.of_match_id的内容，也就是这里的of_match_table，我们再追进去看：
```c
static const struct of_device_id sun4i_pwm_dt_ids[] = {
	{
		.compatible = "allwinner,sun4i-a10-pwm",
		.data = &sun4i_pwm_data_a10,
	}, {
		.compatible = "allwinner,sun5i-a10s-pwm",
		.data = &sun4i_pwm_data_a10s,
	}, {
		.compatible = "allwinner,sun5i-a13-pwm",
		.data = &sun4i_pwm_data_a13,
	}, {
		.compatible = "allwinner,sun7i-a20-pwm",
		.data = &sun4i_pwm_data_a20,
	}, {
		.compatible = "allwinner,sun8i-h3-pwm",
		.data = &sun4i_pwm_data_h3,
	}, {
		/* sentinel */
	},
};
```
这就和__of_match_node函数匹配上了，该函数最终使用的就是platform_driver.driver_driver.of_device_id->compatible和设备树中的compatible进行比较，再工程中使用全局搜索"allwinner,sun8i-h3-pwm"（因为nanopi使用的是全志h3），可以找到对应的设备树节点在sunxi-h3-h5.dtsi中：
```
pwm: pwm@01c21400 {
            compatible = "allwinner,sun8i-h3-pwm";
            reg = <0x01c21400 0x8>;
            clocks = <&osc24M>;
            #pwm-cells = <3>;
            status = "disabled";
        };
```

##总结
使用设备树传参时的platform device已经没有硬编码再内核当中了，而是使用一个设备树文件，将所有板级相关信息写在了里面，在platform总线进行匹配时，使用的是platform_driver.driver_driver.of_device_id->compatible和设备树中的compatible进行匹配，所以想要添加驱动，只需要在设备树文件中添加节点，指定device的compatible，然后在代码中再指定driver的compatible即可完成匹配，执行probe函数。