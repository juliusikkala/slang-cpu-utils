Slang Bindgen
=============

This tool allows generating Slang bindings to C libraries.

## Why

It's technically possible to avoid needing bindings altogether by using the 
various [interop techniques available in Slang.](https://shader-slang.org/slang/user-guide/a1-04-interop.html)

However, doing so is very error-prone and unergonomic. With bindings, you can
interact with C libraries as if they were Slang libraries.

## Setup

You need to install libclang on your system. Then,
```sh
virtualenv venv
source venv/bin/activate
pip install -r requirements.txt
```

## Usage

```sh
./bindgen.py [list of C headers] --output mylibrarybindings.slang
```

There are also a couple of options available.

* `--namespace <ns>` puts everything in a namespace
* `--using <ns>` adds a `using ns;` at the start (to be used in conjunction with `--namespace` and `--import`
* `--import <module>` makes the result bindings import a Slang module
* `--imported <header>` marks declarations from a C header as already included through a `--import` module
* `--define A=B` use a preprocessor define when parsing headers
* `--include-dir <path>` use the given include paths when parsing headers
* `--output <output-file>` write the bindings to the given file.
* `--unscoped-enums <enum-type-name>` uses unscoped enums for the listed types. Supports regular expressions.
* `--remove-common-enum-prefix <prefix-regex>` removes given prefixes from all enum cases, but only if they are truly common to each case in that enum. Regular expressions are supported, only the matching part is removed from the longest prefix that is common to all cases.
* `--enum-safe-prefix <string>` adds a string prefix to all enums that would otherwise not be legal identifiers due to e.g. starting with a number.
* `--remove-enum-case <enum-case>` removes a case with the given name from all enums. This purely exists to nuke `VK_COLORSPACE_SRGB_NONLINEAR_KHR` out of orbit (note the missing underscore in `VK_COLOR_SPACE`), but maybe you can find some other uses for this.

Declarations from the listed C headers are included, as well as type
declarations from dependency includes from those headers. If you want bindings
for a multi-header library, you therefore need to list all of the headers of
that library.

## Capabilities and limitations

Supported features:
* Functions (of course)
* Structs (named, unnamed, typedef'd)
* Unions (cleanly emulated via `property`)
* Enums
* Simple `#define` constants
* Typedefs

Limitations:
* Functional macros are omitted
* Function pointers are translated into `void*` due to Slang not supporting them.
* Variadic arguments are not supported at all
* `const` pointers are turned into non-const due to Slang not supporting const pointers

## Linking with a binding library

You just `import` the binding module and link to the library in CMake.
For example with SDL2:

```cmake
find_package(SDL2 REQUIRED)
add_executable(packer main.slang sdl2.slang)
target_link_libraries(myapp PUBLIC SDL2::SDL2)
```

## Implementation

There's basically two ways you could approach binding C libraries for Slang.
Option 1 is currently taken, but Option 2 could be interesting as an option as
well.

### Option 1. Generate equivalent declarations purely in Slang

Parse C header, then generate exactly equivalent declarations in Slang.
Functions are forward-declared with `__extern_cpp`.

Pros:
- Less generated binding code (& easier-to-read code)
- After generation, no longer reliant on C headers being available
- Would keep working even if Slang someday got a CPU backend without the intermediate C++

Cons:
- Declarations can clash with headers in prelude, if types don't match (e.g. due to non-const pointers)
- Risk for bugs in struct member alignment
- Needs to be updated if headers update, no static checking for this

### Option 2. Rely on C headers directly

Use `__requirePrelude` to `#include` the specified headers.
Use `__target_intrinsic` to map Slang structs to C structs, then define
`property` getters and setters for every member. Create trampolines for all
functions using `__intrinsic_asm`.

Pros:
- No opportunity for bugs in struct sizes, member alignments & offsets
- Generates cleaner internal C++ code

Cons:
- Ironically, generates much more binding code despite relying on headers
- Unclear how to support anonymous structs, unions, enums
- The C++ compiler's include paths must be set up correctly to find the headers
  when compiling a Slang executable


