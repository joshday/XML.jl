#-----------------------------------------------------------------------------# LazyNode
"""
    LazyNode

A lightweight, read-only view into an XML document that navigates the token stream on demand
instead of building a full tree in memory.

    doc = parse(xml_string, LazyNode)
    doc = read("file.xml", LazyNode)

Supports the same read-only interface as `Node`: [`nodetype`](@ref), [`tag`](@ref),
[`attributes`](@ref), [`value`](@ref), [`children`](@ref), plus integer and string indexing.
"""
struct LazyNode{S <: AbstractString}
    data::S
    token::Token{S}
    nodetype::NodeType
end

function LazyNode(data::S, nt::NodeType) where {S <: AbstractString}
    LazyNode{S}(data, Token(TOKEN_TEXT, SubString(data, 1, 0)), nt)
end

nodetype(n::LazyNode) = n.nodetype

_lazy_pos(n::LazyNode) = n.token.raw.offset + 1
_lazy_tokenizer(n::LazyNode) = tokenize(n.data, _lazy_pos(n))

#-----------------------------------------------------------------------------# tag / value
function tag(n::LazyNode)
    nt = n.nodetype
    if nt === Element
        return String(tag_name(n.token))
    elseif nt === ProcessingInstruction
        return String(pi_target(n.token))
    end
    nothing
end

function value(n::LazyNode)
    nt = n.nodetype
    if nt === Text
        return unescape(n.token.raw)
    elseif nt === Comment
        iter = _lazy_tokenizer(n)
        iterate(iter)  # COMMENT_OPEN
        return String(iterate(iter)[1].raw)
    elseif nt === CData
        iter = _lazy_tokenizer(n)
        iterate(iter)  # CDATA_OPEN
        return String(iterate(iter)[1].raw)
    elseif nt === DTD
        iter = _lazy_tokenizer(n)
        iterate(iter)  # DOCTYPE_OPEN
        return String(lstrip(iterate(iter)[1].raw))
    elseif nt === ProcessingInstruction
        iter = _lazy_tokenizer(n)
        iterate(iter)  # PI_OPEN
        result = iterate(iter)
        result === nothing && return nothing
        result[1].kind === TOKEN_PI_CONTENT || return nothing
        content = strip(result[1].raw)
        return isempty(content) ? nothing : String(content)
    end
    nothing
end

#-----------------------------------------------------------------------------# attributes
function attributes(n::LazyNode)
    n.nodetype in (Element, Declaration) || return nothing
    iter = _lazy_tokenizer(n)
    iterate(iter)  # skip OPEN_TAG or XML_DECL_OPEN
    attrs = Pair{String,String}[]
    for tok in iter
        tok.kind === TOKEN_ATTR_NAME || break
        name = String(tok.raw)
        result = iterate(iter)
        result === nothing && break
        push!(attrs, name => unescape(attr_value(result[1])))
    end
    isempty(attrs) ? nothing : Attributes(attrs)
end

function Base.get(n::LazyNode, key::AbstractString, default)
    n.nodetype in (Element, Declaration) || return default
    iter = _lazy_tokenizer(n)
    iterate(iter)  # skip OPEN_TAG or XML_DECL_OPEN
    for tok in iter
        tok.kind === TOKEN_ATTR_NAME || return default
        if tok.raw == key
            result = iterate(iter)
            result === nothing && return default
            return unescape(attr_value(result[1]))
        else
            iterate(iter)  # skip value
        end
    end
    default
end

function Base.getindex(n::LazyNode, key::AbstractString)
    val = get(n, key, _MISSING_ATTR)
    val === _MISSING_ATTR && throw(KeyError(key))
    val
end

function Base.haskey(n::LazyNode, key::AbstractString)
    get(n, key, _MISSING_ATTR) !== _MISSING_ATTR
end

