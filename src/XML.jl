module XML

export
    Node, LazyNode, NodeType, Attributes,
    CData, Comment, Declaration, Document, DTD, Element, ProcessingInstruction, Text,
    nodetype, tag, attributes, value, children, eachchildnode,
    is_simple, simple_value, sourcetext,
    depth, siblings,
    xpath,
    h

include("XMLTokenizer.jl")
using .XMLTokenizer:
    tokenize, tag_name, attr_value, pi_target, TokenKind, Token, Tokenizer, TokenizerState,
    TOKEN_TEXT, TOKEN_OPEN_TAG, TOKEN_CLOSE_TAG, TOKEN_TAG_CLOSE, TOKEN_SELF_CLOSE,
    TOKEN_ATTR_NAME, TOKEN_ATTR_VALUE,
    TOKEN_CDATA_OPEN, TOKEN_CDATA_CONTENT, TOKEN_CDATA_CLOSE,
    TOKEN_COMMENT_OPEN, TOKEN_COMMENT_CONTENT, TOKEN_COMMENT_CLOSE,
    TOKEN_PI_OPEN, TOKEN_PI_CONTENT, TOKEN_PI_CLOSE,
    TOKEN_XML_DECL_OPEN, TOKEN_XML_DECL_CLOSE,
    TOKEN_DOCTYPE_OPEN, TOKEN_DOCTYPE_CONTENT, TOKEN_DOCTYPE_CLOSE

#-----------------------------------------------------------------------------# escape/unescape
const escape_chars = ('&' => "&amp;", '<' => "&lt;", '>' => "&gt;", '\'' => "&apos;", '"' => "&quot;")

"""
    escape(x::AbstractString) -> String

Escape the five XML predefined entities: `&` `<` `>` `'` `"`.

!!! note "Changed in v0.4"
    `escape` is no longer idempotent.  In previous versions, already-escaped sequences like
    `&amp;` were left untouched.  Now every `&` is escaped, so `escape("&amp;")` produces
    `"&amp;amp;"`.  Call `escape` only on raw, unescaped text.
"""
escape(x::AbstractString) = replace(x, escape_chars...)

# Replace a numeric character reference with its Unicode character.
# Numeric character references encode characters by code point: decimal (&#233; → é) or hex (&#xE9; → é).
function _unescape_charref(ref::AbstractString)
    is_hex = length(ref) > 3 && ref[3] in ('x', 'X')
    digits = SubString(ref, is_hex ? 4 : 3, length(ref) - 1)
    cp = tryparse(UInt32, digits; base = is_hex ? 16 : 10)
    !isnothing(cp) && isvalid(Char, cp) ? string(Char(cp)) : ref
end

"""
    unescape(x::AbstractString) -> String

Unescape XML entities in `x`: the five predefined entities (`&amp;` `&lt;` `&gt;` `&apos;`
`&quot;`) and numeric character references (`&#123;`, `&#xAB;`).  Each reference is processed
exactly once (no double-unescaping).
"""
function unescape(x::AbstractString)
    occursin('&', x) || return string(x)
    s = string(x)
    occursin("&#", s) && (s = replace(s, r"&#[xX]?[0-9a-fA-F]+;" => _unescape_charref))
    replace(s, "&lt;" => "<", "&gt;" => ">", "&apos;" => "'", "&quot;" => "\"", "&amp;" => "&")
end

#-----------------------------------------------------------------------------# NodeType
"""
    NodeType:
    - Document                  # prolog & root Element
    - DTD                       # <!DOCTYPE ...>
    - Declaration               # <?xml attributes... ?>
    - ProcessingInstruction    # <?NAME content... ?>
    - Comment                   # <!-- ... -->
    - CData                     # <![CDATA[...]]>
    - Element                   # <NAME attributes... > children... </NAME>
    - Text                      # text

NodeTypes can be used to construct XML.Nodes:

    Document(children...)
    DTD(value)
    Declaration(; attributes)
    ProcessingInstruction(tag, content)
    Comment(text)
    CData(text)
    Element(tag, children...; attributes)
    Text(text)
"""
@enum NodeType::UInt8 CData Comment Declaration Document DTD Element ProcessingInstruction Text

#-----------------------------------------------------------------------------# Attributes
"""
    Attributes{S} <: AbstractDict{S, S}

An ordered dictionary of XML attributes backed by a `Vector{Pair{S, S}}`.
Returned by [`attributes`](@ref).  Preserves insertion order and supports the
full `AbstractDict` interface (`get`, `haskey`, `keys`, `values`, iteration, etc.).
"""
struct Attributes{S} <: AbstractDict{S, S}
    entries::Vector{Pair{S, S}}
end

Base.length(a::Attributes) = length(a.entries)
Base.iterate(a::Attributes, state...) = iterate(a.entries, state...)

