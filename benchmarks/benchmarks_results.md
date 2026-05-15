# XML.jl Benchmarks

```
Parse (small)
	XML.jl             0.0353 ms
	XML.jl (SS)        0.0321 ms
	EzXML              0.0219 ms  (XML.jl 61.2% slower)
	LightXML           0.0228 ms  (XML.jl 54.7% slower)
	XMLDict             0.191 ms  (XML.jl 81.5% faster)

Parse (medium)
	XML.jl              179.0 ms
	XML.jl (SS)         169.0 ms
	EzXML                79.4 ms  (XML.jl 125.3% slower)
	LightXML            124.0 ms  (XML.jl 43.7% slower)
	XMLDict             611.0 ms  (XML.jl 70.7% faster)

Write (small)
	XML.jl            0.00988 ms
	EzXML              0.0107 ms  (XML.jl 7.4% faster)
	LightXML            0.106 ms  (XML.jl 90.7% faster)

Write (medium)
	XML.jl               49.9 ms
	EzXML                52.4 ms  (~same)
	LightXML             56.3 ms  (XML.jl 11.2% faster)

Read file
	XML.jl              181.0 ms
	EzXML               128.0 ms  (XML.jl 41.3% slower)
	LightXML             96.4 ms  (XML.jl 87.6% slower)

Collect tags (small)
	XML.jl           0.000598 ms
	EzXML             0.00211 ms  (XML.jl 71.7% faster)
	LightXML          0.00385 ms  (XML.jl 84.5% faster)

Collect tags (medium)
	XML.jl               13.5 ms
	EzXML                17.2 ms  (XML.jl 21.6% faster)
	LightXML             27.0 ms  (XML.jl 50.1% faster)

Parse SST (LazyNode)
	XML.jl            5.33e-6 ms
	Node (for ref)       42.3 ms  (XML.jl 100.0% faster)

Parse worksheet (LazyNode)
	XML.jl            5.62e-6 ms
	Node (for ref)       66.1 ms  (XML.jl 100.0% faster)

SST: write each <si>
	LazyNode + write (zero-copy)     84.8 ms
	LazyNode + write (normalize)    144.0 ms
	Node (for ref)       10.5 ms

SST: unformatted text
	LazyNode + is_simple_value     91.4 ms
	Node (for ref)       5.31 ms

Worksheet: collect rows
	children() (fresh Vector each call)     81.7 ms
	children!(buf, n) (reused buffer)     82.4 ms

Worksheet: attribute scan
	eachattribute        82.6 ms
	attributes() (materialize dict)     83.5 ms

Worksheet: single attr fetch
	get(c, "r", "")      83.4 ms
	attributes(c)["r"]     82.8 ms

Worksheet: <v> value
	is_simple_value      82.7 ms
	is_simple + simple_value     83.5 ms

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
