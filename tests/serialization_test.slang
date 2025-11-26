import test;
import list;
import string;
import panic;
import serialization;

using scul;

struct Foo : ISerializable
{
    bool isCool;
    int level;
    U8String name;
    float3 direction;

    [mutating]
    void serialize<A: IArchive>(inout A ar) throws SerializationError
    {
        try ar.serialize(isCool);
        try ar.serialize(level);
        try ar.serialize(name);
        try ar.serialize(direction);
    }
}

export __extern_cpp int main(int argc, Ptr<NativeString> argv)
{
    Foo first;
    first.isCool = false;
    first.level = 42;
    first.name = U8String("Wow!");
    defer first.name.drop();
    first.direction = normalize(float3(1,2,3));

    BinaryOutputStream output;
    defer output.drop();

    do
    {
        try output.serialize(first);
    }
    catch
    {
        panic("output serialize");
    }

    test(output.size == 1+4+8+4+4*3, "output size");

    BinaryInputStream input = BinaryInputStream(output.size, output.data);

    Foo second = Foo();

    do
    {
        try input.serialize(second);
    }
    catch
    {
        panic("input serialize");
    }

    test(input.size == 0, "input size");
    test(first.isCool == second.isCool, "bool");
    test(first.level == second.level, "int");
    test(first.name == second.name, "U8String");
    test(all(first.direction == second.direction), "float3");

    return 0;
}
