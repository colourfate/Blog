#!/bin/bash

name="FFmpeg编码器流程分析"

sites=(
    "https://img-blog.csdnimg.cn/18ac65c764234bab851530bbba4baa7f.png"
    "https://img-blog.csdnimg.cn/eb83680fae004425bd5284d580b75e2c.png"
    "https://img-blog.csdnimg.cn/ecaefba7f8814c8cb4fa34e97da8c72e.png"
    "https://img-blog.csdnimg.cn/be3209e816024ba9a929b8232d9ad83b.png"
    "https://img-blog.csdnimg.cn/65e235fb7d524060bbf9ff94a0684f7a.png"
)

#NAME=$1
#NET=$2
#wget $NET -O $NAME

for i in "${sites[@]}"
do
    wget $i -O "res/${name}_$((++count)).png"
done
