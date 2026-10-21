#pragma once

/* 内核基本配置 */
#define RT_NAME_MAX                 8
#define RT_ALIGN_SIZE              16
#define RT_THREAD_PRIORITY_MAX     32
#define RT_TICK_PER_SECOND       1000
#define IDLE_THREAD_STACK_SIZE   1024

/* 控制台 */
#define RT_USING_CONSOLE
#define RT_USING_IDLE_HOOK
#define RT_USING_SEMAPHORE
#define RT_USING_MUTEX
#define RT_CONSOLEBUF_SIZE        128

/* 开启断言，方便定位移植错误 */
#define RT_DEBUG

/* shell 固件的配置，编译时使用 -DRV32_SOC_SHELL */
#ifdef RV32_SOC_SHELL

#define RT_USING_MSH
#define RT_USING_FINSH
#define FINSH_USING_MSH
#define FINSH_USING_SYMTAB
#define FINSH_USING_DESCRIPTION
#define MSH_USING_BUILT_IN_COMMANDS

#define FINSH_USING_HISTORY
#define FINSH_HISTORY_LINES          5
#define FINSH_THREAD_NAME      "tshell"
#define FINSH_THREAD_PRIORITY       20
#define FINSH_THREAD_STACK_SIZE   4096
#define FINSH_CMD_SIZE              80
#define FINSH_ARG_MAX                8

#endif
