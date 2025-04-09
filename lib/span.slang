import platform;

public struct Span<T> : IRWArray<T>
{
    public T* data = nullptr;
    public size_t count = 0;

    public int getCount()
    {
        return (int)count;
    }

    public __subscript(size_t i) -> T
    {
        get { return data[i]; }
        set { data[i] = newValue; }
    }
}