function Base.getindex(a::Attributes, key::AbstractString)
    for (k, v) in a.entries
        k == key && return v
    end
    throw(KeyError(key))
end

function Base.get(a::Attributes, key::AbstractString, default)
    for (k, v) in a.entries
        k == key && return v
    end
    default
end

function Base.haskey(a::Attributes, key::AbstractString)
    any(p -> first(p) == key, a.entries)
end

Base.keys(a::Attributes) = first.(a.entries)
Base.values(a::Attributes) = last.(a.entries)

#-----------------------------------------------------------------------------# Node
struct Node{S}
    nodetype::NodeType
    tag::Union{Nothing, S}
    attributes::Union{Nothing, Vector{Pair{S, S}}}
    value::Union{Nothing, S}
    children::Union{Nothing, Vector{Node{S}}}

    function Node{S}(nodetype::NodeType, tag, attributes, value, children) where {S}
        if nodetype in (Text, Comment, CData, DTD)
            isnothing(tag) && isnothing(attributes) && !isnothing(value) && isnothing(children) ||
                error("$nodetype nodes only accept a value.")
        elseif nodetype === Element
            !isnothing(tag) && isnothing(value) ||
                error("Element nodes require a tag and no value.")
        elseif nodetype === Declaration
            isnothing(tag) && isnothing(value) && isnothing(children) ||
                error("Declaration nodes only accept attributes.")
        elseif nodetype === ProcessingInstruction
            !isnothing(tag) && isnothing(attributes) && isnothing(children) ||
                error("ProcessingInstruction nodes require a tag and only accept a value.")
        elseif nodetype === Document
            isnothing(tag) && isnothing(attributes) && isnothing(value) ||
                error("Document nodes only accept children.")
        end
        new{S}(nodetype, tag, attributes, value, children)
    end
end

#-----------------------------------------------------------------------------# interface
nodetype(o::Node) = o.nodetype
tag(o::Node) = o.tag

"""
    attributes(node::Node) -> Union{Nothing, Attributes{String}}

Return the attributes of an `Element` or `Declaration` node as an [`Attributes`](@ref) dict,
or `nothing` if the node has no attributes.

!!! note "Changed in v0.4"
    In previous versions, `attributes` returned an `OrderedDict` from OrderedCollections.jl.
    It now returns an [`Attributes`](@ref), an ordered `AbstractDict` backed by a
    `Vector{Pair}`.
"""
attributes(o::Node) = isnothing(o.attributes) ? nothing : Attributes(o.attributes)

value(o::Node) = o.value
children(o::Node) = something(o.children, ())

is_simple(o::Node) = o.nodetype === Element &&
    (isnothing(o.attributes) || isempty(o.attributes)) &&
    !isnothing(o.children) && length(o.children) == 1 &&
    o.children[1].nodetype in (Text, CData)

simple_value(o::Node) = is_simple(o) ? o.children[1].value :
    error("`simple_value` is only defined for simple nodes.")

#-----------------------------------------------------------------------------# tree navigation

"""
    parent(child::Node, root::Node) -> Node

Return the parent of `child` within the tree rooted at `root`.

Since `Node` does not store parent pointers, this performs a tree search from `root`.
Throws an error if `child` is not found or if `child === root`.
"""
function Base.parent(child::Node, root::Node)
    child === root && error("Root node has no parent.")
    result = _find_parent(child, root)
    isnothing(result) && error("Node not found in tree.")
    result
end

function _find_parent(child::Node, current::Node)
    for c in children(current)
        c === child && return current
        result = _find_parent(child, c)
        isnothing(result) || return result
    end
    nothing
end

"""
    depth(child::Node, root::Node) -> Int

Return the depth of `child` within the tree rooted at `root` (root has depth 0).

Since `Node` does not store parent pointers, this performs a tree search from `root`.
Throws an error if `child` is not found in the tree.
"""
function depth(child::Node, root::Node)
    child === root && return 0
    result = _find_depth(child, root, 0)
    isnothing(result) && error("Node not found in tree.")
    result
end

function _find_depth(child::Node, current::Node, d::Int)
    for c in children(current)
        c === child && return d + 1
        result = _find_depth(child, c, d + 1)
        isnothing(result) || return result
    end
    nothing
end

"""
    siblings(child::Node, root::Node) -> Vector{Node}

Return the siblings of `child` (other children of the same parent) within the tree rooted
at `root`.  The returned vector does not include `child` itself.

Throws an error if `child` is the root or is not found in the tree.
"""
function siblings(child::Node, root::Node)
    p = parent(child, root)
    [c for c in children(p) if c !== child]
end

include("xpath.jl")
include("lazynode.jl")


#-----------------------------------------------------------------------------# _to_node
_to_node(n::Node{String}) = n
_to_node(n::Node) = throw(ArgumentError("Expected Node{String}, got $(typeof(n))"))
_to_node(x) = Node{String}(Text, nothing, nothing, string(x), nothing)

