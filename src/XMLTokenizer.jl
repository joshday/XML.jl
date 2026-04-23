module XMLTokenizer

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

#-----------------------------------------------------------------------# Tokenizer mode
@enum Mode::UInt8 begin
    M_DEFAULT            # normal content mode
    M_TAG                # inside open tag, reading attributes
    M_TAG_VALUE          # expecting quoted attribute value
    M_CLOSE_TAG          # inside close tag, expecting >
    M_XML_DECL           # inside <?xml, reading pseudo-attributes
    M_XML_DECL_VALUE     # expecting quoted attr value in xml decl
    M_COMMENT            # after <!--, reading content
    M_CDATA              # after <![CDATA[, reading content
    M_PI                 # after <?target, reading content
    M_DOCTYPE            # after <!DOCTYPE, reading content
end

#-----------------------------------------------------------------------# TokenizerState (immutable, SROA-friendly)
struct TokenizerState{S <: AbstractString}
    pos::Int
    mode::Mode
    pending::Token{S}  # buffered token for constructs that emit two tokens at once (e.g. content + close)
end

# Create an empty token (no pending token buffered)
@inline no_token(s::AbstractString) = Token(TOKEN_TEXT, @inbounds SubString(s, 1, 0))
# Check whether the state has a buffered pending token
@inline has_pending(st::TokenizerState) = !isempty(st.pending.raw)


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
    print(io, Base.format_bytes(n), ")")
end

Base.IteratorSize(::Type{<:Tokenizer}) = Base.SizeUnknown()
Base.eltype(::Type{Tokenizer{S}}) where {S} = Token{S}

function Base.iterate(t::Tokenizer, st::TokenizerState=TokenizerState(t.start, M_DEFAULT, no_token(t.data)))
    (; data) = t
    (; pending, pos, mode) = st

    if has_pending(st)
        return (pending, TokenizerState(pos, mode, no_token(data)))
    end
    iseof(data, pos) && return nothing

    if mode == M_DEFAULT
        peek(data, pos) == UInt8('<') ? read_markup(data, pos) : read_text(data, pos)
    elseif mode == M_TAG || mode == M_XML_DECL
        read_in_tag(data, pos, mode)
    elseif mode == M_TAG_VALUE || mode == M_XML_DECL_VALUE
        read_attr_value(data, pos, mode)
    elseif mode == M_CLOSE_TAG
        read_close_tag_end(data, pos)
    elseif mode == M_COMMENT
        read_comment_body(data, pos)
    elseif mode == M_CDATA
        read_cdata_body(data, pos)
    elseif mode == M_PI
        read_pi_body(data, pos)
    else  # M_DOCTYPE
        read_doctype_body(data, pos)
    end
end

#-----------------------------------------------------------------------# Internal helpers
# Check if pos is past the end of data
@inline iseof(data::AbstractString, pos::Int)::Bool = pos > ncodeunits(data)
# Read the byte at pos without bounds checking
@inline peek(data::AbstractString, pos::Int)::UInt8 = @inbounds codeunit(data, pos)
# Check if pos + offset is within bounds
@inline canpeek(data::AbstractString, pos::Int, offset::Int)::Bool = pos + offset <= ncodeunits(data)

# Lookup table for XML name bytes (letter, digit, _, -, ., :)
const NAME_BYTE_TABLE = let t = falses(256)
    for r in (UInt8('a'):UInt8('z'), UInt8('A'):UInt8('Z'), UInt8('0'):UInt8('9'))
        for b in r; t[b + 1] = true; end
    end
    for b in (UInt8('_'), UInt8('-'), UInt8('.'), UInt8(':')); t[b + 1] = true; end
    NTuple{256,Bool}(t)
end
@inline is_name_byte(b::UInt8)::Bool = @inbounds NAME_BYTE_TABLE[b + 1]

# Check if byte is XML whitespace (space, tab, newline, carriage return)
@inline function is_whitespace(b::UInt8)::Bool
    b == UInt8(' ') || b == UInt8('\t') || b == UInt8('\n') || b == UInt8('\r')
end

