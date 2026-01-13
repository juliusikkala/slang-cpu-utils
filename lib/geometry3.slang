import mapping;

namespace scul
{

public interface ISurfacePoint<T>
{
    public float3 getPosition(T s);
    public float3 getNormal(T s);
}

public struct Ray3
{
    public float3 origin;
    public float3 direction;
}

public interface IRayIntersectionImpl<T: IRayIntersectionSurface>
{
    // Call repeatedly to discover all intersections for this query.
    // The order of the returned intersections is unspecified.
    // Traversal is over after `none` is returned.
    [mutating]
    public Optional<Tuple<T.IntersectedPoint, float>> proceed(
        T s,
        float3 rayOrigin,
        float3 rayDir,
        float3 rayInvDir,
        float tmin,
        float tmax);
}

public interface IRayIntersectionQuery<T: IRayIntersectionSurface>
{
    public property T.IntersectedPoint candidate { get; }
    public property float tcandidate { get; }
    public property Optional<T.IntersectedPoint> confirmed { get; }
    public property float tconfirmed { get; }

    [mutating]
    public bool proceed();

    [mutating]
    public void confirm();
}

public struct RayIntersectionQuery<T: IRayIntersectionSurface>: IRayIntersectionQuery<T>
{
    T* surface;
    T.RayIntersectionImpl ri;

    float3 rayOrigin;
    float3 rayDir;
    float3 rayInvDir;
    float tmin;
    float tmax;

    T.IntersectedPoint _candidate;
    float _tcandidate;
    T.IntersectedPoint _confirmed;
    float _tconfirmed;

    public property T.IntersectedPoint candidate { get { return _candidate; } }
    public property float tcandidate { get { return _tcandidate; } }
    public property Optional<T.IntersectedPoint> confirmed
    {
        get {
            if (_tconfirmed >= tmax)
                return none;
            return _confirmed;
        }
    }
    public property float tconfirmed
    {
        get {
            return _tconfirmed;
        }
    }

    public __init(
        T* surface,
        float3 rayOrigin,
        float3 rayDir,
        float tmin,
        float tmax)
    {
        this.surface = surface;
        this.rayOrigin = rayOrigin;
        this.rayDir = rayDir;
        this.rayInvDir = rcp(rayDir);
        this.ri = surface.beginRayIntersectionQuery(rayOrigin, rayDir, rayInvDir);
        this.tmin = tmin;
        this.tmax = tmax;
        this._tcandidate = tmax + 1.0;
        this._tconfirmed = tmax;
    }

    [mutating]
    public bool proceed()
    {
        let result = ri.proceed(*surface, rayOrigin, rayDir, rayInvDir, tmin, tconfirmed);
        if (!result.hasValue)
            return false;
        this._candidate = result.value._0;
        this._tcandidate = result.value._1;
        return true;
    }

    [mutating]
    public void confirm()
    {
        _confirmed = _candidate;
        _tconfirmed = _tcandidate;
    }
}

// A surface with a known area.
public interface IAreaSurface
{
    public property float area { get; }
}

// A surface with a known area that can be sampled with a 2D coordinate.
public interface IMappedSurface: IAreaSurface
{
    associatedtype MappedPoint: ISurfacePoint<This>;

    // "jacobian" is actually the absolute jacobian determinant here. If the pdf
    // of `s` is 1, then the PDF after this sampling is 1.0/jacobian.
    public MappedPoint sampleSurface(float2 s, out float jacobian);
}

// A surface where the distance to the nearest point can be determined.
public interface IDistanceSurface
{
    // Returns _unsigned_ distance of the surface to point 'p'.
    public float distanceFromPoint(float3 p);
}

// A surface where the signed distance to the nearest point can be determined.
// The surface must divide the world into negative and positive parts.
public interface ISignedDistanceSurface
{
    public float signedDistanceFromPoint(float3 p);
}

// A surface that can be intersected with a ray.
public interface IRayIntersectionSurface
{
    //==========================================================================
    // Mandatory members
    //==========================================================================

