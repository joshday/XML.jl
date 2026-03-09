# XML.jl Benchmark Comparison: dev vs v0.3.8

```
Parse (small)
	v0.3.8              0.116 ms
	String             0.0351 ms  (69.7% faster)
	SubString          0.0309 ms  (73.4% faster)

Parse (medium)
	v0.3.8              736.0 ms
	String              170.0 ms  (76.9% faster)
	SubString           162.0 ms  (77.9% faster)

Write (small)
	v0.3.8             0.0257 ms
	dev                0.0212 ms  (17.7% faster)

Write (medium)
	v0.3.8              154.0 ms
	dev                  84.6 ms  (44.9% faster)

Read file (medium)
	v0.3.8              714.0 ms
	String              177.0 ms  (75.2% faster)
	SubString           171.0 ms  (76.1% faster)

Collect tags (small)
	v0.3.8           0.000527 ms
	String           0.000614 ms  (16.5% slower)
	SubString         0.00177 ms  (235.1% slower)

Collect tags (medium)
	v0.3.8               25.0 ms
	String               10.9 ms  (56.4% faster)
	SubString            16.0 ms  (36.0% faster)

```

```julia
versioninfo()
# Julia Version 1.12.5
# Commit 5fe89b8ddc1 (2026-02-09 16:05 UTC)
# Build Info:
#   Official https://julialang.org release
# Platform Info:
#   OS: macOS (arm64-apple-darwin24.0.0)
#   CPU: 10 × Apple M1 Pro
#   WORD_SIZE: 64
#   LLVM: libLLVM-18.1.7 (ORCJIT, apple-m1)
#   GC: Built with stock GC
# Threads: 8 default, 1 interactive, 8 GC (on 8 virtual cores)
# Environment:
#   JULIA_NUM_THREADS = auto
```
