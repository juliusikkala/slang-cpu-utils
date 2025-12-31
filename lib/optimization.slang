import drop;
import memory;
import list;
import span;

namespace scul
{

// Must read parameter values from first param 'w' and write derivates to second
// param 'dw'. The returned value is interpreted as loss after this step, but
// you can also return -1 if you somehow don't have that info.
typealias OptimizationStepFunc = IFunc<double, Span<double> /*w*/, Span<double> /*dw*/>;

public interface IOptimizer
{
    [mutating]
    void begin(Span<double> params) {}
    [mutating]
    void update(Span<double> params, Span<double> gradients);
}

public struct GradientDescentOptimizer: IOptimizer
{
    double _learningRate;

    public __init(double learningRate = 0.01)
    {
        _learningRate = learningRate;
    }

    [mutating]
    void update(Span<double> params, Span<double> gradients)
    {
        for(size_t i = 0; i < gradients.count; ++i)
            params[i] -= _learningRate * gradients[i];
    }
}

public struct AdamOptimizer: IOptimizer, IDroppable
{
    List<double> _m;
    List<double> _v;
    double _learningRate;
    double _beta1;
    double _beta2;
    int iter;

    public __init(double learningRate = 0.001, double beta1 = 0.9, double beta2 = 0.99)
    {
        _m = List<double>();
        _v = List<double>();
        _learningRate = learningRate;
        _beta1 = beta1;
        _beta2 = beta2;

        iter = 0;
    }

    [mutating]
    public void drop()
    {
        _m.drop();
        _v.drop();
    }

    [mutating]
    override void begin(Span<double> params)
    {
        _m.resize(params.count, 0);
        _v.resize(params.count, 0);

        iter = 0;
    }

    [mutating]
    void update(Span<double> params, Span<double> gradients)
    {
        iter++;
        for(size_t i = 0; i < gradients.count; ++i)
        {
            double d = gradients[i];
            _m[i] = lerp(d, _m[i], _beta1);
            _v[i] = lerp(d*d, _v[i], _beta2);
            double mhat = _m[i] / (1-pow(_beta1, iter));
            double vhat = _v[i] / (1-pow(_beta2, iter));
            params[i] -= _learningRate * mhat / (sqrt(vhat)+1e-8);
        }
    }
}

public double optimize<O: IOptimizer, F: OptimizationStepFunc>(
    Span<double> params,
    O optimizer,
    F stepFunc,
    uint maxSteps = 1000,
    uint printLossEverySteps = 0
){
    List<double> gradients;
    gradients.resize(params.count, 0);
    defer gradients.drop();

    List<double> w;
    w.insert(0, params);
    defer w.drop();

    optimizer.begin(w.span);

    double bestLoss = -1.0f;
    uint printStepCounter = 0;

    for (uint i = 0; i < maxSteps; ++i)
    {
        double loss = stepFunc(w.span, gradients.span);
        if (loss <= bestLoss || bestLoss < 0)
        {
            bestLoss = loss;
            copyBytes(Ptr<void>(params.data), Ptr<void>(w.data), sizeof(double) * params.count);
        }

        printStepCounter++;
        if (loss > 0 && printLossEverySteps != 0 && printStepCounter == printLossEverySteps)
        {
            printStepCounter = 0;
            printf("(Step %u) loss: %f, best loss %f\n", i+1, loss, bestLoss);
        }
        optimizer.update(w.span, gradients.span);
    }
    return bestLoss;
}

}
