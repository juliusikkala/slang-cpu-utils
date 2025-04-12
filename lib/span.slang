import array;

public struct Span<T> : IRWBigArray<T>
{
    public T* data = nullptr;
    public size_t count = 0;

    public size_t getSize()
    {
        return count;
    }

    public __subscript(size_t i) -> T
    {
        get { return data[i]; }
        set { data[i] = newValue; }
    }
}
