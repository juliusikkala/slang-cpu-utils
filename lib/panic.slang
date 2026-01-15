import crt;

namespace scul
{

public void abort()
{
    // Flush so that whatever was printed before abort is visible. It's annoying
    // when you can't see what happened right before the crash.
    C.exit(1);
}

public void panic<each T>(String format, expand each T args)
{
    // TODO: Make this print to stderr somehow and flush.
    printf(format, expand each args);
    abort();
}

}
