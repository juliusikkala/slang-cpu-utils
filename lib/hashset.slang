import hash;
import array;
import memory;
import drop;
import equal;

public struct HashSet<T>: IDroppable, IBigArray<T>
    where T: IHashable, IEqual
    where optional T: IDroppable
{
    private size_t _indexCounter;
    private size_t _allocSize;
    private Ptr<size_t> _hashes;
    private Ptr<size_t> _next;
    private Ptr<T> _data;

    private static const size_t hashFactor = 4;

    public __init()
    {
        _data = nullptr;
        _hashes = nullptr;
        _next = nullptr;
        _indexCounter = 0;
        _allocSize = 0;
    }

    [mutating]
    public void drop()
    {
        clear();
        if (_data != nullptr)
            deallocate<T>(_data);
        if (_hashes != nullptr)
            deallocate<size_t>(_hashes);
        if (_next != nullptr)
            deallocate<size_t>(_next);
        _data = nullptr;
        _hashes = nullptr;
        _next = nullptr;
        _indexCounter = 0;
        _allocSize = 0;
    }

    public bool contains(T key)
    {
        size_t index = _hashes[key.hash() & getHashMask()];
        while (index != size_t.maxValue)
        {
            if (_data[index] == key)
                return true;
            else
                index = _next[index];
        }
        return false;
    }

    private uint64_t getHashMask()
    {
        return _allocSize * hashFactor - 1;
    }

    [mutating]
    private void expand()
    {
        size_t newAllocSize = max(_allocSize * 2, size_t(8));
        size_t hashCount = _allocSize * hashFactor;
        size_t newHashCount = newAllocSize * hashFactor;

        _hashes = reallocate<size_t>(_hashes, hashCount, newHashCount);
        for (size_t i = 0; i < newHashCount; ++i)
            _hashes[i] = size_t.maxValue;

        _next = reallocate<size_t>(_next, _allocSize, newAllocSize);
        _data = reallocate<T>(_data, _allocSize, newAllocSize);
        _allocSize = newAllocSize;

        // Rehash.
        for (size_t i = 0; i < _indexCounter; ++i)
        {
            uint64_t h = _data[i].hash() & getHashMask();
            Ptr<size_t> index = _hashes + int64_t(h);
            while (*index != size_t.maxValue)
                index = _next + int64_t(*index);
            *index = i;
            _next[*index] = size_t.maxValue;
        }
    }

    // Returns false if the key already existed. Always takes ownership of the
    // key.
    [mutating]
    public bool add(T key)
    {
        // Rehash if there's no space to add to.
        if (_indexCounter == _allocSize)
            expand();

        uint64_t h = key.hash() & getHashMask();
        Ptr<size_t> index = _hashes + int64_t(h);
        while (*index != size_t.maxValue)
        {
            if (_data[*index] == key)
            {
                if (T is IDroppable)
                    key.drop();
                return false; // Already exists.
            }
            else
                index = _next + int64_t(*index);
        }

        *index = _indexCounter;
        ++_indexCounter;

        _data[*index] = key;
        _next[*index] = size_t.maxValue;
        return true;
    }

    // Returns index to next entry after erase.
    // Does not drop the given key.
    [mutating]
    public Optional<size_t> remove(T key)
    {
        // Remove old value
        uint64_t h = key.hash() & getHashMask();
        Ptr<size_t> index = _hashes + int64_t(h);
        while (*index != size_t.maxValue)
        {
            if (_data[*index] == key)
                break;
            else
                index = _next + int64_t(*index);
        }

        // Not found
        if (*index == size_t.maxValue)
            return none;

        // Destruct the found entry.
        if (T is IDroppable)
            _data[*index].drop();
        size_t i = *index;
        *index = _next[*index];

        size_t lastIndex = _indexCounter-1;
        // Swap with last value
        if (i != lastIndex)
        {
            _data[i] = _data[lastIndex];
            h = _data[i].hash() & getHashMask();
            Ptr<size_t> prevIndex = _hashes + int64_t(h);
            while (*prevIndex != lastIndex)
                prevIndex = _next + int64_t(*prevIndex);
            *prevIndex = i;
            _next[i] = _next[lastIndex];
        }
        _indexCounter--;
        return *index;
    }

    [mutating]
    public void clear()
    {
        if (T is IDroppable)
        {
            for (size_t i = 0; i < _indexCounter; ++i)
                _data[i].drop();
        }
        for (size_t i = 0; i < _allocSize * hashFactor; ++i)
            _hashes[i] = size_t.maxValue;
        _indexCounter = 0;
    }

    public property size_t size
    {
        get { return _indexCounter; }
    }

    public property Ptr<T> data
    {
        get { return _data; }
    }

    // For IBigArray
    public size_t getSize()
    {
        return _indexCounter;
    }

    public __subscript(size_t i) -> T
    {
        get { return _data[i]; }
    }
}