# Advance pos past any whitespace bytes
@inline function skip_whitespace(data::AbstractString, pos::Int)::Int
    @inbounds while !iseof(data, pos) && is_whitespace(peek(data, pos))
        pos += 1
    end
    pos
end

# Advance pos past a quoted string (single or double quotes)
function skip_quoted(data::AbstractString, pos::Int)::Int
    q = @inbounds peek(data, pos)
    pos += 1
    @inbounds while !iseof(data, pos)
        peek(data, pos) == q && return pos + 1
        pos += 1
    end
    error("Unterminated quoted string")
end

# Throw a tokenizer error with position context (noinline to keep error paths out of hot code)
@noinline err(msg::AbstractString, pos::Int) = throw(ArgumentError("XML tokenizer error at position $pos: $msg"))

#-----------------------------------------------------------------------# Text and markup
# Read text content up to the next '<'
function read_text(data::AbstractString, pos::Int)
    start = pos
    @inbounds while !iseof(data, pos) && peek(data, pos) != UInt8('<')
        pos += 1
    end
    tok = Token(TOKEN_TEXT, @inbounds SubString(data, start, prevind(data, pos)))
    (tok, TokenizerState(pos, M_DEFAULT, no_token(data)))
end

# Dispatch on the character after '<' to the appropriate reader
function read_markup(data::AbstractString, pos::Int)
    start = pos
    pos += 1  # skip '<'
    iseof(data, pos) && err("unexpected end of input after '<'", start)

    b = peek(data, pos)
    if b == UInt8('!')
        read_bang(data, pos + 1, start)
    elseif b == UInt8('?')
        read_pi_start(data, pos + 1, start)
    elseif b == UInt8('/')
        read_close_tag_start(data, pos + 1, start)
    else
        read_open_tag_start(data, pos, start)
    end
end

#-----------------------------------------------------------------------# <! dispatch
# Handle '<!' — comment, CDATA, or DOCTYPE
function read_bang(data::AbstractString, pos::Int, start::Int)
    # Comment: <!--
    if !iseof(data, pos) && peek(data, pos) == UInt8('-')
        pos += 1
        (!iseof(data, pos) && peek(data, pos) == UInt8('-')) || err("expected '<!--'", start)
        pos += 1
        tok = Token(TOKEN_COMMENT_OPEN, @inbounds SubString(data, start, pos - 1))
        return (tok, TokenizerState(pos, M_COMMENT, no_token(data)))
    end

    # CDATA: <![CDATA[
    if !iseof(data, pos) && peek(data, pos) == UInt8('[')
        pos += 1
        for expected in (UInt8('C'), UInt8('D'), UInt8('A'), UInt8('T'), UInt8('A'), UInt8('['))
            iseof(data, pos) && err("unterminated CDATA", start)
            peek(data, pos) == expected || err("invalid CDATA section", start)
            pos += 1
        end
        tok = Token(TOKEN_CDATA_OPEN, @inbounds SubString(data, start, pos - 1))
        return (tok, TokenizerState(pos, M_CDATA, no_token(data)))
    end

    # <!DOCTYPE ...> or other <! declaration
    @inbounds while !iseof(data, pos) && is_name_byte(peek(data, pos))
        pos += 1
    end
    tok = Token(TOKEN_DOCTYPE_OPEN, @inbounds SubString(data, start, pos - 1))
    (tok, TokenizerState(pos, M_DOCTYPE, no_token(data)))
end

#-----------------------------------------------------------------------# <? (PI / XML declaration)
# Handle '<?' — XML declaration or processing instruction
function read_pi_start(data::AbstractString, pos::Int, start::Int)
    name_start = pos
    @inbounds while !iseof(data, pos) && is_name_byte(peek(data, pos))
        pos += 1
    end

    is_xml = (pos - name_start == 3) &&
        codeunit(data, name_start)     == UInt8('x') &&
        codeunit(data, name_start + 1) == UInt8('m') &&
        codeunit(data, name_start + 2) == UInt8('l')

    if is_xml
        tok = Token(TOKEN_XML_DECL_OPEN, @inbounds SubString(data, start, pos - 1))
        (tok, TokenizerState(pos, M_XML_DECL, no_token(data)))
    else
        tok = Token(TOKEN_PI_OPEN, @inbounds SubString(data, start, pos - 1))
        (tok, TokenizerState(pos, M_PI, no_token(data)))
    end
