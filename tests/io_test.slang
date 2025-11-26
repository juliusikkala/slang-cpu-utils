import io;
import drop;
import string;
import panic;
import list;
import test;

using scul;

export __extern_cpp int main(int argc, Ptr<NativeString> argv)
{
    List<uint8_t> data;

    for (int i = 0; i < 32; ++i)
        data.push(uint8_t(i));

    do
    {
        try writeBinaryFile("io_test.bin", data.data, data.size);
        data.drop();
        data = try readBinaryFile("io_test.bin");
        test(data.size == 32, "read size");
        for (int i = 0; i < 32; ++i)
            test(data.data[i] == i, "read data");
        data.drop();

        try writeTextFile("io_test.txt", "Hello world!");

        U8String str = try readTextFile("io_test.txt");
        defer str.drop();

        test(str == "Hello world!", "text IO");
    }
    catch
    {
        panic("Unexpect IOError!");
    }

    return 0;
}
