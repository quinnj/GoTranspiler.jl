struct Identifier <: Token
    value::String
end

function transpile(io, x::Identifier, cmts)
    print(io, x.value)
    return
end

mutable struct QualifiedIdent
    QualifiedIdent() = new()
    package::Identifier
    identifier::Identifier
end

function transpile(io, x::QualifiedIdent, cmts)
    print(io, x.package.value, ".", x.identifier.value)
    return
end

const TypeName = Union{Identifier, QualifiedIdent}

function objectify(::Type{TypeName}, tokens, i, cmts)
    ident_or_package = tokens[i]
    i += 1
    token = tokens[i]
    if token == DOT
        x = QualifiedIdent()
        x.package = ident_or_package
        i += 1
        x.identifier = tokens[i]
        i += 1
    else
        x = ident_or_package
    end
    return x, i
end

function objectify(::Type{Vector{TypeName}}, tokens, i, cmts)
    x = TypeName[]
    # identifiers list
    while true
        tn, i = objectify(TypeName, tokens, i, cmts)
        push!(x, tn)
        i += 1
        token = tokens[i]
        token == COM || break
        i += 1
        token = tokens[i]
        token isa Identifier || break
    end
    return x, i
end

abstract type AbstractType end

# const TypeLit = Union{ArrayType, StructType, PointerType, FunctionType, InterfaceType, SliceType, MapType, ChannelType}
# we use AbstractType instead of TypeLit to break the cyclic dependency
const GoType = Union{TypeName, AbstractType}

function objectify(::Type{GoType}, tokens, i, cmts)
    starti = i
    i = consumecmts!(nothing, tokens, i, cmts)
    token = tokens[i]
    parens = false
    if token == OP
        parens = true
        i += 1
        token = tokens[i]
    end
    if token isa Identifier
        x, i = objectify(TypeName, tokens, i, cmts)
    elseif token == OSB
        # ArrayType or SliceType
        x, i = objectify(ArrayTypes, tokens, i, cmts)
    elseif token == STRUCT
        # StructType
        x, i = objectify(StructType, tokens, i, cmts)
    elseif token == MUL
        # PointerType
        x, i = objectify(PointerType, tokens, i, cmts)
    elseif token == FUNC
        # FunctionType
        x, i = objectify(FunctionType, tokens, i, cmts)
    elseif token == INTERFACE
        # InterfaceType
        x, i = objectify(InterfaceType, tokens, i, cmts)
    elseif token == MAP
        # MapType
        x, i = objectify(MapType, tokens, i, cmts)
    elseif token == CHAN
        # ChannelType
        x, i = objectify(ChannelType, tokens, i, cmts)
    elseif token == LTMINUS
        # ChannelType
        x, i = objectify(ChannelType, tokens, i, cmts)
    else
        @_assert token isa GoType
    end
    if parens
        token = tokens[i]
        @_assert token == CP
        i += 1
    end
    consumecmts!(x, tokens, starti, cmts)
    return x, i
end

# forward declare Expression because ArrayType needs it
abstract type AbstractExpression end
abstract type AbstractUnaryExpr <: AbstractExpression end
abstract type AbstractBinaryExpr <: AbstractExpression end

mutable struct Expression
    Expression() = new()
    expr::Union{AbstractUnaryExpr, AbstractBinaryExpr}
end

function transpile(io, x::Expression, cmts)
    transpile(io, x.expr, cmts)
    return
end

mutable struct ArrayType <: AbstractType
    ArrayType() = new()
    len::Expression
    type::GoType
end

mutable struct SliceType <: AbstractType
    SliceType() = new()
    type::GoType
end

mutable struct DynamicArrayType <: AbstractType
    DynamicArrayType() = new()
    type::GoType
end

const ArrayTypes = Union{ArrayType, SliceType, DynamicArrayType}

function transpile(io, x::ArrayTypes, cmts)
    print(io, "Vector{")
    transpile(io, x.type, cmts)
    print(io, "}")
    return
end

function objectify(::Type{ArrayTypes}, tokens, i, cmts)
    token = tokens[i]
    @_assert token == OSB
    i += 1
    token = tokens[i]
    if token == CSB
        i += 1
        # SliceType
        x = SliceType()
        x.type, i = objectify(GoType, tokens, i, cmts)
    elseif token == DOTDOTDOT
        i += 1
        @_assert tokens[i] == CSB
        i += 1
        # DynamicArrayType
        x = DynamicArrayType()
        x.type, i = objectify(GoType, tokens, i, cmts)
    else
        # ArrayType
        x = ArrayType()
        x.len, i = objectify(Expression, tokens, i, cmts)
        @_assert tokens[i] == CSB
        i += 1
        x.type, i = objectify(GoType, tokens, i, cmts)
    end
    return x, i
