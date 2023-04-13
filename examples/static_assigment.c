#include<stdio.h>

extern unsigned long int foo;
extern void *p;

void print()
{
	printf("%lu %p\n", foo, p);
	return;
}
