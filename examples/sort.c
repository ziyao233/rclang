#include<stdio.h>

unsigned long int array[] = { 2, 1, 7, 5, 4, 3, 9 };
unsigned long int n = sizeof(array) / sizeof(unsigned long int);

void
print(void)
{
	for (unsigned long int i = 0; i < n; i++)
		printf("%lu ", array[i]);
	putchar('\n');
	return;
}
