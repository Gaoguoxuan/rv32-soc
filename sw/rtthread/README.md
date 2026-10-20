RT-Thread v4.1.1 移植。内核源码在 ../../third_party/rt-thread/，来源见其中的 UPSTREAM.md。

目前完成控制台、中断接口、线程初始栈和首次现场恢复。
启动测试直接调用 CPU 端口，内核调度器和系统 tick 尚未接入。

文件对应关系：

- rtconfig.h：内核配置。
- cpuport.h / cpuport.c：现场布局、初始栈和中断接口。
- context.S：rt_hw_context_switch_to()，恢复现场并执行 mret。
- board.c：将控制台字符写入 0x20000000 的 UART MMIO。
- main.c：M11.1 控制台测试。
- start_test.c：M11.2 初始栈和首次启动测试。
- link.ld / start_test.ld：两个测试各自的内存布局，均使用 64 KiB ROM/RAM。

编译使用 rv32i_zicsr / ilp32 和 RV32I libgcc。scripts/rtthread_symbols.py
检查链接后的指令，包括 libgcc 中的代码。

运行：

```bash
make rtthread-test
make rtthread-start-test
```

两个测试都分别运行 -O0 和 -O2 版本。
rtthread-test 检查版本输出、格式化、缓冲区边界和中断接口。
rtthread-start-test 检查 16 种栈尾位置，再依次启动 A、B，并验证正常返回到退出函数。
成功时分别输出 M11.1 RT-THREAD CONSOLE O0/O2 CHECKS PASS 和
M11.2 RT-THREAD START O0/O2 CHECKS PASS。

反汇编和波形可用 rtthread-dump / rtthread-wave，或
rtthread-start-dump / rtthread-start-wave 查看。
