/*
 * Basic tests that exercise Linux VSDO calls.
 *
 * clock_getres
 * clock_gettime
 * gettimeofday
 * rt_sigreturn
 *
 */

#include <errno.h>
#include <stdio.h>
#include <signal.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <unistd.h>
#include <sys/time.h>

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

#if 0
static void test_sizes(void)
{
	struct timespec ts;
	struct timeval tv;

	char (*__1)[sizeof(ts)] = 1;         // ilp32 = 8 bytes, lp64 = 16 bytes.
	char (*__2)[sizeof(ts.tv_sec)] = 1;  // ilp32 = 4 bytes, lp64 = 8 bytes.
	char (*__3)[sizeof(ts.tv_nsec)] = 1; // ilp32 = 4 bytes, lp64 = 8 bytes.
	
	char (*__4)[sizeof(tv)] = 1;         // ilp32 = 8 bytes, lp64 = 16 bytes.
	char (*__5)[sizeof(tv.tv_sec)] = 1;  // ilp32 = 4 bytes, lp64 = 8 bytes.
	char (*__6)[sizeof(tv.tv_usec)] = 1; // ilp32 = 4 bytes, lp64 = 8 bytes.
}
#endif

static void print_timespec_size(void)
{
	struct timespec ts;

	printf("%s %s: timespec: tv_sec = %u bytes, tv_nsec = %u bytes\n",
		linkage_abi, __func__,
		(unsigned int)sizeof(ts.tv_sec),
		(unsigned int)sizeof(ts.tv_nsec));
}

/*
 * int clock_getres(clockid_t clk_id, struct timespec *res);
 * int clock_gettime(clockid_t clk_id, struct timespec *tp);
 * size_t strftime(char *s, size_t max, const char *format, const struct tm *tm);
 *
 * struct timespec {
 *     time_t   tv_sec;  // seconds
 *     long     tv_nsec; // nanoseconds
 * };
 */

struct clock {
	clockid_t clk;
	char *name;
};

static int test_clock_getres(const struct clock *p)
{
	int result;
	struct timespec ts;

	result = clock_getres(p->clk, &ts);

	if (result) {
		printf("%s %s: %s failed: %s (%d)\n", linkage_abi,
			__func__, p->name, strerror(errno), errno);
		return 1;
	}

	printf("%s %s: %s: %llu sec, %ld ns\n", linkage_abi, __func__,
		p->name, (unsigned long long int)ts.tv_sec, ts.tv_nsec);

	return 0;
}

static int test_clock_gettime(const struct clock *p)
{
	int result;
	struct timespec ts;

	result = clock_gettime(p->clk, &ts);

	if (result) {
		printf("%s %s: %s failed: %s (%d)\n", linkage_abi,
			__func__, p->name, strerror(errno), errno);
		return 1;
	}

	printf("%s %s: %s: %llu sec, %ld ns\n", linkage_abi, __func__,
		p->name, (unsigned long long int)ts.tv_sec, ts.tv_nsec);

	return 0;
}

static int test_clocks(void)
{
	static const struct clock clocks[] = {
		{CLOCK_REALTIME, "CLOCK_REALTIME"},
		{CLOCK_REALTIME_COARSE, "CLOCK_REALTIME_COARSE"},
		{CLOCK_MONOTONIC, "CLOCK_MONOTONIC"},
		{CLOCK_MONOTONIC_COARSE, "CLOCK_MONOTONIC_COARSE"},
		{CLOCK_MONOTONIC_RAW, "CLOCK_MONOTONIC_RAW"},
		{CLOCK_BOOTTIME, "CLOCK_BOOTTIME"},
		{CLOCK_PROCESS_CPUTIME_ID, "CLOCK_PROCESS_CPUTIME_ID"},
		{CLOCK_THREAD_CPUTIME_ID, "CLOCK_THREAD_CPUTIME_ID"},
	};
	static const unsigned int clock_count = sizeof(clocks) / sizeof(clocks[0]);
	const struct clock *p;
	int error_count;

	for (p = clocks, error_count = 0; p < clocks + clock_count; p++) {
		//printf("%s:\n", p->name);
		error_count += test_clock_getres(p) ? 1 : 0;
		error_count += test_clock_gettime(p) ? 1 : 0;
		printf("\n");
	}

	return error_count;
}

/*
 * int gettimeofday(struct timeval *tv, struct timezone *tz);
 *
 * struct timeval {
 *     time_t      tv_sec;  // seconds
 *     suseconds_t tv_usec; // microseconds
 * };
 *
 * struct timezone {
 *     int tz_minuteswest; // minutes west of Greenwich
 *     int tz_dsttime;     // type of DST correction
 * };
 */

static int test_gettimeofday(void)
{
	int result;
	struct timeval tv;

	result = gettimeofday(&tv, NULL);

	if (result) {
		printf("%s %s: failed: %s (%d)\n", linkage_abi, __func__,
			strerror(errno), errno);
		return 1;
	}

	printf("%s %s: %llu sec, %ld ms\n\n", linkage_abi , __func__,
		(unsigned long long int)tv.tv_sec, tv.tv_usec);

	return 0;
}

/*
 * sighandler_t signal(int signum, sighandler_t action);
 *
 */

static int alarm_event;

static void SIGALRM_handler(int __attribute__((unused)) signum)
{
	fflush(stdout);
	printf("\n%s\n", __func__);
	fflush(stdout);
	alarm_event = 1;
}

static void alpha_print(char c, unsigned limit)
{
	int i;

	for(i = 0; i < limit; i++) {
		fprintf(stderr, "%c", c + i);
		fflush(stderr);
		if (alarm_event) {
			return;
		}
	}

}

static int test_sigreturn(void)
{
	__sighandler_t result;

	result = signal(SIGALRM, SIGALRM_handler);

	if (result == SIG_ERR) {
		printf("%s %s: failed: %s (%d)\n", linkage_abi,
			__func__, strerror(errno), errno);
		return 1;
	}

	printf("\n%s %s: start\n", linkage_abi, __func__);
	fflush(stdout);

	alarm_event = 0;
	alarm(1);

	for(int i = 0; !alarm_event; i++) {
		fprintf(stderr, "%i: ", i);

		alpha_print('a', 26);
		if (alarm_event)
			break;

		alpha_print('a', 26);
		if (alarm_event)
			break;

		alpha_print('0', 10);
		if (alarm_event)
			break;

		fprintf(stderr, "\n");
		fflush(stderr);
	}

	signal(SIGALRM, SIG_DFL);

	printf("\n%s %s: done\n\n", linkage_abi, __func__);
	
	return 0;
}

int main(void)
{
	int error_count = 0;

	snprintf(linkage_abi, sizeof(linkage_abi), linkage_abi_fmt, linkage, abi);

	printf("%s -- tests start --\n", linkage_abi);
	print_timespec_size();

	fflush(stdout);
	sleep(1);

	error_count += test_clocks();
	error_count += test_gettimeofday() ? 1 : 0;
	error_count += test_sigreturn() ? 1 : 0;

	printf("%s %d tests failed.\n", linkage_abi, error_count);
	printf("%s -- tests end --\n", linkage_abi);

	return error_count ? EXIT_FAILURE : EXIT_SUCCESS;
}
