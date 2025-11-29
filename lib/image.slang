import list;
import drop;
import panic;
import io;
import serialization;
import binarystream;

namespace scul
{

public interface IPixelFormat
{
    float4 toFloat();
    static This fromFloat(float4 value);
}

// TODO: These conversions are fairly untested.
float channelDataToFloat<T: __BuiltinArithmeticType>(T pixelData)
{
    if (T is half)
        return float((pixelData as half).value);
    else if (T is float)
        return (pixelData as float).value;
    else if (T is double)
        return float((pixelData as double).value);
    else if (T is int8_t)
        return clamp(float((pixelData as int8_t).value) / 127.0, -1.0, 1.0);
    else if (T is int16_t)
        return clamp(float((pixelData as int16_t).value) / 32727.0, -1.0, 1.0);
    else if (T is int32_t)
        return clamp(float((pixelData as int32_t).value) / 2147483647.0, -1.0, 1.0);
    else if (T is int64_t)
        return clamp(float((pixelData as int64_t).value) / 9223372036854775807.0, -1.0, 1.0);
    else if (T is uint8_t)
        return float((pixelData as uint8_t).value) / 255.0;
    else if (T is uint16_t)
        return float((pixelData as uint16_t).value) / 65535.0;
    else if (T is uint32_t)
        return float((pixelData as uint32_t).value) / 4294967295.0;
    else if (T is uint64_t)
        return float((pixelData as uint64_t).value) / 18446744073709551615.0;
    else return 0.0f;
}

T channelDataFromFloat<T: __BuiltinArithmeticType>(float pixelData)
{
    if (T is half)
        return (half(pixelData) as T).value;
    else if (T is float)
        return (pixelData as T).value;
    else if (T is double)
        return (double(pixelData) as T).value;
    else if (T is int8_t)
        return (int8_t(round(clamp(pixelData, -1.0, 1.0) * 127.0)) as T).value;
    else if (T is int16_t)
        return (int16_t(round(clamp(pixelData, -1.0, 1.0) * 32727.0)) as T).value;
    else if (T is int32_t)
        return (int32_t(round(clamp(pixelData, -1.0, 1.0) * 2147483647.0)) as T).value;
    else if (T is int64_t)
        return (int64_t(round(clamp(pixelData, -1.0, 1.0) * 9223372036854775807.0)) as T).value;
    else if (T is uint8_t)
        return (uint8_t(round(clamp(pixelData, 0.0, 1.0) * 255.0)) as T).value;
    else if (T is uint16_t)
        return (uint16_t(round(clamp(pixelData, 0.0, 1.0) * 65535.0)) as T).value;
    else if (T is uint32_t)
        return (uint32_t(round(clamp(pixelData, 0.0, 1.0) * 4294967295.0)) as T).value;
    else if (T is uint64_t)
        return (uint64_t(round(clamp(pixelData, 0.0, 1.0) * 18446744073709551615.0)) as T).value;
    else return T(0);
}

public struct SimplePixelFormat<T: __BuiltinArithmeticType, let N: int>: IPixelFormat
{
    public T data[N];

    public __init(T value[N])
    {
        data = value;
    }

    public property uint channels { get { return N; } }
    public __subscript(uint c) -> T { get { return data[c]; } set { data[c] = newValue; } }

    public float4 toFloat()
    {
        float4 floatData = float4(0);
        for (int i = 0; i < N; ++i)
            floatData[i] = channelDataToFloat(this[i]);
        return floatData;
    }