function Base.keys(n::LazyNode)
    n.nodetype in (Element, Declaration) || return ()
    iter = _lazy_tokenizer(n)
    iterate(iter)
    result = String[]
    for tok in iter
        tok.kind === TOKEN_ATTR_NAME || break
        push!(result, String(tok.raw))
        iterate(iter)  # skip value
    end
    result
end

#-----------------------------------------------------------------------------# children
function children(n::LazyNode{S}) where {S}
    nt = n.nodetype
    if nt === Document
        return _lazy_collect_children(n.data, _lazy_tokenizer(n))
    elseif nt !== Element
        return ()
    end
    iter = _lazy_tokenizer(n)
    for tok in iter
        tok.kind === TOKEN_SELF_CLOSE && return LazyNode{S}[]
        tok.kind === TOKEN_TAG_CLOSE && break
    end
    _lazy_collect_children(n.data, iter)
end

function _lazy_collect_children(data::S, iter) where {S <: AbstractString}
    result = LazyNode{S}[]
    for tok in iter
        k = tok.kind
        if k === TOKEN_TEXT
            push!(result, LazyNode(data, tok, Text))
        elseif k === TOKEN_OPEN_TAG
            push!(result, LazyNode(data, tok, Element))
            _lazy_skip_element!(iter)
        elseif k === TOKEN_COMMENT_OPEN
            push!(result, LazyNode(data, tok, Comment))
            _lazy_skip_until!(iter, TOKEN_COMMENT_CLOSE)
        elseif k === TOKEN_CDATA_OPEN
            push!(result, LazyNode(data, tok, CData))
            _lazy_skip_until!(iter, TOKEN_CDATA_CLOSE)
        elseif k === TOKEN_PI_OPEN
            push!(result, LazyNode(data, tok, ProcessingInstruction))
            _lazy_skip_until!(iter, TOKEN_PI_CLOSE)
        elseif k === TOKEN_XML_DECL_OPEN
            push!(result, LazyNode(data, tok, Declaration))
            _lazy_skip_until!(iter, TOKEN_XML_DECL_CLOSE)
        elseif k === TOKEN_DOCTYPE_OPEN
            push!(result, LazyNode(data, tok, DTD))
            _lazy_skip_until!(iter, TOKEN_DOCTYPE_CLOSE)
        elseif k === TOKEN_CLOSE_TAG
            break
        end
    end
    result
end

function _lazy_skip_element!(iter)
    depth = 1
    for tok in iter
        k = tok.kind
        if k === TOKEN_OPEN_TAG
            depth += 1
        elseif k === TOKEN_SELF_CLOSE
            depth -= 1
            depth == 0 && return
        elseif k === TOKEN_CLOSE_TAG
            depth -= 1
            if depth == 0
                iterate(iter)  # consume trailing TAG_CLOSE
                return
            end
        end
    end
end

function _lazy_skip_until!(iter, target::TokenKind)
    for tok in iter
        tok.kind === target && return
    end
end

_token_end(tok) = tok.raw.offset + tok.raw.ncodeunits

function _scan_to_close(iter, close_kind::TokenKind)
    for tok in iter
        tok.kind === close_kind && return _token_end(tok)
    end
    error("Could not find closing token")
end

