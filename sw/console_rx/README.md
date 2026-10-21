CPU 轮询接收寄存器，读取字符、写 ACK，再通过 UART TX 回显。
固件复用 sw/uart/ 的启动代码和链接脚本，使用 4 KiB ROM、1 KiB RAM。

| 地址 | 作用 |
| --- | --- |
| 0x20000000 | 写入一个输出字符 |
| 0x20000004 | 读 bit 0：是否有字符 |
| 0x20000008 | 读低 8 位字符；空时返回零 |
| 0x2000000C | 写 bit 0 为 1：取走字符 |

状态和数据读取不会取走字符。ACK 需要选中低字节，其他写入无效。
输入通过 uart_rx_valid / uart_rx_data / uart_rx_ready 握手，每次传一个字节。
满时输入方保持 valid 和 data，直到某个上升沿 ready 为 1。

运行：

```bash
make console-rx-test console-rx-lint
make soc-console-rx-test
```

集成测试分别运行 -O0 和 -O2 固件。输入由 testbench 提供，包含 NUL、
0xFF 和连续字符；最后暂停输入，再送入 Z。它检查 CPU 的真实 MMIO
读写、无效 ACK、地址隔离、ACK 同拍接收以及逐字节回显。
输出中的 <00>、<FF> 等标记是 testbench 对不可打印字节的显示方式。
目前还没有连接键盘和 msh。
