import platform;

// sizeof() in Slang gives the size of a struct without trailing padding, but
// we need to include the padding for memory allocations.
[ForceInline]
public size_t strideof<T>() { return __naturalStrideOf<T>(); }

[ForceInline]
public size_t alignof<T>() { return __alignOf<T>(); }

[ForceInline]
public Ptr<void> takeFunctionPointer<T>(T fn)
{
    __intrinsic_asm "(void*)($0)";
}

public Ptr<void> clearBytes(Ptr<void> dest, uint8_t value, size_t n)
{
    __intrinsic_asm "memset($0, int($1), $2)";
}

public Ptr<void> copyBytes(Ptr<void> dest, Ptr<void> src, size_t n)
{
    __intrinsic_asm "memcpy($0, $1, $2)";
}

public void zeroInitialize<T>(inout T value)
{
    clearBytes(Ptr<void>(&value), 0, strideof<T>());
}

public interface IAllocator
{
    [mutating]
    Ptr<void> allocate(size_t bytes, size_t alignment);

    [mutating]
    void deallocate(Ptr<void> data);

    [mutating]
    Ptr<void> reallocate(
        Ptr<void> prevPtr,
        size_t prevBytes,
        size_t bytes,
        size_t alignment
    );
}

// You can use this to implement "reallocate" for an allocator that can't do
// anything special there.
public Ptr<void> fallbackRellocate(
    IAllocator alloc, 
    Ptr<void> prevPtr,
    size_t prevBytes,
    size_t bytes,
    size_t alignment
){
    let newPtr = alloc.allocate(bytes, alignment);
    copyBytes(newPtr, prevPtr, min(bytes, prevBytes));
    alloc.deallocate(prevPtr);
    return newPtr;
}

Ptr<void> systemRealloc(
    Ptr<void> prevPtr,
    size_t bytes,
    size_t alignment
){
    __intrinsic_asm R"(
#if SLANG_WINDOWS_FAMILY
    _aligned_realloc($0, $1, $2)
#else
    realloc($0, $1)
#endif
    )";
}

public struct SystemAllocator: IAllocator
{
    [mutating]
    public Ptr<void> allocate(size_t bytes, size_t alignment)
    {
        // posix_memalign fails if alignment is less than sizeof(void*).
        __intrinsic_asm "Slang::alignedAllocate($1, $2 < sizeof(void*) ? sizeof(void*) : $2)";
    }

    [mutating]
    public void deallocate(Ptr<void> data)
    {
        __intrinsic_asm "Slang::alignedDeallocate($1)";
    }

    [mutating]
    public Ptr<void> reallocate(
        Ptr<void> prevPtr,
        size_t prevBytes,
        size_t bytes,
        size_t alignment
    ){
        Ptr<void> newPtr = systemRealloc(prevPtr, bytes, alignment);
        if ((uintptr_t(newPtr) % alignment) != 0)
        {
            let prevPtr = newPtr;
            newPtr = allocate(bytes, alignment);
            copyBytes(newPtr, prevPtr, min(prevBytes, bytes));
            deallocate(prevPtr);
        }
        return newPtr;
    }
}

public static SystemAllocator defaultAllocator = SystemAllocator();

public Ptr<T> allocate<T, A:IAllocator>(size_t count, inout A alloc)
{
    Ptr<void> addr = alloc.allocate(strideof<T>() * count, alignof<T>());
    return reinterpret<Ptr<T>>(addr);
}

public Ptr<T> allocate<T>(size_t count = 1)
{
    return allocate<T>(count, defaultAllocator);
}

public Ptr<T> reallocate<T, A:IAllocator>(Ptr<T> oldPtr, size_t oldCount, size_t newCount, inout A alloc)
{
    return reinterpret<Ptr<T>>(alloc.reallocate(reinterpret<Ptr<void>>(oldPtr), strideof<T>() * oldCount, strideof<T>() * newCount, alignof<T>()));
}

public Ptr<T> reallocate<T>(Ptr<T> oldPtr, size_t oldCount, size_t newCount)
{
    return reallocate<T>(oldPtr, oldCount, newCount, defaultAllocator);
}

public void deallocate<T, A:IAllocator>(Ptr<T> oldPtr, inout A alloc)
{
    alloc.deallocate(reinterpret<Ptr<void>>(oldPtr));
}

public void deallocate<T>(Ptr<T> oldPtr)
{
    deallocate<T>(oldPtr, defaultAllocator);
}
