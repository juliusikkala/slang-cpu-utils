import hash;
import array;
import memory;
import drop;
import equal;

namespace scul
{

public struct HashMap<K, T>: IDroppable
    where K: IHashable, IEqual
    where optional K: IDroppable
    where optional T: IDroppable
{
    private size_t _indexCounter;
    private size_t _allocSize;
    private Ptr<size_t> _hashes;
    private Ptr<size_t> _next;
    private Ptr<K> _keys;
    private Ptr<T> _values;

    private static const size_t hashFactor = 4;

    public __init()
    {
        _keys = nullptr;
        _values = nullptr;
        _hashes = nullptr;
        _next = nullptr;
        _indexCounter = 0;
        _allocSize = 0;
    }

    [mutating]
    public void drop()
    {
        clear();
        if (_keys != nullptr)
            deallocate<K>(_keys);
        if (_values != nullptr)
            deallocate<T>(_values);
        if (_hashes != nullptr)
            deallocate<size_t>(_hashes);
        if (_next != nullptr)
            deallocate<size_t>(_next);
        _keys = nullptr;
        _values = nullptr;
        _hashes = nullptr;
        _next = nullptr;
        _indexCounter = 0;
        _allocSize = 0;
    }

    public bool contains(K key)
    {
        if(!_hashes) return false;

        size_t index = _hashes[key.hash() & getHashMask()];
        while (index != size_t.maxValue)
        {
            if (_keys[index] == key)
                return true;
            else
                index = _next[index];
        }
        return false;
    }

    public Optional<T> get(K key)
    {
        if(!_hashes) return none;

        size_t index = _hashes[key.hash() & getHashMask()];
        while (index != size_t.maxValue)
        {
            if (_keys[index] == key)
                return _values[index];
            else
                index = _next[index];
        }
        return none;
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
        _keys = reallocate<K>(_keys, _allocSize, newAllocSize);
        _values = reallocate<T>(_values, _allocSize, newAllocSize);
        _allocSize = newAllocSize;

        // Rehash.
        for (size_t i = 0; i < _indexCounter; ++i)
        {
            uint64_t h = _keys[i].hash() & getHashMask();
            Ptr<size_t> index = _hashes + int64_t(h);
            while (*index != size_t.maxValue)
                index = _next + int64_t(*index);
            *index = i;
            _next[*index] = size_t.maxValue;
        }
    }

    // Returns false if the key already existed, but always replaces with new
    // value. Takes ownership of both the key and value.
    [mutating]
    public bool add(K key, T value)
    {
        // Rehash if there's no space to add to.
        if (_indexCounter == _allocSize)
            expand();

        uint64_t h = key.hash() & getHashMask();
        Ptr<size_t> index = _hashes + int64_t(h);
        while (*index != size_t.maxValue)
        {
            if (_keys[*index] == key)
            {
                if (T is IDroppable)
                    _values[*index].drop();
                _values[*index] = value;
                if (K is IDroppable)
                    key.drop();
                return false; // Already exists.
            }
            else
                index = _next + int64_t(*index);
        }

        *index = _indexCounter;
        ++_indexCounter;

        _keys[*index] = key;
        _values[*index] = value;
        _next[*index] = size_t.maxValue;
        return true;
    }

    // Returns index to next entry after erase. 
    [mutating]
    public Optional<size_t> remove(K key)
    {
        if(!_hashes) return none;

        // Remove old value
        uint64_t h = key.hash() & getHashMask();
        Ptr<size_t> index = _hashes + int64_t(h);
        while (*index != size_t.maxValue)
        {
            if (_keys[*index] == key)
                break;
            else
                index = _next + int64_t(*index);
        }

        // Not found
        if (*index == size_t.maxValue)
            return none;

        // Destruct the found entry.
        if (K is IDroppable)
            _keys[*index].drop();
        if (T is IDroppable)
            _values[*index].drop();
        size_t i = *index;
        *index = _next[*index];

        size_t lastIndex = _indexCounter-1;
        // Swap with last value
        if (i != lastIndex)
        {
            _keys[i] = _keys[lastIndex];
            _values[i] = _values[lastIndex];
            h = _keys[i].hash() & getHashMask();
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
        for (size_t i = 0; i < _indexCounter; ++i)
        {
            if (K is IDroppable)
                _keys[i].drop();
            if (T is IDroppable)
                _values[i].drop();
        }
        for (size_t i = 0; i < _allocSize * hashFactor; ++i)
            _hashes[i] = size_t.maxValue;
        _indexCounter = 0;
    }

    public property size_t size
    {
        get { return _indexCounter; }
    }

    public property Ptr<K> keys
    {
        get { return _keys; }
    }

    public property Ptr<T> values
    {
        get { return _values; }
    }

    public size_t getSize()
    {
        return _indexCounter;
    }

    public K getKeyByIndex(size_t index)
    {
        return _keys[index];
    }

    public T getValueByIndex(size_t index)
    {
        return _values[index];
    }

    public void setValueByIndex(size_t index, T value)
    {
        if (T is IDroppable)
            _values[index].drop();
        _values[index] = value;
    }

    public Optional<size_t> getKeyIndex(K key)
    {
        if(!_hashes) return none;

        size_t index = _hashes[key.hash() & getHashMask()];
        while (index != size_t.maxValue)
        {
            if (_keys[index] == key)
                return index;
            else
                index = _next[index];
        }
        return none;
    }

    public __subscript(K key) -> Optional<T>
    {
        get {
            return get(key);
        }
        set {
            if (let value = newValue)
                add(key, value);
            else
                remove(key);
        }
    }
}

}
