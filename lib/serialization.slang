import list;
import string;
import memory;
import drop;

namespace scul
{

public enum SerializationError
{
    Output = 0,
    Input,
};

// This is a bit funky. The behavior of `serialize` depends on whether the
// IArchive wants to save or load - serializable objects don't actually know
// that! This allows one to write serialization code in one function that serves
// both directions.
public interface IArchive
{
    property bool output { get; }

    [mutating]
    void serialize(inout bool value) throws SerializationError;
    [mutating]
    void serialize<T: __BuiltinArithmeticType>(inout T value) throws SerializationError;
    [mutating]
    void serialize(inout U8String value) throws SerializationError;

    [mutating]
    void serialize<S : ISerializable>(inout S value) throws SerializationError
    {
        try value.serialize(this);
    }

    [mutating]
    void beginStruct() throws SerializationError {}
    [mutating]
    void endStruct() throws SerializationError {}
    // If returns true, the caller should resize their array.
    [mutating]
    bool beginArray(inout uint64_t len) throws SerializationError;
    [mutating]
    void endArray() throws SerializationError {}
}

public interface ISerializable
{
    [mutating]
    void serialize<A: IArchive>(inout A ar) throws SerializationError;
}

public struct BinaryOutputStream: IArchive, IDroppable
{
    List<uint8_t> _data;

    property bool output { get { return true; } }

    public __init()
    {
        _data = List<uint8_t>();
    }

    [mutating]
    void drop()
    {
        _data.drop();
    }

    public property size_t size 
    {
        get { return _data.size; }
    }

    public property Ptr<uint8_t> data 
    {
        get { return _data.data; }
    }

    [mutating]
    void serialize(inout bool value) throws SerializationError
    {
        _data.push(uint8_t(value ? 1 : 0));
    }

    [mutating]
    void serialize<T: __BuiltinArithmeticType>(inout T value) throws SerializationError
    {
        let data = Ptr<uint8_t>(&value);
        for (int i = 0; i < strideof<T>(); ++i)
            _data.push(data[i]);
    }

    [mutating]
    void serialize(inout U8String value) throws SerializationError
    {
        uint64_t size = value.length;
        try serialize(size);
        for (int i = 0; i < size; ++i)
            _data.push(value[i]);
    }

    [mutating]
    bool beginArray(inout uint64_t len) throws SerializationError
    {
        try serialize(len);
        return false;
    }
}

public struct BinaryInputStream: IArchive
{
    size_t _head;
    size_t _size;
    Ptr<uint8_t> _data;

    property bool output { get { return false; } }

    public __init(size_t size, Ptr<uint8_t> data)
    {
        _head = 0;
        _size = size;
        _data = data;
    }

    public property size_t size 
    {
        get { return _size - _head; }
    }

    public property Ptr<uint8_t> data 
    {
        get { return _data + _head; }
    }

    void ensureBytes(size_t bytes) throws SerializationError
    {
        if (size < bytes)
            throw SerializationError.Input;
    }

    [mutating]
    void serialize(inout bool value) throws SerializationError
    {
        try ensureBytes(1);
        value = *data != 0;
        _head += 1;
    }

    [mutating]
    void serialize<T: __BuiltinArithmeticType>(inout T value) throws SerializationError
    {
        try ensureBytes(strideof<T>());
        copyBytes(Ptr<void>(&value), Ptr<void>(data), strideof<T>());
        _head += strideof<T>();
    }

    [mutating]
    void serialize(inout U8String value) throws SerializationError
    {
        value.clear();
        uint64_t size;
        try serialize(size);
        try ensureBytes(size_t(size));
        for (int i = 0; i < size; ++i)
            value.appendByte(data[i]);
        _head += size_t(size);
    }

    [mutating]
    bool beginArray(inout uint64_t len) throws SerializationError
    {
        uint64_t oldLen = len;
        try serialize(len);
        return oldLen != len;
    }
}

public extension<T : __BuiltinArithmeticType, let N:int> vector<T, N>: ISerializable
{
    [mutating]
    void serialize<A: IArchive>(inout A ar) throws SerializationError
    {
        try ar.beginStruct();
        for (int i = 0; i < N; ++i)
        {
            T element = this[i];
            try ar.serialize(element);
            if (!ar.output)
                this[i] = element;
        }
        try ar.endStruct();
    }
}

public extension<T : __BuiltinArithmeticType, let R : int, let C : int, let L : int> matrix<T, R, C, L> : ISerializable
{
    [mutating]
    void serialize<A: IArchive>(inout A ar) throws SerializationError
    {
        try ar.beginStruct();
        for (int i = 0; i < R; ++i)
        {
            var row = this[i];
            try ar.serialize(row);
            if (!ar.output)
                this[i] = row;
        }
        try ar.endStruct();
    }
}

public extension<T : ISerializable> Optional<T>: ISerializable
{
    [mutating]
    void serialize<A: IArchive>(inout A ar) throws SerializationError
    { 
        bool hasValue = this.hasValue;
        try ar.serialize(hasValue);
        if (hasValue)
        {
            T element = T();
            if (ar.output)
                element = this.value;

            try ar.serialize(element);
            if (!ar.output)
                this = element;
        }
    }
}

}