    // Having a different point type for each shape allows that data to vary
    // depending on what is easily accessible and compact to store.
    associatedtype IntersectedPoint: ISurfacePoint<This>;
    associatedtype RayIntersectionImpl: IRayIntersectionImpl<This>;

    public RayIntersectionImpl beginRayIntersectionQuery(
        float3 rayOrigin,
        float3 rayDir,
        float3 rayInvDir);

    public Optional<Tuple<IntersectedPoint, float>> intersect(
        float3 rayOrigin,
        float3 rayDir,
        float3 rayInvDir,
        float tmin = 0,
        float tmax = float.maxValue);

    //==========================================================================
    // Optionally overridable members
    //==========================================================================
    // These can be overridden for extra performance, but the above functions
    // are sufficient.

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
        return sp.value._1;
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

    public Optional<Tuple<IntersectedPoint, float>> intersect(Ray3 ray, float tmin = 0, float tmax = float.maxValue)
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

// A surface that can be used as a bounding volume.
public interface IBoundingVolume: IAreaSurface, IVolume
{
    public property float3 centroid { get; }
    public Tuple<float3, float3> axisAlignedExtents();
    public float2 extents(float3 axis);
}

// A surface for which a bounding volume can be computed.
public interface IBoundedShape<T>
{
    public void computeBounds(out T boundShape);
}

public struct AABB3:
    IMappedSurface,
    IRayIntersectionSurface,
    IBoundingVolume,
    IBoundedShape<AABB3>,
    IDistanceSurface,
    ISignedDistanceSurface
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

    public property float3 centroid {
        get {
            return center;
        }
    }

    public Tuple<float3, float3> axisAlignedExtents()
    {
        return makeTuple(minBound, maxBound);
    }

    public float2 extents(float3 axis)
    {
        float3 a = axis * minBound;
        float3 b = axis * maxBound;
        float3 mine = min(a, b);
        float3 maxe = max(a, b);
        return float2(mine.x+mine.y+mine.z, maxe.x+maxe.y+maxe.z);
    }

    public void computeBounds(out AABB3 bounds)
    {
        bounds = this;
    }

    public float distanceFromPoint(float3 p)
    {
        float3 q = abs(p-center) - radius;
        return length(max(q, 0)) + abs(min(max(q.x, max(q.y, q.z)), 0));
    }

    public float signedDistanceFromPoint(float3 p)
    {
        float3 q = abs(p-center) - radius;
        return length(max(q, 0)) + min(max(q.x, max(q.y, q.z)), 0);
    }

    public struct MappedPoint: ISurfacePoint<This>
    {
        public float2 mapping;
        public int chosenFace;

        public float3 getPosition(AABB3 s)
        {
            int chosenAxis = chosenFace >= 3 ? chosenFace - 3 : chosenFace;
            int chosenSign = chosenFace < 3 ? -1 : 1;

            var p = s.center;
            let r = s.radius;

            float3 offset;
            if (chosenAxis == 0)
                offset = float3(chosenSign, mapping.xy);
            else if(chosenAxis == 1)
                offset = float3(mapping.x, chosenSign, mapping.y);
            else
                offset = float3(mapping.xy, chosenSign);

            return p + offset * r;
        }

        public float3 getNormal(AABB3 s)
        {
            int chosenAxis = chosenFace >= 3 ? chosenFace - 3 : chosenFace;
            float3 normal = float3(0);
            normal[chosenAxis] = chosenFace < 3 ? -1 : 1;
            return normal;
        }

        public This getMapping(AABB3 s)
        {
            return this;
        }
    }

    public MappedPoint sampleSurface(float2 s, out float jacobian)
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

        jacobian = 2.0f * sum;
        return MappedPoint(
            2.0f * u - 1.0f,
            chosenAxis + (chosenSign < 0 ? 0 : 3));
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
        public float3 pos;

        private float3 getAxisSign(AABB3 s, out int axis, out int asign)
        {
            let d = (pos - s.center) / s.edges;
            let ad = abs(d);

            if (ad.x > ad.y && ad.x > ad.z)
            {
                axis = 0;
                asign = sign(d.x);
            }
            else if (ad.y > ad.z)
            {
                axis = 1;
                asign = sign(d.y);
            }
            else
            {
                axis = 2;
                asign = sign(d.z);
            }
            return d;
        }

