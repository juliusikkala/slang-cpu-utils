import list;
import array;
import drop;
import span;
import hash;

public NativeString ptrToString<T>(Ptr<T> ptr)
{
    // These bad boys are surprisingly hard to construct, since reinterpret<T>
    // doesn't like NativeString.
    __target_switch
    {
    case cpp: __intrinsic_asm "((const char*)$0)";
    };
}

public Ptr<T> stringToPtr<T>(NativeString ptr)
{
    return Ptr<T>(ptr.getBuffer());
}

public uint codePointLength(NativeString u8str, size_t offset = 0)
{
    Ptr<int8_t> str = stringToPtr<int8_t>(u8str) + int64_t(offset);

    if(*str == 0) return 0;
    if(*str > 0) return 1;

    uint count = 0;
    while (*str < 0)
    {
        if(count != 0 && *str >= -64)
            break;
        str++;
        count++;
    }
    return count;
}

public size_t codePointStringLength(NativeString str, size_t offset = 0)
{
    size_t count = 0;
    size_t i = 0;

    for(;;)
    {
        size_t len = codePointLength(str, i);
        if (len == 0) break;
        count++;
        i += len;
    }
    return count;
}

// Adapted from PDCursesMod
public uint32_t utf8ToUtf32(NativeString str, size_t offset = 0)
{
    Ptr<uint8_t> string = stringToPtr<uint8_t>(str) + int64_t(offset);
    uint32_t key = string[0];

    if ((key & 0x80) == 0)
        return string[0];
    else if ((key & 0xc0) == 0xc0 && (string[1] & 0xc0) == 0x80)
    {
        if ((key & 0xe0) == 0xc0)
        {
            key = ((key & 0x1f) << 6) | uint32_t(string[1] & 0x3f);
        }
        else if ((key & 0xf0) == 0xe0 && (string[2] & 0xc0) == 0x80)
        {
            key = ((key & 0x0f) << 12) | (uint32_t(string[1] & 0x3f) << 6) |
                  uint32_t(string[2] & 0x3f);
        }
        else if ((key & 0xf8) == 0xf0 && (string[2] & 0xc0) == 0x80 && (string[3] & 0xc0) == 0x80)
        {
            key = ((key & 0x07) << 18) | (uint32_t(string[1] & 0x3f) << 12) |
                  (uint32_t(string[2] & 0x3f) << 6) | uint32_t(string[3] & 0x3f);
        }
    }

    return key;
}

public struct U8String: IBigArray<uint8_t>, IDroppable, IComparable, IHashable
{
    private List<uint8_t> _data;

    public __init()
    {
        _data = List<uint8_t>();
    }

    public __init(NativeString str)
    {
        _data = List<uint8_t>();
        append(str);
    }


    [mutating]
    private void ensureNullTerminator()
    {
        if (_data.size == 0)
            _data.push(0);
    }

    [mutating]
    public void drop()
    {
        _data.drop();
    }

    // For IBigArray
    public size_t getSize()
    {
        // -1 to exclude hidden null terminator.
        return max(_data.getSize(), size_t(1))-1;
    }

    public property size_t length
    {
        get {
            return getSize();
        }
    }

    public __subscript(size_t i) -> uint8_t
    {
        get { return _data[i]; }
        set { _data[i] = newValue; }
    }

    public size_t getCodePointCount()
    {
        return codePointStringLength(cStr);
    }

    public uint32_t readCodePoint(size_t offset)
    {
        return utf8ToUtf32(cStr, offset);
    }

    // Returns false if `offset` is at the end of the string. You can use this
    // function to iterate over codepoints efficiently.
    public bool stepCodePoint(inout size_t offset, inout uint32_t codePoint)
    {
        codePoint = utf8ToUtf32(cStr, offset);
        size_t len = codePointLength(cStr, offset);
        offset += len;
        return len != 0;
    }

    public property NativeString cStr
    {
        get {
            if (_data.getSize() == 0)
                return "";
            return ptrToString(_data.data);
        }
    }

    [mutating]
    public void erase(size_t fromIndex, size_t count)
    {
        // Prevent erasing null terminator.
        size_t limitedCount = min(count, getSize()-fromIndex);
        _data.erase(fromIndex, limitedCount);
    }

    [mutating]
    public void clear()
    {
        _data.clear();
    }

    [mutating]
    public void appendChar(uint8_t c)
    {
        ensureNullTerminator();
        _data.insert(getSize(), c);
    }

    [mutating]
    public void append(NativeString str)
    {
        ensureNullTerminator();
        _data.insert(getSize(), Span<uint8_t>(stringToPtr<uint8_t>(str), str.length));
    }

    [mutating]
    public void append(U8String other)
    {
        ensureNullTerminator();
        _data.insert(getSize(), Span<uint8_t>(other._data.data, other.getSize()));
    }

    [mutating]
    public void append<U: __BuiltinIntegerType>(U c, uint radix = 10)
    {
        ensureNullTerminator();
        if (c < U(0))
            appendChar(45);

        uint64_t absc = abs(c).toUInt64();
        uint64_t div = 1;
        while (div * radix < absc) div *= radix;

        while (div > 0)
        {
            int64_t v = absc / div;
            absc -= v * div;
            uint8_t numChar = uint8_t(48 + v);
            if (v >= 10)
                numChar = uint8_t(55 + v);
            appendChar(numChar);
            div /= radix;
        }
    }

    public int cmp(U8String other)
    {
        for (size_t i = 0; i < min(_data.size, other._data.size); ++i)
        {
            if(_data[i] < other._data[i])
                return -1;
            else if(_data[i] > other._data[i])
                return 1;
        }
        return 0;
    }

    public bool equals(U8String other)
    {
        return cmp(other) == 0;
    }

    public bool lessThan(U8String other)
    {
        return cmp(other) < 0;
    }

    public bool lessThanOrEquals(U8String other)
    {
        return cmp(other) <= 0;
    }

    public uint64_t hash()
    {
        return fnv1a(_data.data, getSize());
    }
}
