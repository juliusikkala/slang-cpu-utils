import mapping;

namespace scul
{

public struct Ray3
{
    public float3 origin;
    public float3 direction;
}

public interface ISurfacePoint<T>
{
    public float3 getPosition(T s);
    public float3 getNormal(T s);
    // Aka: barycoords or some other 2D mapping on 3D surface. The values must
    // uniquely identify a point on the surface, this is not for texture
    // coordinates or arbitrary data.
    public float2 getMapping(T s);
}

public interface ISurface
{
    //==========================================================================
    // Mandatory members
    //==========================================================================
    public property float area { get; }
    public property AABB3 bounds { get; }

    // The variety of point types are used to only return the minimal amount
    // of information that can be used to reconstruct more complex aspects
    // later. Having a different type for each function allows that data to vary
    // depending on what is easily accessible.
    associatedtype SampledPoint: ISurfacePoint<This>;
    associatedtype MappedPoint: ISurfacePoint<This>;
    associatedtype IntersectedPoint: ISurfacePoint<This>;

    // "jacobian" is actually the absolute jacobian determinant here. If the pdf
    // of `s` is 1, then the PDF after this sampling is 1.0/jacobian.
    public SampledPoint sampleSurface(float2 s, out float jacobian);

    public MappedPoint getMappedPoint(float2 mapping);

    public Optional<IntersectedPoint> intersect(
        float3 rayOrigin,
        float3 rayDir,
        float3 rayInvDir,
        float tmin = 0,
        float tmax = float.maxValue);

    //==========================================================================
    // Optionally overridable members
    //==========================================================================

    public Optional<float> intersectDist(
        float3 rayOrigin,
        float3 rayDir,
        float3 rayInvDir,
        float tmin = 0,
        float tmax = float.maxValue)
    {
        let sp = intersect(rayOrigin, rayDir, rayInvDir, tmin, tmax);
        if (!sp.hasValue)
            return none;
        return distance(rayOrigin, sp.value.getPosition(this));
    }

    public bool intersectBool(
        float3 rayOrigin,
        float3 rayDir,
        float3 rayInvDir,
        float tmin = 0,
        float tmax = float.maxValue)
    {
        return intersectDist(rayOrigin, rayDir, rayInvDir, tmin, tmax).hasValue;
    }

    public Optional<IntersectedPoint> intersect(Ray3 ray, float tmin = 0, float tmax = float.maxValue)
    {
        return intersect(ray.origin, ray.direction, rcp(ray.direction), tmin, tmax);
    }

    public Optional<float> intersectDist(Ray3 ray, float tmin = 0, float tmax = float.maxValue)
    {
        return intersectDist(ray.origin, ray.direction, rcp(ray.direction), tmin, tmax);
    }

    public bool intersectBool(Ray3 ray, float tmin = 0, float tmax = float.maxValue)
    {
        return intersectDist(ray.origin, ray.direction, rcp(ray.direction), tmin, tmax).hasValue;
    }
}

public interface IVolume
{
    public void sampleVolume(
        float3 s,
        out float3 point,
        out float jacobian
    );
    public property float volume { get; }
}

public struct AABB3: ISurface, IVolume
{
    public float3 minBound;
    public float3 maxBound;

    public property float3 edges {
        get {
            return maxBound - minBound;
        }
    }

    public property float3 center {
        get {
            return (maxBound + minBound) * 0.5;
        }
        set {
            let r = radius;
            minBound = newValue - r;
            maxBound = newValue + r;
        }
    }

    public property float3 radius {
        get {
            return edges * 0.5;
        }
        set {
            let c = center;
            minBound = c - newValue;
            maxBound = c + newValue;
        }
    }

    public float2 sideSize(int axis)
    {
        let e = edges;
        if (axis == 0)
            return float2(e.y, e.z);
        if (axis == 1)
            return float2(e.x, e.z);
        return float2(e.x, e.y);
    }

    public float3 sideCenter(int axis, int plus)
    {
        var origin = center;
        origin[axis] = origin[axis] + radius[axis] * plus;
        return origin;
    }

    [ForceInline]
    public float sideArea(int n)
    {
        float2 size = sideSize(n);
        return size.x * size.y;
    }

    public property float area {
        get {
            let e = edges;
            return 2.0*(e.x*e.y + e.x*e.z + e.y*e.z);
        }
    }

    public property float volume
    {
        get {
            let e = edges;
            return e.x*e.y*e.z;
        }
    }
    public property AABB3 bounds { get { return this; } }

    public struct MappedPoint: ISurfacePoint<This>
    {
        public float2 mapping;
        public float3 getPosition(AABB3 s)
        {
            int chosenFace = int(mapping[0]);
            int chosenAxis = chosenFace >= 3 ? chosenFace - 3 : chosenFace;
            int chosenSign = chosenFace < 3 ? -1 : 1;

            // Scale to [-1, 1]
            let u = 2.0 * frac(mapping) - 1.0;

            var p = s.center;
            let r = s.radius;

            float3 offset;
            if (chosenAxis == 0)
                offset = float3(chosenSign, u.xy);
            else if(chosenAxis == 1)
                offset = float3(u.x, chosenSign, u.y);
            else
                offset = float3(u.xy, chosenSign);

            return p + offset * r;
        }