#-----------------------------------------------------------------------------# sourcetext
"""
    sourcetext(n::LazyNode) -> SubString{String}

Return the original source text of the node as a `SubString`, with no parsing, escaping,
or reformatting.  This is the zero-copy counterpart of [`write`](@ref) for lazy nodes.
"""
function sourcetext(n::LazyNode)
    nt = n.nodetype
    start = _lazy_pos(n)
    if nt === Element
        iter = _lazy_tokenizer(n)
        for tok in iter
            tok.kind === TOKEN_SELF_CLOSE && return SubString(n.data, start, _token_end(tok))
            tok.kind === TOKEN_TAG_CLOSE && break
        end
        depth = 1
        for tok in iter
            k = tok.kind
            if k === TOKEN_OPEN_TAG
                depth += 1
            elseif k === TOKEN_SELF_CLOSE
                depth -= 1
            elseif k === TOKEN_CLOSE_TAG
                depth -= 1
                if depth == 0
                    result = iterate(iter)
                    result === nothing && error("Could not find closing '>'")
                    return SubString(n.data, start, _token_end(result[1]))
                end
            end
        end
        error("Could not find closing tag")
    elseif nt === Comment
        return SubString(n.data, start, _scan_to_close(_lazy_tokenizer(n), TOKEN_COMMENT_CLOSE))
    elseif nt === CData
        return SubString(n.data, start, _scan_to_close(_lazy_tokenizer(n), TOKEN_CDATA_CLOSE))
    elseif nt === ProcessingInstruction
        return SubString(n.data, start, _scan_to_close(_lazy_tokenizer(n), TOKEN_PI_CLOSE))
    elseif nt === Declaration
        return SubString(n.data, start, _scan_to_close(_lazy_tokenizer(n), TOKEN_XML_DECL_CLOSE))
    elseif nt === DTD
        return SubString(n.data, start, _scan_to_close(_lazy_tokenizer(n), TOKEN_DOCTYPE_CLOSE))
    elseif nt === Text
        return n.token.raw
    elseif nt === Document
        return SubString(n.data)
    end
end

#-----------------------------------------------------------------------------# write
write(n::LazyNode) = String(sourcetext(n))
write(filename::AbstractString, n::LazyNode) = Base.write(filename, sourcetext(n))
write(io::IO, n::LazyNode) = Base.write(io, sourcetext(n))

#-----------------------------------------------------------------------------# eachchildnode
struct LazyChildIterator{S <: AbstractString, I}
    data::S
    iter::I
    done::Base.RefValue{Bool}
end

Base.IteratorSize(::Type{<:LazyChildIterator}) = Base.SizeUnknown()
Base.eltype(::Type{LazyChildIterator{S,I}}) where {S,I} = LazyNode{S}

"""
    eachchildnode(n::LazyNode)

Return a lazy iterator over the children of `n`, yielding one [`LazyNode`](@ref) at a time
without collecting them all into a vector.

See also [`children`](@ref), which returns a `Vector{LazyNode}`.
"""
function eachchildnode(n::LazyNode{S}) where {S}
    nt = n.nodetype
    iter = _lazy_tokenizer(n)
    if nt === Document
        return LazyChildIterator{S, typeof(iter)}(n.data, iter, Ref(false))
    elseif nt === Element
        for tok in iter
            if tok.kind === TOKEN_SELF_CLOSE
                return LazyChildIterator{S, typeof(iter)}(n.data, iter, Ref(true))
            elseif tok.kind === TOKEN_TAG_CLOSE
                return LazyChildIterator{S, typeof(iter)}(n.data, iter, Ref(false))
            end
        end
    end
    LazyChildIterator{S, typeof(iter)}(n.data, iter, Ref(true))
end

