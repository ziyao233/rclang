#include<stdio.h>

extern long int a, b;

void
print(void)
{
	printf("%ld %ld\n", a, b);
	return;
}
