RT-Thread v4.1.1 移植。内核源码在 ../../third_party/rt-thread/，来源见其中的 UPSTREAM.md。

目前已验证线程启动、主动切换、定时器抢占、延时唤醒、静态信号量、互斥锁优先级继承和 idle 清理。
交互命令行使用同版本的 FinSH/msh，在本机终端通过 Verilator 运行。

文件对应关系：

- rtconfig.h：内核配置。
- cpuport.h / cpuport.c：现场布局、初始栈、中断接口、请求记录和中断分发。
- context.S：首次启动、线程切换和公共现场恢复代码，最后执行 mret。
- trap.S：保存中断现场，调用 C 分发函数，再恢复选定线程。
- tick.c：读取 mtime、设置 mtimecmp、初始化和停止系统 tick。
- board.c：控制台输出和输入；无输入时让接收线程延时 1 tick。
- main.c：M11.1 控制台测试。
- start_test.c：M11.2 初始栈和首次启动测试。
- sched_test.c：M11.3 内核调度测试，A/B 主动让出，返回后由检查线程收尾。
- tick_test.c：M11.4 定时器抢占测试，A/B 只计算，不调用 yield 或 delay。
- delay_test.c：M11.5 延时测试，A/B 定期唤醒，idle 运行并清理退出线程。
- sem_test.c：M11.6 信号量测试，生产者释放后由高优先级消费者先运行。
- mutex_test.c：M11.7 互斥锁测试，检查递归持锁、优先级继承和释放后的调度顺序。
- demo.c：M11.8 持续运行的生产者、消费者和心跳线程。
- input_test.c：接收线程等待和读取字符，低优先级心跳线程继续运行。
- shell_main.c：启动 msh，注册 hello 和 ticks 命令。
- shell.ld：shell 的链接脚本，保留 FSymTab 命令表。
- finsh_compat/：shell 使用的少量 C 库接口，字符串操作使用 rt_* 函数。
- link.ld / start_test.ld / sched_test.ld：各固件均使用 64 KiB ROM/RAM；调度及之后的测试和演示共用 sched_test.ld。

编译使用 rv32i_zicsr / ilp32 和 RV32I libgcc。scripts/rtthread_symbols.py
检查链接后的指令，包括 libgcc 中的代码。

运行：

```bash
make rtthread-test
make rtthread-start-test
make rtthread-sched-test
make rtthread-tick-test
make rtthread-delay-test
make rtthread-sem-test
make rtthread-mutex-test
make rtthread-demo-test
make rtthread-input-test
make rtthread-shell-test
```

十个测试都分别运行 -O0 和 -O2 版本。
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
rtthread-sem-test 增加 ipc.c，使用静态信号量，不启用堆。
生产者在第 2/4/6 tick 释放信号量，每次都由消费者先运行，生产者再从 release 返回。
两次带 5 tick 超时的等待被提前唤醒，核对定时器停用且移出链表；最后一次等待在第 8 tick 返回 -RT_ETIMEOUT。
还检查非阻塞获取、无人等待时的计数增加和消耗、静态信号量 detach、12 次中断和 26 次完整现场恢复。
rtthread-mutex-test 使用一把静态锁，H/M/L 的优先级分别为 10/11/12。
H、M 先延时，L 在此期间递归获取两次；H 等锁时，L 继承优先级 10，先于已就绪的 M 运行。
第一次释放保留持有者和继承优先级，最后一次释放将锁交给 H，并将 L 恢复为 12。
H、M 均在 L 的最后一次 release 返回前运行。还检查非持有者释放失败、非阻塞获取失败、锁恢复空闲和 detach。
线程优先级、锁字段和等待队列通过字段地址检查，不依赖结构体偏移。
该版本已删除线程的 init_priority 字段；本测试检查 current_priority 和锁的 original_priority。
延时到期只表示进入就绪队列，实际返回还受优先级影响；测试分别检查定时器到期和线程恢复。
当前 -O0 检查 9 次中断、17 次现场恢复，-O2 检查 8 次中断、16 次现场恢复。
每次均逐项检查 31 个通用寄存器、返回位置和 mstatus。
rtthread-demo-test 运行 205 个 tick，检查 20 条连续样本和 8 次心跳。
两个信号量管理单槽缓冲区，app_lock 保护统计数据和 rt_kprintf 的共享缓冲区。
生产者每 10 tick 工作，心跳每 25 tick 工作，使用 delay_until 按计划时刻推进周期。
仿真按 API 调用和定时器到期维护就绪线程模型，检查调度目标及每次完整现场恢复。
每 50 tick 两个周期线程同时到期，检查重复调度请求保留最初来源和最终目标。
结束观察时三个应用线程仍在等待后续工作，idle 正在运行，tick、MTIE 和 MIE 均保持开启。
固件持续运行，由 testbench 结束仿真。