    public static This fromFloat(float4 value)
    {
        T pixelData[N];
        for (int i = 0; i < N; ++i)
            pixelData[i] = channelDataFromFloat<T>(value[i]);
        return This(pixelData);
    }
}

public extension<T: __BuiltinArithmeticType> SimplePixelFormat<T, 1>
{
    public __init(T rVal)
    {
        data[0] = rVal;
    }
    public property T r { get { return data[0]; } set { data[0] = newValue; } }
}

public extension<T: __BuiltinArithmeticType> SimplePixelFormat<T, 2>
{
    public __init(T rVal, T gVal)
    {
        data[0] = rVal;
        data[1] = gVal;
    }
    public property T r { get { return data[0]; } set { data[0] = newValue; } }
    public property T g { get { return data[1]; } set { data[1] = newValue; } }
}

public extension<T: __BuiltinArithmeticType> SimplePixelFormat<T, 3>
{
    public __init(T rVal, T gVal, T bVal)
    {
        data[0] = rVal;
        data[1] = gVal;
        data[2] = bVal;
    }
    public property T r { get { return data[0]; } set { data[0] = newValue; } }
    public property T g { get { return data[1]; } set { data[1] = newValue; } }
    public property T b { get { return data[2]; } set { data[2] = newValue; } }
}

public extension<T: __BuiltinArithmeticType> SimplePixelFormat<T, 4>
{
    public __init(T rVal, T gVal, T bVal, T aVal)
    {
        data[0] = rVal;
        data[1] = gVal;
        data[2] = bVal;
        data[3] = aVal;
    }
    public property T r { get { return data[0]; } set { data[0] = newValue; } }
    public property T g { get { return data[1]; } set { data[1] = newValue; } }
    public property T b { get { return data[2]; } set { data[2] = newValue; } }
    public property T a { get { return data[3]; } set { data[3] = newValue; } }
}

public typealias R8 = SimplePixelFormat<uint8_t, 1>;
public typealias RG8 = SimplePixelFormat<uint8_t, 2>;
public typealias RGB8 = SimplePixelFormat<uint8_t, 3>;
public typealias RGBA8 = SimplePixelFormat<uint8_t, 4>;

public typealias R16 = SimplePixelFormat<uint16_t, 1>;
public typealias RG16 = SimplePixelFormat<uint16_t, 2>;
public typealias RGB16 = SimplePixelFormat<uint16_t, 3>;
public typealias RGBA16 = SimplePixelFormat<uint16_t, 4>;

public typealias R16F = SimplePixelFormat<half, 1>;
public typealias RG16F = SimplePixelFormat<half, 2>;
public typealias RGB16F = SimplePixelFormat<half, 3>;
public typealias RGBA16F = SimplePixelFormat<half, 4>;

public typealias R32 = SimplePixelFormat<uint32_t, 1>;
public typealias RG32 = SimplePixelFormat<uint32_t, 2>;
public typealias RGB32 = SimplePixelFormat<uint32_t, 3>;
public typealias RGBA32 = SimplePixelFormat<uint32_t, 4>;

public typealias R32F = SimplePixelFormat<float, 1>;
public typealias RG32F = SimplePixelFormat<float, 2>;
public typealias RGB32F = SimplePixelFormat<float, 3>;
public typealias RGBA32F = SimplePixelFormat<float, 4>;

public typealias R64F = SimplePixelFormat<double, 1>;
public typealias RG64F = SimplePixelFormat<double, 2>;
public typealias RGB64F = SimplePixelFormat<double, 3>;
public typealias RGBA64F = SimplePixelFormat<double, 4>;

// Images are read/write, have no mips and provide no interpolation.
public interface IImage2D
{
    associatedtype PixelFormat : IPixelFormat;

    // Returns the size of the image.
    property uint2 size { get; }

    // Native load / store, should be fastest and be direct indexing.
    __subscript(uint2 i) -> PixelFormat
    {
        get;
        set;
    }

    // The vector elements are filled starting from the first; e.g. for a
    // 3-channel image, the returned value should be float4(r,g,b,0). Integer
    // types are normalized - signed is from -1 to 1 and unsigned is from 0 to
    // 1.
    float4 loadf(uint2 p);
    [mutating]
    void storef(uint2 p, float4 value);
}

public struct Image2D<T: IPixelFormat>: IImage2D, IDroppable
{
    typealias PixelFormat = T;

