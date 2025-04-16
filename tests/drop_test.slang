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
        drop(dc);
        test(dc.count == 1, "1");
        defer drop(dc);

        Undroppable ud = Undroppable();
        test(ud.count == 0, "2");
        drop(ud);
        test(ud.count == 0, "3");
    }
    test(dc.count == 2, "4");

    return 0;
}
