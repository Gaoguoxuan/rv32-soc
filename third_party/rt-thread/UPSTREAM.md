RT-Thread 内核源码，来源：https://github.com/RT-Thread/rt-thread

固定版本：v4.1.1

固定提交：aab2428d4177a02cd3b0fd020e47a88de379a6ab

保留上游的 include/、src/、LICENSE 和 AUTHORS，文件内容未修改。
SHA256SUMS 记录这些文件的 SHA-256；构建测试通过 rtthread-vendor-check 检查。
本目录未包含上游 Git 仓库，后续编译与仿真无需网络。

M11.1 仅编译 src/kservice.c，运行版本输出和格式化服务。
本工程的配置、CPU 接口和板级代码位于 sw/rtthread/。
后续接入线程调度时，再增加相应内核源文件。
