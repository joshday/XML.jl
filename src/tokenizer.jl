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

#-----------------------------------------------------------------------# Tokenizer
mutable struct Tokenizer{S <: AbstractString}
    const data::S
    pos::Int
    state::_State
    pending::Union{Token{S},Nothing}
end

"""
    tokenize(xml::AbstractString) -> Tokenizer

Return a lazy iterator of `Token`s over the XML string `xml`.
"""
tokenize(xml::AbstractString) = Tokenizer(xml, 1, _S_DEFAULT, nothing)
tokenize(xml::AbstractString, pos::Int) = Tokenizer(xml, pos, _S_DEFAULT, nothing)

Base.IteratorSize(::Type{<:Tokenizer}) = Base.SizeUnknown()
Base.eltype(::Type{Tokenizer{S}}) where {S} = Token{S}

function Base.iterate(t::Tokenizer, _=nothing)
    tok = _next_token!(t)
    tok === nothing ? nothing : (tok, nothing)
end

#-----------------------------------------------------------------------# Internal helpers
@inline _iseof(t::Tokenizer) = t.pos > ncodeunits(t.data)
@inline _peek(t::Tokenizer) = @inbounds codeunit(t.data, t.pos)
@inline _peek(t::Tokenizer, offset::Int) = @inbounds codeunit(t.data, t.pos + offset)
@inline _canpeek(t::Tokenizer, offset::Int) = t.pos + offset <= ncodeunits(t.data)

@inline function _is_name_byte(b::UInt8)
    (UInt8('a') <= b <= UInt8('z')) || (UInt8('A') <= b <= UInt8('Z')) ||
    (UInt8('0') <= b <= UInt8('9')) || b == UInt8('_') || b == UInt8('-') ||
    b == UInt8('.') || b == UInt8(':')
end

@inline function _is_whitespace(b::UInt8)
    b == UInt8(' ') || b == UInt8('\t') || b == UInt8('\n') || b == UInt8('\r')
end

function _skip_whitespace!(t::Tokenizer)
    while !_iseof(t) && _is_whitespace(_peek(t))
        t.pos += 1
    end
end

function _skip_quoted!(t::Tokenizer)
    q = _peek(t)
    t.pos += 1
    while !_iseof(t)
        _peek(t) == q && (t.pos += 1; return)
        t.pos += 1
    end
    error("Unterminated quoted string")
end

@noinline _err(msg, pos) = throw(ArgumentError("XML tokenizer error at position $pos: $msg"))

#-----------------------------------------------------------------------# Main dispatch
function _next_token!(t::Tokenizer)
    if t.pending !== nothing
        tok = t.pending::Token
        t.pending = nothing
        return tok
    end
    _iseof(t) && return nothing

    s = t.state
    if s == _S_DEFAULT
        _peek(t) == UInt8('<') ? _read_markup!(t) : _read_text!(t)
    elseif s == _S_TAG || s == _S_XML_DECL
        _read_in_tag!(t)
    elseif s == _S_TAG_VALUE || s == _S_XML_DECL_VALUE
        _read_attr_value!(t)
    elseif s == _S_CLOSE_TAG
        _read_close_tag_end!(t)
    elseif s == _S_COMMENT
        _read_comment_body!(t)
    elseif s == _S_CDATA
        _read_cdata_body!(t)
    elseif s == _S_PI
        _read_pi_body!(t)
    else  # _S_DOCTYPE
        _read_doctype_body!(t)
    end
end

#-----------------------------------------------------------------------# S_DEFAULT tokens
function _read_text!(t::Tokenizer)
    start = t.pos
    while !_iseof(t) && _peek(t) != UInt8('<')
        t.pos += 1
    end
    Token(TOKEN_TEXT, SubString(t.data, start, prevind(t.data, t.pos)))
end

function _read_markup!(t::Tokenizer)
    start = t.pos
    t.pos += 1  # skip '<'
    _iseof(t) && _err("unexpected end of input after '<'", start)

    b = _peek(t)
    if b == UInt8('!')
        _read_bang!(t, start)
    elseif b == UInt8('?')
        _read_pi_start!(t, start)
    elseif b == UInt8('/')
        _read_close_tag_start!(t, start)
    else
        _read_open_tag_start!(t, start)
    end
end

