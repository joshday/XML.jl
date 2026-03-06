"""
    XMLTokenizer

A self-contained module for tokenizing XML documents into a fine-grained stream of tokens.

# Usage

```julia
using .XMLTokenizer: tokenize, tag_name, attr_value, pi_target

for token in tokenize(\"\"\"<?xml version="1.0"?><root attr="val">text<!-- comment --></root>\"\"\")
    println(token)
end
```
"""
module XMLTokenizer

export tokenize, tag_name, attr_value, pi_target, TokenKind, Token,
    TOKEN_TEXT,
    TOKEN_OPEN_TAG, TOKEN_CLOSE_TAG, TOKEN_TAG_CLOSE, TOKEN_SELF_CLOSE,
    TOKEN_ATTR_NAME, TOKEN_ATTR_VALUE,
    TOKEN_CDATA_OPEN, TOKEN_CDATA_CONTENT, TOKEN_CDATA_CLOSE,
    TOKEN_COMMENT_OPEN, TOKEN_COMMENT_CONTENT, TOKEN_COMMENT_CLOSE,
    TOKEN_PI_OPEN, TOKEN_PI_CONTENT, TOKEN_PI_CLOSE,
    TOKEN_XML_DECL_OPEN, TOKEN_XML_DECL_CLOSE,
    TOKEN_DOCTYPE_OPEN, TOKEN_DOCTYPE_CONTENT, TOKEN_DOCTYPE_CLOSE

#-----------------------------------------------------------------------# TokenKind
@enum TokenKind::UInt8 begin
    # Character data
    TOKEN_TEXT               # text content between markup

    # Element tags
    TOKEN_OPEN_TAG           # <name
    TOKEN_CLOSE_TAG          # </name
    TOKEN_TAG_CLOSE          # >
    TOKEN_SELF_CLOSE         # />
    TOKEN_ATTR_NAME          # attribute name
    TOKEN_ATTR_VALUE         # "value" or 'value' (with quotes in raw)

    # CDATA sections
    TOKEN_CDATA_OPEN         # <![CDATA[
    TOKEN_CDATA_CONTENT      # raw text content
    TOKEN_CDATA_CLOSE        # ]]>

    # Comments
    TOKEN_COMMENT_OPEN       # <!--
    TOKEN_COMMENT_CONTENT    # comment text
    TOKEN_COMMENT_CLOSE      # -->

    # Processing instructions
    TOKEN_PI_OPEN            # <?target (includes target name)
    TOKEN_PI_CONTENT         # PI body text
    TOKEN_PI_CLOSE           # ?>

    # XML declaration (<?xml ...?>)
    TOKEN_XML_DECL_OPEN      # <?xml
    TOKEN_XML_DECL_CLOSE     # ?>
    # (reuses TOKEN_ATTR_NAME / TOKEN_ATTR_VALUE for pseudo-attributes)

    # DOCTYPE
    TOKEN_DOCTYPE_OPEN       # <!DOCTYPE (or other <! declarations)
    TOKEN_DOCTYPE_CONTENT    # declaration body
    TOKEN_DOCTYPE_CLOSE      # >
end

#-----------------------------------------------------------------------# Token
struct Token{S <: AbstractString}
    kind::TokenKind
    raw::SubString{S}
end

function Base.show(io::IO, t::Token)
    print(io, t.kind, ": ", repr(String(t.raw)))
end

#-----------------------------------------------------------------------# Tokenizer state
@enum _State::UInt8 begin
    _S_DEFAULT            # normal content mode
    _S_TAG                # inside open tag, reading attributes
    _S_TAG_VALUE          # expecting quoted attribute value
    _S_CLOSE_TAG          # inside close tag, expecting >
    _S_XML_DECL           # inside <?xml, reading pseudo-attributes
    _S_XML_DECL_VALUE     # expecting quoted attr value in xml decl
    _S_COMMENT            # after <!--, reading content
    _S_CDATA              # after <![CDATA[, reading content
    _S_PI                 # after <?target, reading content
    _S_DOCTYPE            # after <!DOCTYPE, reading content
end

#-----------------------------------------------------------------------# TokenizerState (immutable, SROA-friendly)
struct TokenizerState{S <: AbstractString}
    pos::Int
    state::_State
    pending::Token{S}
