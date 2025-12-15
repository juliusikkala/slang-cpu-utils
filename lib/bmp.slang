import image;
import binarystream;
import serialization;
import panic;
import io;

namespace scul
{

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
                if (ChannelCount == 1)
                {
                    try stream.write(pixel[0]);
                }
                else if (ChannelCount == 2)
                {
                    try stream.write(pixel[1]);
                    try stream.write(pixel[0]);
                }
                else if (ChannelCount == 3)
                {
                    try stream.write(pixel[2]);
                    try stream.write(pixel[1]);
                    try stream.write(pixel[0]);
                }
                else if (ChannelCount == 4)
                {
                    try stream.write(pixel[2]);
                    try stream.write(pixel[1]);
                    try stream.write(pixel[0]);
                    try stream.write(pixel[3]);
                }
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
