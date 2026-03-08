import crt;

namespace scul
{

// sizeof() in Slang gives the size of a struct without trailing padding, but
// we need to include the padding for memory allocations.
[ForceInline]
public size_t strideof<T>() { return __naturalStrideOf<T>(); }

[ForceInline]
public uint alignof<T>() { return __alignOf<T>(); }

[ForceInline]
public void clearBytes(Ptr<void> dest, uint8_t value, size_t n)
{
    __intrinsic_asm "call void @llvm.memset($0, $1, $2, i1 0)";
}

[ForceInline]
public void copyBytes<T, AddressSpace addrSpace, L:IBufferDataLayout>(
    Ptr<T, Access::ReadWrite, addrSpace, L> dest,
    Ptr<T, Access::ReadWrite, addrSpace, L> src,
    size_t n)
{
    __intrinsic_asm "call void @llvm.memcpy($0, $1, $2, i1 0)";
}

public void zeroInitialize<T>(inout T value)
{
    clearBytes(Ptr<void>(&value), 0, strideof<T>());
}

/// Allocators can be used to allocate, deallocate and reallocate memory.
public interface IAllocator<AddressSpace addrSpace = AddressSpace.Device>
{
    /// Returns a pointer to a contiguous segment of memory that is at least
    /// the specified number of `bytes` long. The pointer must have at least
    /// the given `alignment`. `alignment` must be a power of two.
    [mutating]
    Ptr<void, Access.ReadWrite, addrSpace> allocate(size_t bytes, uint alignment);

    /// Deallocates the given memory, if possible. Not all allocators are
    /// necessarily able to actually deallocate memory like this, so this
    /// function may be a no-op on such allocators.
    [mutating]
    void deallocate<T>(Ptr<T, Access.ReadWrite, addrSpace> data) { }

    /// Reallocates a memory segment into a differently sized one.
    [mutating]
    Ptr<void, Access.ReadWrite, addrSpace> reallocate(
        Ptr<void, Access.ReadWrite, addrSpace> prevPtr,
        size_t prevBytes,
        size_t bytes,
        uint alignment
    ){
        let newPtr = allocate(bytes, alignment);
        copyBytes(newPtr, prevPtr, min(bytes, prevBytes));
        deallocate(prevPtr);
        return newPtr;
    }

    /// Allocates a contiguous block of memory large enough to store `count`
    /// instances of `T` .
    [mutating]
    Ptr<T, Access.ReadWrite, addrSpace> allocate<T>(int count = 1)
    {
        let addr = allocate(__naturalStrideOf<T>() * count, __alignOf<T>());
        return reinterpret<Ptr<T, Access.ReadWrite, addrSpace>>(addr);
    }

    /// Reallocates a contiguous block of memory containing instances of `T` to
    /// contain at least `newCount` instances. `oldPtr` must point to an array
    /// of at least `oldCount` instances. The first `min(oldCount, newCount)`
    /// instances are guaranteed to be preserved.
    [mutating]
    Ptr<T, Access.ReadWrite, addrSpace> reallocate<T>(Ptr<T, Access.ReadWrite, addrSpace> oldPtr, size_t oldCount, size_t newCount)
    {
        return reinterpret<Ptr<T, Access.ReadWrite, addrSpace>>(
            reallocate(reinterpret<Ptr<void, Access.ReadWrite, addrSpace>>(oldPtr),
            __naturalStrideOf<T>() * oldCount,
            __naturalStrideOf<T>() * newCount,
            __alignOf<T>()));
    }
}

public typealias IDeviceAllocator = IAllocator<AddressSpace.Device>;

/// This allocator allocates memory on the calling function's stack frame. This
/// memory cannot be deallocated manually, but is deallocated automatically when
/// the function returns.
//[require(llvm)]
public struct StackFrameAllocatorType: IDeviceAllocator
{
    [ForceInline]
    //__intrinsic_op($(kIROp_StackAlloca))
    public Ptr<void> allocate(size_t bytes, uint alignment);
}

public property StackFrameAllocatorType StackFrameAllocator
{
    //[require(llvm)]
    get
    {
        __target_switch
        {
        case llvm:
            return StackFrameAllocatorType();
        }
    }
}

//[require(llvm)]
public struct HeapAllocatorType: IDeviceAllocator
{
    public Ptr<void> allocate(size_t bytes, uint alignment)
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

    override public void deallocate<T>(Ptr<T> data)
    {
#ifdef SLANG_PLATFORM_WIN32
        C._aligned_free(reinterpret<Ptr<void>(data));
#else
        C.free(reinterpret<Ptr<void>>(data));
#endif
    }

    override public Ptr<void> reallocate(
        Ptr<void> prevPtr,
        size_t prevBytes,
        size_t bytes,
        uint alignment
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

public property HeapAllocatorType HeapAllocator
{
    //[require(llvm)]
    get
    {
        __target_switch
        {
        case llvm:
            return HeapAllocatorType();
        }
    }
}

public Ptr<T> allocate<T, A: IDeviceAllocator>(size_t count, inout A alloc)
{
    Ptr<void> addr = alloc.allocate(strideof<T>() * count, alignof<T>());
    return reinterpret<Ptr<T>>(addr);
}

public Ptr<T> allocate<T>(size_t count = 1)
{
    Ptr<void> addr = HeapAllocator.allocate(strideof<T>() * count, alignof<T>());
    return reinterpret<Ptr<T>>(addr);
}

public Ptr<T> reallocate<T, A:IDeviceAllocator>(Ptr<T> oldPtr, size_t oldCount, size_t newCount, inout A alloc)
{
    return reinterpret<Ptr<T>>(alloc.reallocate(reinterpret<Ptr<void>>(oldPtr), strideof<T>() * oldCount, strideof<T>() * newCount, alignof<T>()));
}

public Ptr<T> reallocate<T>(Ptr<T> oldPtr, size_t oldCount, size_t newCount)
{
    return reinterpret<Ptr<T>>(HeapAllocator.reallocate(reinterpret<Ptr<void>>(oldPtr), strideof<T>() * oldCount, strideof<T>() * newCount, alignof<T>()));
}

public void deallocate<T, A:IDeviceAllocator>(Ptr<T> oldPtr, inout A alloc)
{
    alloc.deallocate(reinterpret<Ptr<void>>(oldPtr));
}

public void deallocate<T>(Ptr<T> oldPtr)
{
    HeapAllocator.deallocate(reinterpret<Ptr<void>>(oldPtr));
}

}
