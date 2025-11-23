import crt;

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
#ifdef WIN32
    // TODO
#else
    C.timespec ts;
    ts.tv_sec = int64_t(seconds);
    ts.tv_nsec = int64_t(frac(seconds) * 1e9);
    C.thrd_sleep(&ts, nullptr);
#endif
}

public void sleep(TimeTicks ticks)
{
    sleep(ticks.seconds);
}

static bool startTimeInitialized = false;
static TimeTicks startTime;

// Ticks reported in nanoseconds
public TimeTicks getTicks()
{
    C.timespec ts;
    ts.tv_sec = 0;
    ts.tv_nsec = 0;
    C.timespec_get(&ts, C.TimeUTC);
    TimeTicks t;
    t.nanoseconds = ts.tv_nsec + ts.tv_sec * 1000000000llu;

    if (!startTimeInitialized)
    {
        startTimeInitialized = true;
        startTime = t;
    }
    return t-startTime;
}
