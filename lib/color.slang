namespace scul
{

public float blackbody(float kTemperature, float nmWavelength)
{
    float l = 1.5304336773e-06 * nmWavelength;
    float l2 = l*l;
    float l5 = l2*l2*l;
    return rcp(l5*(exp2(31.7674607818 / (l*kTemperature)) - 1));
}

// Peak = 1
public float normalizedBlackbody(float kTemperature, float nmWavelength)
{
    float t = 1.2802052515e-07 * nmWavelength * kTemperature;
    float t2 = t*t;
    float t5 = t2*t2*t;
    return rcp(t5*(exp2(2.6573428645 / t) - 1.0));
}

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
    // observer. It is an analytic approximation, based on:
    //
    // "Chromaticity Preserving Analytic Approximations to the CIE Color Matching Functions",
    // 2025, Thomas Puls https://jcgt.org/published/0014/01/01/paper.pdf
    //
    // Particularly, the loss computation follows [2]. This allows for a fairly
    // accurate fit that avoids color shifting issues.
    //
    // I know it looks like it's doing a lot, but it's actually mostly just
    // FMA operations, which are generally really cheap to compute. Avoiding
    // excess exp2 and rsqrt calls is far more important than reducing the
    // number of FMA calls; see
    // https://docs.nvidia.com/cuda/cuda-c-best-practices-guide/index.html#throughput-of-native-arithmetic-instructions
    // as banana for scale. The maximum throughput of FMA is 8 times that of
    // exp2 & rsqrt & division, and this function does exactly 4 costly
    // operations. Everything else is all FMA.
    public float3 colorMatching(float nmWavelength)
    {
        float l = 0.004545454545454545 * nmWavelength - 2.5318181818181817;

        float y;
        {
            float num = 0.1301275*l + 1.00245928e-01;
            num = num*l + 9.57561402e-03;
            num = num*l + -1.38932987e-03;
            num = num*l + 8.37894528e-03;
            num = num*l + 2.74830341e-03;

            float denom = l + 1.47507955;
            denom = denom * l + 7.25887155e-01;
            denom = denom * l + 1.68454073e-01;
            denom = denom * l + 1.34359038e-01;
            denom = denom * l + 1.17288495e-01;
            denom = denom * l + 4.96394646e-02;
            denom = denom * l + 1.24815140e-02;
            denom = denom * l + 2.43539194e-03;
            denom = denom * l + 3.79132912e-04;
            denom = denom * l + 3.12008180e-05;

            y = num*rsqrt(denom) + 0.1484435;
        }

        float z;
        {
            float num = -0.4076485*l + -0.35095361;
            num = num*l + -0.1331233;
            num = num*l + -0.0180628;

            float denom = l + 1.71743649;
            denom = denom*l + 1.39074655;
            denom = denom*l + 0.65230375;
            denom = denom*l + 0.18359156;
            denom = denom*l + 0.02887253;
            denom = denom*l + 0.00197652;

            z = num*rsqrt(denom) + 0.4076485;
        }

        float sum;
        {
            float n1 = -1.45387399e+03 * l + 4.79802283e+03;
            n1 = n1*l + -5.08758577e+03;
            n1 = n1*l + 9.83598255e+02;
            n1 = n1*l + 1.42460683e+03;
            n1 = n1*l + -6.27295111e+02;
            n1 = n1*l + -8.05333092e+01;
            n1 = n1*l + 3.70651841e+01;
            n1 = n1*l + -1.13196450e+01;
            n1 = n1*l + 2.85970242;
            n1 = n1*l + 6.52507271e-01;

            float n2 = -1.59139682e+03*l + -3.22209280e+03;
            n2 = n2*l + -2.20605442e+03;
            n2 = n2*l + -3.60207361e+02;
            n2 = n2*l + 1.50810052e+02;
            n2 = n2*l + 2.34086691e+01;
            n2 = n2*l + -7.78294776;

            sum = exp2(n1) + exp2(n2);
        }

        return float3((1-y-z)*sum, y*sum, z*sum);
    }

    public float3 toxyY(float3 xyz)
    {
        float invSum = 1.0/(xyz.x+xyz.y+xyz.z);
        return float3(xyz.x*invSum, xyz.y*invSum, xyz.y);
    }

    public float3 fromxyY(float3 xyY)
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