end

@inline _no_token(s::AbstractString) = Token(TOKEN_TEXT, @inbounds SubString(s, 1, 0))
@inline _has_pending(st::TokenizerState) = !isempty(st.pending.raw)

@inline function _init_state(data::AbstractString, pos::Int=1)
    TokenizerState(pos, _S_DEFAULT, _no_token(data))
end

#-----------------------------------------------------------------------# Tokenizer (immutable iterator)
"""
    tokenize(xml::AbstractString) -> Tokenizer

Return a lazy iterator of `Token`s over the XML string `xml`.
"""
struct Tokenizer{S <: AbstractString}
    data::S
    start::Int
end

tokenize(xml::AbstractString) = Tokenizer(xml, 1)
tokenize(xml::AbstractString, pos::Int) = Iterators.Stateful(Tokenizer(xml, pos))

function Base.show(io::IO, t::Tokenizer)
    n = ncodeunits(t.data)
    print(io, "Tokenizer(")
    t.start > 1 && print(io, t.start, "/")
    print(io, n, " bytes)")
end

Base.IteratorSize(::Type{<:Tokenizer}) = Base.SizeUnknown()
Base.eltype(::Type{Tokenizer{S}}) where {S} = Token{S}

function Base.iterate(t::Tokenizer, st::TokenizerState=_init_state(t.data, t.start))
    result = _next_token(t.data, st)
    result === nothing ? nothing : result
end

#-----------------------------------------------------------------------# Internal helpers
@inline _iseof(data, pos) = pos > ncodeunits(data)
@inline _peek(data, pos) = @inbounds codeunit(data, pos)
@inline _canpeek(data, pos, offset) = pos + offset <= ncodeunits(data)

@inline function _is_name_byte(b::UInt8)
    (UInt8('a') <= b <= UInt8('z')) || (UInt8('A') <= b <= UInt8('Z')) ||
    (UInt8('0') <= b <= UInt8('9')) || b == UInt8('_') || b == UInt8('-') ||
    b == UInt8('.') || b == UInt8(':')
end

@inline function _is_whitespace(b::UInt8)
    b == UInt8(' ') || b == UInt8('\t') || b == UInt8('\n') || b == UInt8('\r')
end

@inline function _skip_whitespace(data, pos)
    while !_iseof(data, pos) && _is_whitespace(_peek(data, pos))
        pos += 1
    end
    pos
end

function _skip_quoted(data, pos)
    q = _peek(data, pos)
    pos += 1
    while !_iseof(data, pos)
        _peek(data, pos) == q && return pos + 1
        pos += 1
    end
    error("Unterminated quoted string")
end

@noinline _err(msg, pos) = throw(ArgumentError("XML tokenizer error at position $pos: $msg"))

#-----------------------------------------------------------------------# Main dispatch
function _next_token(data, st::TokenizerState)
    if _has_pending(st)
        return (st.pending, TokenizerState(st.pos, st.state, _no_token(data)))
    end
    pos = st.pos
    _iseof(data, pos) && return nothing

    s = st.state
    if s == _S_DEFAULT
        _peek(data, pos) == UInt8('<') ? _read_markup(data, pos) : _read_text(data, pos)
    elseif s == _S_TAG || s == _S_XML_DECL
        _read_in_tag(data, pos, s)
    elseif s == _S_TAG_VALUE || s == _S_XML_DECL_VALUE
        _read_attr_value(data, pos, s)
    elseif s == _S_CLOSE_TAG
        _read_close_tag_end(data, pos)
    elseif s == _S_COMMENT
        _read_comment_body(data, pos)
    elseif s == _S_CDATA
        _read_cdata_body(data, pos)
    elseif s == _S_PI
        _read_pi_body(data, pos)
    else  # _S_DOCTYPE
        _read_doctype_body(data, pos)
    end
end

#-----------------------------------------------------------------------# S_DEFAULT tokens
function _read_text(data, pos)
    start = pos
    while !_iseof(data, pos) && _peek(data, pos) != UInt8('<')
        pos += 1
    end
    tok = Token(TOKEN_TEXT, @inbounds SubString(data, start, prevind(data, pos)))
    (tok, TokenizerState(pos, _S_DEFAULT, _no_token(data)))
