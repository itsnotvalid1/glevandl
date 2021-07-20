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

static const char linkage_abi_fmt[] = "[%s-%s]";
static char linkage_abi[sizeof(linkage) + sizeof(abi) + sizeof(linkage_abi_fmt)];

int main(void)
{
	snprintf(linkage_abi, sizeof(linkage_abi), linkage_abi_fmt, linkage, abi);

	printf("%s Hello World!\n", linkage_abi);
	return 0;
}
