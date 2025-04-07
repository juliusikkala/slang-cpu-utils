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
./bindgen.py [list of C headers] > mylibrarybindings.slang
```

There are also a couple of options available.

* `--namespace <ns>` puts everything in a namespace
* `--using <ns>` adds a `using ns;` at the start (to be used in conjunction with `--namespace` and `--import`
* `--import <module>` makes the result bindings import a Slang module
* `--imported <header>` marks declarations from a C header as already included through a `--import` module

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

## TODO

* Rewrite to use [pycparser](https://github.com/eliben/pycparser) instead of libclang
    - libclang turned out to be very limited and kinda crappy

