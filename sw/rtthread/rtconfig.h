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
#define RT_CONSOLEBUF_SIZE        128

/* 开启断言，方便定位移植错误 */
#define RT_DEBUG