#-----------------------------------------------------------------------------# NodeType constructors
function (T::NodeType)(args...; attrs...)
    S = String
    if T in (Text, Comment, CData, DTD)
        length(args) == 1 || error("$T nodes require exactly one value argument.")
        !isempty(attrs) && error("$T nodes do not accept attributes.")
        Node{S}(T, nothing, nothing, string(only(args)), nothing)
    elseif T === Element
        isempty(args) && error("Element nodes require at least a tag.")
        t = string(first(args))
        a = Pair{S,S}[String(k) => String(v) for (k, v) in pairs(attrs)]
        c = Node{S}[_to_node(x) for x in args[2:end]]
        Node{S}(T, t, a, nothing, c)
    elseif T === Declaration
        !isempty(args) && error("Declaration nodes only accept keyword attributes.")
        a = isempty(attrs) ? nothing : [String(k) => String(v) for (k, v) in pairs(attrs)]
        Node{S}(T, nothing, a, nothing, nothing)
    elseif T === ProcessingInstruction
        length(args) >= 1 || error("ProcessingInstruction nodes require a target.")
        length(args) <= 2 || error("ProcessingInstruction nodes accept a target and optional content.")
        !isempty(attrs) && error("ProcessingInstruction nodes do not accept attributes.")
        t = string(args[1])
        v = length(args) == 2 ? string(args[2]) : nothing
        Node{S}(T, t, nothing, v, nothing)
    elseif T === Document
        !isempty(attrs) && error("Document nodes do not accept attributes.")
        c = Node{S}[_to_node(x) for x in args]
        Node{S}(T, nothing, nothing, nothing, c)
    end
end

#-----------------------------------------------------------------------------# equality
_eq(::Nothing, ::Nothing) = true
_eq(::Nothing, b) = isempty(b)
_eq(a, ::Nothing) = isempty(a)
_eq(a, b) = a == b

# Attribute equality is order-insensitive per XML spec
function _attrs_eq(a, b)
    a_empty = isnothing(a) || isempty(a)
    b_empty = isnothing(b) || isempty(b)
    a_empty && b_empty && return true
    (a_empty != b_empty) && return false
    length(a) != length(b) && return false
    for p in a
        p in b || return false
    end
    true
end

function Base.:(==)(a::Node, b::Node)
    a.nodetype == b.nodetype &&
    a.tag == b.tag &&
    _attrs_eq(a.attributes, b.attributes) &&
    a.value == b.value &&
    _eq(a.children, b.children)
end

#-----------------------------------------------------------------------------# indexing
Base.getindex(o::Node, i::Integer) = children(o)[i]
Base.getindex(o::Node, ::Colon) = children(o)
Base.lastindex(o::Node) = lastindex(children(o))
Base.only(o::Node) = only(children(o))
Base.length(o::Node) = length(children(o))

function Base.get(o::Node, key::AbstractString, default)
    isnothing(o.attributes) && return default
    for (k, v) in o.attributes
        k == key && return v
    end
    default
end

const _MISSING_ATTR = gensym(:missing_attr)

function Base.getindex(o::Node, key::AbstractString)
    val = get(o, key, _MISSING_ATTR)
    val === _MISSING_ATTR && throw(KeyError(key))
    val
end

function Base.haskey(o::Node, key::AbstractString)
    get(o, key, _MISSING_ATTR) !== _MISSING_ATTR
end

Base.keys(o::Node) = isnothing(o.attributes) ? () : first.(o.attributes)

#-----------------------------------------------------------------------------# mutation
function Base.setindex!(o::Node, val, i::Integer)
    isnothing(o.children) && error("Node has no children.")
    o.children[i] = _to_node(val)
end

function Base.setindex!(o::Node, val, key::AbstractString)
    isnothing(o.attributes) && error("Node has no attributes.")
    v = string(val)
    for i in eachindex(o.attributes)
        if first(o.attributes[i]) == key
            o.attributes[i] = key => v
            return v
        end
    end
    push!(o.attributes, key => v)
    v
end

function Base.push!(a::Node, b)
    isnothing(a.children) && error("Node does not accept children.")
    push!(a.children, _to_node(b))
    a
end

function Base.pushfirst!(a::Node, b)
    isnothing(a.children) && error("Node does not accept children.")
    pushfirst!(a.children, _to_node(b))
    a
end

