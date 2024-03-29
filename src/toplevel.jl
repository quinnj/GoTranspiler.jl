mutable struct ConstSpec <: AbstractGoType
    ConstSpec() = new()
    identifiers::Vector{Identifier}
    type::Union{Nothing, GoType}
    expressions::Vector{Expression}
end

function objectify(::Type{ConstSpec}, tokens, i, cmts)
    x = ConstSpec()
    i = consumecmts!(x, tokens, i, cmts)
    x.identifiers, i = objectify(Vector{Identifier}, tokens, i, cmts)
    token = tokens[i]
    if token != SEMI # if const list started w/ iota, subsequent identifiers are empty
        if token != EQ
            # type
            x.type, i = objectify(GoType, tokens, i, cmts)
        end
        token = tokens[i]
        if token == EQ
            # assignments
            x.expressions, i = objectify(Vector{Expression}, tokens, i + 1, cmts)
        end
    end
    i = consumelinecmt!(x, tokens, i, cmts)
    return x, i
end 

function transpile(io, x::ConstSpec, cmts)
    outputcomments(io, x, cmts)
    print(io, "const ")
    len = length(x.identifiers)
    for (i, id) in enumerate(x.identifiers)
        transpile(io, id, cmts)
        if isdefined(x, :type) && x.type !== nothing
            print(io, "::")
            transpile(io, x.type, cmts)
        end
        i == len || print(io, ", ")
    end
    if isdefined(x, :expressions) && !isempty(x.expressions)
        print(io, " = ")
        for (i, expr) in enumerate(x.expressions)
            transpile(io, expr, cmts)
            i == len || print(io, ", ")
        end
    else
        print(io, " = iota")
    end
    return
end

mutable struct ConstDecl <: Statement
    ConstDecl() = new()
    consts::Vector{ConstSpec}
end

function objectify(::Type{ConstDecl}, tokens, i, cmts)
    x = ConstDecl()
    x.consts = ConstSpec[]
    token = tokens[i]
    if token == OP
        i += 1
        token = tokens[i]
        # list of consts
        while token != CP
            varspec, i = objectify(ConstSpec, tokens, i, cmts)
            push!(x.consts, varspec)
            token = tokens[i]
        end
        i += 1
    else
        varspec, i = objectify(ConstSpec, tokens, i, cmts)
        push!(x.consts, varspec)
    end
    i = consumelinecmt!(x, tokens, i, cmts)
    return x, i
end

function transpile(io, x::ConstDecl, cmts)
    outputcomments(io, x, cmts)
    for con in x.consts
        transpile(io, con, cmts)
        println(io)
    end
    return
end

mutable struct AliasDecl <: AbstractGoType
    AliasDecl() = new()
    name::Identifier
    type::GoType
end

function transpile(io, x::AliasDecl, cmts)
    outputcomments(io, x, cmts)
    print(io, "const ")
    transpile(io, x.name, cmts)
    print(io, " = ")
    transpile(io, x.type, cmts)
    return
end

mutable struct TypeDef <: AbstractGoType
    TypeDef() = new()
    name::Identifier
    type::GoType
end

function transpile(io, x::TypeDef, cmts)
    outputcomments(io, x, cmts)
    if x.type isa InterfaceType
        print(io, "abstract type ")
    else
        print(io, "mutable struct ")
    end
    transpile(io, x.name, cmts)
    if x.type isa StructType
        println(io)
        for field in x.type.fields
            for nm in field.names
                print(io, nm.value)
                print(io, "::")
                transpile(io, field.type, cmts)
                println(io)
            end
        end
        println(io, "end")
    elseif x.type isa InterfaceType
        println(io, " end")
        transpile(io, x.type, cmts)
        println(io)
    else
        transpile(io, x.type, cmts)
        print(io, "::")
        transpile(io, x.type, cmts)
        println(io)
        println(io, "end")
    end
    return
end

const TypeSpec = Union{AliasDecl, TypeDef}

function objectify(::Type{TypeSpec}, tokens, i, cmts)
    starti = i
    i = consumecmts!(nothing, tokens, i, cmts)
    token = tokens[i]
    @_assert token isa Identifier
    name = token
    i += 1
    token = tokens[i]
    if token == EQ
        # AliasDecl
        i += 1
        x = AliasDecl()
        x.name = name
        x.type, i = objectify(GoType, tokens, i, cmts)
    else
        # TypeDef
        x = TypeDef()
        x.name = name
        x.type, i = objectify(GoType, tokens, i, cmts)
    end
    consumecmts!(x, tokens, starti, cmts)
    i = consumelinecmt!(x, tokens, i, cmts)
    return x, i
end

mutable struct TypeDecl <: Statement
    TypeDecl() = new()
    typespecs::Vector{TypeSpec}
end

