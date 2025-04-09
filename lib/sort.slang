import memory;

static const size_t RADIX_PASS_BITS = 8;
static const size_t RADIX_PASS_MASK = (1<<RADIX_PASS_BITS)-1;

// Implemented as quicksort.
public void sort<T: IComparable>(in IArray<T> input, inout IRWArray<T> output)
{
}

// Implemented as merge sort.
public void stableSort<T: IComparable>(in IArray<T> input, inout IRWArray<T> output)
{
}

public void radixSort<T>(in IArray<T> input, inout IRWArray<T> output, IFunc<uint64_t, T> keyFunc, int sortBits)
{
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

public void radixSort<T: __BuiltinIntegerType>(in IArray<T> input, inout IRWArray<T> output)
{
    radixSort(input, output, IntegerKeyFunctor<T>(), sizeof(T) * 8);
}

public void radixSort<T: __BuiltinFloatingPointType>(in IArray<T> input, inout IRWArray<T> output)
{
    radixSort(input, output, FloatingPointKeyFunctor<T>(), sizeof(T) * 8);
}
