#pragma once

/* ASCII helpers used by the pinned msh_parse.c. */
static inline int isdigit(int character)
{
    return character >= '0' && character <= '9';
}

static inline int tolower(int character)
{
    return character >= 'A' && character <= 'Z' ? character + ('a' - 'A') : character;
}

static inline int isxdigit(int character)
{
    return isdigit(character) || (character >= 'a' && character <= 'f') ||
           (character >= 'A' && character <= 'F');
}
