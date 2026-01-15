import csv;
import string;
import panic;
import test;

using scul;

export __extern_cpp int main(int argc, Ptr<NativeString> argv)
{
    do
    {
        NativeString content = "a;1.0;2.0;3.0\nb;4.0;5.0;6.0\nc;7.0;8.0;9.0";
        CSV data = try CSV.parse(content, ';');

        test(data.rows == 3, "csv parse rows");
        test(data.cols == 4, "csv parse cols");
        test(data.text.slice(0, content.len) == content, "csv parse text");
        test(data[1, 1] == "4.0", "csv entry 1");
        test(data[2, 3] == "9.0", "csv entry 2");
        data.drop();
    }
    catch
    {
        panic("csv parse 1");
    }

    do
    {
        NativeString content = "a,b\nc\nd,e";
        CSV data = try CSV.parse(content);
        data.drop();
        panic("csv parse 2");
    }
    catch
    {
        // Should error!
    }

    CSV output = CSV(2, ':');

    output.push("1.0");
    output.push("2.0");
    output.push("3.0");
    output.push("4.0");

    test(output.text == "1.0:2.0\n3.0:4.0\n", "csv output");

    return 0;
}
