RT-Thread v4.1.1 移植。内核源码在 ../../third_party/rt-thread/，来源见其中的 UPSTREAM.md。

目前已验证线程启动、主动切换、定时器抢占、rt_thread_delay()、超时唤醒和 idle 清理。

文件对应关系：

- rtconfig.h：内核配置。
- cpuport.h / cpuport.c：现场布局、初始栈、中断接口、请求记录和中断分发。
- context.S：首次启动、线程切换和公共现场恢复代码，最后执行 mret。
- trap.S：保存中断现场，调用 C 分发函数，再恢复选定线程。
- tick.c：读取 mtime、设置 mtimecmp、初始化和停止系统 tick。
- board.c：将控制台字符写入 0x20000000 的 UART MMIO。
- main.c：M11.1 控制台测试。
- start_test.c：M11.2 初始栈和首次启动测试。
- sched_test.c：M11.3 内核调度测试，A/B 主动让出，返回后由检查线程收尾。
- tick_test.c：M11.4 定时器抢占测试，A/B 只计算，不调用 yield 或 delay。
- delay_test.c：M11.5 延时测试，A/B 定期唤醒，idle 运行并清理退出线程。
- link.ld / start_test.ld / sched_test.ld：各测试均使用 64 KiB ROM/RAM；调度、tick 和延时测试共用 sched_test.ld。

编译使用 rv32i_zicsr / ilp32 和 RV32I libgcc。scripts/rtthread_symbols.py
检查链接后的指令，包括 libgcc 中的代码。

运行：

```bash
make rtthread-test
make rtthread-start-test
make rtthread-sched-test
make rtthread-tick-test
make rtthread-delay-test
```

五个测试都分别运行 -O0 和 -O2 版本。
rtthread-test 检查版本输出、格式化、缓冲区边界和中断接口。
rtthread-start-test 检查 16 种栈尾位置，再依次启动 A、B，并验证正常返回到退出函数。
rtthread-sched-test 链接 object、thread、scheduler、timer、clock、irq、idle 和 kservice。
它检查 8 次现场保存、9 次恢复、6 次 yield、两次正常退出、临界区状态和栈底保护字。
所有保存和恢复都逐项检查 31 个通用寄存器、返回位置和 mstatus。
rtthread-tick-test 检查 12 次真实定时器中断：6 次原线程返回、6 次抢占切换。
同时检查中断进入/退出计数、请求消费、比较值安全写入、低 32 位回绕和线程正常退出。
rtthread-delay-test 检查 9 次阻塞延时、18 次定时器中断和 30 次现场恢复，包含 idle 栈。
A 在第 3/6/9/12/15 tick 醒来，B 在第 5/10/15 tick 醒来，检查线程在第 18 tick 收尾。
第 15 tick 先唤醒 B，再唤醒优先级更高的 A，核对两次请求保留 idle 为来源、A 为最终目标。
中断唤醒阻塞线程时先恢复到内核临界区，再由内核恢复 MIE 并从 delay 返回。

调度测试创建 idle 线程；A/B 退出后由优先级更高的检查线程运行并结束测试。
启动测试直接调用 CPU 端口，调度测试通过 rt_system_scheduler_start() 启动内核。
tick 测试也创建 idle 线程，最后由检查线程收尾。
延时测试通过 idle_hook 记录 idle 运行，并检查两个 cleanup 回调均由 idle 执行。
静态线程清理后，线程对象类型变为 Null，原来的栈和控制块仍由测试程序持有。

tick 和延时测试的时钟为 10 MHz，RT_TICK_PER_SECOND 为 1000，每 tick 为 10000 个计数。
rt_hw_tick_init() 在启动调度器前调用，保持 MIE=0，由首次 mret 开中断。
中断处理全程保持 MIE=0，调度请求在 C 函数返回前处理，再由汇编切换栈。
比较值按上次截止时间累加；错过下个截止时间会停止并报错，目前不补偿丢失的 tick。
tick_test.c 在初始化 tick 前设置 mtime，以覆盖低 32 位回绕；驱动自身不重置 mtime。

每个测试成功时，make 都会输出对应轮次的 O0/O2 CHECKS PASS。
反汇编和波形可用 rtthread-dump / rtthread-wave、
rtthread-start-dump / rtthread-start-wave、rtthread-sched-dump / rtthread-sched-wave、
rtthread-tick-dump / rtthread-tick-wave、rtthread-delay-dump / rtthread-delay-wave 查看。
