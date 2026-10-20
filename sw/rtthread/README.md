M11.1：让官方 RT-Thread 内核服务在自制 RV32 SoC 上运行。

源码位于 ../../third_party/rt-thread/，固定为 v4.1.1 的
aab2428d4177a02cd3b0fd020e47a88de379a6ab。上游文件未修改，构建无需网络。
本阶段编译 kservice.c，验证版本输出、格式化、缓冲区边界和 CPU 中断接口。
线程初始化、上下文切换和系统 tick 将在后续阶段接入。

文件对应关系：

- rtconfig.h：内核配置。
- cpuport.c：将 RT-Thread 的中断接口接到 ../common/irq.h。
- board.c：将控制台字符写入 0x20000000 的 UART MMIO。
- main.c：入口和本阶段验证程序。
- link.ld：64 KiB ROM、64 KiB RAM、16 字节对齐栈及栈保护区。

输出经过 rt_show_version / rt_kprintf、rt_hw_console_output 和真实 UART MMIO。
RT-Thread 的默认弱控制台实现由 board.c 中的强符号覆盖。

保持 -march=rv32i_zicsr、-mabi=ilp32；使用当前工具链的 RV32I libgcc
完成编译器生成的软件算术。scripts/rtthread_symbols.py 同时检查链接后
的指令，覆盖 libgcc，排除当前 CPU 不支持的扩展指令。

运行：

```bash
make rtthread-test
make rtthread-dump
make rtthread-wave
```

rtthread-test 分别运行 -O0 和 -O2 两个版本。
成功时最后输出 M11.1 RT-THREAD CONSOLE O0/O2 CHECKS PASS。
UART 中应包含 4.1.1 版本横幅、RTHW IRQ PASS、FORMAT、ARGS、BUFFER PASS
以及 M11.1 PASS。版本横幅中的日期和时间由实际编译决定。
