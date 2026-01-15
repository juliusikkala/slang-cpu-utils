import string;
import list;
import drop;

namespace scul
{

public enum CSVError
{
    OK = 0,
    PARSE_FAIL_RAGGED_EDGE
}

public struct CSV: IDroppable
{
    U8String _data;
    // Field byte offsets to the CSV data.
    List<Tuple<size_t, size_t>> _fields;
    size_t _cols;
    size_t _rows;
    uint8_t _separator;

    public __init(size_t cols, uint8_t separator = ',')
    {
        _data = U8String();
        _fields = List<Tuple<size_t, size_t>>();
        _cols = cols;
        _rows = 0;
        _separator = separator;
    }

    [mutating]
    public void drop()
    {
        _data.drop();
        _fields.drop();
    }

    public property size_t rows { get { return _rows; } }
    public property size_t cols { get { return _cols; } }
    public property StringSlice text { get { return _data.slice(0, _data.len); } }
    public property NativeString cStr { get { return _data.cStr; } }

    public __subscript(size_t row, size_t column) -> StringSlice
    {
        get {
            Tuple<size_t, size_t> offsetLen = _fields[column + row * _cols];
            return _data.slice(offsetLen._0, offsetLen._1);
        }
    }

    [mutating]
    public void push<T: IU8String>(T str)
    {
        _fields.push(makeTuple(_data.len, str.len));
        _data.append(str);
        size_t nextCol = _fields.size % _cols;
        if (nextCol == 0)
            _data.appendChar('\n');
        else
            _data.appendChar(_separator);
    }

    public static CSV parse<T: IU8String>(T str, uint8_t separator = ',') throws CSVError
    {
        var res = CSV(0, separator);

        res._data = U8String(str);

        // Ensure we end with a newline, the parsing actually depends on this.
        if (res._data.len > 0 && res._data[res._data.len-1] != '\n')
            res._data.appendChar('\n');

        size_t begin = 0;
        size_t nonTrailingLen = 0;
        size_t trailingLen = 0;

        size_t offset = 0;
        size_t len = res._data.len;
        size_t col = 0;

        while (offset < len)
        {
            uint8_t c = res._data[offset];
            offset++;
            if (c == separator || c == '\n')
            {
                res._fields.push(makeTuple(begin, nonTrailingLen));

                begin = offset;
                nonTrailingLen = 0;
                trailingLen = 0;

                if (c == '\n')
                {
                    if (res._rows == 0)
                    {
                        res._cols = col+1;
                    }
                    else if (col+1 != res._cols)
                    {
                        res.drop();
                        throw CSVError.PARSE_FAIL_RAGGED_EDGE;
                    }
                    col = 0;
                    res._rows++;
                }
                else
                {
                    col++;
                    if (res._rows != 0 && col >= res._cols)
                    {
                        res.drop();
                        throw CSVError.PARSE_FAIL_RAGGED_EDGE;
                    }
                }
            }
            else if (nonTrailingLen == 0 && c == ' ')
            {
                // Skip leading spaces
                begin++;
            }
            else
            {
                // Skip trailing spaces by tracking full length including
                // them, but only committing on non-space chars.
                trailingLen++;
                if (c != ' ')
                {
                    nonTrailingLen = trailingLen;
                }
            }
        }

        if (col != 0)
        {
            res.drop();
            throw CSVError.PARSE_FAIL_RAGGED_EDGE;
        }

        return res;
    }
}

}
