import drop;
import list;
import test;

static int drops = 0;

public struct DropCounter: IDroppable
{
    int val;

    [mutating]
    public void drop()
    {
        drops += val;
    }
};

export __extern_cpp int main(int argc, Ptr<NativeString> argv)
{
    List<DropCounter> l;
    test(l.size == 0, "size 0");

    for (int i = 0; i < 10; ++i)
    {
        DropCounter dc;
        dc.val = i+1;
        l.push(dc);
    }

    test(l.size == 10, "size 1");

    for (int i = 0; i < 10; ++i)
        test(l[i].val == i+1, "indexing");

    l.erase(2, 3); // Should remove 3,4,5.

    test(l.size == 7, "erase size");
    test(drops == 12, "erase drop");

    int j = 0;
    for (int i = 0; i < 10; ++i)
    {
        if (i >= 2 && i < 5)
            continue;

        test(l[j].val == i+1, "erase");
        j++;
    }

    l.clear();

    test(l.size == 0, "clear size");
    test(drops == 55, "clear drop");

    drops = 0;

    DropCounter placeholder;
    placeholder.val = 8;

    l.resize(16, placeholder);

    test(l.size == 16, "resize size 1");
    test(drops == 0, "resize drop 1");

    for (size_t i = 0; i < l.size; ++i)
    {
        test(l[i].val == 8, "resize contents");
    }

    l.resize(10);
    test(l.size == 10, "resize size 2");
    test(drops == 48, "resize drop 2");

    drops = 0;

    for (int i = 0; i < 10; ++i)
    {
        DropCounter dc;
        dc.val = i+1;
        l.insert(5, dc);
    }
    // 5x8 + 1 2 3 4 5 6 7 8 9 10 + 5x8

    test(drops == 0, "insert drop");

    for (int i = 0; i < 5; ++i)
    {
        test(l.pop().val == 8, "pop");
        // INTENTIONALLY FORGOTTEN DROPS
    }

    test(drops == 0, "pop drop");

    for (int i = 0; i < 5; ++i)
    {
        test(l.swapAndPop(i).val == 8, "swapAndPop %d", i);
        // INTENTIONALLY FORGOTTEN DROPS
    }

    test(drops == 0, "swapAndPop drop");
    test(l.size == 10, "swapAndPop size");

    l.erase(0, 10);

    test(l.size == 0, "erase 2 size");
    test(drops == 55, "erase 2 drop (%d)", drops);

    drops = 0;
    l.resize(7, placeholder);
    l.drop();
    test(drops == 56, "drop drops");
    test(l.size == 0, "drop clears");

    return 0;
}
