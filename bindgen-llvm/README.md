Slang LLVM Bindgen
==================

This tool generates Slang bindings for C libraries. This allows you to use C
libraries from Slang code on the LLVM targets.

## Usage

```sh
slang-bindgen [list of C headers] --output mylibrarybindings.slang
```

Declarations from the listed C headers are included, as well as type
declarations from dependency includes from those headers. If you want bindings
for a multi-header library, you need to list all of the headers of that library.

Options:
* `--namespace <ns>` puts everything in the given namespace
* `--using <ns>` adds a `using ns;` at the start (to be used in conjunction with `--namespace` and `--import`)
* `--import <module>` makes the result bindings import a Slang module
* `--imported <header>` marks declarations from a C header as already included through a `--import` module
* `--define A=B` use a preprocessor define when parsing headers
* `--include-dir <path>` use the given include paths when parsing headers
* `--output <output-file>` write the bindings to the given file.
* `--unscoped-enums <enum-type-name>` uses unscoped enums for the listed types. Supports regular expressions.
* `--rm-enum-prefix <prefix-regex>` removes given prefixes from all enum cases, but only if they are truly common to each case in that enum. Regular expressions are supported, only the matching part is removed from the longest prefix that is common to all cases.
* `--fallback-prefix <string>` adds a string prefix to all enums that would otherwise not be legal identifiers due to e.g. starting with a number.
* `--rm-enum-case <enum-case>` removes a case with the given name from all enums, which is useful for removing potentially unwanted entries like `ENUM_COUNT` etc.

## How it's made

This section is only relevant to you if you are planning to modify the binding
generator itself or are wondering how the output is derived. Usually, you don't
need to consider these details when using the bindings; they should be usable
as if you were writing C instead of Slang.

### Basic types

`bool` is difficult. In the LLVM and C memory layouts, Slang uses a byte for it.
In std430 & scalar layout, it's 4 bytes. Hence, the user is given an option of
how to handle them, with `bool -> bool` as default and `bool -> uint8_t` as an
option.

Integers and floats behave as one would expect. `const char*` is translated as
`NativeString`, while `char*` is just `int8_t*`.

### Structs

Structs are usually translated 1:1, except that they're manually padded to
minimize the risk of layout issues when a non-default layout is used. Padding
entries are set to private and a constructor is generated skipping those
paddings.

An exception to this are bitfields; they generate `property` members to the
struct that dig out the bitfield data.

### Unions

Unions are implemented with `property` spam. They only contain an array of the
appropriate alignment, and all actual members are implemented with `property`
reinterpreting the data from that array.

### Enums

Nothing difficult there.

### Typedefs

Nothing difficult here either.

### Macros

Support for C macros is limited. Because such macros cannot be exported from
a Slang module, they are instead handled with some interpretation: if a
`#define` is clearly just a constant, it is emitted as a global constant value.

Functional macros are omitted for now.

### Pointers

`const` pointers are turned into non-const due to Slang not supporting const
pointers.

Function pointers are translated as `Ptr<void>` because Slang doesn't have
function pointers. Variadic arguments are not supported for now.

### Functions

Functions are generally forward-declared with `__extern_cpp`, but only when the
Slang's LLVM ABI matches the C ABI. This is not the case when passing or
returning structs; in that case, an adapter function is generated using Clang:

```
// C header code:
MyStruct func(MyStruct val);

// Slang bindings:
[ForceInline]
void funcAdapter(MyStruct* val, MyStruct* returnval)
{
    __requirePrelude(R"(declare i64 @func(i64))");
    __intrinsic_asm R"(
      %0 = load i64, $0, align 4
      %call = tail call i64 @func(i64 %0)
      store i64 %call, $1, align 4
      ret void
    )";
}

[ForceInline]
public MyStruct func(MyStruct val)
{
    MyStruct returnval;
    funcAdapter(&val, &returnval);
    return returnval;
}
```
