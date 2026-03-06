[![CI](https://github.com/JuliaComputing/XML.jl/actions/workflows/CI.yml/badge.svg)](https://github.com/JuliaComputing/XML.jl/actions/workflows/CI.yml)

<h1 align="center">XML.jl</h1>

<p align="center">Read and write XML in pure Julia.</p>

<br>

# Quickstart

```julia
using XML

filename = joinpath(dirname(pathof(XML)), "..", "test", "data", "books.xml")

doc = read(filename, Node)

children(doc)
# 2-Element Vector{Node}:
#  Node Declaration <?xml version="1.0"?>
#  Node Element <catalog> (12 children)

doc[end]  # The root node
# Node Element <catalog> (12 children)

doc[end][2]  # Second child of root
# Node Element <book id="bk102"> (6 children)
```

<br>

# `Node` Interface

Every node in the XML DOM is represented by `Node`, a single type parametrized on its string storage.

```
nodetype(node)      -> XML.NodeType (an enum)
tag(node)           -> String or Nothing
attributes(node)    -> Dict{String, String} or Nothing
value(node)         -> String or Nothing
children(node)      -> Vector{Node}
is_simple(node)     -> Bool (e.g. <tag>text</tag>)
simple_value(node)  -> e.g. "text" from <tag>text</tag>
```

<br>

## `NodeType`

Each item in an XML DOM is classified by its `NodeType`:

| NodeType | XML Representation | Constructor |
|----------|--------------------|-------------|
| `Document` | An entire document | `Document(children...)` |
| `DTD` | `<!DOCTYPE ...>` | `DTD(...)` |
| `Declaration` | `<?xml attributes... ?>` | `Declaration(; attrs...)` |
| `ProcessingInstruction` | `<?tag attributes... ?>` | `ProcessingInstruction(tag; attrs...)` |
| `Comment` | `<!-- text -->` | `Comment(text)` |
| `CData` | `<![CDATA[text]]>` | `CData(text)` |
| `Element` | `<tag attrs...> children... </tag>` | `Element(tag, children...; attrs...)` |
| `Text` | the `text` part of `<tag>text</tag>` | `Text(text)` |

<br>

## Mutation

```julia
push!(parent, child)   # Add a child
parent[2] = child      # Replace a child
node["key"] = "value"  # Add/change an attribute
node["key"]            # Get an attribute
```

<br>

## Tree Navigation

```julia
depth(child, root)      # Depth of child relative to root
parent(child, root)     # Parent of child within root's tree
siblings(child, root)   # Siblings of child within root's tree
```

<br>

## Writing Elements with `XML.h`

Similar to [Cobweb.jl](https://github.com/JuliaComputing/Cobweb.jl#-creating-nodes-with-cobwebh), `XML.h` enables you to write elements with a simpler syntax:

```julia
using XML: h

node = h.parent(
    h.child("first child content", id="id1"),
    h.child("second child content", id="id2")
)
# Node Element <parent> (2 children)

print(XML.write(node))
# <parent>
#   <child id="id1">first child content</child>
#   <child id="id2">second child content</child>
# </parent>
```

<br>

# Reading

```julia
# From a file:
read(filename, Node)

# From a string:
parse(str, Node)
```

<br>

# Writing

```julia
XML.write(filename::String, node)  # write to file
XML.write(io::IO, node)            # write to stream
XML.write(node)                    # return String
```

`XML.write` respects `xml:space="preserve"` on elements, suppressing automatic indentation.

<br>

# XPath

Query nodes using a subset of XPath 1.0 via `xpath(node, path)`:

```julia
doc = parse("""
<root>
  <a id="1"><b>hello</b></a>
  <a id="2"><b>world</b></a>
</root>
""", Node)

root = doc[end]

xpath(root, "//b")           # All <b> descendants
xpath(root, "a[@id='2']/b")  # <b> inside <a id="2">
xpath(root, "a[1]")          # First <a> child
xpath(root, "//b/text()")    # Text nodes inside all <b>s
```

### Supported syntax

| Expression | Description |
|------------|-------------|
| `/` | Root / path separator |
| `tag` | Child element by name |
| `*` | Any child element |
| `//` | Descendant-or-self (recursive) |
| `.` | Current node |
| `..` | Parent node |
| `[n]` | Positional predicate (1-based) |
| `[@attr]` | Has-attribute predicate |
| `[@attr='v']` | Attribute-value predicate |
| `text()` | Text node children |
| `node()` | All node children |
| `@attr` | Attribute value (returns strings) |

<br>

# Streaming Tokenizer

For large files or when you need fine-grained control, `XML.XMLTokenizer` provides a streaming tokenizer that yields tokens without building a DOM:

```julia
using XML.XMLTokenizer

for token in tokenize("<root><child attr=\"val\">text</child></root>")
    println(token.kind, " => ", repr(String(token.raw)))
end
# TOKEN_OPEN_TAG => "<root"
# TOKEN_TAG_CLOSE => ">"
# TOKEN_OPEN_TAG => "<child"
# TOKEN_ATTR_NAME => "attr"
# TOKEN_ATTR_VALUE => "\"val\""
# TOKEN_TAG_CLOSE => ">"
# TOKEN_TEXT => "text"
# TOKEN_CLOSE_TAG => "</child"
# TOKEN_TAG_CLOSE => ">"
# TOKEN_CLOSE_TAG => "</root"
# TOKEN_TAG_CLOSE => ">"
```

<br>

# `LazyNode`

For read-only access without building a full DOM tree, use `LazyNode`. It stores only a reference to the source string and re-tokenizes on demand, using significantly less memory:

```julia
doc = parse(xml_string, LazyNode)
doc = read("file.xml", LazyNode)
```

`LazyNode` supports the same read-only interface as `Node`: `nodetype`, `tag`, `attributes`, `value`, `children`, `is_simple`, `simple_value`, plus integer and string indexing.

### Memory-mapped files

For very large files, combine `LazyNode` with memory mapping via the `StringViews` extension:

```julia
using XML, StringViews

doc = XML.mmap("very_large.xml", LazyNode)
```

<br>

# Benchmarks

Benchmark source: [benchmarks.jl](benchmarks/benchmarks.jl).  Test data: `books.xml` (small, ~4 KB) and a generated XMark auction XML (medium, ~14 MB).



```
                         Parse (small) — median time (ms)

        XML.jl  ■■■■■■■ 0.041
   XML.jl (SS)  ■■■■■■ 0.034
         EzXML  ■■■■■ 0.030
      LightXML  ■■■■■■ 0.033
       XMLDict  ■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■ 0.232


                         Parse (medium) — median time (ms)

        XML.jl  ■■■■■■■■■■■■ 194.2
   XML.jl (SS)  ■■■■■■■■■■ 172.8
         EzXML  ■■■■■■ 105.8
      LightXML  ■■■■■■ 105.0
       XMLDict  ■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■ 687.7


                      Write (small) — median time (ms)

     XML.jl  ■■■■■■■■ 0.021
      EzXML  ■■■■ 0.012
   LightXML  ■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■ 0.110


                      Write (medium) — median time (ms)

     XML.jl  ■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■ 93.2
      EzXML  ■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■ 84.6
   LightXML  ■■■■■■■■■■■■■■■■■■■■■■■■■■■ 60.4


                        Read file — median time (ms)

     XML.jl  ■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■ 214.1
      EzXML  ■■■■■■■■■■■■■■■■■■■■■■■■■■■ 143.1
   LightXML  ■■■■■■■■■■■■■■■■■■■■■■■ 121.9


                   Collect tags (small) — median time (ms)

     XML.jl  ■■■■■■ 0.000698
      EzXML  ■■■■■■■■■■■■■■■■■■■■■■■ 0.00255
   LightXML  ■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■ 0.00430


                  Collect tags (medium) — median time (ms)

     XML.jl  ■■■■■■■■■■■■■■■■■■■ 12.6
      EzXML  ■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■ 20.5
   LightXML  ■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■ 27.6
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
