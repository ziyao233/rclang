#include<stdio.h>

extern unsigned long int foo;
extern void *p;
extern unsigned long int one64;

int array[4];

void print()
{
	printf("%lu %p\n", foo, p);
	printf("%lu\n", one64);
	printf("%d %d\n", *array, array[2]);
	return;
}
