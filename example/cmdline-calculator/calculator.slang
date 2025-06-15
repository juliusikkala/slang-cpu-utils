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

Optional<double> parseFloatOrAns(List<double> ans, U8String str, inout int offset)
{
    if (str[offset] == '$')
    {
        ++offset;
        let index = parseInt(str.cStr, offset);
        if (!index.hasValue || index.value >= ans.size || index.value < 0)
            return none;
        return ans[uint(index.value)];
    }
    return parseFloat(str.cStr, offset, true);
}

export __extern_cpp int main(int argc, Ptr<NativeString> argv)
{
    List<double> ans;
    defer ans.drop();

    for(;;)
    {
        let maybeLine = readLine();
        if (!maybeLine.hasValue)
            break;
        U8String line = maybeLine.value;
        defer line.drop();

        int offset = 0;
        skipWhitespace(line.cStr, offset);
        let a = parseFloatOrAns(ans, line, offset);
        skipWhitespace(line.cStr, offset);
        let op = line[offset];
        if (line[offset] != 0) ++offset;
        skipWhitespace(line.cStr, offset);
        let b = parseFloatOrAns(ans, line, offset);
        skipWhitespace(line.cStr, offset, true);
        if (!a.hasValue)
        {
            printf("Failed to parse first number\n");
            continue;
        }
        if (!b.hasValue)
        {
            printf("Failed to parse second number\n");
            continue;
        }

        if (line[offset] != 0)
        {
            printf("Unexpected characters at end of line\n");
            continue;
        }

        double result;
        bool parsed = true;
        switch (op)
        {
        case '+':
            result = a.value + b.value;
            break;
        case '-':
            result = a.value - b.value;
            break;
        case '*':
            result = a.value * b.value;
            break;
        case '/':
            result = a.value / b.value;
            break;
        case '^':
            result = pow(a.value, b.value);
            break;
        default:
            parsed = false;
            break;
        }

        if (!parsed)
        {
            printf("Unknown operator %c\n", op);
            continue;
        }

        printf("$%lu = %f\n", ans.size, result);
        ans.push(result);
    }

    return 0;
}
