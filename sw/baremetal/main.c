volatile int global_zero;

static volatile int counter;


__attribute__((noinline))
static int add_three(int a, int b, int c)
{
    return a + b + c;
}


__attribute__((noinline))
static void update_globals(void)
{
    global_zero = 100;

    counter = 23;
}


int main(void)
{
    volatile int a = 10;
    volatile int b = 20;
    volatile int c = 12;

    int result;

    result = add_three(a, b, c);

    update_globals();

    if (global_zero != 100)
        return -1;

    if (counter != 23)
        return -2;

    return result;
}