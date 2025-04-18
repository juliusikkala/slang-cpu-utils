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

public extension<T : IHashable> Optional<T>: IHashable
{
    public uint64_t hash()
    { 
        if (let val = this)
            return val.hash();
        // "Chosen by a fair dice roll"
        return 0x898B5D104B0BA055;
    }
}

// Also handles vector types, as those are IArray.
public extension<U : IHashable, T : IArray<U>> T: IHashable
{
    public uint64_t hash()
    {
        uint64_t h = 0;
        for (int i = 0; i < this.getCount(); ++i)
            h = hashCombine(h, this[i].hash());
        return h;
    }
}

public uint64_t fnv1a(Ptr<uint8_t> bytes, size_t count)
{
    uint64_t h = 0xcbf29ce484222325;
    for (size_t i = 0; i < count; ++i)
    {
        h = h ^ bytes[i];
        h = h * 0x100000001b3;
    }
    return h;
}
