# XML.jl Benchmarks

```
Parse (small)
	XML.jl             0.0341 ms
	XML.jl (SS)        0.0271 ms
	EzXML              0.0224 ms  (XML.jl 52.3% slower)
	LightXML            0.022 ms  (XML.jl 55.2% slower)
	XMLDict             0.205 ms  (XML.jl 83.4% faster)

Parse (medium)
	XML.jl              188.0 ms
	XML.jl (SS)         159.0 ms
	EzXML                81.4 ms  (XML.jl 131.3% slower)
	LightXML            122.0 ms  (XML.jl 53.9% slower)
	XMLDict             582.0 ms  (XML.jl 67.6% faster)

Write (small)
	XML.jl             0.0182 ms
	EzXML              0.0106 ms  (XML.jl 72.0% slower)
	LightXML            0.104 ms  (XML.jl 82.4% faster)

Write (medium)
	XML.jl               83.3 ms
	EzXML                39.7 ms  (XML.jl 109.8% slower)
	LightXML             55.0 ms  (XML.jl 51.5% slower)

Read file
	XML.jl              189.0 ms
	EzXML               127.0 ms  (XML.jl 48.3% slower)
	LightXML            102.0 ms  (XML.jl 85.3% slower)

Collect tags (small)
	XML.jl           0.000592 ms
	EzXML             0.00244 ms  (XML.jl 75.8% faster)
	LightXML          0.00393 ms  (XML.jl 84.9% faster)

Collect tags (medium)
	XML.jl               15.7 ms
	EzXML                18.0 ms  (XML.jl 12.5% faster)
	LightXML             23.8 ms  (XML.jl 34.0% faster)

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
