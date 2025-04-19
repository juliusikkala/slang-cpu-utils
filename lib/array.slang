// IBigArray & IRWBigArray exist because Slang's own IArray and IRWArray are
// limited to 32-bit signed integer sizes, which is actually pretty small.
public interface IBigArray<T>
{
    size_t getSize();
    __subscript(size_t x) -> T
    {
        get;
    }
}

public interface IRWBigArray<T>: IBigArray<T>
{
    __subscript(size_t x) -> T
    {
        get;
        set;
    }
}

public extension<T, U: IArray<T>> U : IBigArray<T>
{
    public size_t getSize()
    {
        return getCount();
    }

    public __subscript(size_t x) -> T
    {
        get { return this[int(x)]; }
    }
}

public extension<T, U: IRWArray<T>> U : IRWBigArray<T>
{
    public size_t getSize()
    {
        return getCount();
    }

    public __subscript(size_t x) -> T
    {
        get { return this[int(x)]; }
        set { this[int(x)] = newValue; }
    }
}

public void copy<T, A: IBigArray<T>, B: IRWBigArray<T>>(inout A from, inout B to)
{
    size_t count = min(from.getSize(), to.getSize());
    for (size_t i = 0; i < count; ++i)
        to[i] = from[i];
}