        public float3 getNormal(AABB3 s)
        {
            int chosenFace = int(mapping[0]);
            int chosenAxis = chosenFace >= 3 ? chosenFace - 3 : chosenFace;
            float3 normal = float3(0);
            normal[chosenAxis] = chosenFace < 3 ? -1 : 1;
            return normal;
        }

        public float2 getMapping(AABB3 s)
        {
            return mapping;
        }
    }
    public typealias SampledPoint = MappedPoint;

    public SampledPoint sampleSurface(float2 s, out float jacobian)
    {
        jacobian = area;
        var u = s;
        let e = edges;

        // Determine surface areas on each side, this is needed later for
        // uniform sampling. Larger edges/faces get proportionally more samples!
        float3 sideAreas = float3(e.y * e.z, e.x * e.z, e.x * e.y);
        float sum = sideAreas.x + sideAreas.y + sideAreas.z;

        float invSum = rcp(sum);

        // Use the first random var to select which axis to sample. This is
        // normalized by the surface area of the sides, so that sampling is
        // uniform.
        int chosenAxis = 0;
        [ForceUnroll]
        for (int i = 0; i < 3; ++i)
        {
            float a = sideAreas[i] * invSum;
            if (u.x < a)
            {
                chosenAxis = i;
                u.x /= a;
                break;
            }
            else u.x -= a;
        }

        // Use the second random var to select whether to sample +axis or -axis
        int chosenSign = -1;
        if (u.y > 0.5)
        {
            u.y -= 0.5;
            chosenSign = 1;
        }
        u.y = u.y * 2.0;

        // Identify chosen face in mapping
        var mapping = u;
        mapping.x += (chosenSign < 0 ? 0 : 3) + chosenAxis;

        jacobian = 2.0f * sum;
        return SampledPoint(mapping);
    }

    public MappedPoint getMappedPoint(float2 mapping)
    {
        return MappedPoint(mapping);
    }

    public void sampleVolume(
        float3 s,
        out float3 point,
        out float jacobian
    ){
        point = minBound + s * edges;
        jacobian = volume;
    }

    public struct IntersectedPoint: ISurfacePoint<This>
    {
        public int face;
        public float3 pos;
        public float3 getPosition(AABB3 s)
        {
            return pos;
        }

        public float3 getNormal(AABB3 s)
        {
            let uv = (pos - s.minBound) / s.edges;
            int chosenAxis = face >= 3 ? face - 3 : face;
            int chosenSign = face < 3 ? -1 : 1;
            float3 normal = float3(0);
            normal[chosenAxis] = chosenSign;
            return normal;
        }

        public float2 getMapping(AABB3 s)
        {
            let uv = (pos - s.minBound) / s.edges;
            int chosenAxis = face >= 3 ? face - 3 : face;
            int chosenSign = face < 3 ? -1 : 1;

            float2 mapping;
            if (chosenAxis == 0)
                mapping = float2(uv.y, uv.z);
            else if (chosenAxis == 1)
                mapping = float2(uv.x, uv.z);
            else
                mapping = float2(uv.x, uv.y);

            mapping.x += chosenAxis + (chosenSign < 0 ? 0 : 3);
            return mapping;
        }
    }

    public override Optional<IntersectedPoint> intersect(
        float3 rayOrigin,
        float3 rayDir,
        float3 rayInvDir,
        float tmin,
        float tmax)
    {
        let t0 = (minBound - rayOrigin) * rayInvDir;
        let t1 = (maxBound - rayOrigin) * rayInvDir;
        let mins = min(t0, t1);
        let maxs = max(t0, t1);
        float near = max(mins[0], max(mins[1], mins[2]));
        float far = min(maxs[0], min(maxs[1], maxs[2]));
        if(near <= far && far > tmin && near < tmax)
        {
            float t = near > tmin ? near : far;
            int face = 0;
            if (t == t0.y) face = 1;
            else if (t == t0.z) face = 2;
            else if (t == t1.x) face = 3;
            else if (t == t1.y) face = 4;
            else if (t == t1.z) face = 5;
            return IntersectedPoint(face, rayOrigin + t * rayDir);
        }
        return none;
    }

    private float2 intersectionCandidates(
        float3 rayOrigin,
        float3 rayDir,
        float3 rayInvDir
    ){
        let t0 = (minBound - rayOrigin) * rayInvDir;
        let t1 = (maxBound - rayOrigin) * rayInvDir;
        let mins = min(t0, t1);
        let maxs = max(t0, t1);
        float near = max(mins[0], max(mins[1], mins[2]));
        float far = min(maxs[0], min(maxs[1], maxs[2]));
        return float2(near, far);
    }

