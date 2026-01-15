import memory;
import serialization;
import drop;
import list;
import string;
import crt;

namespace scul
{

public struct BinaryOutputStream: IOutputStream, IDroppable
{
    List<uint8_t> _data;

    public property bool output { get { return true; } }

    public __init()
    {
        _data = List<uint8_t>();
    }

    [mutating]
    public void drop()
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
    public void writeBytes(NativeString str)
    {
        uint64_t len = uint64_t(C.strlen(str));
        Ptr<uint8_t> bytes = stringToPtr<uint8_t>(str);
        for (uint64_t i = 0; i < len; ++i)
            _data.push(bytes[i]);
    }

    [mutating]
    internal void writeBuiltin(bool value) throws SerializationError
    {
        _data.push(uint8_t(value ? 1 : 0));
    }

    [mutating]
    internal void writeBuiltin<T: __BuiltinArithmeticType>(T value) throws SerializationError
    {
        let data = Ptr<uint8_t>(&value);
        for (int i = 0; i < strideof<T>(); ++i)
            _data.push(data[i]);
    }
}

public struct BinaryInputStream: IInputStream
{
    size_t _head;
    size_t _size;
    Ptr<uint8_t> _data;

    public property bool output { get { return false; } }

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

    private void ensureBytes(size_t bytes) throws SerializationError
    {
        if (size < bytes)
            throw SerializationError.Input;
    }

    [mutating]
    internal void readBuiltin(inout bool value) throws SerializationError
    {
        try ensureBytes(1);
        value = *data != 0;
        _head += 1;
    }

    [mutating]
    internal void readBuiltin<T: __BuiltinArithmeticType>(inout T value) throws SerializationError
    {
        try ensureBytes(strideof<T>());
        copyBytes(Ptr<void>(&value), Ptr<void>(data), strideof<T>());
        _head += strideof<T>();
    }
}

}
