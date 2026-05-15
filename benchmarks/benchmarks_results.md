# XML.jl Benchmarks

```
Parse (small)
	XML.jl             0.0353 ms
	XML.jl (SS)        0.0284 ms
	EzXML              0.0202 ms  (XML.jl 74.3% slower)
	LightXML            0.021 ms  (XML.jl 68.1% slower)
	XMLDict             0.199 ms  (XML.jl 82.3% faster)

Parse (medium)
	XML.jl              170.0 ms
	XML.jl (SS)         146.0 ms
	EzXML                71.9 ms  (XML.jl 136.8% slower)
	LightXML             79.5 ms  (XML.jl 114.2% slower)
	XMLDict             532.0 ms  (XML.jl 68.0% faster)

Write (small)
	XML.jl              0.018 ms
	EzXML              0.0103 ms  (XML.jl 74.6% slower)
	LightXML            0.101 ms  (XML.jl 82.2% faster)

Write (medium)
	XML.jl               80.8 ms
	EzXML                35.4 ms  (XML.jl 128.3% slower)
	LightXML             54.2 ms  (XML.jl 49.0% slower)

Read file
	XML.jl              190.0 ms
	EzXML               112.0 ms  (XML.jl 69.1% slower)
	LightXML             94.2 ms  (XML.jl 101.2% slower)

Collect tags (small)
	XML.jl           0.000588 ms
	EzXML             0.00208 ms  (XML.jl 71.7% faster)
	LightXML          0.00377 ms  (XML.jl 84.4% faster)

Collect tags (medium)
	XML.jl               13.8 ms
	EzXML                16.6 ms  (XML.jl 16.4% faster)
	LightXML             22.7 ms  (XML.jl 39.0% faster)

Parse SST (LazyNode)
	XML.jl            5.21e-6 ms
	Node (for ref)       40.9 ms  (XML.jl 100.0% faster)

Parse worksheet (LazyNode)
	XML.jl            5.21e-6 ms
	Node (for ref)       64.9 ms  (XML.jl 100.0% faster)

SST: write each <si>
	LazyNode + write (zero-copy)     82.0 ms
	LazyNode + write (normalize)    151.0 ms
	Node (for ref)       18.1 ms

SST: unformatted text
	LazyNode + is_simple_value     86.5 ms
	Node (for ref)       5.17 ms

Worksheet: collect rows
	children() (fresh Vector each call)     70.7 ms
	children!(buf, n) (reused buffer)     71.0 ms

Worksheet: attribute scan
	eachattribute        70.4 ms
	attributes() (materialize dict)     70.2 ms

Worksheet: single attr fetch
	get(c, "r", "")      70.4 ms
	attributes(c)["r"]     70.9 ms

Worksheet: <v> value
	is_simple_value      70.6 ms
	is_simple + simple_value     71.0 ms

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