#-----------------------------------------------------------------------------# show (REPL)
function Base.show(io::IO, o::Node)
    nt = o.nodetype
    print(io, nt)
    if nt === Text
        print(io, ' ', repr(o.value))
    elseif nt === Element
        print(io, " <", o.tag)
        if !isnothing(o.attributes)
            for (k, v) in o.attributes
                print(io, ' ', k, '=', '"', v, '"')
            end
        end
        print(io, '>')
        n = length(children(o))
        n > 0 && print(io, n == 1 ? " (1 child)" : " ($n children)")
    elseif nt === DTD
        print(io, " <!DOCTYPE ", o.value, '>')
    elseif nt === Declaration
        print(io, " <?xml")
        if !isnothing(o.attributes)
            for (k, v) in o.attributes
                print(io, ' ', k, '=', '"', v, '"')
            end
        end
        print(io, "?>")
    elseif nt === ProcessingInstruction
        print(io, " <?", o.tag)
        !isnothing(o.value) && print(io, ' ', o.value)
        print(io, "?>")
    elseif nt === Comment
        print(io, " <!--", o.value, "-->")
    elseif nt === CData
        print(io, " <![CDATA[", o.value, "]]>")
    elseif nt === Document
        n = length(children(o))
        n > 0 && print(io, n == 1 ? " (1 child)" : " ($n children)")
    end
end

#-----------------------------------------------------------------------------# show (text/xml)

# Write XML-escaped content directly to IO (single pass, no intermediate string)
function _write_escaped(io::IO, s::String)
    start = 1
    i = 1
    n = ncodeunits(s)
    @inbounds while i <= n
        b = codeunit(s, i)
        esc = if b == UInt8('&'); "&amp;"
        elseif b == UInt8('<'); "&lt;"
        elseif b == UInt8('>'); "&gt;"
        elseif b == UInt8('"'); "&quot;"
        elseif b == UInt8('\''); "&apos;"
        else
            i += 1
            continue
        end
        i > start && GC.@preserve s Base.unsafe_write(io, pointer(s, start), (i - start) % UInt)
        print(io, esc)
        i += 1
        start = i
    end
    start <= n && GC.@preserve s Base.unsafe_write(io, pointer(s, start), (n - start + 1) % UInt)
    nothing
end

# Cached indentation strings to avoid repeated allocation
const _MAX_CACHED_INDENT = 64
const _INDENT_STRINGS = [" " ^ n for n in 0:_MAX_CACHED_INDENT]
@inline function _indent_str(n::Int)
    0 <= n <= _MAX_CACHED_INDENT && return @inbounds _INDENT_STRINGS[n + 1]
    " " ^ n
end

function _print_attrs(io::IO, attributes)
    isnothing(attributes) && return
    for (k, v) in attributes
        print(io, ' ', k, "=\"")
        _write_escaped(io, v)
        print(io, '"')
    end
end

function _write_xml(io::IO, node::Node, depth::Int=0, indent::Int=2, preserve::Bool=false)
    pad = preserve ? "" : _indent_str(indent * depth)
    nt = node.nodetype
    if nt === Text
        _write_escaped(io, node.value)
    elseif nt === Element
        # Check xml:space on this element
        child_preserve = preserve
        if !isnothing(node.attributes)
            for (k, v) in node.attributes
                k == "xml:space" && (child_preserve = v == "preserve")
            end
        end
        print(io, pad, '<', node.tag)
        _print_attrs(io, node.attributes)
        ch = node.children
        if isnothing(ch) || isempty(ch)
            print(io, "/>")
        elseif length(ch) == 1 && only(ch).nodetype === Text
            print(io, '>')
            _write_xml(io, only(ch), 0, 0, child_preserve)
            print(io, "</", node.tag, '>')
        else
            child_preserve ? print(io, '>') : println(io, '>')
            for child in ch
                _write_xml(io, child, depth + 1, indent, child_preserve)
                child_preserve || println(io)
            end
            print(io, child_preserve ? "" : pad, "</", node.tag, '>')
        end
    elseif nt === Declaration
        print(io, pad, "<?xml")
        _print_attrs(io, node.attributes)
        print(io, "?>")
    elseif nt === ProcessingInstruction
        print(io, pad, "<?", node.tag)
        isnothing(node.value) || print(io, ' ', node.value)
        print(io, "?>")
    elseif nt === Comment
        print(io, pad, "<!--", node.value, "-->")
    elseif nt === CData
        print(io, pad, "<![CDATA[", node.value, "]]>")
    elseif nt === DTD
        print(io, pad, "<!DOCTYPE ", node.value, '>')
    elseif nt === Document
        ch = node.children
        if !isnothing(ch)
            for (i, child) in enumerate(ch)
                _write_xml(io, child, 0, indent, preserve)
                i < length(ch) && println(io)
            end
        end
    end
end

Base.show(io::IO, ::MIME"text/xml", node::Node) = _write_xml(io, node)

#-----------------------------------------------------------------------------# write / read
write(node::Node; indentsize::Int=2) = (io = IOBuffer(); _write_xml(io, node, 0, indentsize); String(take!(io)))
write(filename::AbstractString, node::Node; kw...) = open(io -> write(io, node; kw...), filename, "w")
write(io::IO, node::Node; indentsize::Int=2) = _write_xml(io, node, 0, indentsize)

