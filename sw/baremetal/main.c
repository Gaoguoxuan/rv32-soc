__attribute__((noinline))
static int add_three(int a, int b, int c)
{
    return a + b + c;
}


int main(void)
{
    volatile int a = 10;
    volatile int b = 20;
    volatile int c = 12;

    int result;

    result = add_three(a, b, c);

    return result;
}