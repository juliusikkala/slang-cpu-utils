namespace scul
{

public enum SerializationError
{
    Output = 0,
    Input,
};

public interface IOutputStream
{
    [mutating]
    internal void writeBuiltin(bool value) throws SerializationError;
    [mutating]
    internal void writeBuiltin<T: __BuiltinArithmeticType>(T value) throws SerializationError;
    [mutating]
    void write<S : ISerializable>(S value) throws SerializationError
    {
        try value.write(this);
    }
}

public interface IInputStream
{
    [mutating]
    internal void readBuiltin(inout bool value) throws SerializationError;
    [mutating]
    internal void readBuiltin<T: __BuiltinArithmeticType>(inout T value) throws SerializationError;
    [mutating]
    void read<S : ISerializable>(inout S value) throws SerializationError
    {
        try value.read(this);
    }
}

public interface ISerializer
{
    property bool output { get; }

    [mutating]
    void serialize(inout bool value) throws SerializationError;
    [mutating]
    void serialize<T: __BuiltinArithmeticType>(inout T value) throws SerializationError;

    [mutating]
    void serialize<S : ISerializable>(inout S value) throws SerializationError;
}

public extension<T: IOutputStream> T : ISerializer
{
    property bool output { get { return true; } }

    [mutating]
    void serialize(inout bool value) throws SerializationError
    {
        try writeBuiltin(value);
    }

    [mutating]
    void serialize<T: __BuiltinArithmeticType>(inout T value) throws SerializationError
    {
        try writeBuiltin(value);
    }

    [mutating]
    void serialize<S : ISerializable>(inout S value) throws SerializationError
    {
        try write(value);
    }
}

public extension<T: IInputStream> T : ISerializer
{
    property bool output { get { return true; } }

    [mutating]
    void serialize(inout bool value) throws SerializationError
    {
        try readBuiltin(value);
    }

    [mutating]
    void serialize<T: __BuiltinArithmeticType>(inout T value) throws SerializationError
    {
        try readBuiltin(value);
    }

    [mutating]
    void serialize<S : ISerializable>(inout S value) throws SerializationError
    {
        try read(value);
    }
}

public interface ISerializable
{
    [mutating]
    void write<A: IOutputStream>(inout A ar) throws SerializationError
    {
        try serialize(ar);
    }

    [mutating]
    void read<A: IInputStream>(inout A ar) throws SerializationError
    {
        try serialize(ar);
    }

    [mutating]
    void serialize<A: ISerializer>(inout A ar) throws SerializationError
    {
        try ar.serialize(this);
    }
}

public extension bool: ISerializable
{
    [mutating]
    override void write<A: IOutputStream>(inout A ar) throws SerializationError
    {
        try ar.writeBuiltin(this);
    }

    [mutating]
    override void read<A: IInputStream>(inout A ar) throws SerializationError
    {
        try ar.readBuiltin(this);
    }
}

public extension<T : __BuiltinArithmeticType> T: ISerializable
{
    [mutating]
    override void write<A: IOutputStream>(inout A ar) throws SerializationError
    {
        try ar.writeBuiltin<T>(this);
    }

    [mutating]
    override void read<A: IInputStream>(inout A ar) throws SerializationError
    {
        try ar.readBuiltin<T>(this);
    }
}

public extension<T : __BuiltinArithmeticType, let N:int> vector<T, N>: ISerializable
{
    [mutating]
    override void write<A: IOutputStream>(inout A ar) throws SerializationError
    {
        for (int i = 0; i < N; ++i)
            try ar.write(this[i]);
    }

    [mutating]
    override void read<A: IInputStream>(inout A ar) throws SerializationError
    {
        for (int i = 0; i < N; ++i)
        {
            T element;
            try ar.read(element);
            this[i] = element;
        }
    }

    [mutating]
    override void serialize<A: ISerializer>(inout A ar) throws SerializationError
    {
        try ar.serialize(this);
    }
}

public extension<T : __BuiltinArithmeticType, let R : int, let C : int, let L : int> matrix<T, R, C, L> : ISerializable
{
    [mutating]
    override void write<A: IOutputStream>(inout A ar) throws SerializationError
    {
        for (int i = 0; i < R; ++i)
            try ar.write(this[i]);
    }

    [mutating]
    override void read<A: IInputStream>(inout A ar) throws SerializationError
    {
        for (int i = 0; i < R; ++i)
        {
            var row = this[i];
            try ar.read(row);
            this[i] = row;
        }
    }

    [mutating]
    override void serialize<A: ISerializer>(inout A ar) throws SerializationError
    {
        try ar.serialize(this);
    }
}

public extension<T : ISerializable> Optional<T>: ISerializable
{
    [mutating]
    override void write<A: IOutputStream>(inout A ar) throws SerializationError
    {
        try ar.write(this.hasValue);
        if (hasValue)
            try ar.write(this.value);
    }

    [mutating]
    override void read<A: IInputStream>(inout A ar) throws SerializationError
    {
        bool hasValue;
        try ar.read(hasValue);
        if (hasValue)
        {
            T element = T();
            try ar.read(element);
            this = element;
        }
        else this = none;
    }

    [mutating]
    override void serialize<A: ISerializer>(inout A ar) throws SerializationError
    {
        try ar.serialize(this);
    }
}

}
