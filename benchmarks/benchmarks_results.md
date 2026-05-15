# XML.jl Benchmarks

```
Parse (small)
	XML.jl             0.0374 ms
	XML.jl (SS)        0.0339 ms
	EzXML              0.0218 ms  (XML.jl 71.2% slower)
	LightXML           0.0218 ms  (XML.jl 71.5% slower)
	XMLDict               0.2 ms  (XML.jl 81.3% faster)

Parse (medium)
	XML.jl              185.0 ms
	XML.jl (SS)         168.0 ms
	EzXML                81.5 ms  (XML.jl 127.4% slower)
	LightXML            107.0 ms  (XML.jl 72.5% slower)
	XMLDict             520.0 ms  (XML.jl 64.4% faster)

Write (small)
	XML.jl            0.00929 ms
	EzXML              0.0103 ms  (XML.jl 10.1% faster)
	LightXML            0.101 ms  (XML.jl 90.8% faster)

Write (medium)
	XML.jl               48.0 ms
	EzXML                52.6 ms  (XML.jl 8.7% faster)
	LightXML             56.1 ms  (XML.jl 14.4% faster)

Read file
	XML.jl              193.0 ms
	EzXML               121.0 ms  (XML.jl 60.3% slower)
	LightXML             95.6 ms  (XML.jl 102.4% slower)

Collect tags (small)
	XML.jl           0.000586 ms
	EzXML             0.00205 ms  (XML.jl 71.5% faster)
	LightXML          0.00368 ms  (XML.jl 84.1% faster)

Collect tags (medium)
	XML.jl               13.1 ms
	EzXML                29.4 ms  (XML.jl 55.4% faster)
	LightXML             23.2 ms  (XML.jl 43.4% faster)

Parse SST (LazyNode)
	XML.jl            5.25e-6 ms
	Node (for ref)       45.4 ms  (XML.jl 100.0% faster)

Parse worksheet (LazyNode)
	XML.jl            5.38e-6 ms
	Node (for ref)       67.8 ms  (XML.jl 100.0% faster)

SST: write each <si>
	LazyNode + write (zero-copy)     89.0 ms
	LazyNode + write (normalize)    153.0 ms
	Node (for ref)       10.1 ms

SST: unformatted text
	LazyNode + is_simple_value     98.3 ms
	Node (for ref)        5.3 ms

Worksheet: collect rows
	children() (fresh Vector each call)     87.8 ms
	children!(buf, n) (reused buffer)     87.6 ms

Worksheet: attribute scan
	eachattribute        87.5 ms
	attributes() (materialize dict)     86.6 ms

Worksheet: single attr fetch
	get(c, "r", "")      86.7 ms
	attributes(c)["r"]     87.1 ms

Worksheet: <v> value
	is_simple_value      87.0 ms
	is_simple + simple_value     87.2 ms

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