end

function _read_markup(data, pos)
    start = pos
    pos += 1  # skip '<'
    _iseof(data, pos) && _err("unexpected end of input after '<'", start)

    b = _peek(data, pos)
    if b == UInt8('!')
        _read_bang(data, pos + 1, start)
    elseif b == UInt8('?')
        _read_pi_start(data, pos + 1, start)
    elseif b == UInt8('/')
        _read_close_tag_start(data, pos + 1, start)
    else
        _read_open_tag_start(data, pos, start)
    end
end

#-----------------------------------------------------------------------# <! dispatch
function _read_bang(data, pos, start)
    # Comment: <!--
    if !_iseof(data, pos) && _peek(data, pos) == UInt8('-')
        pos += 1
        (!_iseof(data, pos) && _peek(data, pos) == UInt8('-')) || _err("expected '<!--'", start)
        pos += 1
        tok = Token(TOKEN_COMMENT_OPEN, @inbounds SubString(data, start, pos - 1))
        return (tok, TokenizerState(pos, _S_COMMENT, _no_token(data)))
    end

    # CDATA: <![CDATA[
    if !_iseof(data, pos) && _peek(data, pos) == UInt8('[')
        pos += 1
        for expected in (UInt8('C'), UInt8('D'), UInt8('A'), UInt8('T'), UInt8('A'), UInt8('['))
            _iseof(data, pos) && _err("unterminated CDATA", start)
            _peek(data, pos) == expected || _err("invalid CDATA section", start)
            pos += 1
        end
        tok = Token(TOKEN_CDATA_OPEN, @inbounds SubString(data, start, pos - 1))
        return (tok, TokenizerState(pos, _S_CDATA, _no_token(data)))
    end

    # <!DOCTYPE ...> or other <! declaration
    while !_iseof(data, pos) && _is_name_byte(_peek(data, pos))
        pos += 1
    end
    tok = Token(TOKEN_DOCTYPE_OPEN, @inbounds SubString(data, start, pos - 1))
    (tok, TokenizerState(pos, _S_DOCTYPE, _no_token(data)))
end

#-----------------------------------------------------------------------# <? (PI / XML declaration)
function _read_pi_start(data, pos, start)
    name_start = pos
    while !_iseof(data, pos) && _is_name_byte(_peek(data, pos))
        pos += 1
    end

    is_xml = (pos - name_start == 3) &&
        codeunit(data, name_start)     == UInt8('x') &&
        codeunit(data, name_start + 1) == UInt8('m') &&
        codeunit(data, name_start + 2) == UInt8('l')

    if is_xml
        tok = Token(TOKEN_XML_DECL_OPEN, @inbounds SubString(data, start, pos - 1))
        (tok, TokenizerState(pos, _S_XML_DECL, _no_token(data)))
    else
        tok = Token(TOKEN_PI_OPEN, @inbounds SubString(data, start, pos - 1))
        (tok, TokenizerState(pos, _S_PI, _no_token(data)))
    end
end

#-----------------------------------------------------------------------# Tags
function _read_open_tag_start(data, pos, start)
    while !_iseof(data, pos) && _is_name_byte(_peek(data, pos))
        pos += 1
    end
    tok = Token(TOKEN_OPEN_TAG, @inbounds SubString(data, start, pos - 1))
    (tok, TokenizerState(pos, _S_TAG, _no_token(data)))
end

function _read_close_tag_start(data, pos, start)
    while !_iseof(data, pos) && _is_name_byte(_peek(data, pos))
        pos += 1
    end
    tok = Token(TOKEN_CLOSE_TAG, @inbounds SubString(data, start, pos - 1))
    (tok, TokenizerState(pos, _S_CLOSE_TAG, _no_token(data)))
end

function _read_close_tag_end(data, pos)
    pos = _skip_whitespace(data, pos)
    _iseof(data, pos) && _err("unterminated close tag", pos)
    _peek(data, pos) == UInt8('>') || _err("expected '>'", pos)
    tok = Token(TOKEN_TAG_CLOSE, @inbounds SubString(data, pos, pos))
    (tok, TokenizerState(pos + 1, _S_DEFAULT, _no_token(data)))
end

