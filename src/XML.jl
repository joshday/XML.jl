module XML

using StyledStrings, StringViews

export tokens, escape, unescape

#-----------------------------------------------------------------------------# escape/unescape
const escape_chars = ('&' => "&amp;", '<' => "&lt;", '>' => "&gt;", "'" => "&apos;", '"' => "&quot;")
unescape(x::AbstractString) = replace(x, reverse.(escape_chars)...)
escape(x::AbstractString) = replace(x, escape_chars...)

#-----------------------------------------------------------------------------# misc. utils
# Add _ separator for large Ints
format(x::Int) = replace(string(x), r"(\d)(?=(\d{3})+(?!\d))" => s"\1_")

#-----------------------------------------------------------------------------# Token
"""
Enumeration of XML token types:

| Token Type | Decription | Example |
|------------|:-----------|:-------|
| UNKNOWN_TOKEN | Unknown token type | ??? |
| TAGSTART_TOKEN | Start of a tag | `<name` |
| TAGEND_TOKEN | End of a tag | `>` |
| TAGCLOSE_TOKEN | Closing tag | `</name>` |
| TAGSELFCLOSE_TOKEN | Self-closing tag | `/>` |
| EQUALS_TOKEN | Equals sign | `=` |
| ATTRKEY_TOKEN | Attribute key | `key` |
| ATTRVAL_TOKEN | Attribute value | `"value"` |
| TEXT_TOKEN | Text between tags | `text` |
| PI_START_TOKEN | Start of processing instruction | `<?target` |
| PI_END_TOKEN | End of processing instruction | `?>` |
| DECL_START_TOKEN | Start of XML declaration | `<?xml` |
| COMMENT_TOKEN | Comment | `<!-- comment -->` |
| CDATA_TOKEN | CDATA section | `<![CDATA[ ... ]]>` |
| DTD_TOKEN | Document type declaration | `<!DOCTYPE ... >` |
| WS_TOKEN | Whitespace | One of `' ', '\\t', '\\r', '\\n'` |
| ENTITYREF_TOKEN | Entity reference | `&name;` |
"""
@enum TokenType begin
    UNKNOWN_TOKEN
    TAGSTART_TOKEN      # <tag
    TAGEND_TOKEN        # >
    TAGCLOSE_TOKEN      # </tag>
    TAGSELFCLOSE_TOKEN  # />
    EQUALS_TOKEN        # =
    ATTRKEY_TOKEN       # attr
    ATTRVAL_TOKEN       # "value"
    TEXT_TOKEN          # between > and <
    PI_START_TOKEN      # <?target data
    PI_END_TOKEN        # ?>
    DECL_START_TOKEN    # <?xml
    COMMENT_TOKEN       # <!-- ... -->
    CDATA_TOKEN         # <![CDATA[ ... ]]>
    DTD_TOKEN           # <!DOCTYPE ... >
    WS_TOKEN            # " \t\n\r"
    ENTITYREF_TOKEN     # &name;
end

"""
Enumeration of xml:space states (used for Lexer iteration):

| State | Description |
|-------|:------------|
| DEFAULT | Default whitespace handling (collapse) |
| PRESERVE | Preserve all whitespace |
| CHECK | Indicates an attribute key was `xml:space` and the following value should be checked for "preserve" or "default" |
"""
@enum PRESERVE_SPACE_STATE begin
    DEFAULT
    PRESERVE
    CHECK  # Indicates attr key was `xml:space` --> attr value should be checked for "preserve" or "default"
end

#-----------------------------------------------------------------------------# Token
"""
    Token(data::Union{IO, AbstractVector{UInt8}}, type, i, j, preserve_space=false)

A view into `data` from indices `i` to `j` (inclusive) of token type `type`.
If `preserve_space` is true then this token is inside an `xml:space="preserve"` context.
"""
struct Token{T <: Union{IO, AbstractVector{UInt8}}}
    data::T
    type::TokenType
    i::Int
    j::Int
    preserve_space::Bool  # Is token inside an `xml:space="preserve"` context
end
Token(data) = Token(data, UNKNOWN_TOKEN, 1, 0, false)
(t::Token)(type, j, preserve_space=t.preserve_space) = Token(t.data, type, t.i, j, preserve_space)

Base.view(t::Token) = view(t.data, t.i:t.j)
StringViews.StringView(t::Token) = StringView(t.data)[t.i:t.j]

function Base.show(io::IO, t::Token)
    n = length(t.data)
    rng_width = 2length(format(n)) + 1
    print(io, styled"{bright_yellow:$(rpad(t.type, 19))}", rpad(format(t.i) * ":" * format(t.j), rng_width))
    # print(io, styled"{bright_black:($(Base.format_bytes(ncodeunits(StringView(t)))))}")
    s = repr(StringView(t))[2:end-1]
    print(io, styled" {inverse:{bright_green:$s}}")
    t.preserve_space && print(io, styled" {bright_cyan:(preserve_space)}")
end

#-----------------------------------------------------------------------------# Lexer
"""
    Lexer(data::Union{IO, AbstractVector{UInt8}})

A lexer that tokenizes XML data from an `IO` or `Vector{UInt8}` source.  Tokens are produced by iterating over the lexer.

### Example

    using XML

    lex = XML.Lexer(b"<tag>content</tag>")

    collect(lex)
"""
struct Lexer{T <: Union{IO, AbstractVector{UInt8}}}
    data::T
end
Base.show(io::IO, o::Lexer) = print(io, "XML.Lexer(", Base.format_bytes(length(o.data)), ')')

Base.IteratorSize(::Type{Lexer{T}}) where {T} = Base.SizeUnknown()
Base.eltype(::Type{Lexer{T}}) where {T} = Token{T}
Base.isdone(o::Lexer{T}, t::Token{T}) where {T} = t.j == length(t.data)

