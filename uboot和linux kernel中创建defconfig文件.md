## 1. 介绍
最近在移植uboot的时候我想根据当前的`.config`文件创建自己的defconfig文件到`configs/`目录中，开始以为是直接拷贝`.config`文件然后重命名即可，然后想了想uboot的Makefile文件中应该是有这个功能的，但是百度时没有人提到，最后翻墙用google终于发现确实有这个功能，于是在这里记录一下。

## 2. 使用make命令创建defconfig文件
总结一下现在的情况：在移植uboot时，我们通常是从一个已有的相近的板子上移植，所以开始是`make xxx_defconfig`，此时会在源码目录下多出一个`.config`的配置文件；在移植过程中可能会对当前的配置进行一些修改，一般在使用`make menuconfig`修改，此时再重新编译时`.config`文件已经改变了；当我移植完成时需要将当前的配置生成一个新的`defconfig`文件加入到`configs/`目录中。此时执行：
```
make savedefconfig
```
即可在源码目录生成当前的`defconfig`文件。

## 3. 总结
因为uboot是仿照linux kernel开发的，所以linux kernel中能够使用的make命令子在uboot中一般都能使用。
最后使用`make help`命令可以查看当前所有能够使用的make命令。