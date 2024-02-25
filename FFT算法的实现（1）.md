本文章参考：http://tieba.baidu.com/p/2513502552
那一天，作者终于想起了他CSDN的密码，填坑完毕：）
#### 不想看理论想直接看代码的同学，请到我的第二篇博客拉到最底。点击[传送门](https://blog.csdn.net/Egean/article/details/53258286)传送

----------


由于需要在Arduino上进行声音处理，需要用到FFT变换，查找了相关库过后发现FFT的库比较少，而且版本比较老了，挑编译器，也因为种种个人原因，索性自己来实现一个FFT变换。
FFT（快速傅里叶变换）变换本质就是DFT（离散傅里叶变换），但是对DFT进行了优化，减少了计算量并能够比较方便地用程序实现。这里是在Arduino平台上实现了一个基2的FFT算法，大致需要如下预备知识：

 - 傅里叶变换的概念
 - 复数的概念
 - 欧拉公式

因为是用程序实现数学算法，要完全理解程序，肯定是会涉及到公式推导，但是这里的推导很简单，大概需要高中的数学知识即可。首先上DFT的公式，下面将由这个公式一步步推出FFT的算法。


----------


$$\Large
X[k]=\sum\limits_{n=0}^{N-1} x[n]e^{-i\frac{2\pi k}{N}n}
$$


----------


学过傅里叶变换的话应该比较熟悉这个公式，它其实就是针对离散的采样点 $x[n]$ 的傅里叶变换，其意义还是将信号从时域转换到频域。那么这里的 $X[k]$ 表示的就是频域信号了，下标k表示信号的频率， $X[k]$ 的值就是该频率信号的幅值。这里可以看到，当k固定的时候，对应于频率为k的信号幅值是与 $x[n]$ 有关的一个级数的和，因此每一个频域的点实际上包含了所有时域点的信息。

有两点需要注意，一是因为 $x[n]$ 的长度为 $N$ ，因此 $DFT$ 后的频域信号 $X[k]$ 的长度也是 $N$；二是为了进行FFT变换，$N$ 的取值一般是2的整数次幂。

----------
***将下标n分解为奇偶两部分，然后分别求和***
$\\$
$$\Large
X[k]=\sum\limits_{r=0}^{\frac N2-1} x[2r]e^{-i\frac{2\pi k}{N}2r}+\sum\limits_{r=0}^{\frac N2-1} x[2r+1]e^{-i\frac{2\pi k}{N}(2r+1)}
$$
$\\$
***这里进行一次代换，用 $x_0[n]$表示 $x[n]$ 中的偶数项，用 $x_1[n]$ 表示 $x[n]$ 中的奇数项***
$\\$
$$\Large
X[k]=\sum\limits_{n=0}^{\frac N2-1} x_0[n]e^{-i\frac{2\pi k}{N/2}n}+\sum\limits_{n=0}^{\frac N2-1} x_1[n]e^{-i\frac{2\pi k}{N/2}n-i\frac {2\pi k}N}
$$
$\\$
***第二项求和中，$\large e^{-i \frac {2\pi}Nk} $ 与 $n$ 无关，因此可以单独提出***
$\\$
$$\Large
X[k]=\underbrace {\sum\limits_{n=0}^{\frac N2-1} x_0[n]e^{-i\frac{2\pi k}{N/2}n}}_{对x_0[n]进行DFT}+e^{-i \frac {2\pi}Nk}\underbrace{\sum\limits_{n=0}^{\frac N2-1} x_1[n]e^{-i\frac{2\pi k}{N/2}n}}_{对x_1[n]进行DFT}
$$
$\\$
$$\Large
X[k]=DFT(x_0)+e^{-i \frac {2\pi}Nk}DFT(x_1)
$$
$\\$
***利用欧拉公式，将：$\large e^{-i \frac {2\pi}Nk}=\cos\frac {2\pi k}N-i\sin\frac {2\pi k}N $代入：***
$\\$
$$\Large
X[k]=DFT(x_0)+(\cos\frac {2\pi k}N-i\sin\frac {2\pi k}N)DFT(x_1)
$$
$\\$
***设：$X_0[k]=DFT(x_0)，X_1[k]=DFT(x_1)$***
$\\$
$$\Large
X[k]=X_0[k]+(\cos\frac {2\pi k}N-i\sin\frac {2\pi k}N)X_1[k]
$$
$\\$


----------


因为这里 $x_0[n]$ 和 $x_1[n]$ 分别是 $x[n]$的偶数项和奇数项，因此它们的长度都是 $\large \frac N2$ ，所以 $X_0[k]$ 和 $X_1[k]$ 的长度也是 $\large \frac N2$ ，而 $X[k]$ 是 $X_0[k]$ 和 $X_1[k]$ 的线性组合，因此其长度也是  $\large \frac N2$ 。

前面已经提到，原式的变换中 $X[k]$ 的长度为 $N$ ，经过一轮变换之后其长度变为了 $\large \frac N2$ ，那岂不是意味着丢失了一半的频率信息吗？这肯定是不允许的，下面就利用 $DFT$ 的对称性找回这一半丢失的信息。

在此之前先引入旋转因子的概念：


----------
***旋转因子表示为：***
$$\Large
W_N=e^{-i\frac {2\pi}N}=\cos \frac{2\pi}N-i\sin \frac {2\pi}N
$$
$\\$
***旋转因子的对称性：***
$\\$
$$\Large
W_N^{k+\frac N2}=e^{-i\frac {2\pi}N(k+\frac N2)}=e^{-i\frac {2\pi}N}*e^{-i\pi}=-e^{-i\frac {2\pi}N}=-W_N^k
$$
$\\$
***使用旋转因子表达将更简洁：***
$\\$
$$\Large
X[k]=X_0[k]+W_N^kX_1[k]
$$


----------
上面已经说到， $X_0[k]$ 和 $X_1[k]$ 的长度为 $\large \frac N2$ ，那么超出 $\large \frac N2$ 的部分会出现什么情况呢？事实上超出的部分将会呈周期性变化，即：$X_0[k+\frac N2]=X_0[k]$，这一点将 $k+\frac N2$ 代入 $X_0[k]$ 的表达式即可证明，这里就省去了。知道这一点后，我们用在上式中用 $k+\frac N2$ 代替 $k$ ：


----------
$\\$
$$\Large
X[k+\frac N2]=X_0[k+\frac N2]+W_N^{k+\frac N2}X_1[k+\frac N2]=X_0[k]-W_N^{k}X_1[k]
$$

----------
至此已经得出了整个频域上的表达式：


----------
$\\$
$$\Large
X[k]=X_0[k]+W_N^{k}X_1[k]
$$
$$\Large
X[k+\frac N2]=X_0[k]-W_N^{k}X_1[k]
$$


----------
写了这么多公式，还没有讲到FFT，其实算到这里，已经完成了FFT的关键部分了。

[下一篇](https://blog.csdn.net/Egean/article/details/53258286)中将完成算法的具体实现。