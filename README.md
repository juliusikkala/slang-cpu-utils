Slang CPU Utility collection
============================

This repo is all about running Slang on CPUs: it's a collection of tools to
streamline standalone [Slang](https://github.com/shader-slang/slang) application
development.

The tools are collected together like this, because they assume a common basis:
[`platform.slang`](lib/platform.slang). This module maps C types to Slang
equivalents to allow working with C bindings.

All components of this library are MIT-0, so you can just use it without even
crediting anyone. No warranties though. See [LICENSE](LICENSE) for details.

## Building

Currently, the only supported platforms are Linux and Windows.

To build the utility library and tests in this repository, you need to have
Slang binaries available somewhere. This project often uses latest and
experimental features of the compiler, so it's best to download or compile the
latest version. If you have Slangc installed system-wide, the toolchain files
should just find it. Otherwise, you'll need to use the `CMAKE_Slang_COMPILER`
option to provide the path.

Note that these instructions just build the tests. To build the examples, you'll
need to go into their directories in `example` and run the cmake commands there.
To use the binding generator and utility library in a project, see
[this sample.](https://github.com/juliusikkala/slang-simple-vulkan)

### Linux

You'll need to install cmake. Then:

```sh
cmake -S . -B build
cmake --build build
```

### Windows

I'm not a Windows expert, but I got this compiling on Windows with the method
below. If you've got a simpler way to do this, please let me know or submit a
PR to update the instructions!

1. Install [CMake](https://cmake.org), [Ninja](https://ninja-build.org) and [Visual Studio 2022](https://visualstudio.microsoft.com/vs/) (Community edition is fine, we just need the MSVC compiler from this).
2. Open "x64 Native Tools Command Prompt for VS 2022" from the Windows start menu
3. Navigate to the root of this repository.
4. Run `cmake -G Ninja -S . -B build` 
    - It's important to specify Ninja as the generator, as the Visual Studio generator does not appear to deal with custom languages too well.
    - If this doesn't find the Slang compiler, you should give CMake the path to it, so `cmake -G Ninja -S . -B build -DCMAKE_Slang_COMPILER=C:/path/to/your/slang/bin/slangc`.
5. Run `cmake --build build`
    - If you see a bunch of errors from Slang, it's likely that an old version of Slang was found (e.g. the version that comes with Vulkan SDK). Go back to step 4 and define the path to your newer build.

## CMake toolchain (`cmake`)

This directory contains toolchain files for compiling Slang CPU software with
CMake. You can use them in your project by copying the `cmake` directory to your
project root and adding the following lines to your CMakeLists.txt:

```cmake
list(APPEND CMAKE_MODULE_PATH "${CMAKE_SOURCE_DIR}/cmake")
project(<yourprojectname> LANGUAGES Slang)
```

Alternatively, you can add slang-cpu-utils as a submodule and adjust the
`CMAKE_MODULE_PATH` to match your directory structure.

## Binding generator (`bindgen`)

This tool generates Slang bindings for C libraries, based on their headers. This
allows you to seamlessly use C libraries in Slang. See [the readme for bindgen
for more details.](bindgen/README.md).

## Utility library (`lib`)

The utility library comes with various modules to ease CPU development with Slang:

* `array.slang`: `IBigArray` and `IRWBigArray`, see [limitations section](#limitations-of-using-slang-on-cpu) for explanation.
* `drop.slang`: `IDroppable` interface for "destructors" where caller doesn't need to know the type
* `equal.slang`: `IEqual`, a subset of `IComparable` without ordering
* `hash.slang`: utilities for computing hashes
* `hashmap.slang`: a hash map (similar to `std::unordered_map`)
* `hashset.slang`: a hash set (similar to `std::unordered_set`)
* `io.slang`: reading and writing files
* `list.slang`: a dynamically sized array (similar to `std::vector`)
* `memory.slang`: memory management utilities
* `panic.slang`: `panic()` for easily crashing the program with an error
* `platform.slang`: platform-specific types and constants
* `sort.slang`: sorting algorithms
* `span.slang`: a wrapper to make plain pointers into `IRWBigArray`
* `string.slang`: string handling helpers, `U8String`
* `thread.slang`: multithreading
* `time.slang`: timing & sleep utilities

Interfaces are subject to change. Slang is still a quickly evolving language; if
a cleaner way to implement things is added to the language, it should be adopted
in this library. If the built-in modules of Slang gain a features that this
library also provides, the corresponding feature will be removed from this
library.

The library provides a simplistic resource management scheme, `IDroppable`.
This interface allows you to define a function called `drop()` to release
allocated resources. The generic data structures in this library automatically
call `drop()` when you remove or clear entries that are `IDroppable`. Other than
that, you'll need to usually follow this pattern:

```slang
List<int> l;
defer l.drop();
```

All kinds of contributions to the utility library are highly welcome. The doors
are open for any features that may be useful but don't (yet) fit for inclusion
in the built-in modules of Slang.

## Examples (`example`)

This repo comes with a few example CPU Slang projects, showing how to use these
utilities.

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

## Limitations of using Slang on CPU

Here's an assortment of issues or inconveniences you can currently expect when
working with Slang on the CPU.

* **No destructors**: use `defer myInstance.drop();` after creating the instance.
* **No ownership & lifetimes**: related to above, there are no language constructs for tracking these.
* **Transpilation through C++**: The compiler first translated Slang to C++, then invokes a C++ compiler to create a binary.
* **Long-ish compile times**: inherited via C++ and a large-ish prelude.
* **String pains**: The built-in `String` type is a somewhat opaque handle to an `Slang::String`. This causes "magical" non-Slang behavior like RAII and is generally quite limited. `NativeString` is a C string type. This library also introduces `U8String` as a Slang-native UTF8 string.
* **`IArray` & `IRWArray`**: the size and index for these is an `int`, so they don't support arrays longer than 2147483647. This library introduces `IBigArray` & `IRWBigArray` to use `size_t` instead. `IArray` is extended to implement `IBigArray`, so you can use all the `IBigArray` functions with `IArray` as well.
* **Funky function pointers**: as in, they don't really exist, but you can get them with some hacky template & intrinsic magic. See `thread.slang`. The fact that this works may actually be an oversight in the Slang compiler, but I hope it won't get "fixed".
* **`IComparable`:** requires being able to order the entries, it's not just equality. `IEqual` is introduced for supporting equality comparison only, which is useful when working with hash map keys.
