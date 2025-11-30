namespace scul
{

public float3 powerLawEOTF(float3 nonlinearSRGB, float power = 2.2)
{
    return pow(nonlinearSRGB, power);
}

public float3 powerLawOETF(float3 linearSRGB, float power = 2.2)
{
    return pow(linearSRGB, 1.0/power);
}

namespace XYZ
{
    // This color matching function is based on the 2006 CIE XYZ standard
    // observer. These analytic approximations are based on the approach from
    // "Simple Analytic Approximations to the CIE XYZ Color Matching Functions",
    // 2013, Wyman et al. https://jcgt.org/published/0002/02/01/
    // The values have been fit for the 2006 LMS, `exp` has been replaced with
    // `exp2` and parts have been reformulated as multiply-adds.
    public float3 colorMatching(float nmWavelength)
    {
        // Vector ops are only used to group similar operations together; this
        // should have no performance benefit on GPUs. On CPUs, this may
        // occasionally be helpful by making the SLP vectorizer's job more obvious.
        float3 xl = 
            nmWavelength *
            float3(0.0441311400, 0.0309176439, 0.0226333433) +
            float3(-19.5313351307, -15.4037794413, -13.5977664676);
        float4 yzl = 
            nmWavelength *
            float4(0.0146988109, 0.0438508950, 0.0473006696, 0.0835678744) +
            float4(-8.4914035797, -23.4908313751, -21.0235350314, -35.3313406769);
        float3 xt = 
            (xl*xl) *
            select(xl<0, float3(-1), float3(-0.0410610477, -1.2071651668, -1.1243407493)) +
            float3(-1.3655766440, -1.5721567877, 0.0488937785);
        float4 yzt = 
            (yzl*yzl) *
            select(yzl<0, float4(-1), float4(-2.3044874668, -0.2456761897, -0.4601937151, -0.0678942731)) +
            float4(-0.5015742183, -1.3757036924, 0.5974377211, -1.1005945318);

        float3 xe = exp2(xt);
        float4 yze = exp2(yzt);
        return float3(
            xe.x-xe.y+xe.z,
            yze.x+yze.y,
            yze.z+yze.w
        );
    }

    float3 toxyY(float3 xyz)
    {
        float invSum = 1.0/(xyz.x+xyz.y+xyz.z);
        return float3(xyz.x*invSum, xyz.y*invSum, xyz.y);
    }

    float3 fromxyY(float3 xyY)
    {
        float sum = xyY.z/xyY.y;
        return float3(xyY.x*sum, xyY.z, sum*(1-xyY.x-xyY.y));
    }

    // Clips given color to a limited gamut, or, "absolute colorimetric".
    // Preserves hue and brightness, but desaturates colors until they are
    // within the gamut.
    public float3 gamutClipping(
        float3 xyz,
        float3x2 primaries,
        float2 whitePoint
    ){
        float3 xyY = toxyY(xyz);
        float2 d = xyY.xy - whitePoint;
        float mint = 1;

        // Trace ray from white point to the edges defined by primaries.
        [ForceUnroll]
        for (int i = 0; i < 3; ++i)
        {
            float2 a = primaries[i] - whitePoint;
            float2 b = primaries[(i+1)%3] - whitePoint;

            float num = a.y*b.x - a.x*b.y;
            float denom = d.y*(b.x-a.x) - d.x*(b.y-a.y);
            float t = num/denom;
            if (t > 0)
                mint = min(t, mint);
        }

        xyY.xy = whitePoint + mint * d;
        return fromxyY(xyY);
    }
}

namespace sRGB
{
    // These are in the xyY color space, although Y is omitted.
    public static const float3x2 primaries = float3x2(
        0.6400, 0.3300, // Red
        0.3000, 0.6000, // Green
        0.1500, 0.0600  // Blue
    );

    // Also in xyY.
    public static const float2 whitePoint = float2(0.3127, 0.3290);

    public float3 EOTF(float3 nonlinearColor)
    {
        return select(
            nonlinearColor <= 0.04045,
            nonlinearColor/12.92,
            pow((nonlinearColor + 0.055)/1.055, 2.4));
    }

    // sRGBOETF is not provided because it's dumb. See powerLawOETF instead if you
    // know what you want.
    public float3 inverseEOTF(float3 linearColor)
    {
        return select(
            linearColor <= 0.031308,
            12.92*linearColor,
            1.055*pow(linearColor, 1/2.4)-0.055);
    }

    // Based on just computing the Y of CIE XYZ.
    public float luminance(float3 linearColor)
    {
        return dot(linearColor, float3(0.2126729, 0.7151522, 0.0721750));
    }

    public float3 toXYZ(float3 linearSRGB)
    {
        return mul(float3x3(
            0.4124564, 0.3575761, 0.1804375,
            0.2126729, 0.7151522, 0.0721750,
            0.0193339, 0.1191920, 0.9503041
        ), linearSRGB);
    }

    public float3 fromXYZ(float3 XYZ)
    {
        return mul(float3x3(
            3.2404542, -1.5371385, -0.4985314,
            -0.9692660, 1.8760108, 0.0415560,
            0.0556434, -0.2040259, 1.0572252
        ), XYZ);
    }
}

}
