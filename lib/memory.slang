import crt;

// sizeof() in Slang gives the size of a struct without trailing padding, but
// we need to include the padding for memory allocations.
[ForceInline]
public size_t strideof<T>() { return __naturalStrideOf<T>(); }

[ForceInline]
public size_t alignof<T>() { return __alignOf<T>(); }

/*
[ForceInline]
public Ptr<void> takeFunctionPointer<T>(T fn)
{
    __intrinsic_asm "(void*)($0)";
}
*/

public Ptr<void> clearBytes(Ptr<void> dest, uint8_t value, size_t n)
{
    return C.memset(dest, value, n);
}

public Ptr<void> copyBytes(Ptr<void> dest, Ptr<void> src, size_t n)
{
    return C.memcpy(dest, src, n);
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
public Ptr<void> fallbackReallocate<T: IAllocator>(
    T alloc, 
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

public struct SystemAllocator: IAllocator
{
    [mutating]
    public Ptr<void> allocate(size_t bytes, size_t alignment)
    {
#ifdef SLANG_PLATFORM_WIN32
        return C._aligned_alloc(bytes, alignment);
#else
        if (alignment <= 16)
            return C.malloc(bytes);
        else
        {
            bytes = max(bytes, alignment);
            return C.aligned_alloc(bytes, alignment);
        }
#endif
    }

    [mutating]
    public void deallocate(Ptr<void> data)
    {
#ifdef SLANG_PLATFORM_WIN32
        C._aligned_free(data);
#else
        C.free(data);
#endif
    }

    [mutating]
    public Ptr<void> reallocate(
        Ptr<void> prevPtr,
        size_t prevBytes,
        size_t bytes,
        size_t alignment
    ){
        if (prevPtr == nullptr)
            return allocate(bytes, alignment);

    #ifdef SLANG_PLATFORM_WIN32
        return C._aligned_realloc(prevPtr, bytes, alignment);
    #else
        if (alignment <= 16)
            return C.realloc(prevPtr, bytes);
        else
        {
            Ptr<void> newPtr = C.realloc(prevPtr, bytes);
            if ((uintptr_t(newPtr) % alignment) != 0)
            {
                let prevPtr = newPtr;
                newPtr = C.aligned_alloc(bytes, alignment);
                copyBytes(newPtr, prevPtr, min(prevBytes, bytes));
                C.free(prevPtr);
            }
            return newPtr;
        }
#endif
    }
}

public static IAllocator defaultAllocator = SystemAllocator();

public Ptr<T> allocate<T, A: IAllocator>(size_t count, inout A alloc)
{
    Ptr<void> addr = alloc.allocate(strideof<T>() * count, alignof<T>());
    return reinterpret<Ptr<T>>(addr);
}

public Ptr<T> allocate<T>(size_t count = 1)
{
    Ptr<void> addr = defaultAllocator.allocate(strideof<T>() * count, alignof<T>());
    return reinterpret<Ptr<T>>(addr);
}

public Ptr<T> reallocate<T, A:IAllocator>(Ptr<T> oldPtr, size_t oldCount, size_t newCount, inout A alloc)
{
    return reinterpret<Ptr<T>>(alloc.reallocate(reinterpret<Ptr<void>>(oldPtr), strideof<T>() * oldCount, strideof<T>() * newCount, alignof<T>()));
}

public Ptr<T> reallocate<T>(Ptr<T> oldPtr, size_t oldCount, size_t newCount)
{
    return reinterpret<Ptr<T>>(defaultAllocator.reallocate(reinterpret<Ptr<void>>(oldPtr), strideof<T>() * oldCount, strideof<T>() * newCount, alignof<T>()));
}

public void deallocate<T, A:IAllocator>(Ptr<T> oldPtr, inout A alloc)
{
    alloc.deallocate(reinterpret<Ptr<void>>(oldPtr));
}

public void deallocate<T>(Ptr<T> oldPtr)
{
    defaultAllocator.deallocate(reinterpret<Ptr<void>>(oldPtr));
}
