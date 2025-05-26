import string;
import drop;
import list;
import memory;

int fgetc_stdin()
{
    __intrinsic_asm "fgetc(stdin)";
}

Ptr<void> fopen_helper(NativeString path, NativeString flags)
{
    __intrinsic_asm "(void*)fopen($0, $1)";
}

size_t fwrite_helper(Ptr<void> data, size_t size, size_t count, Ptr<void> file)
{
    __intrinsic_asm "fwrite($0, $1,$2,(FILE*)$3)";
}

size_t fread_helper(Ptr<void> buffer, size_t size, size_t count, Ptr<void> file)
{
    __intrinsic_asm "fread($0, $1,$2,(FILE*)$3)";
}

property int SEEK_END {
    get { __intrinsic_asm "(SEEK_END)"; }
}

property int SEEK_SET {
    get { __intrinsic_asm "(SEEK_SET)"; }
}

size_t ftell_helper(Ptr<void> file)
{
    __intrinsic_asm "ftell((FILE*)$0)";
}

size_t fseek_helper(Ptr<void> file, int64_t offset, int origin)
{
    __intrinsic_asm "fseek((FILE*)$0, $1, $2)";
}

void fclose_helper(Ptr<void> f)
{
    __intrinsic_asm "fclose((FILE*)$0)";
}

public Optional<U8String> readLine()
{
    U8String str;
    int c = 0;

    while (c != 10)
    {
        c = fgetc_stdin();
        if (c < 0) // EOF
        {
            if (str.length == 0)
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
    Ptr<void> f = fopen_helper(path, "rb");

    if (f == nullptr)
        throw IOError.Open;

    defer fclose_helper(f);

    fseek_helper(f, 0, SEEK_END);
    size_t sz = ftell_helper(f);
    fseek_helper(f, 0, SEEK_SET);

    List<uint8_t> data;
    data.resize(sz);
    if (fread_helper(reinterpret<Ptr<void>>(data.data), 1, sz, f) != sz)
    {
        data.drop();
        throw IOError.Read;
    }
    return data;
}

public void writeBinaryFile(NativeString path, Ptr<uint8_t> data, size_t size) throws IOError
{
    Ptr<void> f = fopen_helper(path, "wb");

    if (f == nullptr)
        throw IOError.Open;

    defer fclose_helper(f);

    if (fwrite_helper(reinterpret<Ptr<void>>(data), 1, size, f) != size)
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
