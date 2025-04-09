public interface IDroppable
{
    [mutating]
    void drop();
}

public void drop<T>(inout T val)
    where T : IDroppable
{
    val.drop();
}

public void drop<T>(inout T val) {}
