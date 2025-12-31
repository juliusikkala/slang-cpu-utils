import array;
import memory;
import drop;
import span;
import serialization;

namespace scul
{

public struct List<T>: IRWBigArray<T>, IDroppable
    where optional T: scul.IDroppable
{
    Ptr<T> _data;
    size_t _capacity;
    size_t _size;

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

    public List<T> clone()
    {
        var other = List<T>();
        other.reserve(_size);
        other._size = _size;
        copyBytes(Ptr<void>(other._data), Ptr<void>(_data), _size * strideof<T>());
        return other;
    }

    [mutating]
    public void drop()
    {
        if (T is IDroppable)
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

    public property Span<T> span
    {
        get {
            Span<T> res;
            res.data = _data;
            res.count = _size;
            return res;
        }
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
        if (T is IDroppable)
        {
            if (newSize < _size)
            {
                for (size_t i = newSize; i < _size; ++i)
                    _data[i].drop();
            }
        }

        if (newSize > _capacity)
            reserve(newSize);

        for (size_t i = _size; i < newSize; ++i)
            _data[i] = defaultValue;
        _size = newSize;
    }

    [mutating]
    public void reserve(size_t newCapacity)
    {
        if (newCapacity < _size)
            return;

        _data = reallocate<T>(_data, _capacity, newCapacity);
        _capacity = newCapacity;
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
        if (T is IDroppable)
        {
            for (size_t i = fromIndex; i < min(fromIndex+count, _size); ++i)
                _data[i].drop();
        }

        if (fromIndex >= _size)
            return;

        size_t end = fromIndex + count;
        if (end >= _size)
            end = _size;

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
        if (T is IDroppable)
        {
            if (_data != nullptr)
            {
                for (size_t i = 0; i < _size; ++i)
                    _data[i].drop();
            }
        }
        _size = 0;
    }
}

public extension<T: scul.ISerializable> List<T>: scul.ISerializable
    where optional T: scul.IDroppable
{
    [mutating]
    override void write<A: IOutputStream>(inout A ar) throws SerializationError
    {
        try ar.write(uint64_t(size));
        for (size_t i = 0; i < size; ++i)
            try ar.write(_data[i]);
    }

    [mutating]
    override void read<A: IInputStream>(inout A ar) throws SerializationError
    {
        uint64_t newSize;
        try ar.read(newSize);
        resize(size_t(newSize));
        for (uint64_t i = 0; i < newSize; ++i)
        {
            T value = T();
            try ar.read(value);
            _data[size_t(i)] = value;
        }
    }
}

}