    public override Optional<float> intersectDist(
        float3 rayOrigin,
        float3 rayDir,
        float3 rayInvDir,
        float tmin,
        float tmax
    ){
        float2 nf = intersectionCandidates(rayOrigin, rayDir, rayInvDir);
        float near = nf.x;
        float far = nf.y;
        if(near <= far && far > tmin && near < tmax)
            return near > tmin ? near : far;
        return none;
    }

    public override bool intersectBool(
        float3 rayOrigin,
        float3 rayDir,
        float3 rayInvDir,
        float tmin,
        float tmax)
    {
        float2 nf = intersectionCandidates(rayOrigin, rayDir, rayInvDir);
        float near = nf.x;
        float far = nf.y;
        if(near <= far && far > tmin && near < tmax)
            return true;
        return false;
    }
}

// TODO: Triangle, TriangleMesh (only after BVH exists)

public struct Sphere: ISurface, IVolume
{
    public float3 origin;
    public float radius;

    public property float area
    {
        get {
            return 4.0 * float.getPi() * radius * radius;
        }
    }

    public property float volume
    {
        get {
            return (4.0/3.0) * float.getPi() * radius * radius * radius;
        }
    }

    public property AABB3 bounds
    {
        get {
            return AABB3(origin-radius, origin+radius);
        }
    }

    public struct SampledPoint: ISurfacePoint<This>
    {
        public float3 normal;
        public float3 getPosition(Sphere s)
        {
            return s.origin + normal * s.radius;
        }

        public float3 getNormal(Sphere s)
        {
            return normal;
        }

        public float2 getMapping(Sphere s)
        {
            return directionToOctahedral(normal);
        }
    }

    public SampledPoint sampleSurface(float2 s, out float jacobian)
    {
        float3 normal = uhcToSphereUniform(s);
        jacobian = area;
        return SampledPoint(normal);
    }

    public struct MappedPoint: ISurfacePoint<This>
    {
        public float2 octahedral;
        public float3 getPosition(Sphere s)
        {
            return s.origin + octahedralToDirection(octahedral) * s.radius;
        }

        public float3 getNormal(Sphere s)
        {
            return octahedralToDirection(octahedral);
        }

        public float2 getMapping(Sphere s)
        {
            return octahedral;
        }
    }

    public MappedPoint getMappedPoint(float2 mapping)
    {
        return MappedPoint(mapping);
    }

    public struct IntersectedPoint: ISurfacePoint<This>
    {
        public float3 pos;
        public float3 getPosition(Sphere s)
        {
            return pos;
        }

        public float3 getNormal(Sphere s)
        {
            return normalize(pos - s.origin);
        }

        public float2 getMapping(Sphere s)
        {
            return directionToOctahedral(pos - s.origin);
        }
    }

    private Optional<float2> intersectionCandidates(
        float3 rayOrigin,
        float3 rayDir
    ){
    }

    public Optional<IntersectedPoint> intersect(
        float3 rayOrigin,
        float3 rayDir,
        float3 rayInvDir,
        float tmin = 0,
        float tmax = float.maxValue)
    {
        Optional<float> t = intersectDist(rayOrigin, rayDir, rayInvDir);
        if (!t.hasValue) return none;
        return IntersectedPoint(rayOrigin + t.value * rayDir);
    }

    public override Optional<float> intersectDist(
        float3 rayOrigin,
        float3 rayDir,
        float3 rayInvDir,
        float tmin = 0,
        float tmax = float.maxValue)
    {
        float3 rp = rayOrigin - origin;
        float b = dot(rp, rayDir);
        float c = dot(rp, rp) - radius * radius;
        float discriminant = b * b - c;
        if (discriminant < 0) return none;

        float sqrtD = sqrt(discriminant);
        float near = -sqrtD - b;
        float far = sqrtD - b;

        if (near > tmax || far < tmin)
            return none;

        float t;
        if (near > tmin)
            t = near;
        else if (far < tmax)
            t = far;
        else return none;

    }

    public override bool intersectBool(
        float3 rayOrigin,
        float3 rayDir,
        float3 rayInvDir,
        float tmin = 0,
        float tmax = float.maxValue)
    {
        float3 rp = rayOrigin - origin;
        float b = dot(rp, rayDir);
        float c = dot(rp, rp) - radius * radius;
        float discriminant = b * b - c;
        if (discriminant < 0) return false;

        float btmax = b + tmax;
        float btmin = b + tmin;
        float btmax2 = btmax * abs(btmax);
        float btmin2 = btmin * abs(btmin);

        if (-discriminant > btmax2 || discriminant < btmin2)
            return false;
        return -discriminant > btmin2 || discriminant < btmax2;
    }

    public void sampleVolume(
        float3 s,
        out float3 point,
        out float jacobian
    ){
        point = origin + uhcToBallUniform(s) * radius;
        jacobian = volume;
    }
}

}
