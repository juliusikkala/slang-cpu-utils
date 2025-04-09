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
* `string.slang`: string handling helpers
* `thread.slang`: multithreading
* `drop.slang`: `IDroppable` interface for "destructors" where caller doesn't need to know the type
* `list.slang`: a dynamically sized array (similar to `std::vector`)
* `hash.slang`: utilities for computing hashes
* `hashmap.slang`: a hash map (similar to `std::unordered_map`)
* `hashset.slang`: a hash set (similar to `std::unordered_set`)
* `sort.slang`: sorting algorithms for the `IArray` \& `IRWArray` interface

Interfaces are subject to change. Slang is still a quickly evolving language; if
a cleaner way to implement things is added to the language, it should be adopted
in this library.

## example

Example CPU Slang projects, showing how to use these utilities. They also work
as "tests" until I get around to setting up a proper unit testing system.
