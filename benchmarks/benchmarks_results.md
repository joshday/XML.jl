# XML.jl Benchmarks

```
Parse (small)
	XML.jl             0.0364 ms
	XML.jl (SS)          0.03 ms
	EzXML              0.0226 ms  (XML.jl 60.8% slower)
	LightXML           0.0263 ms  (XML.jl 38.1% slower)
	XMLDict             0.198 ms  (XML.jl 81.7% faster)

Parse (medium)
	XML.jl              190.0 ms
	XML.jl (SS)         152.0 ms
	EzXML                79.8 ms  (XML.jl 138.3% slower)
	LightXML             82.5 ms  (XML.jl 130.4% slower)
	XMLDict             550.0 ms  (XML.jl 65.5% faster)

Write (small)
	XML.jl            0.00965 ms
	EzXML              0.0107 ms  (XML.jl 10.2% faster)
	LightXML            0.102 ms  (XML.jl 90.5% faster)

Write (medium)
	XML.jl               50.5 ms
	EzXML                37.8 ms  (XML.jl 33.7% slower)
	LightXML             62.8 ms  (XML.jl 19.5% faster)

Read file
	XML.jl              197.0 ms
	EzXML               125.0 ms  (XML.jl 57.1% slower)
	LightXML             97.0 ms  (XML.jl 102.7% slower)

Collect tags (small)
	XML.jl           0.000619 ms
	EzXML             0.00214 ms  (XML.jl 71.0% faster)
	LightXML          0.00354 ms  (XML.jl 82.5% faster)

Collect tags (medium)
	XML.jl               14.3 ms
	EzXML                18.6 ms  (XML.jl 22.7% faster)
	LightXML             24.2 ms  (XML.jl 40.6% faster)

Parse SST (LazyNode)
	XML.jl            5.38e-6 ms
	Node (for ref)       43.3 ms  (XML.jl 100.0% faster)

Parse worksheet (LazyNode)
	XML.jl            5.42e-6 ms
	Node (for ref)       65.6 ms  (XML.jl 100.0% faster)

SST: write each <si>
	LazyNode + write (zero-copy)     85.1 ms
	LazyNode + write (normalize)    148.0 ms
	Node (for ref)       11.9 ms

SST: unformatted text
	LazyNode + is_simple_value    106.0 ms
	Node (for ref)       6.04 ms

Worksheet: collect rows
	children() (fresh Vector each call)     79.9 ms
	children!(buf, n) (reused buffer)     80.1 ms

Worksheet: attribute scan
	eachattribute        79.8 ms
	attributes() (materialize dict)     80.1 ms

Worksheet: single attr fetch
	get(c, "r", "")      79.6 ms
	attributes(c)["r"]     82.1 ms

Worksheet: <v> value
	is_simple_value      82.4 ms
	is_simple + simple_value     80.7 ms

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
