namespace scul
{

public struct Ray<let D: int>
{
    public vector<float, D> origin;
    public vector<float, D> direction;
}

public typealias Ray2 = Ray<2>;
public typealias Ray3 = Ray<2>;

public interface IHyperSurface<let D: int>
{
    public property float area { get; }
    public property AABB<D> bounds { get; }

    // "jacobian" is actually the absolute jacobian determinant here. If the pdf
    // of `u` is 1, then the PDF after this sampling is 1.0/jacobian.
    public void sampleSurface(
        vector<float, D-1> rnd,
        out vector<float, D> point,
        out float jacobian
    );
    public Optional<float> intersect(vector<float, D> origin, vector<float, D> invDir, float tmin = 0);
    public Optional<float> intersect(Ray<D> ray)
    {
        return intersect(ray.origin, rcp(ray.direction));
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

    public void sampleSurface(
        vector<float, D-1> rnd,
        out vector<float, D> point,
        out float jacobian
    ){
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

        // Scale to [-1, 1]
        u = 2.0 * u - 1.0;

        point = center;
        let r = radius;
        [ForceUnroll]
        for (int i = 0; i < D; ++i)
        {
            float offset = i == chosenAxis ? chosenSign : u[i >= chosenAxis ? i+1 : i];
            point[i] = point[i] + offset * r[i];
        }

        jacobian = 2.0f * sum;
    }

    public void sampleVolume(
        vector<float, D> rnd,
        out vector<float, D> point,
        out float jacobian
    ){
        point = minBound + rnd * edges;
        jacobian = volume;
    }

    public Optional<float> intersect(vector<float, D> origin, vector<float, D> invDir, float tmin)
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

        if(near <= far && far > tmin)
            return near > tmin ? near : far;
        return none;
    }
}

public typealias AABB2 = AABB<2>;
public typealias AABB3 = AABB<3>;

}