#-----------------------------------------------------------------------# Attributes (shared by S_TAG and S_XML_DECL)
function _read_in_tag(data, pos, state)
    pos = _skip_whitespace(data, pos)
    _iseof(data, pos) && _err("unterminated tag", pos)

    b = _peek(data, pos)
    is_decl = (state == _S_XML_DECL)

    # Check for end delimiters
    if is_decl
        if b == UInt8('?') && _canpeek(data, pos, 1) && _peek(data, pos + 1) == UInt8('>')
            tok = Token(TOKEN_XML_DECL_CLOSE, @inbounds SubString(data, pos, pos + 1))
            return (tok, TokenizerState(pos + 2, _S_DEFAULT, _no_token(data)))
        end
    else
        if b == UInt8('>')
            tok = Token(TOKEN_TAG_CLOSE, @inbounds SubString(data, pos, pos))
            return (tok, TokenizerState(pos + 1, _S_DEFAULT, _no_token(data)))
        end
        if b == UInt8('/') && _canpeek(data, pos, 1) && _peek(data, pos + 1) == UInt8('>')
            tok = Token(TOKEN_SELF_CLOSE, @inbounds SubString(data, pos, pos + 1))
            return (tok, TokenizerState(pos + 2, _S_DEFAULT, _no_token(data)))
        end
    end

    # Attribute name
    name_start = pos
    while !_iseof(data, pos) && _is_name_byte(_peek(data, pos))
        pos += 1
    end
    name_end = pos - 1
    name_start > name_end && _err("expected attribute name or tag close", pos)

    # Consume '=' and surrounding whitespace (not part of any token)
    pos = _skip_whitespace(data, pos)
    (!_iseof(data, pos) && _peek(data, pos) == UInt8('=')) || _err("expected '=' after attribute name", pos)
    pos += 1
    pos = _skip_whitespace(data, pos)

    next_state = is_decl ? _S_XML_DECL_VALUE : _S_TAG_VALUE
    tok = Token(TOKEN_ATTR_NAME, @inbounds SubString(data, name_start, name_end))
    (tok, TokenizerState(pos, next_state, _no_token(data)))
end

function _read_attr_value(data, pos, state)
    _iseof(data, pos) && _err("expected attribute value", pos)

    q = _peek(data, pos)
    (q == UInt8('"') || q == UInt8('\'')) || _err("expected quoted attribute value", pos)

    start = pos
    pos += 1  # skip opening quote
    while !_iseof(data, pos) && _peek(data, pos) != q
        pos += 1
    end
    _iseof(data, pos) && _err("unterminated attribute value", start)
    pos += 1  # skip closing quote

    next_state = (state == _S_XML_DECL_VALUE) ? _S_XML_DECL : _S_TAG
    tok = Token(TOKEN_ATTR_VALUE, @inbounds SubString(data, start, pos - 1))
    (tok, TokenizerState(pos, next_state, _no_token(data)))
end

#-----------------------------------------------------------------------# Content bodies (comment, CDATA, PI, DOCTYPE)
function _read_comment_body(data, pos)
    start = pos
    while !_iseof(data, pos)
        if _peek(data, pos) == UInt8('-') &&
           _canpeek(data, pos, 1) && _peek(data, pos + 1) == UInt8('-') &&
           _canpeek(data, pos, 2) && _peek(data, pos + 2) == UInt8('>')
            content_end = prevind(data, pos)
            close_start = pos
            pos += 3
            pending = Token(TOKEN_COMMENT_CLOSE, @inbounds SubString(data, close_start, pos - 1))
            tok = Token(TOKEN_COMMENT_CONTENT, @inbounds SubString(data, start, content_end))
            return (tok, TokenizerState(pos, _S_DEFAULT, pending))
        end
        pos += 1
    end
    _err("unterminated comment", start)
end

function _read_cdata_body(data, pos)
    start = pos
    while !_iseof(data, pos)
        if _peek(data, pos) == UInt8(']') &&
           _canpeek(data, pos, 1) && _peek(data, pos + 1) == UInt8(']') &&
           _canpeek(data, pos, 2) && _peek(data, pos + 2) == UInt8('>')
            content_end = prevind(data, pos)
            close_start = pos
            pos += 3
            pending = Token(TOKEN_CDATA_CLOSE, @inbounds SubString(data, close_start, pos - 1))
            tok = Token(TOKEN_CDATA_CONTENT, @inbounds SubString(data, start, content_end))
            return (tok, TokenizerState(pos, _S_DEFAULT, pending))
        end
        pos += 1
    end
    _err("unterminated CDATA section", start)
