import test;
import drop;
import string;

using scul;

void testParseInt(NativeString str, bool expectSuccess, int base, bool allowNegative, int64_t expectedValue=0, int expectedWidth=0)
{
    int offset = 0;
    let parsedNum = parseInt(str, offset, base, allowNegative);
    test(parsedNum.hasValue == expectSuccess, "parseInt(%s) hasValue", str);
    if (expectSuccess)
    {
        test(offset == expectedWidth, "parseInt(%s) offset", str);
        test(parsedNum.value == expectedValue, "parseInt(%s) value", str);
    }
}

void testParseFloat(NativeString str, bool expectSuccess, bool allowNegative, double expectedValue=0, int expectedWidth=0)
{
    int offset = 0;
    let parsedNum = parseFloat(str, offset, allowNegative);
    test(parsedNum.hasValue == expectSuccess, "parseFloat(%s) hasValue", str);
    if (expectSuccess)
    {
        test(offset == expectedWidth, "parseFloat(%s) offset", str);
        test(parsedNum.value == expectedValue, "parseFloat(%s) value (%.32e vs %.32e)", str, parsedNum.value, expectedValue);
    }
}

export __extern_cpp int main(int argc, Ptr<NativeString> argv)
{
    let ptrRound = ptrToString(stringToPtr<uint8_t>("works"));
    test(ptrRound == "works", "ptrToString & stringToPtr");

    testParseInt("0", true, 10, true, 0, 1);
    testParseInt("42", true, 10, true, 42, 2);
    testParseInt("030", true, 10, true, 30, 3);
    testParseInt("-10", true, 10, true, -10, 3);
    testParseInt("-10", false, 10, false);
    testParseInt("1aBC", true, 16, false, 0x1abc, 4);
    testParseInt("1aBC", true, 10, false, 1, 1);
    testParseInt("???", false, 10, false);
    testParseInt("34359738368", true, 10, false, int64_t(34359738368llu), 11);
    

    testParseFloat("-10", true, true, -10, 3);
    testParseFloat("-10", false, false);
    testParseFloat("-10.12", true, true, -10.12l, 6);
    testParseFloat("10.12", true, true, 10.12l, 5);
    testParseFloat("123456.789", true, true, 123456.789l, 10);

    test(isWhitespace(' '), "isWhitespace(' ')");
    test(isWhitespace('\t'), "isWhitespace('\t')");
    test(!isWhitespace('\n'), "isWhitespace('\n')");
    test(!isWhitespace('\r'), "isWhitespace('\r')");
    test(isWhitespace('\n', true), "isWhitespace('\n', true)");
    test(isWhitespace('\r', true), "isWhitespace('\r', true)");

    {
        let testString = "  \t   ä\n";
        int offset = 0;
        skipWhitespace(testString, offset);
        test(offset == 6, "skipWhitespace");

        test(codePointLength(testString, offset) == 2, "codePointLength 1");
        test(utf8ToUtf32(testString, offset) == 'ä', "utf8ToUtf32 1");
    }
    test(codePointLength("笑") == 3, "codePointLength 2");
    test(utf8ToUtf32("笑asdf") == '笑', "utf8ToUtf32 2");

    uint8_t chars[4];
    test(utf32ToUtf8('笑', chars) == 3, "utf32ToUtf8 1");
    test(chars[0] == 0xE7, "utf32ToUtf8 2");
    test(chars[1] == 0xAC, "utf32ToUtf8 3");
    test(chars[2] == 0x91, "utf32ToUtf8 4");

    test(codePointStringLength("hyvää päivää 𱁬") == 14, "codePointStringLength");

    {
        var testString = U8String(
            "\n"
            "Itse tieän rauan synnyn,\n"
            "arvoan alun teräksen:\n"
            "ilma on emoja ensin,\n"
            "vesi vanhin veljeksiä,\n"
            "rauta nuorin veljeksiä,\n"
            "tuli kerran keskimäinen."
        );
        test(testString.len == 145, "U8String.length %lu", testString.len);
        test(testString.getSize() == 145, "U8String.getSize");
        test(testString.getCodePointCount() == 140, "U8String.getCodePointCount");
        test(testString.asList().size == 145, "U8String.asList() 1");
        test(testString.asList()[11] == 'n', "U8String.asList() 2");
        test(testString[11] == 'n', "U8String.__subscript() 1");
        testString[11] = 't';
        test(testString[11] == 't', "U8String.__subscript() 2");
        testString[11] = 'n';

        test(testString.readCodePoint(9) == 'ä', "U8String.readCodePoint");

        var listString = testString.clone().asList();
        defer listString.drop();

        test(listString[0] == '\n', "asList 1");
        test(listString[1] == 'I', "asList 2");
        test(listString[listString.size-1] == '.', "asList 3");

        var newString = U8String.fromList(listString);
        defer newString.drop();

        test(newString.hash() == testString.hash(), "fromList & hash");

        newString.drop();
        test(newString.len == 0, "U8String.clear 1");
        test(newString.asList().size == 0, "U8String.clear 2");

        uint32_t expected_chars[11] = {
            '\n', 'I', 't', 's', 'e', ' ', 't', 'i', 'e', 'ä', 'n'
        };
        uint32_t codepoint;
        size_t offset = 0;
        for(int i = 0; i < 11 && testString.stepCodePoint(offset, codepoint); ++i)
        {
            test(expected_chars[i] == codepoint, "stepCodePoint %d", i);
        }
        test(offset == 12, "stepCodePoint offset");

        testString.drop();
        test(testString.len == 0, "U8String.drop");
    }

    {
        var constructedString = U8String();
        defer constructedString.drop();

        constructedString.append(1234);
        constructedString.append(" = ");
        constructedString.appendChar('ሴ');

        test(constructedString == "1234 = ሴ", "append");
        test(constructedString.cStr == "1234 = ሴ", "cStr");

        constructedString.erase(2, 2);
        test(constructedString == "12 = ሴ", "erase");
    }
    return 0;
}