function Base.iterate(o::Lexer, state=(Token(o.data), [DEFAULT], false))
    # `stack` tracks PRESERVE_SPACE_STATE of nested elements
    prev, stack, in_tag = state
    (; data, type) = prev
    preserve_space = stack[end] == PRESERVE
    i = prev.j + 1
    i > length(data) && return nothing
    sv = StringView(@view(data[i:end]))
    c = sv[1]
    t = if in_tag  # flips on for `<` and `<?xml`, flips off for `>`, `/>`, and `?>`
        if is_ws(c)
            j = findnext(!is_ws, sv, 2)
            j = isnothing(j) ? length(data) : i + j - 2
            Token(data, WS_TOKEN, i, j, false)  # WS_TOKEN inside tag is never significant
        elseif is_name_start_char(c)
            j = findnext(!is_name_char, sv, 2)
            isnothing(j) && error("Malformed XML: reached end of data while parsing attribute key.")
            out = Token(data, ATTRKEY_TOKEN, i, i + j - 2, preserve_space)
            if StringView(out) == "xml:space"
                stack[end] = CHECK
            end
            out
        elseif c == '='
            Token(data, EQUALS_TOKEN, i, i, preserve_space)
        elseif c in (''', '"')
            j = findnext(c, sv, 2)
            isnothing(j) && error("Malformed XML: reached end of data while parsing attribute value.")
            out = Token(data, ATTRVAL_TOKEN, i, i + j - 1, preserve_space)
            if stack[end] == CHECK
                stack[end] = StringView(out)[2:end-1] == "preserve" ? PRESERVE : DEFAULT
            end
            out
        elseif c == '>'
            in_tag = false
            Token(data, TAGEND_TOKEN, i, i, preserve_space)
        elseif startswith(sv, "/>")
            in_tag = false
            pop!(stack)
            Token(data, TAGSELFCLOSE_TOKEN, i, i + 1, preserve_space)
        elseif startswith(sv, "?>")
            in_tag = false
            Token(data, PI_END_TOKEN, i, i + 1, preserve_space)
        else
            error("Malformed XML: unexpected character '$(c)' inside tag at position $(i).")
        end
    elseif startswith(sv, "<?xml ")
        in_tag = true
        Token(data, DECL_START_TOKEN, i, i + 4, preserve_space)
    elseif startswith(sv, "<?")
        j = findnext("?>", sv, 3)
        in_tag = true
        isnothing(j) && error("Malformed XML: reached end of data while parsing processing instruction.")
        Token(data, PI_START_TOKEN, i, i + j[1] - 2, preserve_space)
    elseif startswith(sv, "<!--")
        j = findnext("-->", sv, 5)
        isnothing(j) && error("Malformed XML: reached end of data while parsing comment.")
        Token(data, COMMENT_TOKEN, i, i + j[end] - 1, preserve_space)
    elseif startswith(sv, "<![CDATA[")
        j = findnext("]]>", sv, 10)
        isnothing(j) && error("Malformed XML: reached end of data while parsing CDATA.")
        Token(data, CDATA_TOKEN, i, i + j[end] - 1, preserve_space)
    elseif startswith(sv, "<!DOCTYPE")
        # Need to find matching '>', ignoring any nested '<...>' from e.g. `<!ELEMENT ...>`
        count = 0
        j = i
        for (_j, c) in enumerate(sv)
            c == '<' && (count += 1)
            c == '>' && (count -= 1)
            if count == 0
                j = _j
                break
            end
        end
        j == length(sv) && error("Malformed XML: reached end of data while parsing DOCTYPE.")
        Token(data, DTD_TOKEN, i, i + j - 1, preserve_space)
    elseif startswith(sv, "</")
        j = findnext('>', sv, 3)
        isnothing(j) && error("Malformed XML: reached end of data while parsing closing tag.")
        pop!(stack)
        in_tag = false
        Token(data, TAGCLOSE_TOKEN, i, i + j - 1, preserve_space)
    elseif c == '<'
        j = findnext(!is_name_char, sv, 2)
        isnothing(j) && error("Malformed XML: reached end of data while parsing tag start.")
        in_tag = true
        push!(stack, stack[end])  # only place to push new state onto stack
        Token(data, TAGSTART_TOKEN, i, i + j - 2, preserve_space)
    elseif c == '&'
        j = findnext(';', sv, 2)
        isnothing(j) && error("Malformed XML: reached end of data while parsing entity reference.")
        Token(data, ENTITYREF_TOKEN, i, i + j - 1, preserve_space)
    elseif is_ws(c)
        # This whitespace is outside of a tag e.g. `<name ...>`
        j = findnext(!is_ws, sv, 2)
        j = isnothing(j) ? length(data) : i + j - 2
        Token(data, WS_TOKEN, i, j, preserve_space)
    else # TEXT
        j = findnext(x -> x ∈ ('<', '&'), sv, 2)
        isnothing(j) && error("Malformed XML: reached end of data while parsing text.")
        Token(data, TEXT_TOKEN, i, i + j - 2, preserve_space)
    end
    return t, (t, stack, in_tag)
end


is_ws(x::Char) = x in (' ', '\t', '\n', '\r')

# For tag names and attribute keys:
function is_name_start_char(c::Char)
    c == ':' || c == '_' ||
    ('A' ≤ c ≤ 'Z') || ('a' ≤ c ≤ 'z') ||
    ('\u00C0' ≤ c ≤ '\u00D6') ||
    ('\u00D8' ≤ c ≤ '\u00F6') ||
    ('\u00F8' ≤ c ≤ '\u02FF') ||
    ('\u0370' ≤ c ≤ '\u037D') ||
    ('\u037F' ≤ c ≤ '\u1FFF') ||
    ('\u200C' ≤ c ≤ '\u200D') ||
    ('\u2070' ≤ c ≤ '\u218F') ||
    ('\u2C00' ≤ c ≤ '\u2FEF') ||
    ('\u3001' ≤ c ≤ '\uD7FF') ||
    ('\uF900' ≤ c ≤ '\uFDCF') ||
    ('\uFDF0' ≤ c ≤ '\uFFFD') ||
    ('\U00010000' ≤ c ≤ '\U000EFFFF')
end
function is_name_char(c::Char)
    is_name_start_char(c) ||
    c == '-' || c == '.' ||
    ('0' ≤ c ≤ '9') ||
    c == '\u00B7' ||
    ('\u0300' ≤ c ≤ '\u036F') ||
    ('\u203F' ≤ c ≤ '\u2040')
end

#-----------------------------------------------------------------------------# write
write(x) = sprint(write, x)

write(io::IO, x::AbstractString) = print(io, escape(x))

function write(io::IO, x::T) where {T}
    Base.isconcretetype(T) || error("Fallback method for XML.write only defined for concrete types.  Found: $T")
    print(io, "<", T.name.name)
    for (k, S) in zip(fieldnames(T), fieldtypes(T))
        print(io, ' ', k, '=', '"', S, '"')
    end
    print(io, '>')
    for (name, val) in zip(fieldnames(T), [getfield(x,f) for f in fieldnames(T)])
        print(io, '<', name, '>', val, "</", name, '>')
    end
    print(io, "</", T.name.name, '>')
end

#-----------------------------------------------------------------------------# Components
include("Components.jl")

#-----------------------------------------------------------------------------# Node
@enum Kind CData Comment Declaration DTD Document Doctype Element Fragment ProcessingInstruction Text

# The "schema":
# - CData/Comment/Text: value
# - Declaration: attributes with keys: version, encoding, standalone
# - Doctype: value
# - Document and Fragment: children
# - Element: name, attributes, children
# - DTD: (Not used yet)
# - ProcessingInstruction: name==target, value==data

struct Node{T}
    kind::Kind
    name::Union{T, Nothing}
    value::Union{T, Nothing}
    attributes::Union{Dict{T,T}, Nothing}
    children::Union{Vector{Node{T}}, Nothing}

    function Node{T}(kind, name, value, attributes, children) where {T}
        name = isnothing(name) ? name : T(name)
        value = isnothing(value) ? value : T(value)
        attributes = isnothing(attributes) ? attributes : Dict{T,T}((T(k) => T(v) for (k,v) in pairs(attributes))...)
        children = isnothing(children) ? children :
            isempty(children) ? Node{T}[] : Vector{Node{T}}(children)
        new{T}(kind, name, value, attributes, children)
    end
end
Node(kind, name, value, attributes, children) = Node{String}(kind, name, value, attributes, children)
Node(s::AbstractString) = Text(s)

function (o::Node)(x...; kw...)
    o.kind == Element || error("Only Element nodes can have children or attributes added.  Found: $(o.kind).")
    children = [o.children..., Node.(x)...]
    attrs = merge(o.attributes, Dict((string(k) => string(v) for (k,v) in pairs(kw))...))
    return Node(o.kind, o.name, o.value, attrs, children)
end

Base.show(io::IO, o::Node) = write(io, o)

function write(io::IO, o::Node)
    if o.kind == CData
        return print(io, "<![CDATA[", o.value, "]]>")
    elseif o.kind == Comment
        return print(io, "<!--", o.value, "-->")
    elseif o.kind == Declaration
        print(io, "<?xml version=\"", o.attributes["version"], "\"")
        haskey(o.attributes, "encoding") && print(io, " encoding=", repr(o.attributes["encoding"]))
        haskey(o.attributes, "standalone") && print(io, " standalone=", repr(o.attributes["standalone"]))
        return print(io, "?>")
    elseif o.kind in (Document, Fragment)
        return foreach(x -> write(io, x), o.children)
    elseif o.kind == Doctype
        return print(io, "<!DOCTYPE ", o.value, '>')
    elseif o.kind == ProcessingInstruction
        return print(io, "<?", o.name, ' ', o.value, "?>")
    elseif o.kind == Text
        return print(io, escape(o.value))
    elseif o.kind == Element
        print(io, '<', o.name)
        isempty(o.attributes) || print(io, ' ', join(["$(k)=$(repr(v))" for (k,v) in pairs(o.attributes)], ' '))
        print(io, '>')
        foreach(x -> write(io, x), o.children)
        return print(io, "</", o.name, '>')
    elseif o.kind in (Document, Fragment)
        return foreach(x -> write(io, x), o.children)
    end
    error("XML.write for Node of kind $(o.kind) not implemented.")  # should be unreachable
end

function (T::Kind)(x...; kw...)
    if T == CData  # <![CDATA[ ... ]]>
        isempty(kw) || error("CDATA does not take attributes.")
        length(x) == 1 || error("CData requires exactly one argument. Found: $(length(x)) arguments.")
        return Node(CData, nothing, x[1], nothing, nothing)
    elseif T == Comment  # <!-- ... -->
        isempty(kw) || error("Comment does not take attributes.")
        length(x) == 1 || error("Comment requires exactly one argument. Found: $(length(x)) arguments.")
        return Node(Comment, nothing, x[1], nothing, nothing)
    elseif T == Declaration  # <?xml ... ?>
        isempty(setdiff(keys(kw), (:version, :encoding, :standalone))) || error("Declaration only takes `version`, `encoding`, and `standalone` attributes.")
        isempty(x) || error("Declaration does not take positional arguments.  Found: $(length(x)) arguments.")
        attrs = Dict((string(k) => string(v) for (k,v) in pairs(kw))...)
        get(attrs, "standalone", "yes") in ("yes", "no") || error("Declaration `standalone` attribute value must be \"yes\" or \"no\".  Found: $(attrs["standalone"])")
        return Node(Declaration, nothing, nothing, attrs, nothing)
    elseif T in (Document, Fragment)
        isempty(kw) || error("$T does not take attributes.")
        length(x) > 0 || error("$T requires at least one child node. Found: $(length(x)) arguments.")
        return Node(T, nothing, nothing, nothing, map(Node, x))
    elseif T == Doctype  # <!DOCTYPE ... >
        isempty(kw) || error("Doctype does not take attributes.")
        0 < length(x) < 4 || error("Doctype requires 1-3 arguments. Found: $(length(x)) arguments.")
        return Node(Doctype, nothing, nothing, nothing, map(Node, x))
    elseif T == Element  # <element> ... </element>
        isempty(x) && error("Element requires at least one argument. Found: $(length(x)) arguments.")
        attrs = Dict((string(k) => string(v) for (k,v) in pairs(kw))...)
        return Node(Element, x[1], nothing, attrs, map(Node, x[2:end]))
    elseif T == ProcessingInstruction  # <?name ... ?>
        isempty(kw) || error("ProcessingInstruction does not take attributes.")
        length(x) == 2 || error("ProcessingInstruction requires exactly two arguments. Found: $(length(x)) arguments.")
        return Node(ProcessingInstruction, x[1], x[2], nothing, nothing)
    elseif T == Text
        length(x) == 1 || error("Text requires exactly one argument. Found: $(length(x)) arguments.")
        isempty(kw) || error("Text does not take attributes.")
        return Node(Text, nothing, x[1], nothing, nothing)
    end
    error("XML: $T(x...; kw...) not implemented.")  # should be unreachable
end

h(name, children...; kw...) = Element(name, children...; kw...)
Base.getproperty(::typeof(h), tag::Symbol) = h(string(tag))

#-----------------------------------------------------------------------------# validate
function validate(o::Node)
    error("TODO: XML.validate not implemented.")
end

#-----------------------------------------------------------------------------# parse
struct Parser{T <: Iterators.Stateful}
    itr::T
end
Parser(data::AbstractVector{UInt8}) = Parser(Iterators.Stateful(Lexer(data)))
Base.show(io::IO, o::Parser) = print(io, "XML.Parser(", Base.format_bytes(length(o.itr.itr.data)), ')')

function skip_ws!(p::Parser)
    while true
        t = peek(p.itr)
        if t.type == WS_TOKEN && !t.preserve_space
            t = popfirst!(p.itr)
        else
            return t
        end
    end
end

function Node(p::Parser)
    Iterators.reset!(p.itr)
    t = skip_ws!(p)
    S = typeof(StringView(t))
    children = Node{S}[]
    while t.j < length(t.data)
        t = skip_ws!(p)
        if t.type == DECL_START_TOKEN
            key = StringView(t)
            val = StringView(t)
            attrs = Dict{S,S}()
            for t2 in p.itr
                t2.type == ATTRKEY_TOKEN && (key = StringView(t2))
                t2.type == ATTRVAL_TOKEN && (val = StringView(t2)[2:end-1]; attrs[key] = val)
                t2.type in (TAGEND_TOKEN, TAGSELFCLOSE_TOKEN) && break
            end
            push!(children, Node{S}(Declaration, nothing, nothing, attrs, nothing))
        elseif t.type == CData
            push!(children, Node{S}(CData, nothing, StringView(t)[9:end-3], nothing, nothing))
        elseif t.type == COMMENT_TOKEN
            push!(children, Node{S}(Comment, nothing, StringView(t)[5:end-3], nothing, nothing))
        elseif t.type == TEXT_TOKEN
            push!(children, Node{S}(Text, nothing, StringView(t), nothing, nothing))
        elseif t.type == PI_START_TOKEN
            j = findnext(' ', StringView(t), 3)
            j === nothing && error("Malformed XML: processing instruction missing target and data.")
            target = StringView(t)[3:j-1]
            content = StringView(t)[j+1:end-2]
            push!(children, Node{S}(ProcessingInstruction, target, content, nothing, nothing))
        elseif t.type == TAGSTART_TOKEN
            error("TODO")
        end
    end

    return children
end


#   DTD Document Doctype Element Fragment ProcessingInstruction



# function Node(p::Parser)
#     Iterators.reset!(p.itr)
#     first_tok = peek(p.itr)
#     S = typeof(StringView(first_tok))
#     out = Node{S}(Document, nothing, nothing, nothing, Node{S}[])
#     cursor = Node{S}[]
#     for t in p.itr
#         if t.type == WS_TOKEN
#             t.preserve_space || continue
#             push!(cursor[end].children, StringV)
#         end
#     end
#     return out
# end

parsefile(file::AbstractString) = Node(Parser(read(file)))

# function Base.parse(itr)

# function parse_declaration(t)
#     first_tok = first(t)
#     first_tok.type == DECL_START_TOKEN || error("`parse_declaration` requires Tokens of type DECL_START_TOKEN.  Found: $(first_tok.type).")
#     key = StringView(first_tok)
#     val = StringView(first_tok)
#     S = typeof(key)
#     attrs = Dict{S,S}()
#     for t2 in t
#         t2.type == ATTRKEY_TOKEN && (key = StringView(t2))
#         t2.type == ATTRVAL_TOKEN && (val = StringView(t2)[2:end-1]; attrs[key] = val)
#         t2.type in (TAGEND_TOKEN, TAGSELFCLOSE_TOKEN) && return Node{S}(Declaration, nothing, nothing, attrs, nothing)
#     end
#     error("Malformed XML: reached end of tokens before closing '?>' of XML declaration.")
# end

# function Base.parse(lexer::Lexer{T}) where {T}
#     S = typeof(StringView(first(lexer)))
#     out = Node{S}(Document, nothing, nothing, nothing, Node{S}[])
#     cursor = Node{S}[]
#     for token in lexer
#         token.type == WS_TOKEN && !token.preserve_space && continue

#             # UNKNOWN_TOKEN
#             # TAGSTART_TOKEN      # <tag
#             # TAGEND_TOKEN        # >
#             # TAGCLOSE_TOKEN      # </tag>
#             # TAGSELFCLOSE_TOKEN  # />
#             # EQUALS_TOKEN        # =
#             # ATTRKEY_TOKEN       # attr
#             # ATTRVAL_TOKEN       # "value"
#             # TEXT_TOKEN          # between > and <
#             # PI_START_TOKEN      # <?target
#             # PI_END_TOKEN        # ?>
#             # DECL_START_TOKEN    # <?xml
#             # COMMENT_TOKEN       # <!-- ... -->
#             # CDATA_TOKEN         # <![CDATA[ ... ]]>
#             # DTD_TOKEN           # <!DOCTYPE ... >
#             # WS_TOKEN            # " \t\n\r"
#             # ENTITYREF_TOKEN     # &name;
#     end
# end


#-----------------------------------------------------------------------------# parsefile
# parsefile(file::AbstractString) = parse(Lexer(read(file)))

# #-----------------------------------------------------------------------------# xml
# xml(o) = sprint(xml, o)

# xml(io::IO, o::Node) = show(io, MIME("application/xml"), o)

# # Starting from `<tag` collect attributes until `>` or `/>`
# function parse_attributes(t::Token)
#     t.type in (TAGSTART_TOKEN, DECL_START_TOKEN) || error("`get_attributes` requires Tokens of type TAGSTART_TOKEN.  Found: $(t.type).")
#     S = typeof(StringView(t))
#     keys = S[]
#     vals = S[]
#     for t2 in t
#         t2.type == ATTRKEY_TOKEN && push!(keys, StringView(t2))
#         t2.type == ATTRVAL_TOKEN && push!(vals, StringView(t2))
#         t2.type in (TAGEND_TOKEN, TAGSELFCLOSE_TOKEN) && return Attributes(keys, vals), t2
#     end
#     error("Malformed XML: reached end of tokens before closing '>' of: <$name ...>")
# end


# # returns: (Node, next_token)
# function _parse(t::Token)
#     sv = StringView(t)
#     @info repr(sv)
#     S = typeof(sv)
#     if t.type == TAGSTART_TOKEN
#         name = sv[2:end]
#         attributes, t = parse_attributes(t)  # t.type here is TAGEND_TOKEN or TAGSELFCLOSE_TOKEN
#         children = Node{S}[]
#         t.type == TAGSELFCLOSE_TOKEN && return Node{S}(ELEMENT, name, attributes, nothing, children), next(t)
#         t = next(t)
#         stack = 1  # count of open tags with `name`
#         while stack > 0
#             sv = StringView(t)
#             isnothing(t) && error("Malformed XML: reached end of tokens before closing tag </$name>.")
#             if t.type == TAGCLOSE_TOKEN
#                 closing_name = sv[3:end-1]  # </name>
#                 @info "    close: $sv"
#                 closing_name == name || error("Malformed XML: found closing tag </$closing_name> but expected </$name>.")
#                 stack -= 1
#                 if stack == 0
#                     t = next(t)
#                     break
#                 end
#             else
#                 child, t = _parse(t)
#                 push!(children, child)
#             end
#         end
#         return Node{S}(ELEMENT, name, attributes, nothing, children), next(t)
#     elseif t.type == TEXT_TOKEN
#         return Node{S}(TEXT, nothing, nothing, sv, nothing), next(t)
#     elseif t.type == COMMENT_TOKEN
#         return Node{S}(COMMENT, nothing, nothing, sv[5:end-3], nothing), next(t)
#     elseif t.type == CDATA_TOKEN
#         return Node{S}(CDATA, nothing, nothing, sv[9:end-3], nothing), next(t)
#     elseif t.type == DECL_START_TOKEN
#         attributes, t = parse_attributes(t)
#         return Node{S}(DECLARATION, nothing, attributes, nothing, nothing), next(t)
#     elseif t.type == PI_START_TOKEN
#         j = findnext(' ', sv, 3)
#         target = sv[3:j-1]
#         content = sv[j+1:end-2]
#         return Node{S}(PI, target, nothing, content, nothing), next(t)
#     elseif t.type == DTD_TOKEN
#         j = findnext(' ', sv, 10)
#         name = sv[10:j-1]
#         return Node{S}(DTD, name, nothing, sv[j+1:end-3], nothing), next(t)
#     elseif t.type in (WS_TOKEN, TEXT_TOKEN)
#         return Node{S}(TEXT, nothing, nothing, sv, nothing), next(t)
#     else
#         error("Cannot parse XML Token: $t")
#     end
# end

# function parse_all(t::Token)
#     S = typeof(StringView(t))
#     children = Node{S}[]
#     while !isnothing(t)
#         node, t = _parse(t)
#         push!(children, node)
#     end
#     return children
# end









# #-----------------------------------------------------------------------------# Lexer
# # Iterates same tokens as Token...minus insignificant WS_TOKENs
# struct Lexer{T <: AbstractVector{UInt8}}
#     data::T
# end

# Base.IteratorSize(::Type{Lexer{T}}) where {T} = Base.SizeUnknown()
# Base.eltype(::Type{Lexer{T}}) where {T} = Token{T}
# Base.isdone(o::Lexer{T}, t::Token{T}) where {T} = t.j == length(t.data)
# function Base.iterate(o::Lexer, (; token=Token(o.data), check_val=false, preserve_stack=[false]))
#     n = next(token)
#     isnothing(n) && return nothing
#     if n.type == ATTRKEY_TOKEN && StringView(n) == "xml:space"
#         state = (; token=n, check_val=true, preserve)
#         return (n, state)
#     elseif n.type == ATTRVAL_TOKEN && check_val
#         s = @view StringView(n)[2:end-1]
#         preserve = s == "preserve"
#         state = (; token=n, check_val=false, preserve)
#         return (n, state)
# end


# #-----------------------------------------------------------------------------# FileNode
# @enum Kind UNKNOWN CDATA COMMENT DECLARATION DOCUMENT FRAGMENT DTD ELEMENT PI TEXT

# struct TokenNode{T}
#     tokens::Token{T}
#     preserve::Vector{Bool}
#     kind::Kind
#     cursor::Int
# end

# function TokenNode(toks::Vector{Token{T}}) where {T}
#     preserve = falses(length(toks))
#     check_val = false
#     for (i, t) in enumerate(toks)
#         if t.type == ATTRKEY_TOKEN && StringView(t) == "xml:space"
#             check_val = true
#         elseif t.type == ATTRVAL_TOKEN && check_val
#             s = @view StringView(t)[2:end-1]

#         end

#     end
# end


# """
#     File(s::AbstractString)

# Wrapper around `Vector{Token{T}}` with insignificant whitespace removed.
# """
# struct File{T}
#     tokens::Token{T}
# end

# # Sequence we need to look out for:
# #   - `ATTRKEY (xml:space) → WS? → EQUALS → WS? → ATTRVAL ("preserve | default")`
# function File(s::AbstractString)
#     toks = tokens(s)
#     out = eltype(toks)[]
#     preserve_space_stack = Bool[]
#     for t in toks
#         if isempty(preserve_space_stack)
#             t.type != WS_TOKEN && push!(out, t)
#         else

#         end
#     end
#     return out
# end


#-----------------------------------------------------------------------------# Node
# @enum Kind UNKNOWN CDATA COMMENT DECLARATION DOCUMENT FRAGMENT DTD ELEMENT PI TEXT

# struct Node{T <: AbstractString}
#     kind::Kind
#     preserve_space_stack::Vector{Bool}
#     name::Union{T, Nothing}
#     attributes::Union{Vector{Pair{T, T}}, Nothing}
#     value::Union{T, Nothing}
#     children::Union{Vector{Node{T}}, Nothing}
# end

# function document(s::T) where {T <: AbstractString}
#     out = Node{T}(DOCUMENT, Bool[], nothing, nothing, nothing, Node{T}[])
# end


# #-----------------------------------------------------------------------------# utils
# function roundtrip(x)
#     io = IOBuffer()
#     write_xml(io, x)
#     seekstart(io)
#     return x == read_xml(io, typeof(x))
# end

# function peek_str(io::IO, n::Integer)
#     pos = position(io)
#     out = String(read(io, n))
#     seek(io, pos)
#     return out
# end

# is_name_start_char(x::Char) = isletter(x) || x == ':' || x == '_'

# #-----------------------------------------------------------------------------# XMLNode
# abstract type XMLNode end

# write_xml(x) = sprint(write_xml, x)

# read_xml(str::AbstractString, ::Type{T}) where {T <: XMLNode} = read_xml(IOBuffer(str), T)

# is_next(s::AbstractString, ::Type{T}) where {T <: XMLNode} = is_next(IOBuffer(s), T)

# function Base.show(io::IO, o::T) where {T <: XMLNode}
#     str = sprint(write_xml, o)
#     # TODO: more compact representation
#     print(io, T.name.name, ": ", styled"{bright_black:$str}")
# end

# #-----------------------------------------------------------------------------# Text
# """
#     Text(value::AbstractString)
#     # value
# """
# struct Text{T <: AbstractString} <: XMLNode
#     value::T
# end
# write_xml(io::IO, o::Text) = print(io, o.value)
# read_xml(io::IO, o::Type{T}) where {T <: Text} = Text(readuntil(io, '<'))
# is_next(io::IO, o::Type{T}) where {T <: Text} = peek(io, Char) != '<'

# #-----------------------------------------------------------------------------# Comment
# """
#     Comment(value::AbstractString)
#     # <!-- value -->
# """
# struct Comment{T <: AbstractString} <: XMLNode
#     value::T
# end
# write_xml(io::IO, o::Comment) = print(io, "<!--", o.value, "-->")
# function read_xml(io::IO, ::Type{T}) where {T <: Comment}
#     read(io, 4) # <!--
#     return Comment(readuntil(io, "-->"))
# end
# is_next(io::IO, ::Type{T}) where {T <: Comment} = peek_str(io, 4) == "<!--"


# #-----------------------------------------------------------------------------# CData
# """
#     CData(value::AbstractString)
#     # <![CDATA[ value ]]>
# """
# struct CData{T <: AbstractString} <: XMLNode
#     value::T
# end
# write_xml(io::IO, o::CData) = print(io, "<![CDATA[", o.value, "]]>")
# function read_xml(io::IO, ::Type{T}) where {T <: CData}
#     read(io, 9)  # <![CDATA[
#     CData(readuntil(io, "]]>"))
# end
# is_next(io::IO, ::Type{T}) where {T <: CData} = peek_str(io, 9) == "<![CDATA["


# #-----------------------------------------------------------------------------# ProcessingInstruction
# """
#     ProcessingInstruction(target::AbstractString, data::AbstractString)
#     # <?target data?>
# """
# struct ProcessingInstruction{T <: AbstractString} <: XMLNode
#     target::T
#     data::T
# end
# ProcessingInstruction(target::T; kw...) where {T} = ProcessingInstruction(target, join([T("$k=\"$v\"") for (k, v) in kw]))
# write_xml(io::IO, o::ProcessingInstruction) = print(io, "<?", o.target, " ", o.data, "?>")
# function read_xml(io::IO, ::Type{T}) where {T <: ProcessingInstruction}
#     read(io, 2)  # <?
#     target = readuntil(io, ' ')
#     data = readuntil(io, "?>")
#     return ProcessingInstruction(target, data)
# end
# is_next(io::IO, ::Type{T}) where {T <: ProcessingInstruction} = peek_str(io, 2) == "<?" && peek_str(io, 5) != "<?xml"


# #-----------------------------------------------------------------------------# Declaration
# """
#     Declaration(version = "1.0", encoding="UTF-8", standalone="no")
#     # <?xml version="1.0" encoding="UTF-8" standalone="no"?>
# """
# struct Declaration{T <: AbstractString} <: XMLNode
#     version::T
#     encoding::Union{Nothing, T}
#     standalone::Union{Nothing, Bool}
# end
# function write_xml(io::IO, o::Declaration)
#     print(io, "<?xml version=", repr(o.version))
#     !isnothing(o.encoding) && print(" encoding=", repr(o.encoding))
#     !isnothing(o.standalone) && print(" standalone=", repr(o.standalone ? "yes" : "no"))
#     print(io, "?>")
# end
# function read_xml(io::IO, ::Type{T}) where {T <: Declaration}
#     read(io, 5)  # <?xml
#     readuntil(io, "version")
#     readuntil(io, "=")
#     readuntil(io, '"')
#     version = readuntil(io, '"')
# end

# is_next(io::IO, ::Type{T}) where {T <: Declaration} = peek_str(io, 2) == "<?" && peek_str(io, 5) == "<?xml"


# #-----------------------------------------------------------------------------# Element
# """
#     Element(name, children...; attributes)
#     # <name attributes...> children... </name>
# """
# struct Element{T} <: XMLNode
#     name::T
#     attributes::Vector{Pair{T, T}}
#     children::Vector{Union{Element{T}, Text{T}, CData{T}, Comment{T}}}
# end
# function write_xml(io::IO, o::Element)
#     print(io, '<', o.name)
#     for x in o.attributes
#         print(io, ' ', x[1], '=', repr(x[2]))
#     end
#     print(io, '>')
#     for x in o.children
#         write_xml(io, x)
#     end
#     print(io, "</", o.name, '>')
# end
# function read_xml(io::IO, ::Type{T}) where {T <: Element}
#     read(io, 1)
#     readuntil(io, )
# end
# function is_next(io::IO, ::Type{T}) where {T <: Element}
#     a, b = peek_str(io)
#     a == '<' && is_name_start_char(b)
# end

# #-----------------------------------------------------------------------------# DTD
# """
#     DTD(value)
#     # <!DOCTYPE
# """
# struct DTD{T} <: XMLNode
#     value::T
# end

# #-----------------------------------------------------------------------------# Document
# struct Document{T} <: XMLNode
#     prolog::Vector{Union{ProcessingInstruction{T}, DTD{T},  Declaration{T}, Comment{T}}}
#     root::Element{T}
# end

# #-----------------------------------------------------------------------------# Fragment
# struct Fragment{T} <: XMLNode
#     children::Vector{Union{Element{T}, Comment{T}, CData{T}, Text{T}}}
# end

# #-----------------------------------------------------------------------------# printing
# xml(x) = sprint(xml, x)

# function xml(io::IO, x)
#     print_open_tag_begin(io, x)
#     print_attributes(io, x)
#     print_open_tag_end(io, x)
#     print_children(io, x)
#     print_close_tag(io, x)
# end

# print_open_tag_begin(io::IO, x) = nothing
# print_attributes(io::IO, x) = nothing
# print_open_tag_end(io::IO, x) = nothing
# print_children(io::IO, x) = nothing
# print_close_tag(io::IO, x) = nothing


# #-----------------------------------------------------------------------------# NodeType
# """
#     NodeType:
#     - Document                  # prolog & root Element
#     - DTD                       # <!DOCTYPE ...>
#     - Declaration               # <?xml attributes... ?>
#     - ProcessingInstruction     # <?NAME attributes... ?>
#     - Comment                   # <!-- ... -->
#     - CData                     # <![CData[...]]>
#     - Element                   # <NAME attributes... > children... </NAME>
#     - Text                      # text

# NodeTypes can be used to construct XML.Nodes:

#     Document(children...)
#     DTD(value)
#     Declaration(; attributes)
#     ProcessingInstruction(tag, attributes)
#     Comment(text)
#     CData(text)
#     Element(tag, children...; attributes)
#     Text(text)
# """
# @enum(NodeType, CData, Comment, Declaration, Document, DTD, Element, ProcessingInstruction, Text)


# #-----------------------------------------------------------------------------# includes
# include("raw.jl")
# include("dtd.jl")

# abstract type AbstractXMLNode end

#-----------------------------------------------------------------------------# LazyNode
# """
#     LazyNode(file::AbstractString)
#     LazyNode(data::XML.Raw)

# A Lazy representation of an XML node.
# """
# mutable struct LazyNode <: AbstractXMLNode
#     raw::Raw
#     tag::Union{Nothing, String}
#     attributes::Union{Nothing, OrderedDict{String, String}}
#     value::Union{Nothing, String}
# end
# LazyNode(raw::Raw) = LazyNode(raw, nothing, nothing, nothing)

# function Base.getproperty(o::LazyNode, x::Symbol)
#     x === :raw && return getfield(o, :raw)
#     x === :nodetype && return nodetype(o.raw)
#     x === :tag && return isnothing(getfield(o, x)) ? setfield!(o, x, tag(o.raw)) : getfield(o, x)
#     x === :attributes && return isnothing(getfield(o, x)) ? setfield!(o, x, attributes(o.raw)) : getfield(o, x)
#     x === :value && return isnothing(getfield(o, x)) ? setfield!(o, x, value(o.raw)) : getfield(o, x)
#     x === :depth && return depth(o.raw)
#     x === :children && return LazyNode.(children(o.raw))
#     error("type LazyNode has no field $(x)")
# end
# Base.propertynames(o::LazyNode) = (:raw, :nodetype, :tag, :attributes, :value, :depth, :children)

# Base.show(io::IO, o::LazyNode) = _show_node(io, o)

# Base.read(io::IO, ::Type{LazyNode}) = LazyNode(read(io, Raw))
# Base.read(filename::AbstractString, ::Type{LazyNode}) = LazyNode(read(filename, Raw))
# Base.parse(x::AbstractString, ::Type{LazyNode}) = LazyNode(parse(x, Raw))

# children(o::LazyNode) = LazyNode.(children(o.raw))
# parent(o::LazyNode) = LazyNode(parent(o.raw))
# depth(o::LazyNode) = depth(o.raw)

# Base.IteratorSize(::Type{LazyNode}) = Base.SizeUnknown()
# Base.eltype(::Type{LazyNode}) = LazyNode

# function Base.iterate(o::LazyNode, state=o)
#     n = next(state)
#     return isnothing(n) ? nothing : (n, n)
# end

# function next(o::LazyNode)
#     n = next(o.raw)
#     isnothing(n) && return nothing
#     n.type === RawElementClose ? next(LazyNode(n)) : LazyNode(n)
# end
# function prev(o::LazyNode)
#     n = prev(o.raw)
#     isnothing(n) && return nothing
#     n.type === RawElementClose ? prev(LazyNode(n)) : LazyNode(n)
# end

# #-----------------------------------------------------------------------------# Node
# """
#     Node(nodetype, tag, attributes, value, children)
#     Node(node::Node; kw...)  # copy node with keyword overrides
#     Node(node::LazyNode)  # un-lazy the LazyNode

# A representation of an XML DOM node.  For simpler construction, use `(::NodeType)(args...)`
# """
# struct Node <: AbstractXMLNode
#     nodetype::NodeType
#     tag::Union{Nothing, String}
#     attributes::Union{Nothing, OrderedDict{String, String}}
#     value::Union{Nothing, String}
#     children::Union{Nothing, Vector{Node}}

#     function Node(nodetype::NodeType, tag=nothing, attributes=nothing, value=nothing, children=nothing)
#         new(nodetype,
#             isnothing(tag) ? nothing : string(tag),
#             isnothing(attributes) ? nothing : OrderedDict(string(k) => string(v) for (k, v) in pairs(attributes)),
#             isnothing(value) ? nothing : string(value),
#             isnothing(children) ? nothing :
#                 children isa Node ? [children] :
#                 children isa Vector{Node} ? children :
#                 children isa Vector ? map(Node, children) :
#                 children isa Tuple ? map(Node, collect(children)) :
#                 [Node(children)]
#         )
#     end
# end

# function Node(o::Node, x...; kw...)
#     attrs = !isnothing(kw) ?
#         merge(
#             OrderedDict(string(k) => string(v) for (k,v) in pairs(kw)),
#             isnothing(o.attributes) ? OrderedDict{String, String}() : o.attributes
#         ) :
#         o.attributes
#     children = isempty(x) ? o.children : vcat(isnothing(o.children) ? [] : o.children, collect(x))
#     Node(o.nodetype, o.tag, attrs, o.value, children)
# end

# function Node(node::LazyNode)
#     nodetype = node.nodetype
#     tag = node.tag
#     attributes = node.attributes
#     value = node.value
#     c = XML.children(node)
#     Node(nodetype, tag, attributes, value, isempty(c) ? nothing : map(Node, c))
# end

# Node(data::Raw) = Node(LazyNode(data))

# # Anything that's not Vector{UInt8} or a (Lazy)Node is converted to a Text Node
# Node(x) = Node(Text, nothing, nothing, string(x), nothing)

# h(tag::Union{Symbol, String}, children...; kw...) = Node(Element, tag, kw, nothing, children)
# Base.getproperty(::typeof(h), tag::Symbol) = h(tag)
# (o::Node)(children...; kw...) = Node(o, Node.(children)...; kw...)

# # NOT in-place for Text Nodes
# function escape!(o::Node, warn::Bool=true)
#     if o.nodetype == Text
#         warn && @warn "escape!() called on a Text Node creates a new node."
#         return Text(escape(o.value))
#     end
#     isnothing(o.children) && return o
#     map!(x -> escape!(x, false), o.children, o.children)
#     o
# end
# function unescape!(o::Node, warn::Bool=true)
#     if o.nodetype == Text
#         warn && @warn "unescape!() called on a Text Node creates a new node."
#         return Text(unescape(o.value))
#     end
#     isnothing(o.children) && return o
#     map!(x -> unescape!(x, false), o.children, o.children)
#     o
# end


# Base.read(filename::AbstractString, ::Type{Node}) = Node(read(filename, Raw))
# Base.read(io::IO, ::Type{Node}) = Node(read(io, Raw))
# Base.parse(x::AbstractString, ::Type{Node}) = Node(parse(x, Raw))

# Base.setindex!(o::Node, val, i::Integer) = o.children[i] = Node(val)
# Base.push!(a::Node, b::Node) = push!(a.children, b)
# Base.pushfirst!(a::Node, b::Node) = pushfirst!(a.children, b)

# Base.setindex!(o::Node, val, key::AbstractString) = (o.attributes[key] = string(val))
# Base.getindex(o::Node, val::AbstractString) = o.attributes[val]
# Base.haskey(o::Node, key::AbstractString) = isnothing(o.attributes) ? false : haskey(o.attributes, key)
# Base.keys(o::Node) = isnothing(o.attributes) ? () : keys(o.attributes)

# Base.show(io::IO, o::Node) = _show_node(io, o)

# #-----------------------------------------------------------------------------# Node Constructors
# function (T::NodeType)(args...; attr...)
#     if T === Document
#         !isempty(attr) && error("Document nodes do not have attributes.")
#         Node(T, nothing, nothing, nothing, args)
#     elseif T === DTD
#         !isempty(attr) && error("DTD nodes only accept a value.")
#         length(args) > 1 && error("DTD nodes only accept a value.")
#         Node(T, nothing, nothing, only(args))
#     elseif T === Declaration
#         !isempty(args) && error("Declaration nodes only accept attributes")
#         Node(T, nothing, attr)
#     elseif T === ProcessingInstruction
#         length(args) == 1 || error("ProcessingInstruction nodes require a tag and attributes.")
#         Node(T, only(args), attr)
#     elseif T === Comment
#         !isempty(attr) && error("Comment nodes do not have attributes.")
#         length(args) > 1 && error("Comment nodes only accept a single input.")
#         Node(T, nothing, nothing, only(args))
#     elseif T === CData
#         !isempty(attr) && error("CData nodes do not have attributes.")
#         length(args) > 1 && error("CData nodes only accept a single input.")
#         Node(T, nothing, nothing, only(args))
#     elseif T === Text
#         !isempty(attr) && error("Text nodes do not have attributes.")
#         length(args) > 1 && error("Text nodes only accept a single input.")
#         Node(T, nothing, nothing, only(args))
#     elseif T === Element
#         tag = first(args)
#         Node(T, tag, attr, nothing, args[2:end])
#     else
#         error("Unreachable reached while trying to create a Node via (::NodeType)(args...; kw...).")
#     end
# end

# #-----------------------------------------------------------------------------# !!! common !!!
# # Everything below here is common to all data structures


# #-----------------------------------------------------------------------------# interface fallbacks
# nodetype(o) = o.nodetype
# tag(o) = o.tag
# attributes(o) = o.attributes
# value(o) = o.value
# children(o::T) where {T} = isnothing(o.children) ? () : o.children

# depth(o) = missing
# parent(o) = missing
# next(o) = missing
# prev(o) = missing

# is_simple(o) = nodetype(o) == Element && (isnothing(attributes(o)) || isempty(attributes(o))) &&
#     length(children(o)) == 1 && nodetype(only(o)) in (Text, CData)

# simple_value(o) = is_simple(o) ? value(only(o)) : error("`XML.simple_value` is only defined for simple nodes.")

# Base.@deprecate_binding simplevalue simple_value

# #-----------------------------------------------------------------------------# nodes_equal
# function nodes_equal(a, b)
#     out = XML.tag(a) == XML.tag(b)
#     out &= XML.nodetype(a) == XML.nodetype(b)
#     out &= XML.attributes(a) == XML.attributes(b)
#     out &= XML.value(a) == XML.value(b)
#     out &= length(XML.children(a)) == length(XML.children(b))
#     out &= all(nodes_equal(ai, bi) for (ai,bi) in zip(XML.children(a), XML.children(b)))
#     return out
# end

# Base.:(==)(a::AbstractXMLNode, b::AbstractXMLNode) = nodes_equal(a, b)

# #-----------------------------------------------------------------------------# parse
# Base.parse(::Type{T}, str::AbstractString) where {T <: AbstractXMLNode} = parse(str, T)

# #-----------------------------------------------------------------------------# indexing
# Base.getindex(o::Union{Raw, AbstractXMLNode}) = o
# Base.getindex(o::Union{Raw, AbstractXMLNode}, i::Integer) = children(o)[i]
# Base.getindex(o::Union{Raw, AbstractXMLNode}, ::Colon) = children(o)
# Base.lastindex(o::Union{Raw, AbstractXMLNode}) = lastindex(children(o))

# Base.only(o::Union{Raw, AbstractXMLNode}) = only(children(o))

# Base.length(o::AbstractXMLNode) = length(children(o))

# #-----------------------------------------------------------------------------# printing
# function _show_node(io::IO, o)
#     printstyled(io, typeof(o), ' '; color=:light_black)
#     !ismissing(depth(o)) && printstyled(io, "(depth=", depth(o), ") ", color=:light_black)
#     printstyled(io, nodetype(o), ; color=:light_green)
#     if o.nodetype === Text
#         printstyled(io, ' ', repr(value(o)))
#     elseif o.nodetype === Element
#         printstyled(io, " <", tag(o), color=:light_cyan)
#         _print_attrs(io, o; color=:light_yellow)
#         printstyled(io, '>', color=:light_cyan)
#         _print_n_children(io, o)
#     elseif o.nodetype === DTD
#         printstyled(io, " <!DOCTYPE "; color=:light_cyan)
#         printstyled(io, value(o), color=:light_black)
#         printstyled(io, '>', color=:light_cyan)
#     elseif o.nodetype === Declaration
#         printstyled(io, " <?xml", color=:light_cyan)
#         _print_attrs(io, o; color=:light_yellow)
#         printstyled(io, "?>", color=:light_cyan)
#     elseif o.nodetype === ProcessingInstruction
#         printstyled(io, " <?", tag(o), color=:light_cyan)
#         _print_attrs(io, o; color=:light_yellow)
#         printstyled(io, "?>", color=:light_cyan)
#     elseif o.nodetype === Comment
#         printstyled(io, " <!--", color=:light_cyan)
#         printstyled(io, value(o), color=:light_black)
#         printstyled(io, "-->", color=:light_cyan)
#     elseif o.nodetype === CData
#         printstyled(io, " <![CData[", color=:light_cyan)
#         printstyled(io, value(o), color=:light_black)
#         printstyled(io, "]]>", color=:light_cyan)
#     elseif o.nodetype === Document
#         _print_n_children(io, o)
#     elseif o.nodetype === UNKNOWN
#         printstyled(io, "Unknown", color=:light_cyan)
#         _print_n_children(io, o)
#     else
#         error("Unreachable reached")
#     end
# end

# function _print_attrs(io::IO, o; color=:normal)
#     attr = attributes(o)
#     isnothing(attr) && return nothing
#     for (k,v) in attr
#         # printstyled(io, ' ', k, '=', '"', v, '"'; color)
#         print(io, ' ', k, '=', '"', v, '"')
#     end
# end
# function _print_n_children(io::IO, o::Node)
#     n = length(children(o))
#     text = n == 0 ? "" : n == 1 ? " (1 child)" : " ($n children)"
#     printstyled(io, text, color=:light_black)
# end
# _print_n_children(io::IO, o) = nothing

# #-----------------------------------------------------------------------------# write_xml
# write(x; kw...) = (io = IOBuffer(); write(io, x; kw...); String(take!(io)))

# write(filename::AbstractString, x; kw...) = open(io -> write(io, x; kw...), filename, "w")

# function write(io::IO, x; indentsize::Int=2, depth::Int=1)
#     indent = ' ' ^ indentsize
#     nodetype = XML.nodetype(x)
#     tag = XML.tag(x)
#     value = XML.value(x)
#     children = XML.children(x)

#     padding = indent ^ max(0, depth - 1)
#     print(io, padding)
#     if nodetype === Text
#         print(io, value)
#     elseif nodetype === Element
#         print(io, '<', tag)
#         _print_attrs(io, x)
#         print(io, isempty(children) ? '/' : "", '>')
#         if !isempty(children)
#             if length(children) == 1 && XML.nodetype(only(children)) === Text
#                 write(io, only(children); indentsize=0)
#                 print(io, "</", tag, '>')
#             else
#                 println(io)
#                 foreach(children) do child
#                     write(io, child; indentsize, depth = depth + 1)
#                     println(io)
#                 end
#                 print(io, padding, "</", tag, '>')
#             end
#         end
#     elseif nodetype === DTD
#         print(io, "<!DOCTYPE ", value, '>')
#     elseif nodetype === Declaration
#         print(io, "<?xml")
#         _print_attrs(io, x)
#         print(io, "?>")
#     elseif nodetype === ProcessingInstruction
#         print(io, "<?", tag)
#         _print_attrs(io, x)
#         print(io, "?>")
#     elseif nodetype === Comment
#         print(io, "<!--", value, "-->")
#     elseif nodetype === CData
#         print(io, "<![CData[", value, "]]>")
#     elseif nodetype === Document
#         foreach(children) do child
#             write(io, child; indentsize)
#             println(io)
#         end
#     else
#         error("Unreachable case reached during XML.write")
#     end
# end

end