end

const Tag = String

mutable struct FieldDecl
    FieldDecl() = new()
    names::Vector{Identifier}
    type::GoType
    tag::Tag
end

function transpile(io, x::FieldDecl, cmts)
    outputcomments(io, x, cmts)
    for nm in x.names
        transpile(io, nm, cmts)
        print(io, "::")
        transpile(io, x.type, cmts)
        println(io)
    end
    if !isempty(x.tag)
        @warn "field tags not supported in Julia: $x"
    end
    return
end

function objectify(::Type{FieldDecl}, tokens, i, cmts)
    x = FieldDecl()
    i = consumecmts!(x, tokens, i, cmts)
    starti = i
    x.names, i = objectify(Vector{Identifier}, tokens, i, cmts)
    token = tokens[i]
    if token == SEMI || token isa LineComment
        # single T embedded field
        x.type = x.names[1]
        i += 1
    elseif token == DOT
        # T.x embedded field
        i = starti
        T, i = objectify(TypeName, tokens, i, cmts)
        x.names = Identifier[T.identifier]
        x.type = T
    else
        x.type, i = objectify(GoType, tokens, i, cmts)
    end
    if tokens[i] isa StringLiteral || tokens[i] isa RawStringLiteral
        x.tag = tokens[i].value
        i += 1
    end
    i = consumelinecmt!(x, tokens, i, cmts)
    return x, i
end

mutable struct StructType <: AbstractType
    StructType() = new()
    fields::Vector{FieldDecl}
end

function transpile(io, x::StructType, cmts)
    print(io, "NamedTuple{(")
    for (i, field) in enumerate(x.fields)
        i > 1 && print(io, ", ")
        print(io, field.names[1].value)
    end
    print(io, "), Tuple{")
    for (i, field) in enumerate(x.fields)
        i > 1 && print(io, ", ")
        transpile(io, field.type, cmts)
    end
    print(io, "}}")
    return
end

function objectify(::Type{StructType}, tokens, i, cmts)
    x = StructType()
    token = tokens[i]
    @_assert token == STRUCT
    i += 1
    token = tokens[i]
    @_assert token == OCB
    i += 1
    x.fields = FieldDecl[]
    while tokens[i] != CCB
        field, i = objectify(FieldDecl, tokens, i, cmts)
        push!(x.fields, field)
    end
    return x, i + 1
end

mutable struct PointerType <: AbstractType
    PointerType() = new()
    type::GoType
end

function transpile(io, x::PointerType, cmts)
    transpile(x, x.type, cmts)
    return
end

function objectify(::Type{PointerType}, tokens, i, cmts)
    x = PointerType()
    token = tokens[i]
    @_assert token == MUL
    x.type, i = objectify(GoType, tokens, i + 1, cmts)
    return x, i
end

mutable struct MapType <: AbstractType
    MapType() = new()
    key::GoType
    value::GoType
end

function transpile(io, x::MapType, cmts)
    print(io, "Dict{")
    transpile(io, x.key, cmts)
    print(io, ", ")
    transpile(io, x.value, cmts)
    print(io, "}")
    return
end

function objectify(::Type{MapType}, tokens, i, cmts)
    x = MapType()
    token = tokens[i]
    @_assert token == MAP
    i += 1
    token = tokens[i]
    @_assert token == OSB
    i += 1
    x.key, i = objectify(GoType, tokens, i, cmts)
    token = tokens[i]
    @_assert token == CSB
    i += 1
    x.value, i = objectify(GoType, tokens, i, cmts)
    return x, i
end

mutable struct ChannelType <: AbstractType
    ChannelType() = new()
    send::Bool
    receive::Bool
    type::GoType
end

function transpile(io, x::ChannelType, cmts)
    print(io, "Channel{")
    transpile(io, x.type, cmts)
    print(io, "}")
    if !x.send || !x.receive
        @warn "send/receive only channels not supported in Julia: $x"
    end
    return
end

