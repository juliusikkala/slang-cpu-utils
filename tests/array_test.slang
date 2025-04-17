import array;
import list;
import drop;
import test;

void f<T: IBigArray<int>>(T arr)
{
    test(arr[arr.getSize()-1] == 15, "4");
}

void g<T: IRWBigArray<int>>(inout T arr)
{
    arr[0] = 16;
}

export __extern_cpp int main(int argc, Ptr<NativeString> argv)
{
    // The Big thing about IBigArray is that it can index over 2^31-1.
    List<uint8_t> l;
    l.resize(2147483700, 0);
    l[0] = 100;
    l[2147483699] = 200;

    test(l.getSize() == 2147483700, "0");

    test(l[0] == 100, "1");
    for(size_t i = 1; i < l.getSize()-1; ++i)
        test(l[i] == 0, "2");
    test(l[2147483699] == 200, "3");

    // IArray should also be usable as IBigArray
    int arr[4];
    arr[3] = 15;
    int4 vec;
    vec.w = 15;
    f(arr);
    f(vec);

    g(arr);
    test(arr[0] == 16, "5");
    g(vec);
    test(vec[0] == 16, "6");

    return 0;
}
