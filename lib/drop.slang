namespace scul
{

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

}
