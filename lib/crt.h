// This file forward declares C functions from the standard library, for which
// bindings are generated automatically.
#include <stddef.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include <stdio.h>
#include <time.h>
#include <threads.h>

typedef char Char;
typedef short Short;
typedef unsigned short UShort;
typedef int Int;
typedef unsigned int UInt;
typedef long Long;
typedef unsigned long ULong;
typedef long long LongLong;
typedef unsigned long long ULongLong;
typedef size_t Size;

typedef time_t Time;
typedef clock_t Clock;

static const uint64_t ClocksPerSec = CLOCKS_PER_SEC;

static const int SeekEnd = SEEK_END;
static const int SeekCur = SEEK_CUR;
static const int SeekSet = SEEK_SET;
static const int TimeUTC = TIME_UTC;


static const int MutexPlain = mtx_plain;
static const int MutexRecursive = mtx_recursive;
static const int MutexTimed = mtx_timed;
