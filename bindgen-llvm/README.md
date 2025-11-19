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

* `--target-triple <triple>` sets the LLVM target triple used to resolve calling conventions of functions with aggregate parameters.
* `--output <output-file>` writes the bindings to the given file. If not specified, bindings are printed to `stdout`.
* `--namespace <ns>` puts the bindings in the given namespace.
* `--using <ns>` adds a `using ns;` at the start.
* `--import <module>` adds a `import module;` at the start.
* `--imported <header>` marks declarations from a C header as already included through an `--import`ed module.
* `--define <name>=<value>` uses the given preprocessor macro when parsing headers.
* `--include-dir <path>` adds the given include path parsing headers.
* `--unscoped-enums <regex>` uses unscoped enums for the listed types.
* `--rm-enum-prefix <regex>` removes a prefix from all enum cases if it's common to all cases in the enum. For a regex, the longest matching and present prefix is removed.
* `--rm-enum-case <regex>` removes matching cases from all enums.
* `--fallback-prefix <str>` adds the given prefix to all enum case names that would not be valid in Slang.
* `--use-byte-bool` uses `uint8_t` instead of bool. Useful when overriding default layout to something where `sizeof(bool) != 1`.

## How it's made

This section is only relevant to you if you are planning to modify the binding
generator itself or are wondering how the output is derived. Usually, you don't
need to consider these details when using the bindings; they should be usable
as if you were writing C instead of Slang.

### Basic types

`bool` is difficult. In the LLVM and C memory layouts, Slang uses a byte for it.
In std430 & scalar layout, it's 4 bytes. Hence, you can use `--use-byte-bool`
to make `_Bool` translate to `uint8_t`, but `_Bool => bool` by default.

Integers and floats behave as one would expect. Note that the resulting bindings
are platform-dependent due to the size of `wchar_t` and `long` changing between
platforms. They get translated to the equivalent sized types.

### Structs

Structs are usually translated 1:1, although e.g. anonymous struct members
are flattened and some padding is generated as needed to match C's alignment
rules for such members.

### Unions

Unions are implemented with `property` and `reinterpret` spam. They only contain
an array of the appropriate alignment, and all actual members are implemented
with `property` reinterpreting the data from that array.

### Enums

Nothing particularly odd here. Unnamed enum types are lowered as global constants.

### Typedefs

Straightforward 1:1 match with C.

### Macros

Support for C macros is limited. Because such macros cannot be exported from
a Slang module, they are instead handled with some interpretation: if a
`#define` is clearly just a constant, it is emitted as a global constant value.

Functional macros are omitted for now.

### Pointers

`const` pointers are turned into non-const due to Slang not supporting const
pointers. An exception to this is `const char*`, which is translated as
`NativeString`, while `char*` is just `int8_t*`.

Function pointers are translated as `Ptr<void>` because Slang doesn't have
function pointers. Variadic arguments are not supported for now.

### Functions

Functions are generally forward-declared with `__extern_cpp`, but only when the
Slang's LLVM ABI matches the C ABI. This is not the case when passing or
returning structs; in that case, a complicated adapter function is generated
using Clang. Luckily, most high-profile C APIs don't pass structs by value.
