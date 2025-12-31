import string;
import drop;
import list;
import memory;
import crt;

namespace scul
{

public Optional<U8String> readLine()
{
    U8String str;
    int c = 0;

    while (c != 10)
    {
        c = C.fgetc(C.stdin);
        if (c < 0) // EOF
        {
            if (str.len == 0)
                return none;
            break;
        }
        str.appendChar(uint8_t(c));
    }

    return str;
}

public enum IOError
{
    Open = 0,
    Write,
    Read
}

public List<uint8_t> readBinaryFile(NativeString path) throws IOError
{
    C.FILE* f = C.fopen(path, "rb");

    if (f == nullptr)
        throw IOError.Open;

    defer C.fclose(f);

    C.fseek(f, 0, C.SeekEnd);
    size_t sz = size_t(C.ftell(f));
    C.fseek(f, 0, C.SeekSet);

    List<uint8_t> data;
    data.resize(sz);
    if (C.fread(reinterpret<Ptr<void>>(data.data), 1, sz, f) != sz)
    {
        data.drop();
        throw IOError.Read;
    }
    return data;
}

public void writeBinaryFile(NativeString path, Ptr<uint8_t> data, size_t size) throws IOError
{
    C.FILE* f = C.fopen(path, "wb");

    if (f == nullptr)
        throw IOError.Open;

    defer C.fclose(f);

    if (C.fwrite(reinterpret<Ptr<void>>(data), 1, size, f) != size)
        throw IOError.Write;
}

public void writeBinaryFile(NativeString path, List<uint8_t> data) throws IOError
{
    try writeBinaryFile(path, data.data, data.size);
}

public U8String readTextFile(NativeString path) throws IOError
{
    List<uint8_t> l = try readBinaryFile(path);
    return U8String::fromList(l);
}

public void writeTextFile(NativeString path, U8String data) throws IOError
{
    try writeBinaryFile(path, data.asList());
}

public void writeTextFile(NativeString path, NativeString data) throws IOError
{
    try writeBinaryFile(path, stringToPtr<uint8_t>(data), data.length);
}

}