function objectify(::Type{TypeDecl}, tokens, i, cmts)
    x = TypeDecl()
    x.typespecs = TypeSpec[]
    token = tokens[i]
    if token == OP
        i += 1
        token = tokens[i]
        # list of typespecs
        while token != CP
            varspec, i = objectify(TypeSpec, tokens, i, cmts)
            push!(x.typespecs, varspec)
            token = tokens[i]
        end
        i += 1
    else
        varspec, i = objectify(TypeSpec, tokens, i, cmts)
        push!(x.typespecs, varspec)
    end
    i = consumelinecmt!(x, tokens, i, cmts)
    return x, i
end

function transpile(io, x::TypeDecl, cmts)
    outputcomments(io, x, cmts)
    for type in x.typespecs
        transpile(io, type, cmts)
    end
    println(io)
    return
end

mutable struct VarSpec <: AbstractGoType
    VarSpec() = new()
    identifiers::Vector{Identifier}
    type::Union{Nothing, GoType}
    expressions::Vector{Expression}
end

function objectify(::Type{Vector{Identifier}}, tokens, i, cmts)
    x = Identifier[]
    token = tokens[i]
    if token isa Identifier
        # identifiers list
        while true
            push!(x, token)
            i += 1
            token = tokens[i]
            token == COM || break
            i += 1
            token = tokens[i]
            token isa Identifier || break
        end
    end
    return x, i
end

function objectify(::Type{VarSpec}, tokens, i, cmts)
    x = VarSpec()
    i = consumecmts!(x, tokens, i, cmts)
    x.identifiers, i = objectify(Vector{Identifier}, tokens, i, cmts)
    token = tokens[i]
    if token != EQ
        # type
        x.type, i = objectify(GoType, tokens, i, cmts)
    end
    token = tokens[i]
    if token == EQ
        # assignments
        x.expressions, i = objectify(Vector{Expression}, tokens, i + 1, cmts)
    end
    i = consumelinecmt!(x, tokens, i, cmts)
    return x, i
end

function transpile(io, x::VarSpec, cmts)
    outputcomments(io, x, cmts)
    len = length(x.identifiers)
    if !isdefined(x, :expressions) || isempty(x.expressions)
        print(io, "local ")
    end
    for (i, var) in enumerate(x.identifiers)
        transpile(io, var, cmts)
        if isdefined(x, :type) && x.type !== nothing
            print(io, "::")
            transpile(io, x.type, cmts)
        end
        i == len || print(io, ", ")
    end
    if isdefined(x, :expressions) && !isempty(x.expressions)
        print(io, " = ")
        for (i, expr) in enumerate(x.expressions)
            transpile(io, expr, cmts)
            i == len || print(io, ", ")
        end
    end
    return
end

mutable struct VarDecl <: Statement
    VarDecl() = new()
    varspecs::Vector{VarSpec}
end

function objectify(::Type{VarDecl}, tokens, i, cmts)
    x = VarDecl()
    x.varspecs = VarSpec[]
    token = tokens[i]
    if token == OP
        i += 1
        # list of varspecs
        while tokens[i] != CP
            varspec, i = objectify(VarSpec, tokens, i, cmts)
            push!(x.varspecs, varspec)
        end
        i += 1
    else
        varspec, i = objectify(VarSpec, tokens, i, cmts)
        push!(x.varspecs, varspec)
    end
    i = consumelinecmt!(x, tokens, i, cmts)
    return x, i
end

function transpile(io, x::VarDecl, cmts)
    outputcomments(io, x, cmts)
    for var in x.varspecs
        transpile(io, var, cmts)
        println(io)
    end
    return
end

const Declaration = Union{ConstDecl, TypeDecl, VarDecl}

function objectify(::Type{Declaration}, tokens, i, cmts)
    starti = i
    i = consumecmts!(nothing, tokens, i, cmts)
    token = tokens[i]
    if token == CONST
        x, i = objectify(ConstDecl, tokens, i + 1, cmts)
    elseif token == TYPE
        x, i = objectify(TypeDecl, tokens, i + 1, cmts)
    elseif token == VAR
        x, i = objectify(VarDecl, tokens, i + 1, cmts)
    else
        @_assert token isa Declaration
    end
    consumecmts!(x, tokens, starti, cmts)
    return x, i
end

mutable struct FunctionDecl <: AbstractGoType
    FunctionDecl() = new()
    name::Identifier
    signature::Signature
    body::Block
end

mutable struct MethodDecl <: AbstractGoType
    MethodDecl() = new()
    receiver::Parameters
    name::Identifier
    signature::Signature
    body::Block
end

function transpile(io, x::Union{FunctionDecl, MethodDecl}, cmts)
    outputcomments(io, x, cmts)
    print(io, "function ")
    transpile(io, x.name, cmts)
    sig = x.signature
    if x isa MethodDecl
        sig = _copy(sig)
        prepend!(sig.params.params, x.receiver.params)
    end
    transpile(io, sig, cmts)
    println(io)
    transpile(io, x.body.statements, cmts)
    println(io, "end")
    return
