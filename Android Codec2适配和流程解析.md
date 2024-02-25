# 1 介绍
Codec2是Android中多媒体相关的软件框架，是MediaCodec的中间件，往上对接MediaCodec Native层，往下提供新的API标准供芯片底层的编解码去实现，也就是说适配了Codec2，就可以通过MediaCodec来调用芯片的硬件编解码的能力，来完成一些多媒体相关的功能。这篇文章先从下到上讲解适配Codec2需要实现的接口，然后再从上到下分析MediaCodec的流程来分析这些接口是如何调用的。

开始之前需要如下前置知识

1. Android异步消息机制
2. Android Binder机制
3. 视频编解码基本流程

# 2 适配
下面以Android中的软件Hevc编码器的实现为例，分析如何适配Codec2接口

## 2.1 目录结构
```shell
.
├── Android.mk
├── components     # 适配的组件，如h264、hevc软件编解码等，由HIDL调用
├── core           # codec2内核，对接component
├── docs
├── faultinjection
├── fuzzer
├── hidl           # hal层相关接口文件，由HIDL语言描述生成
├── OWNERS
├── sfplugin
├── TEST_MAPPING
├── tests
└── vndk
```

## 2.2 core
core层组织了components的运行方式，这里先分析core层，其中主要的文件是：`core/include/C2Component.h`，其中包含了`C2Component`和`C2ComponentInterface`两个类

### 2.2.1 C2Component
`C2Component`中定义了一个组件需要实现的接口，定义如下，其中`queue_nb`可以看作送帧/送流的接口，
```c++
class C2Component {
public:
    ...
    /* Queues up work for the component. */
    virtual c2_status_t queue_nb(std::list<std::unique_ptr<C2Work>>* const items) = 0;
    /*
     * Announces a work to be queued later for the component. This reserves a slot for the queue
     * to ensure correct work ordering even if the work is queued later.
     */
    virtual c2_status_t announce_nb(const std::vector<C2WorkOutline> &items) = 0;

    enum flush_mode_t : uint32_t {
        /// flush work from this component only
        FLUSH_COMPONENT,

        /// flush work from this component and all components connected downstream from it via
        /// tunneling
        FLUSH_CHAIN = (1 << 16),
    };

    /*
     * Discards and abandons any pending work for the component, and optionally any component
     * downstream.
     */
    virtual c2_status_t flush_sm(flush_mode_t mode, std::list<std::unique_ptr<C2Work>>* const flushedWork) = 0;

    enum drain_mode_t : uint32_t {
        DRAIN_COMPONENT_WITH_EOS,
        DRAIN_COMPONENT_NO_EOS = (1 << 0),
        DRAIN_CHAIN = (1 << 16),
    };

    /*
     * Drains the component, and optionally downstream components. This is a signalling method;
     * as such it does not wait for any work completion.
     * Marks last work item as "drain-till-here", so component is notified not to wait for further
     * work before it processes work already queued. This method can also used to set the
     * end-of-stream flag after work has been queued. Client can continue to queue further work
     * immediately after this method returns.
     */
    virtual c2_status_t drain_nb(drain_mode_t mode) = 0;

    // STATE CHANGE METHODS
    // =============================================================================================
    virtual c2_status_t start() = 0;
    virtual c2_status_t stop() = 0;
    virtual c2_status_t reset() = 0;
    virtual c2_status_t release() = 0;
    virtual std::shared_ptr<C2ComponentInterface> intf() = 0;

    virtual ~C2Component() = default;
};
```

C2ComponentInterface
SimpleC2Component
C2SoftHevcEnc

3 MediaCodec
4 流程解析
5 总结