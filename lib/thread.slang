import platform;
import memory;
import drop;

struct WorkerData<each T>
{
    void* callback;
    Tuple<expand each T> params;

    static void call(void* callback, inout Tuple<expand each T> params)
    {
        __intrinsic_asm "((void(*)(decltype($1)))($0))($1)";
    }
};

void* funcPtr<T>(T worker)
{
    __intrinsic_asm "(void*)($0)";
}

#ifdef SLANG_PLATFORM_WIN32
// Due to complications with including windows.h, this just uses the C++
// standard library threads.
typealias thread_t = Ptr<void>; //std::thread*
typealias thread_mutex_t = Ptr<void>;//std::mutex*

thread_t thread_create_helper<T>(T worker, void* userdata)
{
    __requirePrelude("#include <thread>");
    __intrinsic_asm "(void*)(new std::thread($0, $1))";
}

void thread_join_helper(thread_t id)
{
    __intrinsic_asm "((std::thread*)$0)->join(); delete ((std::thread*)$0);";
}

thread_mutex_t thread_mutex_init_helper()
{
    __intrinsic_asm "(void*)(new std::mutex())";
}

void thread_mutex_lock(thread_mutex_t mutex)
{
    __intrinsic_asm "((std::mutex*)$0)->lock()";
}

bool thread_mutex_trylock(thread_mutex_t mutex)
{
    __intrinsic_asm "((std::mutex*)$0)->try_lock()";
}

void thread_mutex_unlock(thread_mutex_t mutex)
{
    __intrinsic_asm "((std::mutex*)$0)->unlock()";
}

void thread_mutex_destroy_helper(thread_mutex_t mutex)
{
    __intrinsic_asm "delete (std::mutex*)$0";
}

__extern_cpp void workerDispatcher<each T>(void* data)
{
    if(!data) return;

    WorkerData<expand each T>* wdata = Ptr<WorkerData<expand each T>>(data);

    wdata.call(wdata.callback, wdata.params);

    deallocate(wdata);
}

public uint64_t startThread<T, each P>(T t, expand each P args)
{
    thread_t id = nullptr;
    WorkerData<expand each P>* userdata = allocate<WorkerData<expand each P>>(1);
    userdata.callback = funcPtr(t);
    userdata.params = makeTuple(expand each args);
    thread_t addr = thread_create_helper(workerDispatcher<expand each P>, Ptr<void>(userdata));
    return reinterpret<uint64_t>(addr);
}

public void joinThread(uint64_t id)
{
    thread_t threadId = reinterpret<thread_t>(id);
    thread_join_helper(threadId);
}

public struct Mutex: IDroppable
{
    thread_mutex_t mutex;
    bool valid;

    public __init()
    {
        zeroInitialize(mutex);
        mutex = thread_mutex_init_helper();
        valid = true;
    }

    [mutating]
    public void drop()
    {
        if(!valid)
            return;
        thread_mutex_destroy_helper(mutex);
	mutex = nullptr;
        valid = false;
    }

    [mutating]
    public void lock()
    {
        if(valid)
            thread_mutex_lock(mutex);
    }

    [mutating]
    public bool tryLock()
    {
        if(valid)
        {
            int ret = thread_mutex_trylock(mutex);
            return ret == 0;
        }
        return false;
    }

    [mutating]
    public void unlock()
    {
        if(valid)
            thread_mutex_unlock(mutex);
    }
}
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

__extern_cpp void* workerDispatcher<each T>(void* data)
{
    if(!data) return nullptr;

    WorkerData<expand each T>* wdata = Ptr<WorkerData<expand each T>>(data);

    wdata.call(wdata.callback, wdata.params);

    deallocate(wdata);
    return nullptr;
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
