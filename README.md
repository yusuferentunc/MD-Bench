# MD-Bench

A simple, sequential  C version of the Mantevo miniMD benchmark.

## Build

1. Open the `Makefile` and edit the `TAG` value according to the tool chain used. Currently supported is GCC, CLANG (LLVM), and ICC (Intel).
2. Open and adapt the compiler flags in `<include_<TOOLCHAIN>.mk`, e.g. in `include_ICC.mk` for the Intel tool chain.
3. Build the binary calling `make`.

You can clean intermediate build results with `make clean`, and all build results with `make distclean`.
You have to call `make clean` before `make` if you changed the build settings.

## Configuration

Currently all settings are hard-coded in `main.c`.

## Run the benchmark

Just execute the binary. There are no options.
