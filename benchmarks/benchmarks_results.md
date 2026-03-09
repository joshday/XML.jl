# XML.jl Benchmarks

```
Parse (small)
	XML.jl             0.0339 ms
	XML.jl (SS)        0.0301 ms
	EzXML              0.0254 ms  (33.5% slower)
	LightXML           0.0282 ms  (20.1% slower)
	XMLDict             0.204 ms  (83.4% faster)

Parse (medium)
	XML.jl              170.0 ms
	XML.jl (SS)         154.0 ms
	EzXML                91.0 ms  (87.0% slower)
	LightXML             92.8 ms  (83.4% slower)
	XMLDict             623.0 ms  (72.7% faster)

Write (small)
	XML.jl             0.0179 ms
	EzXML              0.0107 ms  (68.0% slower)
	LightXML           0.0926 ms  (80.6% faster)

Write (medium)
	XML.jl               81.2 ms
	EzXML                73.2 ms  (11.0% slower)
	LightXML             55.1 ms  (47.5% slower)

Read file
	XML.jl              180.0 ms
	EzXML               129.0 ms  (39.9% slower)
	LightXML            104.0 ms  (73.4% slower)

Collect tags (small)
	XML.jl           0.000597 ms
	EzXML             0.00219 ms  (72.7% faster)
	LightXML          0.00371 ms  (83.9% faster)

Collect tags (medium)
	XML.jl               12.2 ms
	EzXML                28.2 ms  (56.9% faster)
	LightXML             25.7 ms  (52.6% faster)

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