end

const TopLevel = Union{Declaration, FunctionDecl, MethodDecl}

function objectify(::Type{TopLevel}, tokens, i, cmts)
    starti = i
    i = consumecmts!(nothing, tokens, i, cmts)
    token = tokens[i]
    if token == FUNC
        # func def or method def?
        i += 1
        token = tokens[i]
        if token isa Identifier
            # FunctionDecl
            x = FunctionDecl()
            x.name = token
            i += 1
        else
            @_assert token == OP
            # MethodDecl
            x = MethodDecl()
            x.receiver, i = objectify(Parameters, tokens, i, cmts)
            x.name = tokens[i]
            i += 1
        end
        x.signature, i = objectify(Signature, tokens, i, cmts)
        x.body, i = objectify(Block, tokens, i, cmts)
    else
        # ConstDecl, VarDecl, or TypeDecl
        x, i = objectify(Declaration, tokens, i, cmts)
    end
    consumecmts!(x, tokens, starti, cmts)
    i = consumelinecmt!(x, tokens, i, cmts)
    return x, i
end

function objectify(::Type{Vector{TopLevel}}, tokens, i, cmts)
    x = TopLevel[]
    while i <= length(tokens)
        tl, i = objectify(TopLevel, tokens, i, cmts)
        push!(x, tl)
        i > length(tokens) && break
    end
    return x, i
end

const GO_STDLIBS = [
    "archive",
    "bufio",
    "builtin",
    "bytes",
    "cmd",
    "compress",
    "container",
    "context",
    "crypto",
    "database",
    "debug",
    "embed",
    "encoding",
    "errors",
    "expvar",
    "flag",
    "fmt",
    "go",
    "hash",
    "html",
    "image",
    "index",
    "internal",
    "io",
    "log",
    "math",
    "mime",
    "net",
    "os",
    "path",
    "plugin",
    "reflect",
    "regexp",
    "runtime",
    "sort",
    "strconv",
    "strings",
    "sync",
    "syscall",
    "testdata",
    "testing",
    "text",
    "time",
    "unicode",
    "unsafe/"
]

mutable struct Import <: AbstractGoType
    Import() = new()
    package::Identifier
    path::String
end

function objectify(::Type{Import}, tokens, i, cmts)
    x = Import()
    i = consumecmts!(x, tokens, i, cmts)
    token = tokens[i]
    if token == DOT
        x.package = Identifier(".")
        i += 1
        token = tokens[i]
        x.path = token
    elseif token isa Identifier
        x.package = token
        i += 1
        token = tokens[i]
        x.path = token
    else
        @_assert token isa StringLiteral
        x.path = token.value
    end
    i += 1
    i = consumelinecmt!(x, tokens, i, cmts)
    return x, i
end

function transpile(io, x::Import, cmts)
    outputcomments(io, x, cmts)
    if !isdefined(x, :package) || x.package.value != "."
        print(io, "import ")
    else
        print(io, "using ")
    end
    println(io, split(x.path, "/")[end])
    return
end

function objectify(::Type{Vector{Import}}, tokens, i, cmts)
    x = Import[]
    i = consumecmts!(x, tokens, i, cmts)
    token = tokens[i]
    if token != IMPORT
        return x, i
    end
    i += 1
    token = tokens[i]
    if token == OP
        i += 1
        token = tokens[i]
        # multiple imports
        while token != CP
            imp, i = objectify(Import, tokens, i, cmts)
            push!(x, imp)
            token = tokens[i]
        end
        i += 1
    else # single import
        imp, i = objectify(Import, tokens, i, cmts)
        push!(x, imp)
    end
    i = consumelinecmt!(x, tokens, i, cmts)
    return x, i
end

mutable struct Package <: AbstractGoType
    Package() = new()
    name::Identifier
    imports::Vector{Import}
    toplevels::Vector{TopLevel}
end

function objectify(::Type{Package}, tokens, i, cmts)
    x = Package()
    i = consumecmts!(x, tokens, i, cmts)
    token = tokens[i]
    @_assert token == PACKAGE
    i += 1
    x.name = tokens[i]
    i += 1
    @_assert tokens[i] == SEMI
    i += 1
    x.imports, i = objectify(Vector{Import}, tokens, i, cmts)
    x.toplevels, i = objectify(Vector{TopLevel}, tokens, i, cmts)
    return x
end

function transpile(io, x::Package, cmts)
    outputcomments(io, x, cmts)
    print(io, "module ")
    transpile(io, x.name, cmts)
    println(io)
    for imp in x.imports
        if split(imp.path, "/")[1] in GO_STDLIBS
            continue
        end
        transpile(io, imp, cmts)
    end
    println(io)
    for tl in x.toplevels
        transpile(io, tl, cmts)
    end
    println(io, "end # module")
    return
end
