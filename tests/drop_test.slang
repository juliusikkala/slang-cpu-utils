import drop;
import test;

public struct Undroppable
{
    public int count = 0;
}

public struct DropCounter: IDroppable
{
    public int count = 0;

    [mutating]
    public void drop()
    {
        count++;
    }
}

export __extern_cpp int main(int argc, Ptr<NativeString> argv)
{
    DropCounter dc = DropCounter();
    test(dc.count == 0, "0");
    {
        dc.drop();
        test(dc.count == 1, "1");
        defer dc.drop();

        /*
        Undroppable ud = Undroppable();
        test(ud.count == 0, "2");
        ud.drop();
        test(ud.count == 0, "3");
        */
    }
    test(dc.count == 2, "4");

    Optional<DropCounter> odc = DropCounter();
    test(odc.value.count == 0, "5");
    odc.drop();
    test(odc == none, "6");

    return 0;
}
