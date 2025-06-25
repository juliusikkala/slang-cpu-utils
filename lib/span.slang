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

public extension<T> Span<T>: IDifferentiablePtrType
    where T: IDifferentiable
{
    public typealias Differential = Span<T.Differential>;
}

[BackwardDerivative(load_bwd)]
public T load<T: IDifferentiable>(Span<T> span, size_t i)
{
    return span[i];
}

void load_bwd<T : IDifferentiable>(DifferentialPtrPair<Span<T>> pair, size_t i, T.Differential dOut)
{
    pair.d.data[i] = T.dadd(pair.d[i], dOut);
}