        public float3 getPosition(AABB3 s)
        {
            return pos;
        }

        public float3 getNormal(AABB3 s)
        {
            int chosenAxis, chosenSign;
            getAxisSign(s, chosenAxis, chosenSign);
            float3 normal = float3(0);
            normal[chosenAxis] = chosenSign;
            return normal;
        }

        public MappedPoint getMapping(AABB3 s)
        {
            int chosenAxis, chosenSign;
            let uv = getAxisSign(s, chosenAxis, chosenSign);

            float2 mapping;
            if (chosenAxis == 0)
                mapping = float2(uv.y, uv.z);
            else if (chosenAxis == 1)
                mapping = float2(uv.x, uv.z);
            else
                mapping = float2(uv.x, uv.y);

            return MappedPoint(
                2.0 * mapping, chosenAxis + (chosenSign < 0 ? 0 : 3));
        }
    }

    public struct RayIntersectionImpl: IRayIntersectionImpl<This>
    {
        public float2 candidates;

        [mutating]
        public Optional<Tuple<IntersectedPoint, float>> proceed(
            AABB3 s,
            float3 rayOrigin,
            float3 rayDir,
            float3 rayInvDir,
            float tmin,
            float tmax)
        {
            float near = candidates.x;
            float far = candidates.y;
            if (near >= far)
                return none;

            float t;
            if (near > tmin && near < tmax)
            {
                // Make sure we won't return the same value again.
                candidates.x = tmin;
                t = near;
            }
            else if (far > tmin && far < tmax)
            {
                // Make sure near >= far comparison goes through next time.
                candidates.y = near;
                t = far;
            }
            else return none;
            return makeTuple(IntersectedPoint(rayOrigin + t * rayDir), t);
        }
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

    public RayIntersectionImpl beginRayIntersectionQuery(
        float3 rayOrigin,
        float3 rayDir,
        float3 rayInvDir
    ){
        float2 candidates = intersectionCandidates(rayOrigin, rayDir, rayInvDir);
        return RayIntersectionImpl(candidates);
    }

    public override Optional<Tuple<IntersectedPoint, float>> intersect(
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
        {
            float t = near > tmin ? near : far;
            return makeTuple(IntersectedPoint(rayOrigin + t * rayDir), t);
        }
        return none;
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

public struct Sphere:
    IMappedSurface,
    IRayIntersectionSurface,
    IBoundingVolume,
    IDistanceSurface,
    ISignedDistanceSurface,
    IBoundedShape<AABB3>
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

    public property float3 centroid {
        get {
            return origin;
        }
    }

    public Tuple<float3, float3> axisAlignedExtents()
    {
        return makeTuple(origin-radius, origin+radius);
    }

    public float2 extents(float3 axis)
    {
        float c = dot(axis, origin);
        return float2(c - radius, c + radius);
    }

    public void computeBounds(out AABB3 bounds)
    {
        bounds = AABB3(origin-radius, origin+radius);
    }

    public float distanceFromPoint(float3 p)
    {
        return abs(length(p-origin) - radius);
    }

    public float signedDistanceFromPoint(float3 p)
    {
        return length(p-origin) - radius;
    }

    public struct MappedPoint: ISurfacePoint<This>
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
    }

    public MappedPoint sampleSurface(float2 s, out float jacobian)
    {
        float3 normal = uhcToSphereUniform(s);
        jacobian = area;
        return MappedPoint(normal);
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
    }

    public struct RayIntersectionImpl: IRayIntersectionImpl<This>
    {
        public float2 candidates;

        [mutating]
        public Optional<Tuple<IntersectedPoint, float>> proceed(
            Sphere s,
            float3 rayOrigin,
            float3 rayDir,
            float3 rayInvDir,
            float tmin,
            float tmax)
        {
            float near = candidates.x;
            float far = candidates.y;
            if (near >= far)
                return none;

            float t;
            if (near > tmin && near < tmax)
            {
                // Make sure we won't return the same value again.
                candidates.x = tmin;
                t = near;
            }
            else if (far > tmin && far < tmax)
            {
                // Make sure near >= far comparison goes through next time.
                candidates.y = near;
                t = far;
            }
            else return none;
            return makeTuple(IntersectedPoint(rayOrigin + t * rayDir), t);
        }
    }

