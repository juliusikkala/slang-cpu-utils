import memory;
import test;

struct MyStructure
{
    uint64_t n;
    uint8_t s;
};

public struct CustomAllocator: IAllocator
{
    Ptr<uint8_t> mem = nullptr;
    size_t size = 0;
    size_t top = 0;

    [mutating]
    public Ptr<void> allocate(size_t bytes, size_t alignment)
    {
        // Completely braindead alignment :D
        while (reinterpret<uintptr_t>(mem + intptr_t(top)) % alignment != 0)
            top++;

        if (top >= size)
            return nullptr;

        Ptr<void> retval = reinterpret<Ptr<void>>(mem + intptr_t(top));
        return retval;
    }

    [mutating]
    public void deallocate(Ptr<void> data)
    {
        // Sorry, we don't deallocate 'round these parts.
    }

    [mutating]
    public Ptr<void> reallocate(
        Ptr<void> prevPtr,
        size_t prevBytes,
        size_t bytes,
        size_t alignment
    ){
        return fallbackReallocate<CustomAllocator>(this, prevPtr, prevBytes, bytes, alignment);
    }
}

export __extern_cpp int main(int argc, Ptr<NativeString> argv)
{
    test(sizeof(MyStructure) == 9, "sizeof");
    test(strideof<MyStructure>() == 16, "strideof");
    test(alignof<MyStructure>() == 8, "alignof");

    int arr[10];
    for (size_t i = 0; i < 10; ++i)
        arr[i] = 5;
    zeroInitialize(arr);
    for (size_t i = 0; i < 10; ++i)
        test(arr[i] == 0, "zeroInitialize");

    Ptr<uint> data = allocate<uint>(1000);
    test(data != nullptr, "allocate");
    test(uintptr_t(data) % sizeof(uint) == 0, "allocate alignment");

    for (uint i = 0; i < 1000; ++i)
        data[i] = i;

    data = reallocate<uint>(data, 1000, 2000);
    test(data != nullptr, "reallocate");
    test(uintptr_t(data) % sizeof(uint) == 0, "reallocate alignment");

    for (uint i = 0; i < 1000; ++i)
        test(data[i] == i, "reallocate");

    copyBytes(Ptr<void>(data+1000), Ptr<void>(data), 1000 * sizeof(uint));

    for (uint i = 0; i < 1000; ++i)
        test(data[i+1000] == i, "copyBytes");

    clearBytes(Ptr<void>(data), 0, 2000 * sizeof(uint));
    for (uint i = 0; i < 2000; ++i)
        test(data[i] == 0, "clearBytes");

    deallocate<uint>(data);

    CustomAllocator ca;
    ca.mem = reinterpret<Ptr<uint8_t>>(&arr);
    ca.size = arr.getCount() * sizeof(arr[0]);
    ca.top = 0;

    data = allocate<uint>(4, ca);
    test(reinterpret<Ptr<void>>(data) == reinterpret<Ptr<void>>(ca.mem), "custom allocate");

    return 0;
}
