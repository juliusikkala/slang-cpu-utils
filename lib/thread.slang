import platform;
import memory;
import drop;

#ifdef SLANG_PLATFORM_WIN32
// TODO: Threads not implemented on win32 yet!
#else
typealias pthread_t = ulong;
typealias pthread_mutex_t = ulong[16];

int pthread_create_helper<T>(pthread_t* id, T worker, void* userdata)
{
    __requirePrelude("#include <pthread.h>");
    __intrinsic_asm "pthread_create($0, nullptr, $1, $2)";
}

int pthread_join_helper(pthread_t id, void** retval)
{
    __intrinsic_asm "pthread_join($0, $1)";
}

int pthread_mutex_init_helper(pthread_mutex_t* mutex)
{
    __intrinsic_asm "pthread_mutex_init((pthread_mutex_t*)$0, nullptr)";
}

int pthread_mutex_lock(pthread_mutex_t* mutex)
{
    __intrinsic_asm "pthread_mutex_lock((pthread_mutex_t*)$0)";
}

int pthread_mutex_trylock(pthread_mutex_t* mutex)
{
    __intrinsic_asm "pthread_mutex_trylock((pthread_mutex_t*)$0)";
}

int pthread_mutex_unlock(pthread_mutex_t* mutex)
{
    __intrinsic_asm "pthread_mutex_unlock((pthread_mutex_t*)$0)";
}

int pthread_mutex_destroy_helper(pthread_mutex_t* mutex)
{
    __intrinsic_asm "pthread_mutex_destroy((pthread_mutex_t*)$0)";
}

struct WorkerData<each T>
{
    void* callback;
    Tuple<expand each T> params;

    static void call(void* callback, inout Tuple<expand each T> params)
    {
        __intrinsic_asm "((void(*)(decltype($1)))($0))($1)";
    }
};

__extern_cpp void* workerDispatcher<each T>(void* data)
{
    if(!data) return nullptr;

    WorkerData<expand each T>* wdata = Ptr<WorkerData<expand each T>>(data);

    wdata.call(wdata.callback, wdata.params);

    deallocate(wdata);
    return nullptr;
}

void* funcPtr<T>(T worker)
{
    __intrinsic_asm "(void*)($0)";
}

public uint64_t startThread<T, each P>(T t, expand each P args)
{
    pthread_t id = 0;
    WorkerData<expand each P>* userdata = allocate<WorkerData<expand each P>>(1);
    userdata.callback = funcPtr(t);
    userdata.params = makeTuple(expand each args);
    pthread_create_helper(&id, workerDispatcher<expand each P>, Ptr<void>(userdata));
    return id;
}

public void joinThread(uint64_t id)
{
    pthread_t threadId = id;
    void* retval = nullptr;
    pthread_join_helper(threadId, &retval);
}

public struct Mutex: IDroppable
{
    pthread_mutex_t mutex;
    bool valid;

    public __init()
    {
        zeroInitialize(mutex);
        pthread_mutex_init_helper(&mutex);
        valid = true;
    }

    [mutating]
    public void drop()
    {
        if(!valid)
            return;
        pthread_mutex_destroy_helper(&mutex);
        valid = false;
    }

    [mutating]
    public void lock()
    {
        if(valid)
            pthread_mutex_lock(&mutex);
    }

    [mutating]
    public bool tryLock()
    {
        if(valid)
        {
            int ret = pthread_mutex_trylock(&mutex);
            return ret == 0;
        }
        return false;
    }

    [mutating]
    public void unlock()
    {
        if(valid)
            pthread_mutex_unlock(&mutex);
    }
}
#endif
