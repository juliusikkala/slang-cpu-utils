import platform;
import panic;
import drop;
import memory;
import hash;
import array;
import sort;
import list;
import string;
import io;

export __extern_cpp int main(int argc, Ptr<NativeString> argv)
{
    List<int> array;
    defer drop(array);

    for(int i = 9; i >= 0; --i)
        array.push(i);

    int offset = 0;
    printf("%ld\n", parseInt("66", offset).value);
    printf("> ");

    Optional<U8String> line = readLine();
    defer drop(line);

    if (let str = line)
        printf("%s", str.cStr);
    else
        printf("(closed)\n");

    radixSort(array);

    U8String src = readTextFile("calculator.slang");
    defer drop(src);

    printf("%s\n", src.cStr);

    for(int i = 0; i < array.getSize(); ++i)
        printf("[%d]: %d\n", i, array[i]);

    return 0;
}
