void force_stderr()
{
    // Can't do this trick on Windows
#ifndef SLANG_PLATFORM_WIN32
    // stdout must be flushed before swapping it out, otherwise the preceding 
    // output may get skipped.
    __intrinsic_asm "fflush(stdout); stdout = stderr;";
#endif
}

public void abort()
{
    // Flush so that whatever was printed before abort is visible. It's annoying
    // when you can't see what happened right before the crash.
    __intrinsic_asm "fflush(stdout); fflush(stderr); abort()";
}

public void panic<each T>(String format, expand each T args)
{
    // This ugly hack exists to make printf write to stderr; I couldn't find a
    // way to call fprintf in Slang (= convert `args` to varargs for C)
    force_stderr();
    printf(format, expand each args);
    abort();
}
