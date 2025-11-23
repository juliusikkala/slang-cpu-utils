// This file forward declares C functions from the standard library, for which
// bindings are generated automatically.
#include "ctypes.h"

void* malloc(Size size);
void* realloc(void *ptr, Size new_size);
void free(void* ptr);
void abort(void);
void* memcpy(void* dest, const void* src, Size count);
void* memset(void* dest, Int ch, Size count);

Int strcmp(const char* lhs, const char* rhs);

File* fopen(const char* filename, const char* mode);
Int fclose(File* stream);
Size fread(void* buffer, Size size, Size count, File* stream);
Int fgetc(File* stream);
Size fwrite(const void* buffer, Size size, Size count, File* stream);
Long ftell(File* stream);
Int fseek(File* stream, Long offset, Int origin);

void exit(Int status);

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

extern File* stdout;
extern File* stderr;
extern File* stdin;
