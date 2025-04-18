public struct TimeTicks
{
    private uint64_t nsSinceStart;

    public property double seconds
    {
        get {
            return double(nsSinceStart) * 1e-9;
        }
        set {
            // The upper limit is the biggest double that is below (2^64)-1.
            nsSinceStart = uint64_t(clamp(round(newValue * 1e9), 0.0, 18446744073709549568.0));
        }
    }

    public property double milliseconds
    {
        get {
            return double(nsSinceStart) * 1e-6;
        }
        set {
            nsSinceStart = uint64_t(clamp(round(newValue * 1e6), 0.0, 18446744073709549568.0));
        }
    }

    public property double microseconds
    {
        get {
            return double(nsSinceStart) * 1e-3;
        }
        set {
            nsSinceStart = uint64_t(clamp(round(newValue * 1e3), 0.0, 18446744073709549568.0));
        }
    }

    public property uint64_t nanoseconds
    {
        get {
            return nsSinceStart;
        }
        set {
            nsSinceStart = newValue;
        }
    }
}

public bool operator!=(TimeTicks a, TimeTicks b)
{
    return a.nanoseconds != b.nanoseconds;
}

public bool operator==(TimeTicks a, TimeTicks b)
{
    return a.nanoseconds == b.nanoseconds;
}

public bool operator<(TimeTicks a, TimeTicks b)
{
    return a.nanoseconds < b.nanoseconds;
}

public bool operator>(TimeTicks a, TimeTicks b)
{
    return a.nanoseconds > b.nanoseconds;
}

public bool operator<(TimeTicks a, double seconds)
{
    TimeTicks b;
    b.seconds = seconds;
    return a < b;
}

public bool operator>(TimeTicks a, double seconds)
{
    TimeTicks b;
    b.seconds = seconds;
    return a > b;
}

public TimeTicks operator-(TimeTicks a, TimeTicks b)
{
    TimeTicks res;
    if (a.nanoseconds < b.nanoseconds)
        res.nanoseconds = b.nanoseconds - a.nanoseconds;
    else
        res.nanoseconds = a.nanoseconds - b.nanoseconds;
    return res;
}

public void sleep(double seconds)
{
    __requirePrelude("#include <chrono>");
    __requirePrelude("#include <thread>");
    __intrinsic_asm "std::this_thread::sleep_for(std::chrono::duration<double>($0));";
}

public void sleep(TimeTicks ticks)
{
    sleep(ticks.seconds);
}

void timeHelper(inout uint64_t nanoseconds)
{
    __intrinsic_asm R"(
        static auto startTime = std::chrono::high_resolution_clock::now();
        *($0) = std::chrono::duration_cast<std::chrono::nanoseconds>(std::chrono::high_resolution_clock::now() - startTime).count();
    )";
}

// Ticks reported in nanoseconds
public TimeTicks getTicks()
{
    uint64_t ns = 0;
    timeHelper(ns);
    TimeTicks t;
    t.nanoseconds = ns;
    return t;
}
