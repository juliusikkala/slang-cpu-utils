import list;
import array;
import drop;
import span;
import hash;

public NativeString ptrToString<T>(Ptr<T> ptr)
{
    // These bad boys are surprisingly hard to construct, since reinterpret<T>
    // doesn't like NativeString.
    __intrinsic_asm "((const char*)$0)";
}

public Ptr<T> stringToPtr<T>(NativeString ptr)
{
    return Ptr<T>(ptr.getBuffer());
}

public Optional<int64_t> parseInt(NativeString str, inout int offset, int radix = 10, bool allowNegative = true)
{
    Ptr<uint8_t> string = stringToPtr<uint8_t>(str);
    int64_t result = 0;
    bool found = false;
    bool negative = false;
    int originalOffset = offset;

    while (string[offset] != 0)
    {
        int a = 0;
        uint8_t c = string[offset];
        if (c == 45 && allowNegative && !negative)
        {
            negative = true;
            offset++;
            continue;
        }
        else if (c >= 48 && c <= 57)
            a = c-48;
        else if(c >= 65 && c <= 90)
            a = c-55;
        else if(c >= 97 && c <= 122)
            a = c-87;
        else break;

        if (a >= radix)
            break;

        found = true;
        offset++;
        result = result * radix + a;
    }

    if (!found)
    {
        offset = originalOffset;
        return none;
    }

    return negative ? -result : result;
}

public Optional<double> parseFloat(NativeString str, inout int offset, bool allowNegative = false)
{
    Ptr<uint8_t> string = stringToPtr<uint8_t>(str);
    double result = 0;
    bool found = false;
    bool negative = false;
    bool decimals = false;
    double decimal_div = 10;

    while (string[offset] != 0)
    {
        int a = 0;
        uint8_t c = string[offset];
        if (c == 45 && allowNegative)
        {
            negative = !negative;
            offset++;
            continue;
        }
        else if (c == 46 && !decimals)
        {
            decimals = true;
            offset++;
            continue;
        }
        else if (c >= 48 && c <= 57)
            a = c-48;
        else break;

        found = true;
        offset++;

        if (decimals)
        {
            result += double(a) / decimal_div;
            decimal_div *= 10;
        }
        else
            result = result * 10 + double(a);
    }

    if (!found)
        return none;

    return negative ? -result : result;
}

public bool isWhitespace(uint8_t c, bool newline = false)
{
    if (c == ' ' || c == '\t')
        return true;
    if (newline && (c == '\n' || c == '\r'))
        return true;
    return false;
}

public void skipWhitespace(NativeString str, inout int offset, bool newline = false)
{
    Ptr<uint8_t> string = stringToPtr<uint8_t>(str);
    while (isWhitespace(string[offset], newline))
        offset++;
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

// Adapted from PDCursesMod (public domain)
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

public int utf32ToUtf8(uint32_t c, inout uint8_t o[4])
{
    if (c < 0x80)
    {
        o[0] = uint8_t(c);
        return 1;
    }
    else if (c < 0x800)
    {
        o[0] = uint8_t(0b11000000 | (c >> 6));
        o[1] = uint8_t(0b10000000 | (c & 0x3F));
        return 2;
    }
    else if (c < 0x10000)
    {
        o[0] = uint8_t(0b11100000 | (c >> 12));
        o[1] = uint8_t(0b10000000 | ((c >> 6) & 0x3F));
        o[2] = uint8_t(0b10000000 | (c & 0x3F));
        return 3;
    }
    else if (c < 0x200000)
    {
        o[0] = uint8_t(0b11110000 | (c >> 18));
        o[1] = uint8_t(0b10000000 | ((c >> 12) & 0x3F));
        o[2] = uint8_t(0b10000000 | ((c >> 6) & 0x3F));
        o[3] = uint8_t(0b10000000 | (c & 0x3F));
        return 4;
    }
    return 0;
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

    public U8String clone()
    {
        U8String other;
        other._data = _data.clone();
        return other;
    }

    // DO NOT drop() the return value!
    public List<uint8_t> asList()
    {
        if (_data.size == 0)
            return _data;

        List<uint8_t> l = _data;
        // Remove null terminator. Note that this doesn't change _data, as pop()
        // only changes the "size" member.
        l.pop(0);
        return l;
    }

    // Consumes given list
    public static U8String fromList(inout List<uint8_t> l)
    {
        U8String result;
        result._data = l;

        // Reset to prevent user from dropping the data we yoinked.
        l = List<uint8_t>();

        if (result._data.size != 0)
        {
            // If not null-terminated, add null terminator.
            if (result._data[result._data.size-1] != 0)
                result._data.push(0);
        }
        return result;
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
    public void appendChar(uint32_t c)
    {
        ensureNullTerminator();

        uint8_t chars[4];
        int count = utf32ToUtf8(c, chars);
        _data.insert(getSize(), Span<uint8_t>(&chars[0], count));
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
        // Since 'equals' doesn't care about order, we can quickly determine an
        // inequality with length. 'lessThan' and 'lessThanOrEquals' don't have
        // this convenience.
        if (other.length != length)
            return false;
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

public bool operator==(NativeString str, NativeString other)
{
    __intrinsic_asm "strcmp($0, $1) == 0";
}

public bool operator==(U8String a, NativeString b)
{
    return ((a.cStr) == b);
}

public bool operator==(NativeString a, U8String b)
{
    return ((b.cStr) == a);
}

public bool operator==(U8String a, U8String b)
{
    return a.equals(b);
}