end

function _read_pi_body(data, pos)
    start = pos
    while !_iseof(data, pos)
        if _peek(data, pos) == UInt8('?') && _canpeek(data, pos, 1) && _peek(data, pos + 1) == UInt8('>')
            content_end = prevind(data, pos)
            close_start = pos
            pos += 2
            pending = Token(TOKEN_PI_CLOSE, @inbounds SubString(data, close_start, pos - 1))
            tok = Token(TOKEN_PI_CONTENT, @inbounds SubString(data, start, content_end))
            return (tok, TokenizerState(pos, _S_DEFAULT, pending))
        end
        pos += 1
    end
    _err("unterminated processing instruction", start)
end

function _read_doctype_body(data, pos)
    start = pos
    depth = 0
    while !_iseof(data, pos)
        b = _peek(data, pos)
        if b == UInt8('-') && _canpeek(data, pos, 1) && _peek(data, pos + 1) == UInt8('-') &&
                pos >= 2 &&
                codeunit(data, pos - 1) == UInt8('!') &&
                codeunit(data, pos - 2) == UInt8('<')
            # Inside a <!-- comment: skip until -->
            pos += 2  # skip "--"
            while !_iseof(data, pos)
                if _peek(data, pos) == UInt8('-') && _canpeek(data, pos, 1) && _peek(data, pos + 1) == UInt8('-') &&
                        _canpeek(data, pos, 2) && _peek(data, pos + 2) == UInt8('>')
                    pos += 3  # skip "-->"
                    break
                end
                pos += 1
            end
        elseif b == UInt8('"') || b == UInt8('\'')
            pos = _skip_quoted(data, pos)
        elseif b == UInt8('[')
            depth += 1
            pos += 1
        elseif b == UInt8(']')
            depth -= 1
            pos += 1
        elseif b == UInt8('>') && depth == 0
            content_end = prevind(data, pos)
            close_start = pos
            pos += 1
            pending = Token(TOKEN_DOCTYPE_CLOSE, @inbounds SubString(data, close_start, pos - 1))
            tok = Token(TOKEN_DOCTYPE_CONTENT, @inbounds SubString(data, start, content_end))
            return (tok, TokenizerState(pos, _S_DEFAULT, pending))
        else
            pos += 1
        end
    end
    _err("unterminated DOCTYPE", start)
end

#-----------------------------------------------------------------------# Utility functions

"""
    tag_name(token::Token) -> SubString{String}

Extract the element name from an `OPEN_TAG` or `CLOSE_TAG` token.
"""
function tag_name(token::Token)
    if token.kind == TOKEN_OPEN_TAG
        @inbounds SubString(token.raw, 2, ncodeunits(token.raw))  # skip '<'
    elseif token.kind == TOKEN_CLOSE_TAG
        @inbounds SubString(token.raw, 3, ncodeunits(token.raw))  # skip '</'
    else
        throw(ArgumentError("tag_name requires OPEN_TAG or CLOSE_TAG, got $(token.kind)"))
    end
end

"""
    attr_value(token::Token) -> SubString{String}

Strip the surrounding quotes from an `ATTR_VALUE` token.
"""
function attr_value(token::Token)
    token.kind == TOKEN_ATTR_VALUE ||
        throw(ArgumentError("attr_value requires ATTR_VALUE, got $(token.kind)"))
    @inbounds SubString(token.raw, 2, prevind(token.raw, lastindex(token.raw)))
end

"""
    pi_target(token::Token) -> SubString{String}

Extract the target name from a `PI_OPEN` or `XML_DECL_OPEN` token.
"""
function pi_target(token::Token)
    (token.kind == TOKEN_PI_OPEN || token.kind == TOKEN_XML_DECL_OPEN) ||
        throw(ArgumentError("pi_target requires PI_OPEN or XML_DECL_OPEN, got $(token.kind)"))
    @inbounds SubString(token.raw, 3, ncodeunits(token.raw))  # skip '<?'
end

end # module XMLTokenizer