Base.read(filename::AbstractString, ::Type{Node}) = parse(read(filename, String), Node)
Base.read(io::IO, ::Type{Node}) = parse(read(io, String), Node)

#-----------------------------------------------------------------------------# parse
Base.parse(::Type{Node}, xml::AbstractString) = parse(xml, Node)

function Base.parse(xml::AbstractString, ::Type{Node})
    _parse(String(xml), String, unescape)
end

function Base.parse(xml::AbstractString, ::Type{Node{SubString{String}}})
    _parse(String(xml), SubString{String}, identity)
end

_to(::Type{String}, s::AbstractString) = String(s)
_to(::Type{SubString{String}}, s::SubString{String}) = s

_nothingify(v::Vector) = isempty(v) ? nothing : v

function _parse(xml::String, ::Type{S}, convert_text::F) where {S, F}
    tags = S[]
    attrs_stack = Vector{Pair{S,S}}[]
    children_stack = Vector{Vector{Node{S}}}()
    push!(children_stack, Node{S}[])

    pending_attr_name = SubString(xml, 1, 0)
    decl_attrs = nothing
    pending_pi_tag = SubString(xml, 1, 0)
    pending_pi_value = nothing
    in_close_tag = false

    for token in tokenize(xml)
        k = token.kind

        if k === TOKEN_TEXT
            push!(last(children_stack), Node{S}(Text, nothing, nothing, convert_text(token.raw), nothing))

        elseif k === TOKEN_OPEN_TAG
            push!(tags, _to(S, tag_name(token)))
            push!(attrs_stack, Pair{S,S}[])
            push!(children_stack, Node{S}[])

        elseif k === TOKEN_SELF_CLOSE
            t = pop!(tags)
            a = pop!(attrs_stack)
            pop!(children_stack)
            push!(last(children_stack), Node{S}(Element, t, _nothingify(a), nothing, nothing))

        elseif k === TOKEN_TAG_CLOSE
            in_close_tag && (in_close_tag = false)

        elseif k === TOKEN_CLOSE_TAG
            close_name = tag_name(token)
            isempty(tags) && error("Closing tag </$close_name> with no matching open tag.")
            t = pop!(tags)
            t == close_name || error("Mismatched tags: expected </$t>, got </$close_name>.")
            a = pop!(attrs_stack)
            c = pop!(children_stack)
            push!(last(children_stack), Node{S}(Element, t, _nothingify(a), nothing, isempty(c) ? nothing : c))
            in_close_tag = true

        elseif k === TOKEN_ATTR_NAME
            pending_attr_name = token.raw

        elseif k === TOKEN_ATTR_VALUE
            val = convert_text(attr_value(token))
            name = _to(S, pending_attr_name)
            if decl_attrs !== nothing
                any(p -> first(p) == name, decl_attrs) && error("Duplicate attribute: $name")
                push!(decl_attrs, name => val)
            elseif !isempty(attrs_stack)
                any(p -> first(p) == name, last(attrs_stack)) && error("Duplicate attribute: $name")
                push!(last(attrs_stack), name => val)
            end

        elseif k === TOKEN_XML_DECL_OPEN
            decl_attrs = Pair{S,S}[]

        elseif k === TOKEN_XML_DECL_CLOSE
            a = isempty(decl_attrs) ? nothing : decl_attrs
            push!(last(children_stack), Node{S}(Declaration, nothing, a, nothing, nothing))
            decl_attrs = nothing

        elseif k === TOKEN_COMMENT_CONTENT
            push!(last(children_stack), Node{S}(Comment, nothing, nothing, _to(S, token.raw), nothing))

        elseif k === TOKEN_CDATA_CONTENT
            push!(last(children_stack), Node{S}(CData, nothing, nothing, _to(S, token.raw), nothing))

        elseif k === TOKEN_DOCTYPE_CONTENT
            push!(last(children_stack), Node{S}(DTD, nothing, nothing, _to(S, lstrip(token.raw)), nothing))

        elseif k === TOKEN_PI_OPEN
            pending_pi_tag = pi_target(token)
            pending_pi_value = nothing

        elseif k === TOKEN_PI_CONTENT
            content = strip(token.raw)
            pending_pi_value = isempty(content) ? nothing : _to(S, content)

        elseif k === TOKEN_PI_CLOSE
            push!(last(children_stack), Node{S}(ProcessingInstruction, _to(S, pending_pi_tag), nothing, pending_pi_value, nothing))
        end
    end

    !isempty(tags) && error("Unclosed tags: $(join(tags, ", "))")
    doc_children = only(children_stack)
    Node{S}(Document, nothing, nothing, nothing, isempty(doc_children) ? nothing : doc_children)
