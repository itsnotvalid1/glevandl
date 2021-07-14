#include <stdio.h>

#if defined(LINKAGE_static)
	static const char linkage[] = "static";
#elif defined(LINKAGE_dynamic)
	static const char linkage[] = "dynamic";
#else
	static const char linkage[] = "unknown";
#endif

#if defined(_LP64)
	static const char abi[] = "LP64";
#else
	static const char abi[] = "ILP32";
#endif

int main(void)
{
	printf("Hello %s %s World!\n", linkage, abi);
	return 0;
}
