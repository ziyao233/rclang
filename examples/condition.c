#include<stdio.h>

extern unsigned long int a;

void
print(void)
{
	printf("%lu\n", a);
	return;
}