    private Optional<float2> intersectionCandidates(
        float3 rayOrigin,
        float3 rayDir,
        float3 rayInvDir
    ){
        float3 rp = rayOrigin - origin;
        float b = dot(rp, rayDir);
        float c = dot(rp, rp) - radius * radius;
        float discriminant = b * b - c;
        if (discriminant < 0) return none;

        float sqrtD = sqrt(discriminant);
        float near = -sqrtD - b;
        float far = sqrtD - b;
        return float2(near, far);
    }

    public RayIntersectionImpl beginRayIntersectionQuery(
        float3 rayOrigin,
        float3 rayDir,
        float3 rayInvDir)
    {
        Optional<float2> candidates = intersectionCandidates(rayOrigin, rayDir, rayInvDir);
        float2 nf = float2(1,0); // This always fails the near < far check
        if (candidates.hasValue)
            nf = candidates.value;
        return RayIntersectionImpl(nf);
    }

    public Optional<Tuple<IntersectedPoint, float>> intersect(
        float3 rayOrigin,
        float3 rayDir,
        float3 rayInvDir,
        float tmin = 0,
        float tmax = float.maxValue)
    {
        Optional<float> t = intersectDist(rayOrigin, rayDir, rayInvDir);
        if (!t.hasValue) return none;
        return makeTuple(IntersectedPoint(rayOrigin + t.value * rayDir), t.value);
    }

