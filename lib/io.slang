import string;
import panic;
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

public List<uint8_t> readBinaryFile(NativeString path)
{
    Ptr<void> f = fopen_helper(path, "rb");

    // TODO: Use exception instead, once those work.
    if (f == nullptr)
        panic("Unable to open %s\n", path);

    defer fclose_helper(f);

    fseek_helper(f, 0, SEEK_END);
    size_t sz = ftell_helper(f);
    fseek_helper(f, 0, SEEK_SET);

    List<uint8_t> data;
    data.resize(sz);
    if (fread_helper(reinterpret<Ptr<void>>(data.data), 1, sz, f) != sz)
    {
        data.drop();
        panic("Unable to read %s\n", path);
    }
    return data;
}

public void writeBinaryFile(NativeString path, List<uint8_t> data)
{
    Ptr<void> f = fopen_helper(path, "wb");

    // TODO: Use exception instead, once those work.
    if (f == nullptr)
        panic("Unable to open %s\n", path);

    defer fclose_helper(f);

    if (fwrite_helper(reinterpret<Ptr<void>>(data.data), 1, data.size, f) != data.size)
        panic("Unable to write %s\n", path);
}

public U8String readTextFile(NativeString path)
{
    List<uint8_t> l = readBinaryFile(path);
    return U8String::fromList(l);
}

public void writeTextFile(NativeString path, U8String data)
{
    writeBinaryFile(path, data.asList());
}