end

#-----------------------------------------------------------------------------# h (HTML/XML element builder)
"""
    h(tag, children...; attrs...)
    h.tag(children...; attrs...)

Convenience constructor for `Element` nodes.

    h("div", "hello"; class="main")  # <div class="main">hello</div>
    h.div("hello"; class="main")     # same thing
"""
function h(tag::Union{Symbol, AbstractString}, children...; attrs...)
    t = String(tag)
    a = Pair{String,String}[String(k) => String(v) for (k, v) in pairs(attrs)]
    c = Node{String}[_to_node(x) for x in children]
    Node{String}(Element, t, a, nothing, c)
end

Base.getproperty(::typeof(h), tag::Symbol) = h(tag)

function (o::Node)(args...; attrs...)
    o.nodetype === Element || error("Only Element nodes are callable.")
    old_children = something(o.children, ())
    old_attrs = isnothing(o.attributes) ? () : (Symbol(k) => v for (k, v) in o.attributes)
    h(o.tag, old_children..., args...; old_attrs..., attrs...)
end

#-----------------------------------------------------------------------------# DTD parsing
struct ElementDecl
    name::String
    content::String  # "EMPTY", "ANY", or content model like "(#PCDATA)" or "(a,b,c)*"
end

struct AttDecl
    element::String
    name::String
    type::String     # "CDATA", "ID", "(val1|val2)", "NOTATION (a|b)", etc.
    default::String  # "#REQUIRED", "#IMPLIED", "#FIXED \"val\"", or "\"val\""
end

struct EntityDecl
    name::String
    value::Union{Nothing, String}       # replacement text (internal entities)
    external_id::Union{Nothing, String} # "SYSTEM \"uri\"" or "PUBLIC \"pubid\" \"uri\""
    parameter::Bool
end

struct NotationDecl
    name::String
    external_id::String
end

struct ParsedDTD
    root::String
    system_id::Union{Nothing, String}
    public_id::Union{Nothing, String}
    elements::Vector{ElementDecl}
    attributes::Vector{AttDecl}
    entities::Vector{EntityDecl}
    notations::Vector{NotationDecl}
end

# DTD parsing helpers
@inline _dtd_is_name_char(c::Char) =
    ('a' <= c <= 'z') || ('A' <= c <= 'Z') || ('0' <= c <= '9') ||
    c == '_' || c == '-' || c == '.' || c == ':'

function _dtd_skip_ws(s, pos)
    while pos <= ncodeunits(s) && isspace(s[pos])
        pos += 1
    end
    pos
end

function _dtd_read_name(s, pos)
    pos = _dtd_skip_ws(s, pos)
    start = pos
    while pos <= ncodeunits(s) && _dtd_is_name_char(s[pos])
        pos += 1
    end
    start == pos && error("Expected name at position $pos in DTD")
    SubString(s, start, pos - 1), pos
end

function _dtd_read_quoted(s, pos)
    pos = _dtd_skip_ws(s, pos)
    q = s[pos]
    (q == '"' || q == '\'') || error("Expected quoted string at position $pos in DTD")
    pos += 1
    start = pos
    while pos <= ncodeunits(s) && s[pos] != q
        pos += 1
    end
    val = SubString(s, start, pos - 1)
    pos += 1
    val, pos
end

function _dtd_read_parens(s, pos)
    pos = _dtd_skip_ws(s, pos)
    s[pos] == '(' || error("Expected '(' at position $pos in DTD")
    depth = 1
    start = pos
    pos += 1
    while pos <= ncodeunits(s) && depth > 0
        c = s[pos]
        if c == '('
            depth += 1
        elseif c == ')'
            depth -= 1
        elseif c == '"' || c == '\''
            pos += 1
            while pos <= ncodeunits(s) && s[pos] != c
                pos += 1
            end
        end
        pos += 1
    end
    SubString(s, start, pos - 1), pos
end

function _dtd_skip_to_close(s, pos)
    while pos <= ncodeunits(s) && s[pos] != '>'
        c = s[pos]
        if c == '"' || c == '\''
            pos += 1
            while pos <= ncodeunits(s) && s[pos] != c
                pos += 1
            end
        end
        pos += 1
    end
    pos <= ncodeunits(s) ? pos + 1 : pos
end

function _dtd_parse_element(s, pos)
    name, pos = _dtd_read_name(s, pos)
    pos = _dtd_skip_ws(s, pos)
    if s[pos] == '('
        content, pos = _dtd_read_parens(s, pos)
        if pos <= ncodeunits(s) && s[pos] in ('*', '+', '?')
            content = string(content, s[pos])
            pos += 1
        end
    else
        content, pos = _dtd_read_name(s, pos)
    end
    pos = _dtd_skip_to_close(s, pos)
    ElementDecl(String(name), String(content)), pos
end