function objectify(::Type{ChannelType}, tokens, i, cmts)
    x = ChannelType()
    token = tokens[i]
    if token == LTMINUS
        x.receive = true
        x.send = false
        i += 1
        token = tokens[i]
        @_assert token == CHAN
        i += 1
    else
        @_assert token == CHAN
        i += 1
        token = tokens[i]
        if token == LTMINUS
            x.receive = false
            x.send = true
            i += 1
        else
            x.receive = true
            x.send = true
        end
    end
    x.type, i = objectify(GoType, tokens, i, cmts)
    return x, i
end

mutable struct ParameterDecl
    ParameterDecl() = new()
    identifiers::Vector{Identifier}
    variadic::Bool
    type::GoType
end

function transpile(io, x::ParameterDecl, cmts)
    for (i, ident) in enumerate(x.identifiers)
        i > 1 && print(io, ", ")
        print(io, ident.value)
        print(io, "::")
        transpile(io, x.type, cmts)
    end
    if x.variadic
        print(io, "...")
    end
    return
end

mutable struct Parameters
    Parameters() = new()
    params::Vector{ParameterDecl}
end

function transpile(io, x::Parameters, cmts)
    print(io, "(")
    for (i, param) in enumerate(x.params)
        i > 1 && print
        transpile(io, param, cmts)
    end
    print(io, ")")
    return
end

function objectify(::Type{Parameters}, tokens, i, cmts)
    x = Parameters()
    x.params = ParameterDecl[]
    @_assert tokens[i] == OP
    i += 1
    if tokens[i] == CP
        return x, i + 1
    end
    param = ParameterDecl()
    if tokens[i] == DOTDOTDOT
        param.variadic = true
        i += 1
    else
        param.variadic = false
    end
    ident_or_type, i = objectify(GoType, tokens, i, cmts)
    if tokens[i] == CP
        i += 1
        param.type = ident_or_type
        push!(x.params, param)
    elseif !(ident_or_type isa Identifier)
        @_assert tokens[i] == COM
        # list of types; no identifiers
        i += 1
        param.type = ident_or_type
        push!(x.params, param)
        types, i = objectify(Vector{GoType}, tokens, i, cmts)
        for T in types
            p = ParameterDecl()
            p.variadic = false
            p.type = T
            push!(x.params, p)
        end
        if tokens[i] == DOTDOTDOT
            param = ParameterDecl()
            param.variadic = true
            param.type, i = objectify(GoType, tokens, i, cmts)
            push!(x.params, param)
        end
        @_assert tokens[i] == CP
        i += 1
    elseif tokens[i] != COM
        # ident_or_type is an identifier, next token is type
        param.identifiers = [ident_or_type]
        if tokens[i] == DOTDOTDOT
            param.variadic = true
            i += 1
        else
            param.variadic = false
        end
        param.type, i = objectify(GoType, tokens, i, cmts)
        push!(x.params, param)
        while tokens[i] != CP
            @_assert tokens[i] == COM
            i += 1
            param = ParameterDecl()
            param.identifiers, i = objectify(Vector{Identifier}, tokens, i, cmts)
            if tokens[i] == DOTDOTDOT
                param.variadic = true
                i += 1
            else
                param.variadic = false
            end
            param.type, i = objectify(GoType, tokens, i, cmts)
            push!(x.params, param)
        end
        i += 1
    else
        # ident_or_type isa an identifier or type
        # we're either consuming an IdentifierList (i, j int) or identifier-less TypeList (int, error)
        @_assert tokens[i] == COM
        i += 1
        idents_or_types, i = objectify(Vector{GoType}, tokens, i, cmts)
        if tokens[i] == CP
            # TypeList
            param.type = ident_or_type
            param.variadic = false
            push!(x.params, param)
            for T in idents_or_types
                p = ParameterDecl()
                p.variadic = false
                p.type = T
                push!(x.params, p)
            end
            i += 1
        elseif tokens[i] == DOTDOTDOT
            # TypeList
            param.type = ident_or_type
            param.variadic = false
            push!(x.params, param)
            for T in idents_or_types
                p = ParameterDecl()
                p.variadic = false
                p.type = T
                push!(x.params, p)
            end
            i += 1
            param = ParameterDecl()
            param.variadic = true
            param.type, i = objectify(GoType, tokens, i, cmts)
            @_assert tokens[i] == CP
            push!(x.params, param)
            i += 1
        else
            # IdentifierList
            param.identifiers = [ident_or_type]
            append!(param.identifiers, idents_or_types)
            param.variadic = false # assuming multiple identifiers not allowed w/ variadic arg
            param.type, i = objectify(GoType, tokens, i, cmts)
            push!(x.params, param)
            @_assert tokens[i] == CP || tokens[i] == COM
            while tokens[i] != CP
                param = ParameterDecl()
                param.identifiers, i = objectify(Vector{Identifier}, tokens, i + 1, cmts)
                if tokens[i] == DOTDOTDOT
                    param.variadic = true
                    i += 1
                else
                    param.variadic = false
                end
                param.type, i = objectify(GoType, tokens, i, cmts)
            end
            i += 1
        end
    end
    return x, i
