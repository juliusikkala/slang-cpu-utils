namespace scul
{

public interface IDeleter<T>
{
    [mutating]
    void delete(inout T t);
}

public struct NoDelete<T>: IDeleter<T>
{
    [mutating]
    void delete(inout T t) {}
}

public interface IDroppable
{
    [mutating]
    void drop();
}

public struct DropDelete<T: IDroppable>: IDeleter<T>
{
    [mutating]
    void delete(inout T t) { t.drop(); }
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

}
