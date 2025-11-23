// This file re-declares C constants for bindings.
#include <stdio.h>
#include <time.h>
#include <stdint.h>

static const uint64_t CLOCK_TICKS_PER_SEC = CLOCKS_PER_SEC;

static const int SeekEnd = SEEK_END;
static const int SeekCur = SEEK_CUR;
static const int SeekSet = SEEK_SET;
