import panic;

using scul;

public void test<each T>(bool condition, NativeString str, expand each T args)
{
    if (!condition)
        panic(str, expand each args);
}
