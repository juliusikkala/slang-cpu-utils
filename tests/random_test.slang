import test;
import list;
import random;

export __extern_cpp int main(int argc, Ptr<NativeString> argv)
{
    // The Big thing about IBigArray is that it can index over 2^31-1.
    List<int> l;
    defer l.drop();
    int sum = 0;
    for(int i = 0; i < 1000; ++i)
    {
        sum += i;
        l.push(i);
    }

    uint seed = 0;
    shuffle(seed, l);

    int checksum = 0;
    int in_order = 0;
    for(int i = 0; i < 1000; ++i)
    {
        checksum += l[i];
        if(l[i] == i)
            in_order++;
    }

    test(in_order < 10, "shuffle order");
    test(checksum == sum, "shuffle contents");

    return 0;
}