rtthread-input-test 验证 rt_hw_console_getchar()，由一个线程读取输入。
无字符时调用 rt_thread_delay(1)，已有字符时先读取数据，再写 ACK。
输入函数在调度器和 tick 启动后使用。
testbench 在第 5 次定时器中断后连续送入 7 个字节，第 11 次中断后送入 Z。
检查 NUL、0xFF、0x80、ACK 同拍接收，以及连续 6 次读取不调用 delay。
等待期间心跳线程每 2 tick 运行；共记录 8 次心跳，其中输入前 2 次、间隔中 3 次。
还检查 idle 运行、接收线程正常退出和清理，以及各线程栈底保护字。
这个输入测试的字符由 testbench 提供。

运行交互命令行：

```bash
make rtthread-shell
```

看到 msh > 后输入 help、hello、ps、ticks 或 version，再按回车。
ps 显示 tshell 和 tidle0 两个线程；多次执行 ticks 可以看到系统 tick 增长。
退格、Tab 补全和方向键历史记录均可使用。按 Ctrl-C 退出并恢复终端设置。

make rtthread-shell-build 只构建，-O2 固件在 build/rtthread_shell_o2/。
主机程序 sim/rtthread_shell.cpp 只将键盘字节送入 RX MMIO，并显示 UART TX 输出。
命令解析和执行发生在 RTL CPU 上；等待键盘时仿真和系统 tick 继续运行。
也可以通过管道输入命令，EOF 后再运行 10 ms 仿真时间以输出最后的结果。

rtthread-shell-test 使用伪终端和管道分别运行两个优化版本，检查 help、hello、
ps、version、ticks、未知命令、编辑、历史记录和退出后的终端恢复。
shell 的所有目标文件使用 RV32_SOC_SHELL 配置，单独存放在构建目录。
链接脚本通过 KEEP(*(FSymTab)) 保留命令表，链接后仍检查 RV32I/Zicsr 指令。

只构建演示固件可运行 make rtthread-demo，产物在 build/rtthread_demo_o2/。
rtthread_demo.elf 用于调试，rtthread_demo.bin 是 ROM 映像，rtthread_demo.hex 用于当前仿真 ROM。
持续运行测试默认不记录波形；make rtthread-demo-wave 额外记录 55 tick 后打开波形。

调度测试创建 idle 线程；A/B 退出后由优先级更高的检查线程运行并结束测试。
启动测试直接调用 CPU 端口，调度测试通过 rt_system_scheduler_start() 启动内核。
tick 测试也创建 idle 线程，最后由检查线程收尾。
延时测试通过 idle_hook 记录 idle 运行，并检查两个 cleanup 回调均由 idle 执行。
静态线程清理后，线程对象类型变为 Null，原来的栈和控制块仍由测试程序持有。

tick 及之后的测试和演示时钟为 10 MHz，RT_TICK_PER_SECOND 为 1000，每 tick 为 10000 个计数。
rt_hw_tick_init() 在启动调度器前调用，保持 MIE=0，由首次 mret 开中断。
中断处理全程保持 MIE=0，调度请求在 C 函数返回前处理，再由汇编切换栈。
比较值按上次截止时间累加；错过下个截止时间会停止并报错，目前不补偿丢失的 tick。
tick_test.c 在初始化 tick 前设置 mtime，以覆盖低 32 位回绕；驱动自身不重置 mtime。

每个测试成功时，make 都会输出对应轮次的 O0/O2 CHECKS PASS。
反汇编和波形可用 rtthread-dump / rtthread-wave、
rtthread-start-dump / rtthread-start-wave、rtthread-sched-dump / rtthread-sched-wave、
rtthread-tick-dump / rtthread-tick-wave、rtthread-delay-dump / rtthread-delay-wave、
rtthread-sem-dump / rtthread-sem-wave、rtthread-mutex-dump / rtthread-mutex-wave、
rtthread-demo-dump / rtthread-demo-wave 查看。