end

mutable struct Signature
    Signature() = new()
    params::Parameters
    result::Union{Parameters, GoType}
end

function transpile(io, x::Signature, cmts)
    outputcomments(io, x, cmts)
    transpile(io, x.params, cmts)
    if isdefined(x, :result)
        if x.result isa Parameters
            print(io, "::Tuple{")
            transpile(io, x.result.params, cmts)
            print(io, "}")
        else
            print(io, "::")
            transpile(io, x.result, cmts)
        end
    end
    return
end

function objectify(::Type{Signature}, tokens, i, cmts)
    x = Signature()
    i = consumecmts!(x, tokens, i, cmts)
    x.params, i = objectify(Parameters, tokens, i, cmts)
    token = tokens[i]
    if token == OP
        x.result, i = objectify(Parameters, tokens, i, cmts)
    elseif token != OCB && token != SEMI && token != DOT && token != CP
        x.result, i = objectify(GoType, tokens, i, cmts)
    end
    return x, i
end

mutable struct FunctionType <: AbstractType
    FunctionType() = new()
    signature::Signature
end

function transpile(io, x::FunctionType, cmts)
    outputcomments(io, x, cmts)
    @warn "FunctionTypes not supported in Julia: $x"
    print(io, "Function{")
    transpile(io, x.signature, cmts)
    print(io, "}")
    return
end

function objectify(::Type{FunctionType}, tokens, i, cmts)
    x = FunctionType()
    token = tokens[i]
    @_assert token == FUNC
    i += 1
    x.signature, i = objectify(Signature, tokens, i, cmts)
    return x, i
end

mutable struct MethodSpec
    MethodSpec() = new()
    methodname::Identifier
    signature::Signature
end

function transpile(io, x::MethodSpec, cmts)
    outputcomments(io, x, cmts)
    transpile(io, x.methodname, cmts)
    transpile(io, x.signature, cmts)
    return
end

function objectify(::Type{MethodSpec}, tokens, i, cmts)
    x = MethodSpec()
    x.methodname = tokens[i]
    i += 1
    x.signature, i = objectify(Signature, tokens, i, cmts)
    return x, i
end

mutable struct InterfaceType <: AbstractType
    InterfaceType() = new()
    methodset::Vector{Union{MethodSpec, TypeName}}
end

function transpile(io, x::InterfaceType, cmts)
    outputcomments(io, x, cmts)
    @warn "InterfaceTypes not supported in Julia: $x"
    print(io, "interface")
    print(io, "{")
    for (i, method) in enumerate(x.methodset)
        if i > 1
            print(io, ", ")
        end
        transpile(io, method, cmts)
    end
    print(io, "}")
    return
end

function objectify(::Type{InterfaceType}, tokens, i, cmts)
    x = InterfaceType()
    @_assert tokens[i] == INTERFACE
    i += 1
    @_assert tokens[i] == OCB
    i += 1
    token = tokens[i]
    x.methodset = Union{MethodSpec, TypeName}[]
    while token != CCB
        starti = i
        i = consumecmts!(nothing, tokens, i, cmts)
        @assert tokens[i] isa Identifier
        token = tokens[i + 1]
        if token == OP
            # MethodSpec
            methodspec, i = objectify(MethodSpec, tokens, i, cmts)
            push!(x.methodset, methodspec)
        else
            # InterfaceTypeName
            name, i = objectify(TypeName, tokens, i, cmts)
            push!(x.methodset, name)
        end
        consumecmts!(x.methodset[end], tokens, starti, cmts)
        token = tokens[i]
        if token == SEMI
            i += 1
            token = tokens[i]
        end
    end
    return x, i + 1
end