end

#-----------------------------------------------------------------------# Tags
# Read '<name' and enter tag-attribute mode
function read_open_tag_start(data::AbstractString, pos::Int, start::Int)
    @inbounds while !iseof(data, pos) && is_name_byte(peek(data, pos))
        pos += 1
    end
    tok = Token(TOKEN_OPEN_TAG, @inbounds SubString(data, start, pos - 1))
    (tok, TokenizerState(pos, M_TAG, no_token(data)))
end

# Read '</name' and enter close-tag mode
function read_close_tag_start(data::AbstractString, pos::Int, start::Int)
    @inbounds while !iseof(data, pos) && is_name_byte(peek(data, pos))
        pos += 1
    end
    tok = Token(TOKEN_CLOSE_TAG, @inbounds SubString(data, start, pos - 1))
    (tok, TokenizerState(pos, M_CLOSE_TAG, no_token(data)))
end

# Consume the '>' that closes a '</name>' tag
function read_close_tag_end(data::AbstractString, pos::Int)
    pos = skip_whitespace(data, pos)
    iseof(data, pos) && err("unterminated close tag", pos)
    peek(data, pos) == UInt8('>') || err("expected '>'", pos)
    tok = Token(TOKEN_TAG_CLOSE, @inbounds SubString(data, pos, pos))
    (tok, TokenizerState(pos + 1, M_DEFAULT, no_token(data)))
end

#-----------------------------------------------------------------------# Attributes (shared by M_TAG and M_XML_DECL)
# Read the next attribute name or tag-close delimiter (>, />, ?>)
function read_in_tag(data::AbstractString, pos::Int, mode::Mode)
    pos = skip_whitespace(data, pos)
    iseof(data, pos) && err("unterminated tag", pos)

    b = peek(data, pos)
    is_decl = (mode == M_XML_DECL)

    # Check for end delimiters
    if is_decl
        if b == UInt8('?') && canpeek(data, pos, 1) && peek(data, pos + 1) == UInt8('>')
            tok = Token(TOKEN_XML_DECL_CLOSE, @inbounds SubString(data, pos, pos + 1))
            return (tok, TokenizerState(pos + 2, M_DEFAULT, no_token(data)))
        end
    else
        if b == UInt8('>')
            tok = Token(TOKEN_TAG_CLOSE, @inbounds SubString(data, pos, pos))
            return (tok, TokenizerState(pos + 1, M_DEFAULT, no_token(data)))
        end
        if b == UInt8('/') && canpeek(data, pos, 1) && peek(data, pos + 1) == UInt8('>')
            tok = Token(TOKEN_SELF_CLOSE, @inbounds SubString(data, pos, pos + 1))
            return (tok, TokenizerState(pos + 2, M_DEFAULT, no_token(data)))
        end
    end

    # Attribute name
    name_start = pos
    @inbounds while !iseof(data, pos) && is_name_byte(peek(data, pos))
        pos += 1
    end
    name_end = pos - 1
    name_start > name_end && err("expected attribute name or tag close", pos)

    # Consume '=' and surrounding whitespace (not part of any token)
    pos = skip_whitespace(data, pos)
    (!iseof(data, pos) && peek(data, pos) == UInt8('=')) || err("expected '=' after attribute name", pos)
    pos += 1
    pos = skip_whitespace(data, pos)

    next_state = is_decl ? M_XML_DECL_VALUE : M_TAG_VALUE
    tok = Token(TOKEN_ATTR_NAME, @inbounds SubString(data, name_start, name_end))
    (tok, TokenizerState(pos, next_state, no_token(data)))
end

