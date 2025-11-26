import span;
import array;
import test;

using scul;

export __extern_cpp int main(int argc, Ptr<NativeString> argv)
{
    int data[6] = {0,0,0,1,2,3};

    Span<int> span1;
    span1.data = reinterpret<Ptr<int>>(&data);
    span1.count = 3;

    Span<int> span2;
    span2.data = reinterpret<Ptr<int>>(&data)+3;
    span2.count = 3;

    copy(span2, span1);

    test(data[0] == 1, "1");
    test(data[1] == 2, "2");
    test(data[2] == 3, "3");

    return 0;
}
