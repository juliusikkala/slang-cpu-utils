
namespace scul
{

public uint mortonEncode2D32(uint2 x)
{
    x =              x & 0x0000ffffu;
    x = (x ^ (x << 8)) & 0x00ff00ffu;
    x = (x ^ (x << 4)) & 0x0f0f0f0fu;
    x = (x ^ (x << 2)) & 0x33333333u;
    x = (x ^ (x << 1)) & 0x55555555u;
    return x.x | (x.y << 1);
}

public uint64_t mortonEncode2D64(uint2 x)
{
    uint64_t2 v = x;
    // This step is meaningless because x is already 32-bit.
    //v =               v & 0x00000000ffffffffll;
    v = (v ^ (v << 16)) & 0x0000ffff0000ffffll;
    v = (v ^ (v <<  8)) & 0x00ff00ff00ff00ffll;
    v = (v ^ (v <<  4)) & 0x0f0f0f0f0f0f0f0fll;
    v = (v ^ (v <<  2)) & 0x3333333333333333ll;
    v = (v ^ (v <<  1)) & 0x5555555555555555ll;
    return v.x | (v.y << 1);
}

public uint mortonEncode3D32(uint3 x)
{
    x =               x & 0x000003ffu;
    x = (x ^ (x << 16)) & 0xff0000ffu;
    x = (x ^ (x <<  8)) & 0x0300f00fu;
    x = (x ^ (x <<  4)) & 0x030c30c3u;
    x = (x ^ (x <<  2)) & 0x09249249u;
    return x.x | (x.y << 1) | (x.z << 2);
}

public uint64_t mortonEncode3D64(uint3 x)
{
    uint64_t3 v = x;
    v =               v & 0x00000000001fffffll;
    v = (v ^ (v << 32)) & 0x0000001f0000ffffll;
    v = (v ^ (v << 16)) & 0x001f0000ff0000ffll;
    v = (v ^ (v <<  8)) & 0x100f00f00f00f00fll;
    v = (v ^ (v <<  4)) & 0x10c30c30c30c30c3ll;
    v = (v ^ (v <<  2)) & 0x1249249249249249ll;
    return v.x | (v.y << 1) | (v.z << 2);
}

public uint2 mortonDecode2D32(uint m)
{
    uint2 x = uint2(m, m >> 1);
    x =              x & 0x55555555u;
    x = (x ^ (x >> 1)) & 0x33333333u;
    x = (x ^ (x >> 2)) & 0x0f0f0f0fu;
    x = (x ^ (x >> 4)) & 0x00ff00ffu;
    x = (x ^ (x >> 8)) & 0x0000ffffu;
    return x;
}

public uint2 mortonDecode2D64(uint64_t m)
{
    uint64_t2 x = uint64_t2(m, m >> 1);
    x =               x & 0x5555555555555555ll;
    x = (x ^ (x >>  1)) & 0x3333333333333333ll;
    x = (x ^ (x >>  2)) & 0x0f0f0f0f0f0f0f0fll;
    x = (x ^ (x >>  4)) & 0x00ff00ff00ff00ffll;
    x = (x ^ (x >>  8)) & 0x0000ffff0000ffffll;
    x = (x ^ (x >> 16)) & 0x00000000ffffffffll;
    return uint2(x);
}

public uint3 mortonDecode3D32(uint m)
{
    uint3 x = uint3(m, m >> 1, m >> 2);
    x =               x & 0x09249249u;
    x = (x ^ (x >>  2)) & 0x030c30c3u;
    x = (x ^ (x >>  4)) & 0x0300f00fu;
    x = (x ^ (x >>  8)) & 0xff0000ffu;
    x = (x ^ (x >> 16)) & 0x000003ffu;
    return x;
}

public uint3 mortonDecode3D64(uint64_t m)
{
    uint64_t3 x = uint64_t3(m, m >> 1, m >> 2);
    x =               x & 0x1249249249249249ll;
    x = (x ^ (x >>  2)) & 0x10c30c30c30c30c3ll;
    x = (x ^ (x >>  4)) & 0x100f00f00f00f00fll;
    x = (x ^ (x >>  8)) & 0x001f0000ff0000ffll;
    x = (x ^ (x >> 16)) & 0x0000001f0000ffffll;
    x = (x ^ (x >> 32)) & 0x00000000001fffffll;
    return uint3(x);
}

// From: http://and-what-happened.blogspot.com/2011/08/fast-2d-and-3d-hilbert-curves-and.html
public uint mortonToHilbert2D32(uint morton, uint bits)
{
    uint hilbert = 0u;
    uint remap = 0xb4u;
    uint block = bits * 2u - 2u;
    for(uint i = 0u; i < bits; ++i, block -= 2u)
    {
        uint mcode = (morton >> block) & 3u;
        uint hcode = (remap >> (mcode << 1u)) & 3u;
        remap ^= 0x82000028u >> (hcode << 3u);
        hilbert = (hilbert << 2u) + hcode;
    }
    return hilbert;
}

public uint mortonToHilbert3D32(uint morton, uint bits)
{
    uint shift = 0u;
    uint signs = 0u;
    uint block = bits * 3u - 3u;
    for(uint i = 0u; i < bits; ++i, block -= 3u)
    {
        uint mcode = (morton >> block) & 7u;
        uint hcode = ((mcode | (mcode << 3u)) >> shift) & 7u ^ signs;
        morton ^= (mcode ^ hcode) << block;
        hcode <<= 2u;
        uint tmp = (0x20212021u >> hcode) & 3u;
        signs = (((signs | (signs << 3u)) >> tmp) ^ (0x53560300u >> hcode)) & 7u;
        shift = (0x48u >> (7u - shift - tmp)) & 3u;
    }
    morton ^= (morton >> 1u) & 0x92492492u;
    morton ^= (morton >> 1u) & 0x49249249u;
    return morton;
}

public uint hilbertEncode2D32(uint2 x)
{
    return mortonToHilbert2D32(mortonEncode2D32(x), 16);
}

public uint hilbertEncode3D32(uint3 x)
{
    return mortonToHilbert3D32(mortonEncode3D32(x), 10);
}

}
