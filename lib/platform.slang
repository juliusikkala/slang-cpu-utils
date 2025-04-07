#ifdef SLANG_PLATFORM_WIN32
// Windows
public typealias long = int32_t;
public typealias ulong = uint32_t;
public typealias wchar_t = int16_t;
public typealias _Bool = uint8_t;
#else
// Linux
public typealias long = int64_t;
public typealias ulong = uint64_t;
public typealias wchar_t = int32_t;
public typealias _Bool = uint8_t;
#endif

public struct FILE;