#-----------------------------------------------------------------------# <! dispatch
function _read_bang!(t::Tokenizer, start::Int)
    t.pos += 1  # skip '!'

    # Comment: <!--
    if !_iseof(t) && _peek(t) == UInt8('-')
        t.pos += 1
        (!_iseof(t) && _peek(t) == UInt8('-')) || _err("expected '<!--'", start)
        t.pos += 1
        t.state = _S_COMMENT
        return Token(TOKEN_COMMENT_OPEN, SubString(t.data, start, t.pos - 1))
    end

    # CDATA: <![CDATA[
    if !_iseof(t) && _peek(t) == UInt8('[')
        t.pos += 1
        for expected in (UInt8('C'), UInt8('D'), UInt8('A'), UInt8('T'), UInt8('A'), UInt8('['))
            _iseof(t) && _err("unterminated CDATA", start)
            _peek(t) == expected || _err("invalid CDATA section", start)
            t.pos += 1
        end
        t.state = _S_CDATA
        return Token(TOKEN_CDATA_OPEN, SubString(t.data, start, t.pos - 1))
    end

    # <!DOCTYPE ...> or other <! declaration
    while !_iseof(t) && _is_name_byte(_peek(t))
        t.pos += 1
    end
    t.state = _S_DOCTYPE
    Token(TOKEN_DOCTYPE_OPEN, SubString(t.data, start, t.pos - 1))
end

#-----------------------------------------------------------------------# <? (PI / XML declaration)
function _read_pi_start!(t::Tokenizer, start::Int)
    t.pos += 1  # skip '?'
    name_start = t.pos
    while !_iseof(t) && _is_name_byte(_peek(t))
        t.pos += 1
    end

    is_xml = (t.pos - name_start == 3) &&
        codeunit(t.data, name_start)     == UInt8('x') &&
        codeunit(t.data, name_start + 1) == UInt8('m') &&
        codeunit(t.data, name_start + 2) == UInt8('l')

    if is_xml
        t.state = _S_XML_DECL
        Token(TOKEN_XML_DECL_OPEN, SubString(t.data, start, t.pos - 1))
    else
        t.state = _S_PI
        Token(TOKEN_PI_OPEN, SubString(t.data, start, t.pos - 1))
    end
end

#-----------------------------------------------------------------------# Tags
function _read_open_tag_start!(t::Tokenizer, start::Int)
    while !_iseof(t) && _is_name_byte(_peek(t))
        t.pos += 1
    end
    t.state = _S_TAG
    Token(TOKEN_OPEN_TAG, SubString(t.data, start, t.pos - 1))
end

function _read_close_tag_start!(t::Tokenizer, start::Int)
    t.pos += 1  # skip '/'
    while !_iseof(t) && _is_name_byte(_peek(t))
        t.pos += 1
    end
    t.state = _S_CLOSE_TAG
    Token(TOKEN_CLOSE_TAG, SubString(t.data, start, t.pos - 1))
end

function _read_close_tag_end!(t::Tokenizer)
    _skip_whitespace!(t)
    _iseof(t) && _err("unterminated close tag", t.pos)
    _peek(t) == UInt8('>') || _err("expected '>'", t.pos)
    start = t.pos
    t.pos += 1
    t.state = _S_DEFAULT
    Token(TOKEN_TAG_CLOSE, SubString(t.data, start, start))
end

#-----------------------------------------------------------------------# Attributes (shared by S_TAG and S_XML_DECL)
function _read_in_tag!(t::Tokenizer)
    _skip_whitespace!(t)
    _iseof(t) && _err("unterminated tag", t.pos)

    b = _peek(t)
    is_decl = (t.state == _S_XML_DECL)

    # Check for end delimiters
    if is_decl
        if b == UInt8('?') && _canpeek(t, 1) && _peek(t, 1) == UInt8('>')
            start = t.pos; t.pos += 2; t.state = _S_DEFAULT
            return Token(TOKEN_XML_DECL_CLOSE, SubString(t.data, start, t.pos - 1))
        end
    else
        if b == UInt8('>')
            start = t.pos; t.pos += 1; t.state = _S_DEFAULT
            return Token(TOKEN_TAG_CLOSE, SubString(t.data, start, start))
        end
        if b == UInt8('/') && _canpeek(t, 1) && _peek(t, 1) == UInt8('>')
            start = t.pos; t.pos += 2; t.state = _S_DEFAULT
            return Token(TOKEN_SELF_CLOSE, SubString(t.data, start, t.pos - 1))
        end
    end

    # Attribute name
    name_start = t.pos
    while !_iseof(t) && _is_name_byte(_peek(t))
        t.pos += 1
    end
    name_end = t.pos - 1
    name_start > name_end && _err("expected attribute name or tag close", t.pos)

    # Consume '=' and surrounding whitespace (not part of any token)
    _skip_whitespace!(t)
    (!_iseof(t) && _peek(t) == UInt8('=')) || _err("expected '=' after attribute name", t.pos)
    t.pos += 1
    _skip_whitespace!(t)

    t.state = is_decl ? _S_XML_DECL_VALUE : _S_TAG_VALUE
    Token(TOKEN_ATTR_NAME, SubString(t.data, name_start, name_end))
end

function _read_attr_value!(t::Tokenizer)
    _iseof(t) && _err("expected attribute value", t.pos)

    q = _peek(t)
    (q == UInt8('"') || q == UInt8('\'')) || _err("expected quoted attribute value", t.pos)

    start = t.pos
    t.pos += 1  # skip opening quote
    while !_iseof(t) && _peek(t) != q
        t.pos += 1
    end
    _iseof(t) && _err("unterminated attribute value", start)
    t.pos += 1  # skip closing quote

    t.state = (t.state == _S_XML_DECL_VALUE) ? _S_XML_DECL : _S_TAG
    Token(TOKEN_ATTR_VALUE, SubString(t.data, start, prevind(t.data, t.pos)))
