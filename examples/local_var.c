#include<stdio.h>

extern unsigned long int v;

void
print(void)
{
	printf("%lu\n", v);
	return;
}
