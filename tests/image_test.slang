import test;
import image;
import panic;
import bmp;

using scul;

export __extern_cpp int main(int argc, Ptr<NativeString> argv)
{
    var img = Image2D<RGB8>(512, 512);
    defer img.drop();

    clearImage(img, RGB8(0,255,0));

    for (int y = 0; y < 512; ++y)
    for (int x = 0; x < 512; ++x)
    {
        float2 uv = float2(x, y)/float2(512);
        uv = uv * float2(2.47, 2.24) - float2(2.0, 1.12);
        float2 z = float2(0);

        int i = 0;
        const int maxIters = 1000;
        while (i < maxIters && dot(z,z) < float(1<<16))
        {
            z = float2(z.x*z.x - z.y*z.y + uv.x, 2*z.x*z.y + uv.y);
            ++i;
        }

        float logZn = log2(dot(z,z)) * 0.5;
        float nu = i < maxIters ? log2(logZn) : 1;
        float t = clamp((i+1-nu)/maxIters, 0.0, 1.0);

        uint8_t col = uint8_t(log2(t)*255);

        img[x, y] = RGB8(col,col,col);
    }

    do
    {
        try saveBMP("test.bmp", img);
    }
    catch
    {
        panic("Failed to save image!");
    }

    return 0;
}