end

#-----------------------------------------------------------------------# Content bodies (comment, CDATA, PI, DOCTYPE)
function _read_comment_body!(t::Tokenizer)
    start = t.pos
    while !_iseof(t)
        if _peek(t) == UInt8('-') &&
           _canpeek(t, 1) && _peek(t, 1) == UInt8('-') &&
           _canpeek(t, 2) && _peek(t, 2) == UInt8('>')
            content_end = prevind(t.data, t.pos)
            close_start = t.pos
            t.pos += 3
            t.state = _S_DEFAULT
            t.pending = Token(TOKEN_COMMENT_CLOSE, SubString(t.data, close_start, t.pos - 1))
            return Token(TOKEN_COMMENT_CONTENT, SubString(t.data, start, content_end))
        end
        t.pos += 1
    end
    _err("unterminated comment", start)
end

function _read_cdata_body!(t::Tokenizer)
    start = t.pos
    while !_iseof(t)
        if _peek(t) == UInt8(']') &&
           _canpeek(t, 1) && _peek(t, 1) == UInt8(']') &&
           _canpeek(t, 2) && _peek(t, 2) == UInt8('>')
            content_end = prevind(t.data, t.pos)
            close_start = t.pos
            t.pos += 3
            t.state = _S_DEFAULT
            t.pending = Token(TOKEN_CDATA_CLOSE, SubString(t.data, close_start, t.pos - 1))
            return Token(TOKEN_CDATA_CONTENT, SubString(t.data, start, content_end))
        end
        t.pos += 1
    end
    _err("unterminated CDATA section", start)
end

function _read_pi_body!(t::Tokenizer)
    start = t.pos
    while !_iseof(t)
        if _peek(t) == UInt8('?') && _canpeek(t, 1) && _peek(t, 1) == UInt8('>')
            content_end = prevind(t.data, t.pos)
            close_start = t.pos
            t.pos += 2
            t.state = _S_DEFAULT
            t.pending = Token(TOKEN_PI_CLOSE, SubString(t.data, close_start, t.pos - 1))
            return Token(TOKEN_PI_CONTENT, SubString(t.data, start, content_end))
        end
        t.pos += 1
    end
    _err("unterminated processing instruction", start)
end

function _read_doctype_body!(t::Tokenizer)
    start = t.pos
    depth = 0
    while !_iseof(t)
        b = _peek(t)
        if b == UInt8('-') && _canpeek(t, 1) && _peek(t, 1) == UInt8('-') &&
                t.pos >= 2 &&
                codeunit(t.data, t.pos - 1) == UInt8('!') &&
                codeunit(t.data, t.pos - 2) == UInt8('<')
            # Inside a <!-- comment: skip until -->
            t.pos += 2  # skip "--"
            while !_iseof(t)
                if _peek(t) == UInt8('-') && _canpeek(t, 1) && _peek(t, 1) == UInt8('-') &&
                        _canpeek(t, 2) && _peek(t, 2) == UInt8('>')
                    t.pos += 3  # skip "-->"
                    break
                end
                t.pos += 1
            end
        elseif b == UInt8('"') || b == UInt8('\'')
            _skip_quoted!(t)
        elseif b == UInt8('[')
            depth += 1
            t.pos += 1
        elseif b == UInt8(']')
            depth -= 1
            t.pos += 1
        elseif b == UInt8('>') && depth == 0
            content_end = prevind(t.data, t.pos)
            close_start = t.pos
            t.pos += 1
            t.state = _S_DEFAULT
            t.pending = Token(TOKEN_DOCTYPE_CLOSE, SubString(t.data, close_start, t.pos - 1))
            return Token(TOKEN_DOCTYPE_CONTENT, SubString(t.data, start, content_end))
        else
            t.pos += 1
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
        SubString(token.raw, 2, ncodeunits(token.raw))  # skip '<'
    elseif token.kind == TOKEN_CLOSE_TAG
        SubString(token.raw, 3, ncodeunits(token.raw))  # skip '</'
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
    SubString(token.raw, 2, prevind(token.raw, lastindex(token.raw)))
end

"""
    pi_target(token::Token) -> SubString{String}

Extract the target name from a `PI_OPEN` or `XML_DECL_OPEN` token.
"""
function pi_target(token::Token)
    (token.kind == TOKEN_PI_OPEN || token.kind == TOKEN_XML_DECL_OPEN) ||
        throw(ArgumentError("pi_target requires PI_OPEN or XML_DECL_OPEN, got $(token.kind)"))
    SubString(token.raw, 3, ncodeunits(token.raw))  # skip '<?'
end

end # module XMLTokenizer
