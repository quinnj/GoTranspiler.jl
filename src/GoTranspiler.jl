module GoTranspiler

include("types.jl")

str(bytes, pos, len) = unsafe_string(pointer(bytes, pos), len)

function transpile(dir, outdir)
    isdir(dir) || throw(ArgumentError("must pass valid directory name; to transpile single file, call `transpilefile(file)`"))
    for (root, dirs, files) in walkdir(dir)
        for file in files
            transpilefile(file, outdir)
        end
    end
    return
end

function transpilefile(file, outdir)
    bytes = Base.read(gofile)
    tokens = tokenize(bytes)
    open(joinpath(outdir, basename(file) * ".jl"), "w+") do io
        # recursively calls transpile to consume full token stream
        i = 1
        while i <= length(tokens)
            token = tokens[i]
            i = transpile(io, token, tokens, i)
        end
    end
end

function objectify(file::String)
    bytes = Base.read(file)
    tokens = tokenize(bytes)
    return objectify(tokens)
end

function objectify(tokens)
    cmts = Dict{Any, Vector{Comment}}()
    return objectify(Package, tokens, 1, cmts), cmts
end

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
            return pos + 1, DIV
        end
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
                haskey(OPERATOR_NAMES, string(Char(b))) || break
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

end # module
