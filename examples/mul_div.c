#include<stdio.h>

extern unsigned long int a, b;
extern long int c, d;

extern unsigned long int e;
extern long int f;

void
print(void)
{
	printf("%lu %lu\n", a, b);
	printf("%ld %ld\n", c, d);

	printf("%lu %ld\n", e, f);
	return;
}
