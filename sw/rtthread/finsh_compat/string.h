#pragma once

#include <stddef.h>
#include <rtthread.h>

/* Only used by the freestanding shell build, without a target libc. */
#define strlen  rt_strlen
#define strcpy  rt_strcpy
#define strncpy rt_strncpy
#define strcmp  rt_strcmp
#define strncmp rt_strncmp
#define memcmp  rt_memcmp

static inline char *strcat(char *destination, const char *source)
{
    rt_strcpy(destination + rt_strlen(destination), source);
    return destination;
}
