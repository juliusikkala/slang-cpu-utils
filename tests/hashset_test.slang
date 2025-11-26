import test;
import drop;
import hash;
import hashset;
import equal;
import list;
import sort;

using scul;

static int drops = 0;

public struct DropCounter: IDroppable, IHashable, IEqual
{
    uint val;

    __init(uint v)
    {
        val = v;
    }

    [mutating]
    public void drop()
    {
        drops++;
    }

    public uint64_t hash()
    {
        return val.hash();
    }

    public bool isEqual(DropCounter other)
    {
        return val == other.val;
    }
};

uint lcg(inout uint seed)
{
    seed = seed * 1664525u + 1013904223u;
    return seed;
}

export __extern_cpp int main(int argc, Ptr<NativeString> argv)
{
    var hs = HashSet<DropCounter>();

    var workList = List<uint>();

    int count = 65547;
    uint seed = 0;
    for (int i = 0; i < count; ++i)
    {
        uint value = lcg(seed);
        test(hs.add(DropCounter(value)), "add 1");
        workList.push(value);
    }

    seed = 0;
    for (int i = 0; i < count; ++i)
    {
        uint value = lcg(seed);
        test(!hs.add(DropCounter(value)), "add 2");
    }

    test(drops == count, "add 2 drops");

    test(hs.getSize() == count, "getSize 1");

    // Values should be in the same order as they were added, when no removals
    // have occurred.
    for (int i = 0; i < count; ++i)
    {
        test(hs[i].val == workList[i], "__subscript");
    }

    for (int i = 0; i < count; ++i)
    {
        test(hs.contains(DropCounter(workList[i])), "contains 1 (%d)", i);
    }

    drops = 0;
    for (int i = 0; i < count/2; ++i)
    {
        Optional<size_t> r = hs.remove(DropCounter(workList[i]));
        test(r.hasValue, "remove 1 %d", i);
        test(!hs.contains(DropCounter(workList[i])), "contains 2 (%d)", i);
    }

    for (int i = 0; i < count/2; ++i)
    {
        Optional<size_t> r = hs.remove(DropCounter(workList[i]));
        test(!r.hasValue, "remove 2 %d", i);
    }

    test(drops == count/2, "remove drops");
    test(hs.getSize() == count-count/2, "getSize 2");

    hs.clear();
    test(drops == count, "clear");
    test(hs.getSize() == 0, "getSize 3");

    hs.drop();

    // Stress test: random adds and removes
    int roundCount = 1<<22;
    uint checksum = 0;
    uint expectedDrops = 0;
    drops = 0;

    // Initialize by filling hashmap
    for(int i = 0; i < 1<<17; ++i)
    {
        uint value = lcg(seed)&0xFFFF;
        if(hs.add(DropCounter(value)))
            checksum += value;
        else expectedDrops++;
    }

    for(int i = 0; i < roundCount; ++i)
    {
        uint r1 = lcg(seed);
        uint r2 = lcg(seed);
        uint value = r2&0xFFFF;
        if((r1&2) <= 1)
        { // Add
            if(hs.add(DropCounter(value)))
                checksum += value;
            else expectedDrops++;
        }
        else if((r1&2) == 2)
        { // Remove random entry that may or may not exist
            if(hs.remove(DropCounter(value)).hasValue)
            {
                checksum -= value;
                expectedDrops++;
            }
        }
        else if((r1&2) == 3)
        { // Remove a known existing entry
            let value = hs[r2%hs.getSize()];
            test(hs.remove(value).hasValue, "remove stress");
            checksum -= value.val;
            expectedDrops++;
        }
    }

    for(int i = 0; i < hs.getSize(); ++i)
        checksum -= hs[i].val;

    test(checksum == 0, "stress test checksum");
    test(expectedDrops == drops, "stress test drops");

    drops = 0;
    expectedDrops = int(hs.getSize());
    hs.drop();
    test(hs.getSize() == 0, "drop size");
    test(drops == expectedDrops, "drop drops");
    return 0;
}
