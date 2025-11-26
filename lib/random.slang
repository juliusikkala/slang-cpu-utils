import array;
import panic;

namespace scul
{

public uint pcg(inout uint seed)
{
    seed = seed * 747796405u + 2891336453u;
    seed = ((seed >> ((seed >> 28) + 4)) ^ seed) * 277803737u;
    seed ^= seed >> 22;
    return seed;
}

public uint lcg(inout uint seed)
{
    seed = seed * 1664525u + 1013904223u;
    return seed;
}

// Range: [min_value, max_value)
public float uniform_distribution(uint32_t seed, float min_value = 0.0f, float max_value = 1.0f)
{
    return min_value + float(seed) * (2.3283064365386963e-10f * (max_value-min_value));
}

// Range: [0, max_value)
public uint32_t integer_remap(uint32_t seed, uint32_t max_value)
{
    return uint32_t((uint64_t(seed) * uint64_t(max_value)) >> 32);
}

public void shuffle<T, A: IRWBigArray<T>>(inout uint seed, inout A arr)
{
    if(arr.getSize() > size_t(uint32_t.maxValue))
    {
        panic("array is too large for the current implementation of shuffle()");
    }

    // Fisher-yates
    for(size_t i = 0; i+1 < arr.getSize(); ++i)
    {
        size_t j = i + integer_remap(pcg(seed), uint32_t(arr.getSize()-i));
        T val = arr[i];
        arr[i] = arr[j];
        arr[j] = val;
    }
}

}
