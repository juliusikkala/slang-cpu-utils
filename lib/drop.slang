public interface IDroppable
{
    [mutating]
    void drop();
}

public extension<T: IDroppable> Optional<T>: IDroppable
{
    [mutating]
    public void drop()
    {
        if (hasValue)
        {
            T tmp = value;
            tmp.drop();
            this = none;
        }
    }
}

public void drop<T>(inout T val)
    where T : IDroppable
{
    val.drop();
}

public void drop<T>(inout T val) {}
