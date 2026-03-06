module XMLStringViewsExt

using XML
using StringViews: StringView
using Mmap: Mmap

"""
    XML.mmap(filename, LazyNode) -> LazyNode

Memory-map `filename` and return a `LazyNode` backed by a `StringView` over the mapped bytes.
The file contents are not copied into Julia heap memory, making this suitable for very large
XML files.

Requires `using StringViews` to activate this method.
"""
function XML.mmap(filename::AbstractString, ::Type{XML.LazyNode})
    bytes = open(filename) do io
        Mmap.mmap(io)
    end
    sv = StringView(bytes)
    XML.LazyNode(sv, XML.Document)
end

Base.parse(xml::StringView, ::Type{XML.LazyNode}) = XML.LazyNode(xml, XML.Document)

end # module
