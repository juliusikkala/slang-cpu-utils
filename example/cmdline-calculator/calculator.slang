import platform;
import panic;
import drop;
import memory;
import hash;
import array;
import sort;
import list;
import string;

export __extern_cpp int main()
{
    List<int> array;
    defer drop(array);

    for(int i = 9; i >= 0; --i)
        array.push(i);

    U8String msg = U8String("HELLO WORLD");
    printf("%s\n", msg.cStr);

    radixSort(array);

    for(int i = 0; i < array.getSize(); ++i)
        printf("[%d]: %d\n", i, array[i]);

    return 0;
}
