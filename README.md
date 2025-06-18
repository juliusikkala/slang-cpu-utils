Slang CPU Utility collection
============================

This repo is all about running Slang on CPUs: it's a collection of tools to
streamline standalone [Slang](https://github.com/shader-slang/slang) application
development.

The tools are collected together like this, because they assume a common basis:
[lib/platform.slang](`platform.slang`). This module maps C types to Slang
equivalents and defines platform-specific constants.

Currently, much of this has only been tested on Linux. Windows-related fixed and
extra tools are very welcome as PRs! It's also unstable. No warranties. See
[LICENSE](LICENSE) for details.

## cmake

This directory contains toolchain files for compiling Slang CPU software with
CMake. You can use them in your project by copying the `cmake` directory to your
project root and adding the following lines to your CMakeLists.txt:

```cmake
list(APPEND CMAKE_MODULE_PATH "${CMAKE_SOURCE_DIR}/cmake")
project(<yourprojectname> LANGUAGES Slang)
```

Alternatively, you can add slang-cpu-utils as a submodule and adjust the
`CMAKE_MODULE_PATH` to match your directory structure.

## bindgen

This tool generates Slang bindings for C libraries, based on their headers. This
allows you to seamlessly use C libraries in Slang. See [the readme for bindgen
for more details.](bindgen/README.md).

## lib

Various modules to ease CPU development with Slang.

* `platform.slang`: platform-specific types and constants
* `memory.slang`: memory management utilities
* `panic.slang`: `panic()` for easily crashing the program with an error
* `io.slang`: reading and writing files
* `string.slang`: string handling helpers, `U8String`
* `thread.slang`: multithreading
* `drop.slang`: `IDroppable` interface for "destructors" where caller doesn't need to know the type
* `array.slang`: `IBigArray` and `IRWBigArray`, see [limitations section](#limitations-of-using-slang-on-cpu) for explanation.
* `span.slang`: a wrapper to make plain pointers into `IRWBigArray`
* `list.slang`: a dynamically sized array (similar to `std::vector`)
* `hash.slang`: utilities for computing hashes
* `hashmap.slang`: a hash map (similar to `std::unordered_map`)
* `hashset.slang`: a hash set (similar to `std::unordered_set`)
* `sort.slang`: sorting algorithms
* `time.slang`: timing & sleep utilities
* `equal.slang`: `IEqual`, a subset of `IComparable`

Interfaces are subject to change. Slang is still a quickly evolving language; if
a cleaner way to implement things is added to the language, it should be adopted
in this library.

## example

Example CPU Slang projects, showing how to use these utilities.

The examples have their own CMake projects and aren't built as subdirectories of
the top-level CMake file. This is done for illustratory purposes, as the
examples are also about showing how to use CMake with Slang.

* `function-fitting`: A tool for fitting 1D functions using gradient descent
    - Shows List<T>, drop(), timing
* `cmdline-calculator`: A simple command line calculator (string handling & List)
    - Shows string parsing, List<T>
* `simple-vulkan`: Initializes Vulkan and shows a simple animation
    - [*This is in a separate repo, and shows how a standalone project can depend on this library!*](https://github.com/juliusikkala/slang-simple-vulkan)
    - Shows using C libraries (SDL, Vulkan)

# Limitations of using Slang on CPU

Here's an assortment of issues or inconveniences you can currently expect when
working with Slang on the CPU.

* *No destructors*: use `defer myInstance.drop();` after creating the instance.
* *No ownership & lifetimes*: related to above, there are no language constructs for tracking these.
* *Transpilation through C++*: The compiler first translated Slang to C++, then invokes a C++ compiler to create a binary.
* *Long-ish compile times*: inherited via C++ and a large-ish prelude.
* *String pains*: The built-in `String` type is a somewhat opaque handle to an `Slang::String`. This causes "magical" non-Slang behavior like RAII and is generally quite limited. `NativeString` is a C string type. This library also introduces `U8String` as a Slang-native UTF8 string.
* *`IArray` & `IRWArray`*: the size and index for these is an `int`, so they don't support arrays longer than 2147483647. This library introduces `IBigArray` & `IRWBigArray` to use `size_t` instead. `IArray` is extended to implement `IBigArray`, so you can use all the `IBigArray` functions with `IArray` as well.
* *Funky function pointers*: as in, they don't really exist, but you can get them with some hacky template & intrinsic magic. See `thread.slang`. The fact that this works may actually be an oversight in the Slang compiler, but I hope it won't get "fixed".
* *`IComparable`:* requires being able to order the entries, it's not just equality. `IEqual` is introduced for supporting equality comparison only, which is useful when working with hash map keys.