function Base.iterate(ci::LazyChildIterator, _ = nothing)
    ci.done[] && return nothing
    for tok in ci.iter
        k = tok.kind
        if k === TOKEN_TEXT
            return (LazyNode(ci.data, tok, Text), nothing)
        elseif k === TOKEN_OPEN_TAG
            node = LazyNode(ci.data, tok, Element)
            _lazy_skip_element!(ci.iter)
            return (node, nothing)
        elseif k === TOKEN_COMMENT_OPEN
            node = LazyNode(ci.data, tok, Comment)
            _lazy_skip_until!(ci.iter, TOKEN_COMMENT_CLOSE)
            return (node, nothing)
        elseif k === TOKEN_CDATA_OPEN
            node = LazyNode(ci.data, tok, CData)
            _lazy_skip_until!(ci.iter, TOKEN_CDATA_CLOSE)
            return (node, nothing)
        elseif k === TOKEN_PI_OPEN
            node = LazyNode(ci.data, tok, ProcessingInstruction)
            _lazy_skip_until!(ci.iter, TOKEN_PI_CLOSE)
            return (node, nothing)
        elseif k === TOKEN_XML_DECL_OPEN
            node = LazyNode(ci.data, tok, Declaration)
            _lazy_skip_until!(ci.iter, TOKEN_XML_DECL_CLOSE)
            return (node, nothing)
        elseif k === TOKEN_DOCTYPE_OPEN
            node = LazyNode(ci.data, tok, DTD)
            _lazy_skip_until!(ci.iter, TOKEN_DOCTYPE_CLOSE)
            return (node, nothing)
        elseif k === TOKEN_CLOSE_TAG || k === TOKEN_TAG_CLOSE
            ci.done[] = true
            return nothing
        end
    end
    ci.done[] = true
    return nothing
end

#-----------------------------------------------------------------------------# is_simple / simple_value
function is_simple(n::LazyNode)
    n.nodetype === Element || return false
    attrs = attributes(n)
    (!isnothing(attrs) && !isempty(attrs)) && return false
    ch = children(n)
    length(ch) == 1 && ch[1].nodetype in (Text, CData)
end

function simple_value(n::LazyNode)
    n.nodetype === Element || error("`simple_value` is only defined for simple nodes.")
    attrs = attributes(n)
    (!isnothing(attrs) && !isempty(attrs)) && error("`simple_value` is only defined for simple nodes.")
    ch = children(n)
    length(ch) == 1 && ch[1].nodetype in (Text, CData) || error("`simple_value` is only defined for simple nodes.")
    value(ch[1])
end

#-----------------------------------------------------------------------------# indexing
Base.getindex(n::LazyNode, i::Integer) = children(n)[i]
Base.getindex(n::LazyNode, ::Colon) = children(n)
Base.lastindex(n::LazyNode) = lastindex(children(n))
Base.only(n::LazyNode) = only(children(n))
Base.length(n::LazyNode) = length(children(n))

#-----------------------------------------------------------------------------# parse / read
Base.parse(::Type{LazyNode}, xml::AbstractString) = parse(xml, LazyNode)
Base.parse(xml::AbstractString, ::Type{LazyNode}) = LazyNode(String(xml), Document)

Base.read(filename::AbstractString, ::Type{LazyNode}) = parse(read(filename, String), LazyNode)
Base.read(io::IO, ::Type{LazyNode}) = parse(read(io, String), LazyNode)

#-----------------------------------------------------------------------------# show
function Base.show(io::IO, n::LazyNode)
    nt = n.nodetype
    print(io, "Lazy ", nt)
    if nt === Text
        print(io, ' ', repr(value(n)))
    elseif nt === Element
        print(io, " <", tag(n))
        attrs = attributes(n)
        if !isnothing(attrs)
            for (k, v) in attrs
                print(io, ' ', k, '=', '"', v, '"')
            end
        end
        print(io, '>')
    elseif nt === DTD
        print(io, " <!DOCTYPE ", value(n), '>')
    elseif nt === Declaration
        print(io, " <?xml")
        attrs = attributes(n)
        if !isnothing(attrs)
            for (k, v) in attrs
                print(io, ' ', k, '=', '"', v, '"')
            end
        end
        print(io, "?>")
    elseif nt === ProcessingInstruction
        print(io, " <?", tag(n))
        v = value(n)
        !isnothing(v) && print(io, ' ', v)
        print(io, "?>")
    elseif nt === Comment
        print(io, " <!--", value(n), "-->")
    elseif nt === CData
        print(io, " <![CDATA[", value(n), "]]>")
    elseif nt === Document
        n_ch = length(children(n))
        n_ch > 0 && print(io, n_ch == 1 ? " (1 child)" : " ($n_ch children)")
    end
end
