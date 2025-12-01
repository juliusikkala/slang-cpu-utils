namespace scul
{

public struct Ray<let D: int>
{
    public vector<float, D> origin;
    public vector<float, D> direction;
}

public typealias Ray2 = Ray<2>;
public typealias Ray3 = Ray<2>;

public interface ISurfacePoint<let D: int, T>
{
    public vector<float, D> getPosition(T s);
    public vector<float, D> getNormal(T s);
    // Aka: barycoords or some other 2D mapping on 3D surface. The values must
    // uniquely identify a point on the surface, this is not for texture
    // coordinates or arbitrary data.
    public vector<float, D-1> getMapping(T s);
}

public interface IHyperSurface<let D: int>
{
    //==========================================================================
    // Mandatory members
    //==========================================================================
    public property float area { get; }
    public property AABB<D> bounds { get; }

    // The variety of point types are used to only return the minimal amount
    // of information that can be used to reconstruct more complex aspects
    // later. Having a different type for each function allows that data to vary
    // depending on what is easily accessible.
    associatedtype SampledPoint: ISurfacePoint<D, This>;
    associatedtype MappedPoint: ISurfacePoint<D, This>;
    associatedtype IntersectedPoint: ISurfacePoint<D, This>;

    // "jacobian" is actually the absolute jacobian determinant here. If the pdf
    // of `u` is 1, then the PDF after this sampling is 1.0/jacobian.
    public SampledPoint sampleSurface(vector<float, D-1> rnd, out float jacobian);

    public MappedPoint getMappedPoint(vector<float, D-1> mapping);

    public Optional<IntersectedPoint> intersect(
        vector<float, D> origin,
        vector<float, D> dir,
        vector<float, D> invDir,
        float tmin = 0,
        float tmax = float.maxValue);

    //==========================================================================
    // Optionally overridable members
    //==========================================================================

    public Optional<float> intersectDist(
        vector<float, D> origin,
        vector<float, D> dir,
        vector<float, D> invDir,
        float tmin = 0,
        float tmax = float.maxValue)
    {
        let sp = intersect(origin, dir, invDir, tmin, tmax);
        if (!sp.hasValue)
            return none;
        return distance(origin, sp.value.getPosition(this));
    }

    public bool intersectBool(
        vector<float, D> origin,
        vector<float, D> dir,
        vector<float, D> invDir,
        float tmin = 0,
        float tmax = float.maxValue)
    {
        return intersectDist(origin, dir, invDir, tmin, tmax).hasValue;
    }

    public Optional<IntersectedPoint> intersect(Ray<D> ray, float tmin = 0, float tmax = float.maxValue)
    {
        return intersect(ray.origin, ray.direction, rcp(ray.direction), tmin, tmax);
    }

    public Optional<float> intersectDist(Ray<D> ray, float tmin = 0, float tmax = float.maxValue)
    {
        return intersectDist(ray.origin, ray.direction, rcp(ray.direction), tmin, tmax);
    }

    public bool intersectBool(Ray<D> ray, float tmin = 0, float tmax = float.maxValue)
    {
        return intersectDist(ray.origin, ray.direction, rcp(ray.direction), tmin, tmax).hasValue;
    }
}

public interface IVolume<let D: int>
{
    public void sampleVolume(
        vector<float, D> rnd,
        out vector<float, D> point,
        out float jacobian
    );
    public property float volume { get; }
}

public typealias ICurve = IHyperSurface<2>;
public typealias ISurface = IHyperSurface<3>;

public struct AABB<let D: int>: IHyperSurface<D>, IVolume<D>
{
    public vector<float, D> minBound;
    public vector<float, D> maxBound;

    public property vector<float, D> edges {
        get {
            return maxBound - minBound;
        }
    }

    public property vector<float, D> center {
        get {
            return (maxBound + minBound) * 0.5;
        }
        set {
            let r = radius;
            minBound = newValue - r;
            maxBound = newValue + r;
        }
    }

    public property vector<float, D> radius {
        get {
            return edges * 0.5;
        }
        set {
            let c = center;
            minBound = c - newValue;
            maxBound = c + newValue;
        }
    }

    public vector<float, D-1> side(int axis)
    {
        let e = edges;
        vector<float, D-1> s;
        [ForceUnroll]
        for (int i = 0; i < D-1; ++i)
            s[i] = e[i >= axis ? i+1 : i];
        return s;
    }

    public vector<float, D> sideCenter(int axis, int plus)
    {
        var origin = center;
        origin[axis] = origin[axis] + radius[axis] * plus;
        return origin;
    }

    [ForceInline]
    public float sideArea(int n)
    {
        let e = edges;
        float product = 1;
        [ForceUnroll]
        for (int j = 0; j < D; ++j)
        {
            if (j != n)
                product *= e[j];
        }
        return product;
    }

    public property float area {
        get {
            let e = edges;
            float sum = 0;
            [ForceUnroll]
            for (int i = 0; i < D; ++i)
                sum += sideArea(i);
            return 2*sum;
        }
    }

    public property float volume
    {
        get {
            let e = edges;
            float product = 1;
            [ForceUnroll]
            for (int i = 0; i < D; ++i)
                product *= e[i];
            return product;
        }
    }
    public property AABB<D> bounds { get { return this; } }

    public struct MappedPoint: ISurfacePoint<D, This>
    {
        public vector<float, D-1> mapping;
        public vector<float, D> getPosition(AABB<D> s)
        {
            int chosenFace = int(mapping[0]);
            int chosenAxis = chosenFace % D;
            int chosenSign = chosenFace < D ? -1 : 1;

            // Scale to [-1, 1]
            let u = 2.0 * frac(mapping) - 1.0;

            var p = s.center;
            let r = s.radius;
            [ForceUnroll]
            for (int i = 0; i < D; ++i)
            {
                float offset = i == chosenAxis ? chosenSign : u[i >= chosenAxis ? i+1 : i];
                p[i] = p[i] + offset * r[i];
            }
            return p;
        }

        public vector<float, D> getNormal(AABB<D> s)
        {
            int chosenFace = int(mapping[0]);
            int chosenAxis = chosenFace % D;
            int chosenSign = chosenFace < D ? -1 : 1;
            var normal = vector<float, D>(0);
            normal[chosenAxis] = chosenSign;
            return normal;
        }

        public vector<float, D-1> getMapping(AABB<D> s)
        {
            return mapping;
        }
    }
    public typealias SampledPoint = MappedPoint;

    public SampledPoint sampleSurface(vector<float, D-1> rnd, out float jacobian)
    {
        jacobian = area;
        var u = rnd;

        // Determine surface areas on each side, this is needed later for
        // uniform sampling. Larger edges/faces get proportionally more samples!
        vector<float, D> sideAreas;
        float sum = 0;
        [ForceUnroll]
        for (int i = 0; i < D; ++i)
        {
            float a = sideArea(i);
            sideAreas[i] = a;
            sum += a;
        }

        float invSum = 1.0f/sum;

        // Use the first random var to select which axis to sample. This is
        // normalized by the surface area of the sides, so that sampling is
        // uniform.
        int chosenAxis = 0;
        [ForceUnroll]
        for (int i = 0; i < D; ++i)
        {
            float a = sideAreas[i] * invSum;
            if (u[0] < a)
            {
                chosenAxis = i;
                u[0] = u[0] / a;
                break;
            }
            else u[0] = u[0] - a;
        }

        // Use the last random var to select whether to sample +axis or -axis
        int chosenSign = -1;
        const int last = D-2;
        if (u[last] > 0.5)
        {
            u[last] = u[last] - 0.5;
            chosenSign = 1;
        }
        u[last] = u[last] * 2.0f;

        // Identify chosen face in mapping
        var mapping = u;
        mapping[0] += (chosenSign < 0 ? 0 : D) + chosenAxis;

        jacobian = 2.0f * sum;
        return SampledPoint(mapping);
    }

    public MappedPoint getMappedPoint(vector<float, D-1> mapping)
    {
        return MappedPoint(mapping);
    }

    public void sampleVolume(
        vector<float, D> rnd,
        out vector<float, D> point,
        out float jacobian
    ){
        point = minBound + rnd * edges;
        jacobian = volume;
    }

    public struct IntersectedPoint: ISurfacePoint<D, This>
    {
        public int face;
        public vector<float, D> pos;
        public vector<float, D> getPosition(AABB<D> s)
        {
            return pos;
        }

        public vector<float, D> getNormal(AABB<D> s)
        {
            let uv = (pos - s.minBound) / s.edges;
            int chosenAxis = face % D;
            int chosenSign = face < D ? -1 : 1;
            var normal = vector<float, D>(0);
            normal[chosenAxis] = chosenSign;
            return normal;
        }

        public vector<float, D-1> getMapping(AABB<D> s)
        {
            let uv = (pos - s.minBound) / s.edges;
            int chosenAxis = face % D;
            int chosenSign = face < D ? -1 : 1;

            vector<float, D-1> mapping;
            [ForceUnroll]
            for (int i = 0; i < D-1; ++i)
                mapping[i] = uv[i >= chosenAxis ? i+1 : i];
            mapping[0] += chosenAxis + (chosenSign < 0 ? 0 : 3);
            return mapping;
        }
    }

    public override Optional<IntersectedPoint> intersect(
        vector<float, D> origin,
        vector<float, D> dir,
        vector<float, D> invDir,
        float tmin,
        float tmax)
    {
        let t0 = (minBound - origin) * invDir;
        let t1 = (maxBound - origin) * invDir;
        let mins = min(t0,t1);
        let maxs = max(t0,t1);
        float near = mins[0];
        float far = maxs[0];
        [ForceUnroll]
        for (int i = 1; i < D; ++i)
        {
            near = max(near, mins[i]);
            far = min(far, maxs[i]);
        }
        if(near <= far && far > tmin && near < tmax)
        {
            float t = near > tmin ? near : far;
            int face = 0;
            [ForceUnroll]
            for (int i = 0; i < D; ++i)
            {
                if (t == t0[i]) face = i;
                if (t == t1[i]) face = i+D;
            }
            return IntersectedPoint(face, origin + t * dir);
        }
        return none;
    }

    private float2 intersectionCandidates(
        vector<float, D> origin,
        vector<float, D> dir,
        vector<float, D> invDir
    ){
        let t0 = (minBound - origin) * invDir;
        let t1 = (maxBound - origin) * invDir;
        let mins = min(t0,t1);
        let maxs = max(t0,t1);
        float near = mins[0];
        float far = maxs[0];
        [ForceUnroll]
        for (int i = 1; i < D; ++i)
        {
            near = max(near, mins[i]);
            far = min(far, maxs[i]);
        }
        return float2(near, far);
    }

    public override Optional<float> intersectDist(
        vector<float, D> origin,
        vector<float, D> dir,
        vector<float, D> invDir,
        float tmin,
        float tmax
    ){
        float2 nf = intersectionCandidates(origin, dir, invDir);
        float near = nf.x;
        float far = nf.y;
        if(near <= far && far > tmin && near < tmax)
            return near > tmin ? near : far;
        return none;
    }

    public override bool intersectBool(
        vector<float, D> origin,
        vector<float, D> dir,
        vector<float, D> invDir,
        float tmin,
        float tmax)
    {
        float2 nf = intersectionCandidates(origin, dir, invDir);
        float near = nf.x;
        float far = nf.y;
        if(near <= far && far > tmin && near < tmax)
            return true;
        return false;
    }
}

public typealias AABB2 = AABB<2>;
public typealias AABB3 = AABB<3>;

}