function _dtd_parse_attlist(s, pos)
    element, pos = _dtd_read_name(s, pos)
    atts = AttDecl[]
    while true
        pos = _dtd_skip_ws(s, pos)
        (pos > ncodeunits(s) || s[pos] == '>') && break

        name, pos = _dtd_read_name(s, pos)
        pos = _dtd_skip_ws(s, pos)

        # Attribute type
        if s[pos] == '('
            atype, pos = _dtd_read_parens(s, pos)
        else
            atype, pos = _dtd_read_name(s, pos)
            if atype == "NOTATION"
                pos = _dtd_skip_ws(s, pos)
                parens, pos = _dtd_read_parens(s, pos)
                atype = string("NOTATION ", parens)
            end
        end
        pos = _dtd_skip_ws(s, pos)

        # Default declaration
        if s[pos] == '#'
            pos += 1
            keyword, pos = _dtd_read_name(s, pos)
            if keyword == "FIXED"
                pos = _dtd_skip_ws(s, pos)
                val, pos = _dtd_read_quoted(s, pos)
                default = string("#FIXED \"", val, "\"")
            else
                default = string("#", keyword)
            end
        elseif s[pos] == '"' || s[pos] == '\''
            val, pos = _dtd_read_quoted(s, pos)
            default = string("\"", val, "\"")
        else
            error("Expected default declaration at position $pos in DTD")
        end
        push!(atts, AttDecl(String(element), String(name), String(atype), default))
    end
    pos <= ncodeunits(s) && s[pos] == '>' && (pos += 1)
    atts, pos
end

function _dtd_parse_entity(s, pos)
    pos = _dtd_skip_ws(s, pos)
    parameter = false
    if pos <= ncodeunits(s) && s[pos] == '%'
        parameter = true
        pos += 1
    end
    name, pos = _dtd_read_name(s, pos)
    pos = _dtd_skip_ws(s, pos)

    value = nothing
    external_id = nothing
    if s[pos] == '"' || s[pos] == '\''
        v, pos = _dtd_read_quoted(s, pos)
        value = String(v)
    else
        keyword, pos = _dtd_read_name(s, pos)
        pos = _dtd_skip_ws(s, pos)
        if keyword == "SYSTEM"
            uri, pos = _dtd_read_quoted(s, pos)
            external_id = string("SYSTEM \"", uri, "\"")
        elseif keyword == "PUBLIC"
            pubid, pos = _dtd_read_quoted(s, pos)
            pos = _dtd_skip_ws(s, pos)
            uri, pos = _dtd_read_quoted(s, pos)
            external_id = string("PUBLIC \"", pubid, "\" \"", uri, "\"")
        else
            error("Expected SYSTEM, PUBLIC, or quoted value in ENTITY declaration")
        end
    end
    pos = _dtd_skip_to_close(s, pos)
    EntityDecl(String(name), value, external_id, parameter), pos
end

function _dtd_parse_notation(s, pos)
    name, pos = _dtd_read_name(s, pos)
    pos = _dtd_skip_ws(s, pos)
    keyword, pos = _dtd_read_name(s, pos)
    pos = _dtd_skip_ws(s, pos)
    if keyword == "SYSTEM"
        uri, pos = _dtd_read_quoted(s, pos)
        external_id = string("SYSTEM \"", uri, "\"")
    elseif keyword == "PUBLIC"
        pubid, pos = _dtd_read_quoted(s, pos)
        pos = _dtd_skip_ws(s, pos)
        if pos <= ncodeunits(s) && (s[pos] == '"' || s[pos] == '\'')
            uri, pos = _dtd_read_quoted(s, pos)
            external_id = string("PUBLIC \"", pubid, "\" \"", uri, "\"")
        else
            external_id = string("PUBLIC \"", pubid, "\"")
        end
    else
        error("Expected SYSTEM or PUBLIC in NOTATION declaration")
    end
    pos = _dtd_skip_to_close(s, pos)
    NotationDecl(String(name), external_id), pos
end

