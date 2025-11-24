import memory;
import drop;
import crt;

struct WorkerData<each T>
{
    void* callback;
    Tuple<expand each T> params;

    static void call(void* callback, inout Tuple<expand each T> params)
    {
        __intrinsic_asm "call void $_0($1)\nret void";
    }
};

void* funcPtr<T>(T worker)
{
    __intrinsic_asm "ret $0";
}

#ifdef SLANG_PLATFORM_WIN32
// TODO
#else

__extern_cpp int workerDispatcher<each T>(void* data)
{
    if(!data) return 0;

    WorkerData<expand each T>* wdata = Ptr<WorkerData<expand each T>>(data);

    wdata.call(wdata.callback, wdata.params);

    deallocate(wdata);
    return 0;
}

public uint64_t startThread<T, each P>(T t, expand each P args)
{
    C.thrd_t id = 0;
    WorkerData<expand each P>* userdata = allocate<WorkerData<expand each P>>(1);
    userdata.callback = funcPtr(t);
    userdata.params = makeTuple(expand each args);
    C.thrd_create(&id, funcPtr(workerDispatcher<expand each P>), Ptr<void>(userdata));
    return id;
}

public void joinThread(uint64_t id)
{
    C.thrd_t threadId = id;
    int retval = 0;
    C.thrd_join(threadId, &retval);
}

public struct Mutex: IDroppable
{
    C.mtx_t mutex;
    bool valid;

    public __init()
    {
        zeroInitialize(mutex);
        C.mtx_init(&mutex, C.MutexPlain);
        valid = true;
    }

    [mutating]
    public void drop()
    {
        if(!valid)
            return;
        C.mtx_destroy(&mutex);
        valid = false;
    }

    [mutating]
    public void lock()
    {
        if(valid)
            C.mtx_lock(&mutex);
    }

    [mutating]
    public bool tryLock()
    {
        if(valid)
        {
            int ret = C.mtx_trylock(&mutex);
            return ret == 0;
        }
        return false;
    }

    [mutating]
    public void unlock()
    {
        if(valid)
            C.mtx_unlock(&mutex);
    }
}
#endif
