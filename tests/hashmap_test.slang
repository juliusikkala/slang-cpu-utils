import test;
import drop;
import hash;
import hashmap;
import equal;
import list;
import sort;

using scul;

static int drops = 0;

public struct DropCounter: IDroppable, IEqual
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
    var hm = HashMap<uint, DropCounter>();

    var workList = List<uint>();

    int count = 65547;
    uint seed = 0;
    for (int i = 0; i < count; ++i)
    {
        uint value = lcg(seed);
        test(hm.add(value, DropCounter(value)), "add 1");
        workList.push(value);
    }

    seed = 0;
    for (int i = 0; i < count; ++i)
    {
        uint value = lcg(seed);
        test(!hm.add(value, DropCounter(value)), "add 2");
    }

    test(drops == count, "add 2 drops");

    test(hm.getSize() == count, "getSize 1");

    // Check that get() & __subscript() read work correctly
    seed = 0;
    for (int i = 0; i < count*2; ++i)
    {
        uint value = lcg(seed);
        let t = hm.get(value);
        test(t.hasValue == hm[value].hasValue, "__subscript 1");
        if (t.hasValue)
            test(t.value == hm[value].value, "__subscript 2");

        if (i < count)
        {
            test(t.hasValue, "get 1");
            test(t.value.val == value, "get 2");
        }
        else
        {
            test(!t.hasValue, "get 3");
        }
    }

    // Values should be in the same order as they were added, when no removals
    // have occurred.
    for (int i = 0; i < count; ++i)
    {
        test(hm.getValueByIndex(i).val == workList[i], "getValueByIndex");
    }

    for (int i = 0; i < count; ++i)
    {
        test(hm.contains(workList[i]), "contains 1 (%d)", i);
    }

    drops = 0;
    for (int i = 0; i < count/2; ++i)
    {
        Optional<size_t> r = hm.remove(workList[i]);
        test(r.hasValue, "remove 1 %d", i);
        test(!hm.contains(workList[i]), "contains 2 (%d)", i);
    }

    for (int i = 0; i < count/2; ++i)
    {
        Optional<size_t> r = hm.remove(workList[i]);
        test(!r.hasValue, "remove 2 %d", i);
    }

    test(drops == count/2, "remove drops");
    test(hm.getSize() == count-count/2, "getSize 2");

    hm.clear();
    test(drops == count, "clear");
    test(hm.getSize() == 0, "getSize 3");

    hm.drop();

    drops = 0;
    seed = 0;
    for (int i = 0; i < count; ++i)
    {
        uint value = lcg(seed);
        hm[value] = DropCounter(value);
    }

    test(hm.getSize() == count, "__subscript 2");

    seed = 0;
    for (int i = 0; i < count; ++i)
    {
        uint value = lcg(seed);
        hm[value] = none;
    }

    test(drops == count, "__subscript 3");
    test(hm.getSize() == 0, "__subscript 4");

    hm.drop();

    // Stress test: random adds and removes
    int roundCount = 1<<22;
    uint checksum = 0;
    uint expectedDrops = 0;
    drops = 0;

    // Initialize by filling hashmap
    for(int i = 0; i < 1<<17; ++i)
    {
        uint value = lcg(seed)&0xFFFF;
        if(hm.add(value, DropCounter(value)))
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
            if(hm.add(value, DropCounter(value)))
                checksum += value;
            else expectedDrops++;
        }
        else if((r1&2) == 2)
        { // Remove random entry that may or may not exist
            if(hm.remove(value).hasValue)
            {
                checksum -= value;
                expectedDrops++;
            }
        }
        else if((r1&2) == 3)
        { // Remove a known existing entry
            let key = hm.getKeyByIndex(r2%hm.getSize());
            test(hm.remove(key).hasValue, "remove stress");
            checksum -= key;
            expectedDrops++;
        }
    }

    for(int i = 0; i < hm.getSize(); ++i)
        checksum -= hm.getValueByIndex(i).val;

    test(checksum == 0, "stress test checksum");
    test(expectedDrops == drops, "stress test drops");

    drops = 0;
    expectedDrops = int(hm.getSize());
    hm.drop();
    test(hm.getSize() == 0, "drop size");
    test(drops == expectedDrops, "drop drops");
    return 0;
}