"""
    parse_dtd(value::AbstractString) -> ParsedDTD
    parse_dtd(node::Node) -> ParsedDTD

Parse a DTD value string (from a `DTD` node) into structured declarations.
"""
function parse_dtd(value::AbstractString)
    s = String(value)
    pos = 1

    root, pos = _dtd_read_name(s, pos)
    pos = _dtd_skip_ws(s, pos)

    # External ID
    system_id = nothing
    public_id = nothing
    if pos <= ncodeunits(s) && _dtd_is_name_char(s[pos])
        keyword, kpos = _dtd_read_name(s, pos)
        if keyword == "SYSTEM"
            pos = kpos
            uri, pos = _dtd_read_quoted(s, pos)
            system_id = String(uri)
        elseif keyword == "PUBLIC"
            pos = kpos
            pubid, pos = _dtd_read_quoted(s, pos)
            public_id = String(pubid)
            pos = _dtd_skip_ws(s, pos)
            if pos <= ncodeunits(s) && (s[pos] == '"' || s[pos] == '\'')
                uri, pos = _dtd_read_quoted(s, pos)
                system_id = String(uri)
            end
        end
    end

    elements = ElementDecl[]
    attributes = AttDecl[]
    entities = EntityDecl[]
    notations = NotationDecl[]

    # Internal subset
    pos = _dtd_skip_ws(s, pos)
    if pos <= ncodeunits(s) && s[pos] == '['
        pos += 1
        while pos <= ncodeunits(s)
            pos = _dtd_skip_ws(s, pos)
            pos > ncodeunits(s) && break
            s[pos] == ']' && break

            rest = SubString(s, pos)
            if startswith(rest, "<!--")
                i = findnext("-->", s, pos + 4)
                isnothing(i) && error("Unterminated comment in DTD")
                pos = last(i) + 1
            elseif startswith(rest, "<?")
                i = findnext("?>", s, pos + 2)
                isnothing(i) && error("Unterminated PI in DTD")
                pos = last(i) + 1
            elseif startswith(rest, "<!ELEMENT")
                elem, pos = _dtd_parse_element(s, pos + 9)
                push!(elements, elem)
            elseif startswith(rest, "<!ATTLIST")
                atts, pos = _dtd_parse_attlist(s, pos + 9)
                append!(attributes, atts)
            elseif startswith(rest, "<!ENTITY")
                ent, pos = _dtd_parse_entity(s, pos + 8)
                push!(entities, ent)
            elseif startswith(rest, "<!NOTATION")
                not, pos = _dtd_parse_notation(s, pos + 10)
                push!(notations, not)
            elseif s[pos] == '%'
                i = findnext(';', s, pos + 1)
                isnothing(i) && error("Unterminated parameter entity reference in DTD")
                pos = i + 1
            else
                pos += 1
            end
        end
    end

    ParsedDTD(String(root), system_id, public_id, elements, attributes, entities, notations)
end

function parse_dtd(node::Node)
    node.nodetype === DTD || error("parse_dtd requires a DTD node.")
    parse_dtd(node.value)
end

#-----------------------------------------------------------------------------# deprecations
Base.@deprecate_binding simplevalue simple_value false

# Removed types — informative errors
struct Raw
    Raw(args...; kw...) = error("""
        `XML.Raw` has been removed in XML.jl v0.4.
        Use `parse(str, Node)` or `read(filename, Node)` instead.
        The streaming Raw/LazyNode API has been replaced by a token-based parser.
        See `?XML.Node` for the new API.""")
end

# Removed functions — informative errors
const _REMOVED_LAZYNODE_MSG = """
    This function was part of the LazyNode API, which has been removed in XML.jl v0.4.
    Use `parse(str, Node)` to get a full DOM tree and navigate with `children`, `tag`,
    `attributes`, `value`, and integer indexing (e.g. `node[1]`)."""

for f in (:next, :prev)
    msg = "`XML.$f` has been removed. $_REMOVED_LAZYNODE_MSG"
    @eval function $f(o::Node)
        Base.depwarn($msg, $(QuoteNode(f)))
        error($msg)
    end
end

# 1-arg parent/depth were part of LazyNode API; 2-arg versions are defined above
const _PARENT_1ARG_MSG = "`XML.parent(node)` (single-argument) has been removed. $_REMOVED_LAZYNODE_MSG\n    Use `parent(child, root)` instead to search from a known root node."
function Base.parent(o::Node)
    Base.depwarn(_PARENT_1ARG_MSG, :parent)
    error(_PARENT_1ARG_MSG)
end

const _DEPTH_1ARG_MSG = "`XML.depth(node)` (single-argument) has been removed. $_REMOVED_LAZYNODE_MSG\n    Use `depth(child, root)` instead to search from a known root node."
function depth(o::Node)
    Base.depwarn(_DEPTH_1ARG_MSG, :depth)
    error(_DEPTH_1ARG_MSG)
end

function nodes_equal(a, b)
    msg = """`XML.nodes_equal` has been removed in XML.jl v0.4. Use `==` instead:
        a == b"""
    Base.depwarn(msg, :nodes_equal)
    error(msg)
end

function escape!(o::Node, warn::Bool=true)
    msg = """`XML.escape!` has been removed in XML.jl v0.4.
        Text is now escaped automatically during `XML.write`."""
    Base.depwarn(msg, :escape!)
    error(msg)
end

function unescape!(o::Node, warn::Bool=true)
    msg = """`XML.unescape!` has been removed in XML.jl v0.4.
        Text is now unescaped automatically during `parse`."""
    Base.depwarn(msg, :unescape!)
    error(msg)
end

end # module XML
