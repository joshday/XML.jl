# XML.jl Benchmarks

```
Parse (small)
	XML.jl             0.0368 ms
	XML.jl (SS)        0.0338 ms
	EzXML               0.026 ms  (XML.jl 41.6% slower)
	LightXML           0.0231 ms  (XML.jl 58.9% slower)
	XMLDict             0.242 ms  (XML.jl 84.8% faster)

Parse (medium)
	XML.jl              183.0 ms
	XML.jl (SS)         171.0 ms
	EzXML                92.7 ms  (XML.jl 97.1% slower)
	LightXML            139.0 ms  (XML.jl 31.5% slower)
	XMLDict             634.0 ms  (XML.jl 71.2% faster)

Write (small)
	XML.jl             0.0116 ms
	EzXML              0.0127 ms  (XML.jl 8.5% faster)
	LightXML            0.118 ms  (XML.jl 90.2% faster)

Write (medium)
	XML.jl               54.4 ms
	EzXML                63.5 ms  (XML.jl 14.3% faster)
	LightXML             70.2 ms  (XML.jl 22.5% faster)

Read file
	XML.jl              202.0 ms
	EzXML               151.0 ms  (XML.jl 33.6% slower)
	LightXML            123.0 ms  (XML.jl 63.5% slower)

Collect tags (small)
	XML.jl             0.0007 ms
	EzXML             0.00262 ms  (XML.jl 73.3% faster)
	LightXML          0.00426 ms  (XML.jl 83.6% faster)

Collect tags (medium)
	XML.jl               14.8 ms
	EzXML                33.2 ms  (XML.jl 55.4% faster)
	LightXML             29.8 ms  (XML.jl 50.3% faster)

Parse SST (LazyNode)
	XML.jl            6.29e-6 ms
	Node (for ref)       57.0 ms  (XML.jl 100.0% faster)

Parse worksheet (LazyNode)
	XML.jl            6.38e-6 ms
	Node (for ref)       68.5 ms  (XML.jl 100.0% faster)

SST: write each <si>
	LazyNode + write (zero-copy)     95.2 ms
	LazyNode + write (normalize)    166.0 ms
	Node (for ref)       11.8 ms

SST: unformatted text
	LazyNode + is_simple_value    109.0 ms
	Node (for ref)       6.27 ms

Worksheet: collect rows
	children() (fresh Vector each call)     85.0 ms
	children!(buf, n) (reused buffer)     86.5 ms

Worksheet: attribute scan
	eachattribute        79.0 ms
	attributes() (materialize dict)     72.9 ms

Worksheet: single attr fetch
	get(c, "r", "")      77.0 ms
	attributes(c)["r"]     75.3 ms

Worksheet: <v> value
	is_simple_value      83.2 ms
	is_simple + simple_value     73.4 ms

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
