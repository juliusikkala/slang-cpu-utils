import array;
import memory;
import drop;
import span;

public struct List<T: IDroppable>: IRWBigArray<T>, IDroppable
{
    private Ptr<T> _data;
    private size_t _capacity;
    private size_t _size;

    public __init()
    {
        _data = nullptr;
        _capacity = 0;
        _size = 0;
    }

    /*
    public __init<each U>(expand each U args) where U == T
    {
        _size = 0;
        _capacity = countof(args);
        _data = allocate<T>(_capacity);
        expand push(each args);
    }
    */

    [mutating]
    public void drop()
    {
        clear();
        if (_data != nullptr)
            deallocate<T>(_data);
        _data = nullptr;
        _capacity = 0;
        _size = 0;
    }

    public property size_t size 
    {
        get { return _size; }
    }

    public property Ptr<T> data 
    {
        get { return _data; }
    }

    // For IRWBigArray
    public size_t getSize()
    {
        return _size;
    }

    public __subscript(size_t i) -> T
    {
        get { return _data[i]; }
        set { _data[i] = newValue; }
    }

    [mutating]
    public void resize(size_t newSize, T defaultValue = T())
    {
        if (newSize > _capacity)
            reserve(newSize);

        if (newSize < _size)
        {
            for (size_t i = newSize; i < _size; ++i)
                _data[i].drop();
        }

        for (size_t i = _size; i < newSize; ++i)
            _data[i] = defaultValue;
        _size = newSize;
    }

    [mutating]
    public void reserve(size_t newCapacity)
    {
        if (newCapacity < _size)
            return;

        if (newCapacity == 0)
            drop();
        else
        {
            _data = reallocate<T>(_data, _capacity, newCapacity);
            _capacity = newCapacity;
        }
    }

    [mutating]
    public void push(T value)
    {
        if (_size >= _capacity)
        {
            let newCapacity = _capacity == 0 ? 1 : _capacity * 2;
            reserve(newCapacity);
        }
        _data[_size] = value;
        _size++;
    }

    [mutating]
    public T pop(T failValue = T())
    {
        if (_size == 0)
            return failValue;
        T value = _data[_size-1];
        _size--;
        return value;
    }

    [mutating]
    public T swapAndPop(size_t fromIndex, T failValue = T())
    {
        if (fromIndex >= _size)
            return failValue;
        T value = _data[fromIndex];
        _data[fromIndex] = _data[_size-1];
        _size--;
        return value;
    }

    [mutating]
    public void erase(size_t fromIndex, size_t count)
    {
        if (fromIndex >= _size)
            return;

        size_t end = fromIndex + count;
        if (end >= _size)
            end = _size;

        for (size_t i = fromIndex; i < end; ++i)
            _data[i].drop();

        for (size_t i = fromIndex; i+count < _size; ++i)
            _data[i] = _data[i+count];
        _size -= end - fromIndex;
    }

    [mutating]
    public void insert(size_t toIndex, T value)
    {
        Span<T> valueSpan;
        valueSpan.data = &value;
        valueSpan.count = 1;
        insert(toIndex, valueSpan);
    }

    [mutating]
    public void insert<U: IBigArray<T>>(size_t toIndex, U arr)
    {
        let newSize = _size + arr.getSize();
        if (newSize >= _capacity)
        {
            size_t newCapacity = _capacity * 2;
            if (newCapacity < newSize)
                newCapacity = newSize;
            reserve(newCapacity);
        }

        let target = min(toIndex, _size);

        for(size_t i = _size; i > target; --i)
        {
            let oldIndex = i-1;
            let newIndex = oldIndex + arr.getSize();
            _data[newIndex] = _data[oldIndex];
        }

        for(size_t i = 0; i < arr.getSize(); ++i)
        {
            _data[target + i] = arr[i];
        }

        _size = newSize;
    }

    [mutating]
    public void clear()
    {
        if (_data != nullptr)
        {
            for (size_t i = 0; i < _size; ++i)
                _data[i].drop();
        }
        _size = 0;
    }
}