# Read a quoted attribute value (including the quotes)
function read_attr_value(data::AbstractString, pos::Int, mode::Mode)
    iseof(data, pos) && err("expected attribute value", pos)

    q = peek(data, pos)
    (q == UInt8('"') || q == UInt8('\'')) || err("expected quoted attribute value", pos)

    start = pos
    pos += 1  # skip opening quote
    @inbounds while !iseof(data, pos) && peek(data, pos) != q
        pos += 1
    end
    iseof(data, pos) && err("unterminated attribute value", start)
    pos += 1  # skip closing quote

    next_state = (mode == M_XML_DECL_VALUE) ? M_XML_DECL : M_TAG
    tok = Token(TOKEN_ATTR_VALUE, @inbounds SubString(data, start, pos - 1))
    (tok, TokenizerState(pos, next_state, no_token(data)))
end

#-----------------------------------------------------------------------# Content bodies (comment, CDATA, PI, DOCTYPE)
# Scan for '-->' and emit comment content + close tokens
function read_comment_body(data::AbstractString, pos::Int)
    start = pos
    @inbounds while !iseof(data, pos)
        if peek(data, pos) == UInt8('-') &&
           canpeek(data, pos, 1) && peek(data, pos + 1) == UInt8('-') &&
           canpeek(data, pos, 2) && peek(data, pos + 2) == UInt8('>')
            content_end = prevind(data, pos)
            close_start = pos
            pos += 3
            pending = Token(TOKEN_COMMENT_CLOSE, SubString(data, close_start, pos - 1))
            tok = Token(TOKEN_COMMENT_CONTENT, SubString(data, start, content_end))
            return (tok, TokenizerState(pos, M_DEFAULT, pending))
        end
        pos += 1
    end
    err("unterminated comment", start)
end

# Scan for ']]>' and emit CDATA content + close tokens
function read_cdata_body(data::AbstractString, pos::Int)
    start = pos
    @inbounds while !iseof(data, pos)
        if peek(data, pos) == UInt8(']') &&
           canpeek(data, pos, 1) && peek(data, pos + 1) == UInt8(']') &&
           canpeek(data, pos, 2) && peek(data, pos + 2) == UInt8('>')
            content_end = prevind(data, pos)
            close_start = pos
            pos += 3
            pending = Token(TOKEN_CDATA_CLOSE, SubString(data, close_start, pos - 1))
            tok = Token(TOKEN_CDATA_CONTENT, SubString(data, start, content_end))
            return (tok, TokenizerState(pos, M_DEFAULT, pending))
        end
        pos += 1
    end
    err("unterminated CDATA section", start)
end

# Scan for '?>' and emit PI content + close tokens
function read_pi_body(data::AbstractString, pos::Int)
    start = pos
    @inbounds while !iseof(data, pos)
        if peek(data, pos) == UInt8('?') && canpeek(data, pos, 1) && peek(data, pos + 1) == UInt8('>')
            content_end = prevind(data, pos)
            close_start = pos
            pos += 2
            pending = Token(TOKEN_PI_CLOSE, SubString(data, close_start, pos - 1))
            tok = Token(TOKEN_PI_CONTENT, SubString(data, start, content_end))
            return (tok, TokenizerState(pos, M_DEFAULT, pending))
        end
        pos += 1
    end
    err("unterminated processing instruction", start)
end

# Scan DOCTYPE body, handling nested brackets, quotes, and comments
function read_doctype_body(data::AbstractString, pos::Int)
    start = pos
    depth = 0
    @inbounds while !iseof(data, pos)
        b = peek(data, pos)
        if b == UInt8('-') && canpeek(data, pos, 1) && peek(data, pos + 1) == UInt8('-') &&
                pos >= 3 &&
                codeunit(data, pos - 1) == UInt8('!') &&
                codeunit(data, pos - 2) == UInt8('<')
            # Inside a <!-- comment: skip until -->
            pos += 2  # skip "--"
            while !iseof(data, pos)
                if peek(data, pos) == UInt8('-') && canpeek(data, pos, 1) && peek(data, pos + 1) == UInt8('-') &&
                        canpeek(data, pos, 2) && peek(data, pos + 2) == UInt8('>')
                    pos += 3  # skip "-->"
                    break
                end
                pos += 1
            end
        elseif b == UInt8('"') || b == UInt8('\'')
            pos = skip_quoted(data, pos)
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
            return (tok, TokenizerState(pos, M_DEFAULT, pending))
        else
            pos += 1
        end
    end
    err("unterminated DOCTYPE", start)
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
