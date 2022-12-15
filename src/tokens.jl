macro _assert(cond)
    return esc(quote
        __cond__ = $cond
        if !__cond__
            src = $(string(__source__))
            rng = max(1, i - 5):min(length(tokens), i + 5)
            toks = tokens[rng]
            println("DEBUG: i = $i, $src")
            for (i, tok) in zip(rng, toks)
                println("    $i:", tok)
            end
            error("assertion error: " * $(string(cond)))
        end
    end)
end

const RESERVED = Set(["local", "global", "export", "let",
    "for", "struct", "while", "const", "continue", "import",
    "function", "if", "else", "try", "begin", "break", "catch",
    "return", "using", "baremodule", "macro", "finally",
    "module", "elseif", "end", "quote", "do"])

clean(x) = x in RESERVED ? string("_", x) : x

_copy(x::String) = x
_copy(x) = copy(x)
function _copy(x::T) where {T <: AbstractGoType}
    y = T()
    for f in fieldnames(T)
        if isdefined(x, f)
            setfield!(y, f, _copy(getfield(x, f)))
        end
    end
    return y
end

abstract type Token <: AbstractGoType end

abstract type Comment <: Token end

struct LineComment <: Comment
    value::String
end

struct GeneralComment <: Comment
    value::String
end

function consumecmts!(x, tokens, i, cmts)
    while i <= length(tokens)
        token = tokens[i]
        token isa Comment || break
        if x !== nothing
            push!(get!(() -> Comment[], cmts, x), token)
        end
        i += 1
    end
    return i
end

function consumelinecmt!(x, tokens, i, cmts)
    if i <= length(tokens)
        if tokens[i] isa LineComment
            push!(get!(() -> Comment[], cmts, x), tokens[i])
            i += 1
        end
        if tokens[i] == SEMI
            i += 1
        end
    end
    return i
end

function outputcomments(io, x, cmts)
    if haskey(cmts, x)
        for cmt in cmts[x]
            if cmt isa GeneralComment
                println(io, "#=", cmt.value, "=#")
            elseif cmt isa LineComment
                println(io, "# ", cmt.value)
            end
        end
    end
    return
end

struct Keyword <: Token
    value::String
end

const KEYWORDS = ["break", "default", "func", "interface", "select", "case", "defer", "go", "map", "struct", "chan", "else", "goto", "package", "switch", "const", "fallthrough", "if", "range", "type", "continue", "for", "import", "return", "var"]

const KEYWORD_VALUES = Dict{String, Keyword}()

for x in KEYWORDS
    @eval const $(Symbol(uppercase(x))) = Keyword($x)
    @eval KEYWORD_VALUES[$x] = $(Symbol(uppercase(x)))
end

struct Operator <: Token
    value::String
end

function transpile(io, x::Operator, cmts)
    print(io, x.value)
    return
end

const OPERATOR_NAMES = Dict(
    "+" => "PLUS",
    "&" => "AND",
    "=" => "EQ",
    "!" => "NOT",
    "-" => "MINUS",
    "|" => "PIPE",
    "<" => "LT",
    "*" => "MUL",
    "^" => "POW",
    ">" => "GT",
    "/" => "DIV",
    ":" => "COL",
    "%" => "MOD",
    "." => "DOT"
)

# operator characters that can be used as a suffix w/ other operator characters
const SECONDARY_OPERATORS = Set{UInt8}([
    UInt8('='),
    UInt8('&'),
    UInt8('|'),
    UInt8('<'),
    UInt8('>'),
    UInt8('+'),
    UInt8('-'),
    UInt8('.'),
    UInt8('^')
])

const OPERATORS = [
    "+", "&", "+=", "&=", "&&", "==", "!=",
    "-", "|", "-=", "|=", "||", "<", "<=",
    "*", "^", "*=", "^=", "<-", ">", ">=",
    "/", "<<", "/=", "<<=", "++", "=", ":=",
    "%", ">>", "%=", ">>=", "--", "!",
    "...", ".", ":",
    "&^", "&^="
]

const OPERATOR_VALUES = Dict{String, Operator}()

for x in OPERATORS
    nm = join(map(c -> OPERATOR_NAMES[string(c)], collect(x)))
    @eval const $(Symbol(nm)) = Operator($x)
    @eval OPERATOR_VALUES[$x] = $(Symbol(nm))
end

struct Punctuation <: Token
    value::String
end

const PUNCTUATIONS = [
    "(", ")",
    "[", "]",
    "{", "}",
    ",", ";",
]

const PUNCTUATION_NAMES = Dict(
    "(" => "OP",
    ")" => "CP",
    "[" => "OSB",
    "]" => "CSB",
    "{" => "OCB",
    "}" => "CCB",
    "," => "COM",
    ";" => "SEMI"
)

const PUNCTUATION_VALUES = Dict{String, Punctuation}()

for x in PUNCTUATIONS
    nm = PUNCTUATION_NAMES[x]
    @eval const $(Symbol(uppercase(nm))) = Punctuation($x)
    @eval PUNCTUATION_VALUES[$x] = $(Symbol(uppercase(nm)))
end

abstract type LiteralToken <: Token end

function transpile(io, x::LiteralToken, cmts)
    print(io, x.value)
    return
end

struct NumericLiteral <: LiteralToken
    value::Number
end

struct RuneLiteral <: LiteralToken
    value::Char
end

function transpile(io, x::RuneLiteral, cmts)
    print(io, repr(x.value))
    return
end

struct StringLiteral <: LiteralToken
    value::String
end

function transpile(io, x::StringLiteral, cmts)
    print(io, repr(x.value))
    return
end

struct RawStringLiteral <: LiteralToken
    value::String
end

