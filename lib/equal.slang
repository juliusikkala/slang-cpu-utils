namespace scul
{

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

public extension<T> Ptr<T>: IEqual
{
    public bool isEqual(Ptr<T> other)
    {
        return reinterpret<uintptr_t>(this) == reinterpret<uintptr_t>(other);
    }
}

[OverloadRank(-15)]
public bool operator==<T: IEqual>(T a, T b)
{
    return a.isEqual(b);
}

}
