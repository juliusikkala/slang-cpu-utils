// This file forward declares C functions from the standard library, for which
// bindings are generated automatically.
#include "ctypes.h"

void* malloc(Size size);
void* realloc(void *ptr, Size new_size);
void free(void* ptr);
void abort(void);
void* memcpy(void* dest, const void* src, Size count);
void* memset(void* dest, Int ch, Size count);

void exit(int status);

Time time(Time* arg);
double difftime(Time time_end, Time time_beg);
Clock clock(void);

#ifdef WIN32
void* _aligned_alloc(Size size, Size alignment);
void* _aligned_realloc(void* memblock, Size size, Size alignment);
void* _aligned_free(void* memblock);
#else
void* aligned_alloc(Size alignment, Size size);
#endif

static const uint64_t CLOCK_TICKS_PER_SEC = CLOCKS_PER_SEC;
