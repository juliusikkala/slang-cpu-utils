import list;
import time;

static const uint PARAM_COUNT = 3;
static const double2 FIT_RANGE = double2(-double.getPi(), double.getPi());
static const int FIT_SAMPLES = 1024;

double targetFunction(double x)
{
    return sin(x)/x;
}

[Differentiable]
double fitFunction(double x, double params[PARAM_COUNT])
{
    return params[1] * cos(x) + sqrt(params[0]*x*x + params[2]);
}

[Differentiable]
double lossL2(no_diff List<double> samples, double params[PARAM_COUNT])
{
    double sumLoss = 0;
    for (int i = 0; i < FIT_SAMPLES; ++i)
    {
        double u = double(i) / double(FIT_SAMPLES-1);
        double x = lerp(FIT_RANGE[0], FIT_RANGE[1], u);
        double sample = no_diff samples[i];
        double loss = sample - fitFunction(x, params);
        sumLoss += loss * loss;
    }
    return sqrt(sumLoss / FIT_SAMPLES);
}

double gradientDescent(
    List<double> samples,
    inout double bestParams[PARAM_COUNT],
    uint iterations = 100000,
    double learningRate = 0.001
){
    double bestLoss = lossL2(samples, bestParams);
    double params[PARAM_COUNT] = bestParams;
    for (uint i = 0; i < iterations; ++i)
    {
        DifferentialPair<double[PARAM_COUNT]> diffParams = diffPair(params);

        bwd_diff(lossL2)(samples, diffParams, 1.0);

        for(uint i = 0; i < PARAM_COUNT; ++i)
            params[i] -= learningRate * diffParams.d[i];

        double loss = lossL2(samples, params);
        if(loss < bestLoss)
        {
            bestLoss = loss;
            bestParams = params;
        }
    }
    return bestLoss;
}

export __extern_cpp int main(int argc, Ptr<NativeString> argv)
{
    List<double> samples;
    defer samples.drop();
    samples.resize(FIT_SAMPLES);

    for (int i = 0; i < FIT_SAMPLES; ++i)
    {
        double u = double(i) / double(FIT_SAMPLES-1);
        double x = lerp(FIT_RANGE[0], FIT_RANGE[1], u);
        samples[i] = targetFunction(x);
    }

    double params[PARAM_COUNT];
    for (int i = 0; i < PARAM_COUNT; ++i)
        params[i] = 1;

    let start = getTicks();
    printf("Initial LOSS: %f\n", lossL2(samples, params));
    double loss = gradientDescent(samples, params);
    let end = getTicks();
    printf("Time taken: %f ms\n", (end-start).milliseconds);

    printf("LOSS: %f\n", loss);
    for(int i = 0; i < PARAM_COUNT; ++i)
        printf("params[%d] = %f\n", i, params[i]);

    return 0;
}
