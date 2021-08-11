#include <stdio.h>

int main(void)
{
#if defined(_LP64)
	static const char abi[] = "LP64";
#else
	static const char abi[] = "ILP32";
#endif

	printf("%s: sizeof int     = %u\n", abi, (unsigned int)sizeof(int));
	printf("%s: sizeof long    = %u\n", abi, (unsigned int)sizeof(long));
	printf("%s: sizeof pointer = %u\n", abi, (unsigned int)sizeof(int *));

	return 0;
}
