import sort;
import drop;
import list;
import test;

static uint seed = 0;
uint pcg()
{
    seed = seed * 747796405u + 2891336453u;
    seed = ((seed >> ((seed >> 28) + 4)) ^ seed) * 277803737u;
    seed ^= seed >> 22;
    return seed;
}

// Generate random lists
void generateRandomInts(inout List<int> l)
{
    for (size_t i = 0; i < l.size; ++i)
        l[i] = int(pcg());
}

// Generate random lists
void generateRandomFloats(inout List<float> l, float bottom, float top)
{
    for (size_t i = 0; i < l.size; ++i)
        l[i] = float(pcg()) * 2.3283064365386963e-10f * (top-bottom) + bottom;
}

bool isInOrder<T: IComparable>(List<T> l)
{
    for (size_t i = 1; i < l.size; ++i)
    {
        if (l[i].lessThan(l[i-1]))
        {
            printf("Ordering failure at %d -> %d\n", i-1, i);
            return false;
        }
    }
    return true;
}

void testIntList(size_t len)
{
    List<int> l;
    l.resize(len, 0);
    defer drop(l);

    generateRandomInts(l);
    sort(l);

    test(isInOrder(l), "sort() (size %lu, int) not in order\n", len);

    generateRandomInts(l);
    stableSort(l);

    test(isInOrder(l), "stableSort() (size %lu, int) not in order\n", len);

    generateRandomInts(l);
    radixSort(l);

    test(isInOrder(l), "radixSort() (size %lu, int) not in order\n", len);
}

void testFloatList(size_t len)
{
    List<float> l;
    l.resize(len, 0.0);
    defer drop(l);

    generateRandomFloats(l, -10.0f, 10.0f);

    sort(l);
    
    test(isInOrder(l), "sort() (size %lu, float) not in order\n", len);

    generateRandomFloats(l, -10.0f, 10.0f);
    stableSort(l);

    test(isInOrder(l), "stableSort() (size %lu, float) not in order\n", len);

    generateRandomFloats(l, -10.0f, 10.0f);
    radixSort(l);

    test(isInOrder(l), "radixSort() (size %lu, float) not in order\n", len);
}

export __extern_cpp int main(int argc, Ptr<NativeString> argv)
{
    testIntList(1);
    testIntList(50);
    testIntList(256);
    testIntList(2049);
    testIntList(65530);

    testFloatList(1);
    testFloatList(50);
    testFloatList(256);
    testFloatList(2049);
    testFloatList(65536);

    return 0;
}
