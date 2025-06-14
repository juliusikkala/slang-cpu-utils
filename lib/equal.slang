public interface IEqual
{
    bool isEqual(This other);
}

public extension<T: IComparable> T : IEqual
{
    public bool isEqual(This other)
    {
        return equals(other);
    }
}

public bool operator==<T: IEqual>(T a, T b)
{
    return a.isEqual(b);
}
