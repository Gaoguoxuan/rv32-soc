RT-Thread v4.1.1 移植。内核源码在 ../../third_party/rt-thread/，来源见其中的 UPSTREAM.md。

目前可以运行内核调度器，用 rt_thread_yield() 在线程之间切换。
系统 tick 尚未接入，定时抢占和 rt_thread_delay() 留到下一步。

文件对应关系：

- rtconfig.h：内核配置。
- cpuport.h / cpuport.c：现场布局、初始栈、中断接口和中断切换请求记录。
- context.S：首次启动和线程切换，共用现场恢复代码，最后执行 mret。
- board.c：将控制台字符写入 0x20000000 的 UART MMIO。
- main.c：M11.1 控制台测试。
- start_test.c：M11.2 初始栈和首次启动测试。
- sched_test.c：M11.3 内核调度测试，A/B 主动让出，返回后由检查线程收尾。
- link.ld / start_test.ld / sched_test.ld：各测试的内存布局，均使用 64 KiB ROM/RAM。

编译使用 rv32i_zicsr / ilp32 和 RV32I libgcc。scripts/rtthread_symbols.py
检查链接后的指令，包括 libgcc 中的代码。

运行：

```bash
make rtthread-test
make rtthread-start-test
make rtthread-sched-test
```

三个测试都分别运行 -O0 和 -O2 版本。
rtthread-test 检查版本输出、格式化、缓冲区边界和中断接口。
rtthread-start-test 检查 16 种栈尾位置，再依次启动 A、B，并验证正常返回到退出函数。
rtthread-sched-test 链接 object、thread、scheduler、timer、clock、irq、idle 和 kservice。
它检查 8 次现场保存、9 次恢复、6 次 yield、两次正常退出、临界区状态和栈底保护字。
所有保存和恢复都逐项检查 31 个通用寄存器、返回位置和 mstatus。

调度测试创建 idle 线程；A/B 退出后由优先级更高的检查线程运行并结束测试。
启动测试直接调用 CPU 端口，调度测试通过 rt_system_scheduler_start() 启动内核。
中断切换接口本轮只检查请求记录；实际中断退出切换将在接入 tick 时完成。

每个测试成功时，make 都会输出对应轮次的 O0/O2 CHECKS PASS。
反汇编和波形可用 rtthread-dump / rtthread-wave、
rtthread-start-dump / rtthread-start-wave、rtthread-sched-dump / rtthread-sched-wave 查看。
