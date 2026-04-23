# XML.jl Benchmarks

```
Parse (small)
	XML.jl              0.038 ms
	XML.jl (SS)        0.0302 ms
	EzXML              0.0238 ms  (XML.jl 59.7% slower)
	LightXML            0.027 ms  (XML.jl 41.0% slower)
	XMLDict             0.222 ms  (XML.jl 82.9% faster)

Parse (medium)
	XML.jl              214.0 ms
	XML.jl (SS)         179.0 ms
	EzXML                93.5 ms  (XML.jl 128.8% slower)
	LightXML            102.0 ms  (XML.jl 109.7% slower)
	XMLDict             676.0 ms  (XML.jl 68.4% faster)

Write (small)
	XML.jl             0.0192 ms
	EzXML              0.0113 ms  (XML.jl 69.5% slower)
	LightXML             0.11 ms  (XML.jl 82.6% faster)

Write (medium)
	XML.jl               99.8 ms
	EzXML                48.8 ms  (XML.jl 104.4% slower)
	LightXML             62.6 ms  (XML.jl 59.3% slower)

Read file
	XML.jl              223.0 ms
	EzXML               137.0 ms  (XML.jl 62.4% slower)
	LightXML            114.0 ms  (XML.jl 96.5% slower)

Collect tags (small)
	XML.jl           0.000615 ms
	EzXML             0.00231 ms  (XML.jl 73.3% faster)
	LightXML           0.0038 ms  (XML.jl 83.8% faster)

Collect tags (medium)
	XML.jl               18.3 ms
	EzXML                32.4 ms  (XML.jl 43.5% faster)
	LightXML             29.9 ms  (XML.jl 38.8% faster)

```

```julia
versioninfo()
# Julia Version 1.12.6
# Commit 15346901f00 (2026-04-09 19:20 UTC)
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
