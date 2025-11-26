// IBigArray & IRWBigArray exist because Slang's own IArray and IRWArray are
// limited to 32-bit signed integer sizes, which is actually pretty small.
namespace scul
{

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

public extension<T, let N:int> vector<T, N> : IRWBigArray<T>
{
    public size_t getSize() { return getCount(); }
    public __subscript(size_t x) -> T
    {
        get { return this[int(x)]; }
        set { this[int(x)] = newValue; }
    }
}

public extension<T, let R : int, let C : int, let L : int> matrix<T, R, C, L> : IRWBigArray<vector<T, C>>
{
    public size_t getSize() { return getCount(); }
    public __subscript(size_t x) -> vector<T, C>
    {
        get { return this[int(x)]; }
        set { this[int(x)] = newValue; }
    }
}

public extension<T, let N:int> Array<T, N> : IRWBigArray<T>
{
    public size_t getSize() { return getCount(); }
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

}
