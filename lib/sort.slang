import memory;
import array;
import span;

//==============================================================================
// VARIOUS SORTING PRIMITIVES
//==============================================================================

public void swap<T>(inout T a, inout T b)
{
    T tmp = b;
    b = a;
    a = tmp;
}

public size_t partition<T, A: IRWBigArray<T>, P: IFunc<bool,T>>(inout A arr, size_t lo, size_t hi, P predicate)
{
    size_t i = lo;

    for (size_t j = lo; j < hi; ++j)
    {
        if (predicate(arr[j]))
        {
            swap(arr[j], arr[i]);
            ++i;
        }
    }

    return i;
}

public size_t partition<T, A: IRWBigArray<T>, P: IFunc<bool,T>>(inout A arr, P predicate)
{
    return partition<T, A, P>(arr, 0, arr.getSize(), predicate);
}

public void heapify<T, A: IRWBigArray<T>, C: IFunc<bool, T, T>>(inout A arr, C compare, size_t i, size_t end)
{
    size_t top = i;
    for (;;)
    {
        size_t nextTop = top;
        size_t left = 2*top+1;
        size_t right = 2*top+2;

        if (left < end)
        { // No shortcircuit in Slang &&, so nest the 'if' instead.
            if (compare(arr[nextTop], arr[left]))
                nextTop = left;
        }

        if (right < end)
        {
            if (compare(arr[nextTop], arr[right]))
                nextTop = right;
        }

        if (nextTop == top)
            break;

        swap(arr[top], arr[nextTop]);
        top = nextTop;
    }
}

public void buildHeap<T, A: IRWBigArray<T>, C: IFunc<bool, T, T>>(inout A arr, C compare)
{
    if (arr.getSize() <= 1)
        return;

    size_t lastParent = arr.getSize()>>1;

    for (size_t i = 0; i < lastParent; ++i)
        heapify<T, A, C>(arr, compare, lastParent-1-i, arr.getSize());
}

public void merge<T, A: IBigArray<T>, B: IRWBigArray<T>, C: IFunc<bool, T, T>>(
    inout A from, inout B to, size_t begin, size_t split, size_t end, C compare
){
    size_t i = begin;
    size_t j = split;

    for (size_t k = begin; k < end; ++k)
    {
        if (i < split && (j >= end || !compare(from[j], from[i])))
        {
            to[k] = from[i];
            ++i;
        }
        else
        {
            to[k] = from[j];
            ++j;
        }
    }
}

public void copy<T, A: IBigArray<T>, B: IRWBigArray<T>>(inout A from, inout B to)
{
    size_t count = min(from.getSize(), to.getSize());
    for (size_t i = 0; i < count; ++i)
        to[i] = from[i];
}

//==============================================================================
// SORTING ALGORITHMS
//==============================================================================

// Because Slang doesn't like recursion, this is a recursion-free in-place
// heapsort instead of quicksort. It's the easier in-place algorithm to
// implement without a stack.
public void sort<T, A: IRWBigArray<T>, C: IFunc<bool, T, T>>(inout A arr, C compare)
{
    buildHeap<T, A, C>(arr, compare);

    for (size_t i = arr.getSize()-1; i > 0; --i)
    {
        swap(arr[i], arr[0]);
        heapify<T, A, C>(arr, compare, 0, i);
    }
}

// Recursion-free merge sort. Allocates scratch space for the merge operation.
public void stableSort<T, A: IRWBigArray<T>, C: IFunc<bool, T, T>>(inout A arr, C compare)
{
    size_t len = arr.getSize();
    Span<T> scratchSpan;
    scratchSpan.data = allocate<T>(arr.getSize());
    scratchSpan.count = arr.getSize();
    defer deallocate(scratchSpan.data);

    bool forward = true;
    for (size_t width = 1; width < len; width = width<<1)
    {
        if (forward)
        {
            for (size_t i = 0; i < len; i += width * 2)
                merge<T, A, Span<T>, C>(arr, scratchSpan, i, min(i+width, len), min(i+2*width, len), compare);
        }
        else
        {
            for (size_t i = 0; i < len; i += width * 2)
                merge<T, Span<T>, A, C>(scratchSpan, arr, i, min(i+width, len), min(i+2*width, len), compare);
        }

        forward = !forward;
    }

    if (!forward)
        copy<T, Span<T>, A>(scratchSpan, arr);
}

