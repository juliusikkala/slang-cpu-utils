import memory;
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
    size_t lastParent = (arr.getSize()>>1) - 1;

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


public void radixSort<T>(in IBigArray<T> input, inout IRWBigArray<T> output, IFunc<uint64_t, T> keyFunc, int sortBits)
{
    static const size_t RADIX_PASS_BITS = 8;
    static const size_t RADIX_PASS_MASK = (1<<RADIX_PASS_BITS)-1;
    let pass_count = (sortBits + RADIX_PASS_BITS - 1) / RADIX_PASS_BITS;
    uint32_t histogram[RADIX_PASS_BITS];
    uint32_t cumulative[RADIX_PASS_BITS];

/*
    auto local_key_scratch = stack_allocate<T>(!key_scratch ? count : 0);
    if(!key_scratch)
        key_scratch = local_key_scratch.data();
    auto local_value_scratch = stack_allocate<U>(use_value && !value_scratch ? count : 0);
    if(use_value && !value_scratch)
        value_scratch = local_value_scratch.get();

    placeholder_type<T>* in_key =
        reinterpret_cast<placeholder_type<T>*>(key_ptr);
    placeholder_type<T>* out_key =
        reinterpret_cast<placeholder_type<T>*>(key_scratch);

    U* in_value = value_ptr;
    U* out_value = value_scratch;

    std::memset(histogram, 0, sizeof(histogram));
    for(size_t i = 0; i < count; ++i)
    {
        placeholder_type<T> k;
        memcpy(&k, &key_ptr[i], sizeof(T));
        to_sortable<T>(k);
        in_key[i] = k;
        histogram[in_key[i] & RADIX_PASS_MASK]++;
    }

    std::exclusive_scan(std::begin(histogram), std::end(histogram), cumulative, 0);

    for(size_t pass = 1; pass < pass_count; ++pass)
    {
        std::memset(histogram, 0, sizeof(histogram));
        for(size_t i = 0; i < count; ++i)
        {
            placeholder_type<T> k = in_key[i];
            uint32_t category = (k >> ((pass-1)*RADIX_PASS_BITS)) & RADIX_PASS_MASK;
            uint32_t index = cumulative[category]++;
            out_key[index] = k;
            if constexpr(use_value)
                out_value[index] = std::move(in_value[i]);
            histogram[(k >> (pass*RADIX_PASS_BITS)) & RADIX_PASS_MASK]++;
        }
        std::swap(in_key, out_key);
        if constexpr(use_value)
            std::swap(in_value, out_value);

        std::exclusive_scan(std::begin(histogram), std::end(histogram), cumulative, 0);
    }

    if constexpr(pass_count & 1)
    { // Odd (out_key != key_ptr)
        for(size_t i = 0; i < count; ++i)
        {
            placeholder_type<T> k = in_key[i];
            uint32_t category = (in_key[i] >> ((pass_count-1)*RADIX_PASS_BITS)) & RADIX_PASS_MASK;
            uint32_t index = cumulative[category]++;
            out_key[index] = in_key[i];
            if constexpr(use_value)
                out_value[index] = std::move(in_value[i]);
        }

        for(size_t i = 0; i < count; ++i)
        {
            placeholder_type<T> t = out_key[i];
            from_sortable<T>(t);
            memcpy(&key_ptr[i], &t, sizeof(T));
        }
        if constexpr(use_value)
        {
            if(out_value != value_ptr)
                memcpy(value_ptr, out_value, count*sizeof(U));
        }
    }
    else
    { // Even (out_key == key_ptr)
        for(size_t i = 0; i < count; ++i)
        {
            placeholder_type<T> k = in_key[i];
            uint32_t category = (k >> ((pass_count-1)*RADIX_PASS_BITS)) & RADIX_PASS_MASK;
            uint32_t index = cumulative[category]++;
            from_sortable<T>(k);
            memcpy(&key_ptr[index], &k, sizeof(T));
            if constexpr(use_value)
                value_ptr[index] = std::move(in_value[i]);
        }
    }
*/
}

struct IntegerKeyFunctor<T: __BuiltinIntegerType> : IFunc<uint64_t, T>
{
    uint64_t operator()(T t) { return reinterpret<uint64_t>(t); }
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

public void radixSort<T: __BuiltinIntegerType>(in IBigArray<T> input, inout IRWBigArray<T> output)
{
    radixSort(input, output, IntegerKeyFunctor<T>(), sizeof(T) * 8);
}

public void radixSort<T: __BuiltinFloatingPointType>(in IBigArray<T> input, inout IRWBigArray<T> output)
{
    radixSort(input, output, FloatingPointKeyFunctor<T>(), sizeof(T) * 8);
}
