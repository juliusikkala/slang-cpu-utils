import time;
import drop;
import list;
import memory;
import thread;
import test;

struct WorkerData
{
    Mutex mut;
    List<int> data;

    __init() {}
};

// This MUST be 'inout Tuple<args that you gave startThread>', otherwise you'll
// get undefined garbage!
void worker(inout Tuple<Ptr<WorkerData>, int> data)
{
    Ptr<WorkerData> wd = data._0;
    int id = data._1;
    sleep(0.5);

    for (int i = 0; i < 1000; ++i)
    {
        wd.mut.lock();
        wd.data.push(2*i+id);
        wd.mut.unlock();
    }
}

export __extern_cpp int main(int argc, Ptr<NativeString> argv)
{
    WorkerData data;
    defer data.mut.drop();

    uint64_t t0 = startThread(worker, &data, 0);
    uint64_t t1 = startThread(worker, &data, 1);

    joinThread(t0);
    joinThread(t1);

    test(data.data.size == 2000, "thread 1");

    int sum = 0;
    for (size_t i = 0; i < data.data.size; ++i)
        sum += data.data[i];
    test(sum == 1999000, "thread 2");
    return 0;
}