function transpile(io, x::RawStringLiteral, cmts)
    print(io, repr(x.value))
    return
end

tokenize(file::String) = tokenize(Base.read(file))

function tokenize(bytes)
    tokens = Token[]
    pos = 1
    len = length(bytes)
    while pos < len
        pos, token = parsetoken(bytes, pos, len)
        if token !== nothing
            push!(tokens, token)
        end
        if pos < len
            b = bytes[pos]
            if b == UInt8('\n')
                # When the input is broken into tokens, a semicolon is automatically inserted into the token stream immediately after a line's final token if that token is
                #     an identifier
                #     an integer, floating-point, imaginary, rune, or string literal
                #     one of the keywords break, continue, fallthrough, or return
                #     one of the operators and punctuation ++, --, ), ], or }
                token = tokens[end]
                if token isa Identifier ||
                   token isa LiteralToken ||
                   token == BREAK ||
                   token == CONTINUE ||
                   token == FALLTHROUGH ||
                   token == RETURN ||
                   token == PLUSPLUS ||
                   token == MINUSMINUS ||
                   token == CP ||
                   token == CSB ||
                   token == CCB
                    push!(tokens, SEMI)
                end
            end
        end
    end
    return tokens
end

iswhitespace(b) = b == UInt8(' ') || b == UInt8('\t') || b == UInt8('\n')

function parsetoken(bytes, pos, len)
    pos == len && return pos, nothing
    b = bytes[pos]
    # ignore leading whitespace
    while iswhitespace(b)
        pos += 1
        pos == len && return pos, nothing
        b = bytes[pos]
    end
    # now positioned at the start of a token
    if b == UInt8('/')
        pos += 1
        pos < len || throw(ArgumentError("file ended w/ `/` character"))
        # check if we're parsing a line or general comment
        b = bytes[pos]
        if b == UInt8('/')
            # line comment
            pos += 1
            spos = pos
            slen = 0
            while b != UInt8('\n')
                pos == len && break
                b = bytes[pos]
                pos += 1
                slen += 1
            end
            return pos, LineComment(str(bytes, spos, slen - 1))
        elseif b == UInt8('*')
            # general comment
            pos += 1
            spos = pos
            slen = 0
            while true
                pos == len && break
                b = bytes[pos]
                pos += 1
                if b == UInt8('*') && pos < len && bytes[pos] == UInt8('/')
                    pos += 1
                    break
                end
                slen += 1
            end
            return pos, GeneralComment(str(bytes, spos, slen - 2))
        elseif b == UInt8('=')
            # division update operator
            return pos + 1, DIVEQ
        else
            return pos, DIV
        end
    elseif b == UInt8('`')
        # raw string literal token, parse until closing '`'
        # double backticks are escaped
        pos += 1
        pos < len || throw(ArgumentError("invalid raw string literal"))
        b = bytes[pos]
        spos = pos
        slen = 0
        while b != UInt8('`')
            if b == UInt8('`') && pos < len && bytes[pos + 1] == UInt8('`')
                pos += 1
                slen += 1
                b = bytes[pos]
            end
            pos += 1
            slen += 1
            pos == len && throw(ArgumentError("invalid raw string literal"))
            b = bytes[pos]
        end
        return pos + 1, RawStringLiteral(str(bytes, spos, slen))
    elseif b == UInt8('"')
        # string literal token, parse until closing '"'
        pos += 1
        pos < len || throw(ArgumentError("invalid string literal"))
        b = bytes[pos]
        spos = pos
        slen = 0
        while b != UInt8('"')
            if b == UInt8('\\')
                pos += 1
                slen += 1
                b = bytes[pos]
            end
            pos += 1
            slen += 1
            pos == len && throw(ArgumentError("invalid string literal"))
            b = bytes[pos]
        end
        return pos + 1, StringLiteral(str(bytes, spos, slen))
    elseif b == UInt8('\'')
        # rune literal token, parse until closing '\''
        spos = pos
        slen = 1
        pos += 1
        pos < len || throw(ArgumentError("invalid rune literal"))
        b = bytes[pos]
        while b != UInt8('\'')
            pos += 1
            slen += 1
            pos == len && throw(ArgumentError("invalid rune literal"))
            b = bytes[pos]
        end
        val = str(bytes, spos, slen + 1)
        # TODO: parseatom doesn't quite work for all the rune literals Go supports, but it supports some
        rune = Meta.parseatom(val, 1)[1]
        return pos + 1, RuneLiteral(rune)
    elseif UInt8('0') <= b <= UInt8('9')
        # numeric literal
        # grab a string for the next 50 bytes
        forwardbytes = str(bytes, pos, 50)
        num, slen = Meta.parse(forwardbytes, 1; greedy=false)
        pos += slen - 1
        return pos, NumericLiteral(num)
    else
        # punctuation, operator, keyword, or identifier
        val = string(Char(b))
        if val in PUNCTUATIONS
            return pos + 1, PUNCTUATION_VALUES[val]
        elseif val in OPERATORS
            # parse until non-operator
            spos = pos
            slen = 1
            while true
                pos += 1
                b = bytes[pos]
                b in SECONDARY_OPERATORS || break
                slen += 1
            end
            return pos, OPERATOR_VALUES[str(bytes, spos, slen)]
        else
            # keyword or identifier, parse until non-alphanumeric
            spos = pos
            slen = 1
            while (isletter(Char(b)) || b == UInt8('_') || isdigit(Char(b))) && pos < len
                pos += 1
                b = bytes[pos]
                slen += 1
            end
            val = str(bytes, spos, slen - 1)
            return pos, get(KEYWORD_VALUES, val, Identifier(val))
        end
    end
    return pos, nothing
end
