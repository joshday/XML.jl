# XML.jl Benchmark Comparison: dev vs v0.3.8

```
Parse (small)
	v0.3.8              0.141 ms
	String             0.0415 ms  (70.5% faster)
	SubString          0.0349 ms  (75.2% faster)
	LazyNode          6.62e-6 ms  (100.0% faster)

Parse (medium)
	v0.3.8              768.0 ms
	String              193.0 ms  (74.8% faster)
	SubString           174.0 ms  (77.3% faster)
	LazyNode          6.75e-6 ms  (100.0% faster)

Write (small)
	v0.3.8              0.027 ms
	dev                0.0212 ms  (21.6% faster)
	LazyNode         0.000229 ms  (99.2% faster)

Write (medium)
	v0.3.8              158.0 ms
	dev                  96.4 ms  (39.0% faster)
	LazyNode         0.000289 ms  (100.0% faster)

Read file (medium)
	v0.3.8              739.0 ms
	String              196.0 ms  (73.5% faster)
	SubString           176.0 ms  (76.3% faster)

Collect tags (small)
	v0.3.8           0.000656 ms
	String           0.000716 ms  (9.1% slower)
	SubString           0.002 ms  (205.4% slower)

Collect tags (medium)
	v0.3.8               22.3 ms
	String               12.4 ms  (44.5% faster)
	SubString            16.4 ms  (26.4% faster)

sourcetext
	small            0.000201 ms
	medium           0.000259 ms

children vs eachchildnode (medium)
	children             76.2 ms
	eachchildnode        77.3 ms

SST-like: parse+iterate+write (10k)
	Node                 9.01 ms
	LazyNode+children       9.22 ms
	LazyNode+eachchildnode       9.61 ms

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
