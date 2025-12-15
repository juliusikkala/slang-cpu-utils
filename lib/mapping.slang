// This module uses some abbreviations:
//
// UHC = Unit HyperCube, [0, 1]^D
namespace scul
{

public float2 directionToOctahedral(float3 dir)
{
    float3 na = abs(dir);
    float invNa = 1.0 / (na.x + na.y + na.z);
    float3 o = dir * invNa;
    if (o.z >= 0.0)
        return o.xy;
    float2 p = 1.0 - abs(o.yx);
    if (o.x < 0) p.x = -p.x;
    if (o.y < 0) p.y = -p.y;
    return p;
}

public float3 octahedralToDirection(float2 octahedral)
{
    float2 na = abs(octahedral);
    float3 normal = float3(octahedral.xy, 1.0 - na.x - na.y);
    float offset = saturate(-normal.z);
    float2 o2 = float2(
        normal.x < 0 ? -offset : offset,
        normal.y < 0 ? -offset : offset
    );
    normal.xy += o2;
    return normalize(normal);
}

public float3 uhcToSphereUniform(float2 u)
{
    float cosTheta = 2.0 * u.x - 1.0;
    float sinTheta = sqrt(1.0f - cosTheta * cosTheta);
    float phi = 2.0 * float.getPi() * u.y;
    float s, c;
    sincos(phi, s, c);
    return float3(c * sinTheta, s * sinTheta, cosTheta);
}

public float3 uhcToBallUniform(float3 u)
{
    float3 d = uhcToSphereUniform(u.xy);
    return pow(u.z, 1.0/3.0) * d;
}

}
