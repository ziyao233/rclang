#include<stdio.h>

extern unsigned long int a, b;

void
print(void)
{
	printf("%lu %lu\n", a, b);
	return;
}