public struct LessThanCompare<T: IComparable>: IFunc<bool, T, T>
{
    public bool operator()(T a, T b)
    {
        return a < b;
    }
}

public void sort<T: IComparable, A: IRWBigArray<T>>(inout A arr)
{
    sort(arr, LessThanCompare<T>());
}

public void stableSort<T: IComparable, A: IRWBigArray<T>>(inout A arr)
{
    stableSort(arr, LessThanCompare<T>());
}

public void radixSort<T, A: IRWBigArray<T>, K: IFunc<uint64_t, T>>(inout A arr, K keyFunc, int sortBits)
{
    static const int RADIX_PASS_BITS = 8;
    static const uint64_t RADIX_PASS_MASK = (uint64_t(1)<<RADIX_PASS_BITS)-1;
    let passCount = (sortBits + RADIX_PASS_BITS - 1) / RADIX_PASS_BITS;
    size_t histogram[1<<RADIX_PASS_BITS];

    Span<T> scratchSpan;
    scratchSpan.data = allocate<T>(arr.getSize());
    scratchSpan.count = arr.getSize();
    defer deallocate(scratchSpan.data);

    bool forward = true;
    for(size_t passIndex = 0; passIndex < passCount; ++passIndex)
    {
        // Compute histogram
        zeroInitialize(histogram);
        for(size_t i = 0; i < arr.getSize(); ++i)
        {
            uint64_t k = keyFunc(forward ? arr[i] : scratchSpan[i]);
            uint64_t category = (k >> (passIndex * RADIX_PASS_BITS)) & RADIX_PASS_MASK;
            histogram[category]++;
        }

        // Exclusive scan over histogram
        for (int i = (1<<RADIX_PASS_BITS)-1; i > 0; --i)
            histogram[i] = histogram[i-1];
        histogram[0] = 0;
        for (int i = 1; i < (1<<RADIX_PASS_BITS); ++i)
            histogram[i] += histogram[i-1];

        for(size_t i = 0; i < arr.getSize(); ++i)
        {
            uint64_t k = keyFunc(forward ? arr[i] : scratchSpan[i]);
            uint64_t category = (k >> (passIndex * RADIX_PASS_BITS)) & RADIX_PASS_MASK;
            size_t index = histogram[category];
            histogram[category]++;

            if(forward)
                scratchSpan[index] = arr[i];
            else 
                arr[index] = scratchSpan[i];
        }
        forward = !forward;
    }

    if (!forward)
        copy<T, Span<T>, A>(scratchSpan, arr);
}

struct IntegerKeyFunctor<T: __BuiltinIntegerType> : IFunc<uint64_t, T>
{
    uint64_t operator()(T t)
    {
        var val = t;
        if (T(-1) < T(0)) // Is signed?
            val += T(1)<<(sizeof(T)*8-1);
        return reinterpret<uint64_t>(val);
    }
}

struct FloatingPointKeyFunctor<T: __BuiltinFloatingPointType> : IFunc<uint64_t, T>
{
    uint64_t operator()(T t)
    {
        let msb = uint64_t(1)<<(sizeof(T)*8-1);
        var bits = reinterpret<uint64_t>(t);
        if ((bits & msb) != 0)
            bits = ~bits;
        else bits ^= msb;
        return bits;
    }
}

public void radixSort<T: __BuiltinIntegerType, A: IRWBigArray<T>>(inout A arr)
{
    IntegerKeyFunctor<T> key;
    radixSort<T, A, IntegerKeyFunctor<T>>(arr, key, sizeof(T) * 8);
}

public void radixSort<T: __BuiltinFloatingPointType, A: IRWBigArray<T>>(inout A arr)
{
    FloatingPointKeyFunctor<T> key;
    radixSort<T, A, FloatingPointKeyFunctor<T>>(arr, key, sizeof(T) * 8);
}
