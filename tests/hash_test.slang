import hash;
import test;

void testIntHash<T: __BuiltinIntegerType>(NativeString testName, T min, T max, T step)
{
    for (T i = min; i < max-step; i += step)
    {
        test(i.hash() != (i+T(1)).hash(), "hash seq %s", testName);
        test(i.hash() != i.toUInt64(), "hash direct %s (%ld)", testName, i.toInt64());
        if (-i != i && i != min)
            test((-i).hash() != i.hash(), "hash neg %s (%ld)", testName, i.toInt64());
    }
}

void testFloatHash<T: __BuiltinFloatingPointType>(NativeString testName, T min, T max, T step)
{
    for (T i = min; i < max-step; i += step)
    {
        test(i.hash() != reinterpret<uint64_t>(i), "hash direct %s", testName);
        if (-i != i && i != min)
            test((-i).hash() != i.hash(), "hash neg %s", testName);
    }
}

public struct MyHashable: IHashable
{
    public uint64_t hash()
    {
        return 4;
    }
}

export __extern_cpp int main(int argc, Ptr<NativeString> argv)
{
    uint64_t seed = 0;

    seed = hashCombine(seed, 10);
    test(seed != 0, "hashCombine 1");

    uint64_t second = hashCombine(seed, 10);
    test(seed != second, "hashCombine 2");

    seed = hashMany(seed);
    test(hashMany(seed, 10, 10) != hashMany(seed, 10), "hashMany 1");
    test(hashMany(0, 10, 10) != hashMany(1, 10, 10), "hashMany 2");
    test(hashMany(23) == (23).hash(), "hashMany 3");

    test(false.hash() != true.hash(), "hash bool");
    testIntHash<int8_t>("int8_t", int8_t.minValue, int8_t.maxValue, 1);
    testIntHash<uint8_t>("uint8_t", uint8_t.minValue, uint8_t.maxValue, 1);
    testIntHash<int16_t>("int16_t", int16_t.minValue, int16_t.maxValue, 1);
    testIntHash<uint16_t>("uint16_t", uint16_t.minValue, uint16_t.maxValue, 1);
    testIntHash<int32_t>("int32_t", int32_t.minValue, int32_t.maxValue, 577);
    testIntHash<uint32_t>("uint32_t", uint32_t.minValue, uint32_t.maxValue, 577);
    testIntHash<int64_t>("int64_t", int64_t.minValue, int64_t.maxValue, 300000000000000ll);
    testIntHash<uint64_t>("uint64_t", uint64_t.minValue, uint64_t.maxValue, 300000000000000ll);

    testFloatHash<float>("float", -1e30f, 1e30f, 1e24f);
    testFloatHash<double>("double", -1e30f, 1e30f, 1e24f);

    test(MyHashable().hash() == 4, "custom hash");

    Optional<MyHashable> o = MyHashable();

    test(o.hash() == 4, "optional hash 1");
    o = none;
    test(o.hash() != 4, "optional hash 2");

    test(makeTuple(0, 0.0f, MyHashable()).hash() == hashMany(0, 0.0f, MyHashable()), "tuple hash");

    return 0;
}
