import io;
import drop;
import string;
import list;
import test;

export __extern_cpp int main(int argc, Ptr<NativeString> argv)
{
    List<uint8_t> data;

    for (int i = 0; i < 32; ++i)
        data.push(uint8_t(i));

    writeBinaryFile("io_test.bin", data.data, data.size);
    drop(data);
    data = readBinaryFile("io_test.bin");
    test(data.size == 32, "read size");
    for (int i = 0; i < 32; ++i)
        test(data.data[i] == i, "read data");
    drop(data);

    writeTextFile("io_test.txt", "Hello world!");

    U8String str = readTextFile("io_test.txt");
    defer drop(str);

    test(str == "Hello world!", "text IO");

    return 0;
}
