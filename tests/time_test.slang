import time;
import test;

using scul;

export __extern_cpp int main(int argc, Ptr<NativeString> argv)
{
    let begin = getTicks();
    sleep(0.5); // Sleep for 0.5 seconds
    let end = getTicks();

    test(end != begin, "compare 1");
    test(!(end == begin), "compare 2");
    test(end > begin, "compare 3");
    test(begin < 0.1, "compare 4");
    test(end-begin > 0.4 && begin-end < 0.6, "sleep");
    test((end-begin).milliseconds > 400 && (begin-end).milliseconds < 600, "milliseconds");
    test((end-begin).microseconds > 400000 && (begin-end).microseconds < 600000, "microseconds");
    test((end-begin).nanoseconds > 400000000 && (begin-end).nanoseconds < 600000000, "nanoseconds");

    TimeTicks t;
    t.seconds = -1;
    test(t.seconds == 0.0, "set seconds 1");
    t.seconds = 1;
    test(t.seconds >= 0.9999 && t.seconds <= 1.0001, "set seconds 2");

    t.milliseconds = -1000;
    test(t.seconds == 0.0, "set milliseconds 1");
    t.milliseconds = 1000;
    test(t.seconds >= 0.9999 && t.seconds <= 1.0001, "set milliseconds 2");

    t.microseconds = -1000000;
    test(t.seconds == 0.0, "set microseconds 1");
    t.microseconds = 1000000;
    test(t.seconds >= 0.9999 && t.seconds <= 1.0001, "set microseconds 2");

    t.nanoseconds = 1000000000;
    test(t.seconds >= 0.9999 && t.seconds <= 1.0001, "set nanoseconds");
    return 0;
}