    public override Optional<float> intersectDist(
        float3 rayOrigin,
        float3 rayDir,
        float3 rayInvDir,
        float tmin = 0,
        float tmax = float.maxValue)
    {
        Optional<float2> candidates = intersectionCandidates(rayOrigin, rayDir, rayInvDir);
        if (!candidates.hasValue)
            return none;
        float near = candidates.value.x;
        float far = candidates.value.y;

        if (near > tmax || far < tmin)
            return none;

        float t;
        if (near > tmin)
            t = near;
        else if (far < tmax)
            t = far;
        else return none;
        return t;
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

public struct Plane3:
    IRayIntersectionSurface,
    IDistanceSurface,
    ISignedDistanceSurface
{
    public float3 normal;
    public float dist;

    public float distanceFromPoint(float3 p)
    {
        return abs(distance(normal, p) - dist);
    }

    public float signedDistanceFromPoint(float3 p)
    {
        return distance(normal, p) - dist;
    }

    public struct IntersectedPoint: ISurfacePoint<This>
    {
        public float3 pos;

        public float3 getPosition(Plane3 s)
        {
            return pos;
        }

        public float3 getNormal(Plane3 s)
        {
            return s.normal;
        }
    }

    public struct RayIntersectionImpl: IRayIntersectionImpl<This>
    {
        public bool finished;

        [mutating]
        public Optional<Tuple<IntersectedPoint, float>> proceed(
            Plane3 s,
            float3 rayOrigin,
            float3 rayDir,
            float3 rayInvDir,
            float tmin,
            float tmax)
        {
            if (finished)
                return none;

            finished = true;
            return s.intersect(rayOrigin, rayDir, rayInvDir, tmin, tmax);
        }
    }

    public RayIntersectionImpl beginRayIntersectionQuery(
        float3 rayOrigin,
        float3 rayDir,
        float3 rayInvDir
    ){
        return RayIntersectionImpl();
    }

    public Optional<Tuple<IntersectedPoint, float>> intersect(
        float3 rayOrigin,
        float3 rayDir,
        float3 rayInvDir,
        float tmin = 0,
        float tmax = float.maxValue)
    {
        float t = (dist - dot(normal, rayOrigin)) / dot(normal, rayDir);
        if (t > tmin && t < tmax)
            return makeTuple(IntersectedPoint(rayOrigin + t * rayDir), t);
        return none;
    }
}

public struct Triangle3:
    IMappedSurface,
    IRayIntersectionSurface,
    IDistanceSurface,
    IBoundedShape<AABB3>
{
    public float3 vertices[3];

    public property float area
    {
        get {
            return length(cross(vertices[0]-vertices[1], vertices[0]-vertices[2])) * 0.5;
        }
    }

    public void computeBounds(out AABB3 bounds)
    {
        bounds = AABB3(
            min(min(vertices[0],vertices[1]),vertices[2]),
            max(max(vertices[0],vertices[1]),vertices[2])
        );
    }

    public float distanceFromPoint(float3 p)
    {
        float3 v1 = p - vertices[0];
        float3 v2 = p - vertices[1];
        float3 v3 = p - vertices[2];
        float3 e1 = vertices[1] - vertices[0];
        float3 e2 = vertices[2] - vertices[1];
        float3 e3 = vertices[0] - vertices[2];

        float3 normal = normalize(cross(e1, e2));

        if (
            dot(v1, cross(e1, normal)) > 0.0 ||
            dot(v2, cross(e2, normal)) > 0.0 ||
            dot(v3, cross(e3, normal)) > 0.0
        ){
            // Outer point, distance to closest edge.
            float3 c1 = e1 * saturate(dot(v1,e1)/dot(e1,e1)) - v1;
            float3 c2 = e2 * saturate(dot(v2,e2)/dot(e2,e2)) - v2;
            float3 c3 = e3 * saturate(dot(v3,e3)/dot(e3,e3)) - v3;
            
            return sqrt(min(dot(c1, c1), min(dot(c2, c2), dot(c3, c3))));
        }
        else
        {
            // Inner point, distance to plane.
            return abs(dot(v1, normal));
        }
    }

    public struct MappedPoint: ISurfacePoint<This>
    {
        public float2 barycoords;
        public float3 getPosition(Triangle3 s)
        {
            return
                barycoords.x * s.vertices[0] +
                barycoords.y * s.vertices[1] +
                (1.0-barycoords.x-barycoords.y) * s.vertices[2];
        }

        public float3 getNormal(Triangle3 s)
        {
            float3 e1 = s.vertices[1] - s.vertices[0];
            float3 e2 = s.vertices[2] - s.vertices[0];
            return normalize(cross(e1, e2));
        }
    }

    public MappedPoint sampleSurface(float2 s, out float jacobian)
    {
        jacobian = area;
        return MappedPoint(uhcToBarycentric(s));
    }

    public MappedPoint getMappedPoint(float2 mapping)
    {
        return MappedPoint(mapping);
    }

    // Based on "Watertight Ray/Triangle Intersection" by Woop et al. 2013.
    // https://jcgt.org/published/0002/01/05/paper.pdf
    public void preprocessRayForIntersection(
        float3 rayOrigin,
        float3 rayDir,
        float3 rayInvDir,
        out float3 M,
        out int axis
    ){
        float3 absdir = abs(rayDir);
        float x, y, invZ;

        if(absdir.x > absdir.y && absdir.x > absdir.z)
        {
            axis = 0;
            x = rayDir.z;
            y = rayDir.y;
            invZ = rayInvDir.x;
        }
        else if(absdir.y > absdir.z)
        {
            axis = 1;
            x = rayDir.x;
            y = rayDir.z;
            invZ = rayInvDir.y;
        }
        else
        {
            axis = 2;
            x = rayDir.x;
            y = rayDir.y;
            invZ = rayInvDir.z;
        }
        M = float3(-x * invZ, -y * invZ, invZ);
    }

    public struct IntersectedPoint: ISurfacePoint<This>
    {
        public float2 barycoords;
        public bool backFace;
        public float3 getPosition(Triangle3 s)
        {
            return
                barycoords.x * s.vertices[0] +
                barycoords.y * s.vertices[1] +
                (1.0-barycoords.x-barycoords.y) * s.vertices[2];
        }

        public float3 getNormal(Triangle3 s)
        {
            float3 e1 = s.vertices[1] - s.vertices[0];
            float3 e2 = s.vertices[2] - s.vertices[0];
            return normalize(cross(e1, e2));
        }

        public MappedPoint getMapping(Triangle3 s)
        {
            return MappedPoint(barycoords);
        }
    }

    public struct RayIntersectionImpl: IRayIntersectionImpl<This>
    {
        public bool finished;

        [mutating]
        public Optional<Tuple<IntersectedPoint, float>> proceed(
            Triangle3 s,
            float3 rayOrigin,
            float3 rayDir,
            float3 rayInvDir,
            float tmin,
            float tmax)
        {
            if (finished)
                return none;

            finished = true;
            return s.intersect(rayOrigin, rayDir, rayInvDir, tmin, tmax);
        }
    }

    public RayIntersectionImpl beginRayIntersectionQuery(
        float3 rayOrigin,
        float3 rayDir,
        float3 rayInvDir)
    {
        return RayIntersectionImpl(false);
    }

    private void intersectTransform(
        float3 rayOrigin,
        float3 M,
        int axis,
        out float3 x,
        out float3 y,
        out float3 z
    ){
        float3 A = vertices[0] - rayOrigin;
        float3 B = vertices[1] - rayOrigin;
        float3 C = vertices[2] - rayOrigin;

        if(axis == 0)
        {
            x = float3(A.z, B.z, C.z);
            y = float3(A.y, B.y, C.y);
            z = float3(A.x, B.x, C.x);
        }
        else if(axis == 1)
        {
            x = float3(A.x, B.x, C.x);
            y = float3(A.z, B.z, C.z);
            z = float3(A.y, B.y, C.y);
        }
        else
        {
            x = float3(A.x, B.x, C.x);
            y = float3(A.y, B.y, C.y);
            z = float3(A.z, B.z, C.z);
        }

        x = x + M.x * z;
        y = y + M.y * z;
    }

    public Optional<Tuple<IntersectedPoint, float>> intersectFast(
        float3 rayOrigin,
        float3 M,
        int axis,
        float tmin = 0,
        float tmax = float.maxValue)
    {
        float3 x, y, z;
        intersectTransform(rayOrigin, M, axis, x, y, z);

        float3 uvw = cross(y, x);
        float det = uvw.x + uvw.y + uvw.z;
        float invDet = rcp(det);
        float2 bary = uvw.xy * invDet;
        float t = M.z * dot(uvw, z) * invDet;

        bool backFace = det < 0;
        if(M.z < 0) backFace = !backFace;
        if(axis != 2) backFace = !backFace;

        bool3 less = uvw < 0;
        if (det == 0.0 || t < tmin || t > tmax || less.x != less.y || less.y != less.z)
            return none;
        return makeTuple(IntersectedPoint(bary, backFace), t);
    }

    public bool intersectBoolFast(
        float3 rayOrigin,
        float3 M,
        int axis,
        float tmin = 0,
        float tmax = float.maxValue)
    {
        float3 x, y, z;
        intersectTransform(rayOrigin, M, axis, x, y, z);

        float3 uvw = cross(y, x);
        float det = uvw.x + uvw.y + uvw.z;
        float absDet = det;
        float tdet = M.z * dot(uvw, z);
        if (det < 0)
        {
            tdet = -tdet;
            absDet = -det;
        }

        bool3 less = uvw < 0;
        if (det == 0.0 || tdet < tmin * absDet || tdet > tmax * absDet || less.x != less.y || less.y != less.z)
            return false;
        return true;
    }

    public Optional<Tuple<IntersectedPoint, float>> intersect(
        float3 rayOrigin,
        float3 rayDir,
        float3 rayInvDir,
        float tmin = 0,
        float tmax = float.maxValue)
    {
        float3 M;
        int axis;
        preprocessRayForIntersection(rayOrigin, rayDir, rayInvDir, M, axis);
        return intersectFast(rayOrigin, M, axis, tmin, tmax);
    }

    public override bool intersectBool(
        float3 rayOrigin,
        float3 rayDir,
        float3 rayInvDir,
        float tmin = 0,
        float tmax = float.maxValue)
    {
        float3 M;
        int axis;
        preprocessRayForIntersection(rayOrigin, rayDir, rayInvDir, M, axis);
        return intersectBoolFast(rayOrigin, M, axis, tmin, tmax);
    }
}

// TODO: TriangleMesh (only after BVH exists)

}
