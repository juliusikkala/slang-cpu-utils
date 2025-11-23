public uint64_t hashMix(uint64_t seed)
{
    uint64_t h = seed;
    // https://mostlymangling.blogspot.com/2019/12/stronger-better-morer-moremur-better.html
	h ^= h >> 27;
	h *= 0x3C79AC492BA7B653;
	h ^= h >> 33;
	h *= 0x1C69B3F74AC4AE35;
	h ^= h >> 27;
    return h;
}

public uint64_t hashCombine(uint64_t seed, uint64_t next)
{
    return hashMix(seed + next + 0x9e3779b9);
}

public uint64_t hashMany<each T : IHashable>(expand each T parts)
{
    uint64_t h = 0;
    uint index = 0;
    expand (h = (index++) == 0 ? (each parts).hash() : hashCombine(h, (each parts).hash()));
    return h;
}

public interface IHashable
{
    uint64_t hash();
}

public extension<T:__BuiltinType> T : IHashable
{
    public uint64_t hash() { return hashMix(reinterpret<uint64_t>(this) + 0x9e3779b9); } 
}

public extension<T> Ptr<T>: IHashable
{
    public uint64_t hash() { return hashMix(reinterpret<uint64_t>(this) + 0x9e3779b9); }
}

public extension<each T: IHashable> Tuple<T>: IHashable
{
    public uint64_t hash()
    { 
        return hashMany(expand each this);
    }
}

public uint64_t arrayHash<T : IHashable, U: IArray<T>>(in U arr)
{
    uint64_t h = 0;
    for (int i = 0; i < arr.getCount(); ++i)
        h = hashCombine(h, arr[i].hash());
    return h;
}

public extension<T : IHashable, let N:int> vector<T, N> : IHashable
{
    public uint64_t hash() { return arrayHash(this); }
}

public extension<T : IHashable, let R : int, let C : int, let L : int> matrix<T, R, C, L> : IHashable
{
    public uint64_t hash() { return arrayHash(this); }
}

public extension<T : IHashable, let N:int> Array<T, N> : IHashable
{
    public uint64_t hash() { return arrayHash(this); }
}

public extension<T : IHashable> Optional<T>: IHashable
{
    public uint64_t hash()
    { 
        if (let val = this)
            return val.hash();
        // "Chosen by a fair dice roll"
        return 0x898B5D104B0BA055llu;
    }
}

public uint64_t fnv1a(Ptr<uint8_t> bytes, size_t count)
{
    uint64_t h = 0xcbf29ce484222325llu;
    for (size_t i = 0; i < count; ++i)
    {
        h = h ^ bytes[i];
        h = h * 0x100000001b3llu;
    }
    return h;
}