    uint2 _size;
    List<PixelFormat> _data;

    public __init(uint2 size)
    {
        _size = size;
        _data.resize(_size.x * _size.y);
    }

    public __init(uint width, uint height)
    {
        _size = uint2(width, height);
        _data.resize(_size.x * _size.y);
    }

    [mutating]
    public void drop()
    {
        _data.drop();
        _size = uint2(0, 0);
    }

    uint ravelIndex(uint2 p)
    {
        if (any(p >= _size))
            panic("Index out of range: (%u, %u), image size: (%u, %u)\n", p.x, p.y, _size.x, _size.y);
        return p.x + p.y * _size.y;
    }

    public property uint2 size { get { return _size; } }

    public float4 loadf(uint2 p)
    {
        return _data[ravelIndex(p)].toFloat();
    }

    [mutating]
    public void storef(uint2 p, float4 value)
    {
        _data[ravelIndex(p)] = T.fromFloat(value);
    }

    public __subscript(uint2 i) -> PixelFormat
    {
        get { return _data[ravelIndex(i)]; }
        set { _data[ravelIndex(i)] = newValue; }
    }

    public __subscript(uint x, uint y) -> PixelFormat
    {
        get { return _data[ravelIndex(uint2(x,y))]; }
        set { _data[ravelIndex(uint2(x,y))] = newValue; }
    }

    public Image2D<U> convert<U: IPixelFormat>()
    {
        var newImage = Image2D<U>(_size);

        for (uint i = 0; i < _size.x * _size.y; ++i)
            newImage._data[i] = U.fromFloat(_data[i].toFloat());
        return newImage;
    }
}

public void clearImage<I: IImage2D>(inout I img, I.PixelFormat value)
{
    for (uint y = 0; y < img.size.y; ++y)
    for (uint x = 0; x < img.size.x; ++x)
        img[uint2(x,y)] = value;
}

public void saveBMP<let ChannelCount: int>(
    NativeString path,
    Image2D<SimplePixelFormat<uint8_t, ChannelCount>> img) throws IOError
{
    BinaryOutputStream stream;
    defer stream.drop();

    int nativePitch = img.size.x * ChannelCount;
    uint outPitch = (nativePitch + 3) / 4 * 4;
    uint padding = outPitch - nativePitch;

    do
    {
        // BMP header
        stream.writeBytes("BM");
        try stream.write(uint32_t(54 + outPitch * img.size.y)); // Size
        try stream.write(uint32_t(0)); // Reserved
        try stream.write(uint32_t(54)); // Offset to pixel data

        // DIB header
        try stream.write(uint32_t(40));
        try stream.write(uint32_t(img.size.x));
        try stream.write(uint32_t(img.size.y));
        try stream.write(uint16_t(1)); // planes
        try stream.write(uint16_t(ChannelCount * 8)); // bpp - extend?
        try stream.write(uint32_t(0)); // Compression - none
        try stream.write(uint32_t(outPitch * img.size.y)); // Size
        try stream.write(uint32_t(2835)); // PPM X
        try stream.write(uint32_t(2835)); // PPM Y
        try stream.write(uint32_t(0)); // Color count
        try stream.write(uint32_t(0)); // Important color count

        for(uint y = 0; y < img.size.y; ++y)
        {
            uint flippedY = img.size.y - 1 - y;
            for(uint x = 0; x < img.size.x; ++x)
            {
                let pixel = img[x, flippedY];
                for(uint c = 0; c < ChannelCount; ++c)
                    try stream.write(pixel[c]);
            }

            for(uint i = 0; i < padding; ++i)
                try stream.write(uint8_t(0));
        }
    }
    catch
    {
        // Should never happen for a BinaryOutputStream.
        panic("BMP serialization error");
    }

    try writeBinaryFile(path, stream.data, stream.size);
}

}
