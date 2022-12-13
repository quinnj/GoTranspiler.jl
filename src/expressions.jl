# not a keyword, but special nonetheless
const MAKE = Identifier("make")
const NEW = Identifier("new")

binary_op(x)  = x == PIPEPIPE || x == ANDAND || rel_op(x) || add_op(x) || mul_op(x)
rel_op(x)     = x == EQEQ || x == NOTEQ || x == LT || x == LTEQ || x == GT || x == GTEQ
add_op(x)     = x == PLUS || x == MINUS || x == PIPE || x == POW
mul_op(x)     = x == MUL || x == DIV || x == MOD || x == LTLT || x == GTGT || x == AND || x == ANDPOW
unary_op(x)   = x == PLUS || x == MINUS || x == NOT || x == POW || x == MUL || x == AND || x == LTMINUS
assign_op(x) = x == EQ || x == PLUSEQ || x == MINUSEQ || x == PIPEEQ || x == POWEQ || x == MULEQ || x == DIVEQ || x == MODEQ || x == LTLTEQ || x == GTGTEQ || x == ANDEQ || x == ANDPOWEQ

ident(x::Expression) = x.expr.expr.expr

function objectify(::Type{Expression}, tokens, i, cmts, parens_required=false, within_parens=false)
    x = Expression()
    expr1, i = objectify(UnaryExpr, tokens, i, cmts, parens_required, within_parens)
    token = tokens[i]
    if binary_op(token)
        expr = BinaryExpr()
        # NOTE: this does a pure left-to-right BinaryExpr chain w/ multple binary_ops
        while true
            expr.op = token
            expr.expr1 = Expression()
            expr.expr1.expr = expr1
            i += 1
            expr.expr2 = Expression()
            expr.expr2.expr, i = objectify(UnaryExpr, tokens, i, cmts, parens_required, within_parens)
            expr1 = expr
            token = tokens[i]
            binary_op(token) || break
            expr = BinaryExpr()
        end
        # TODO: if we want to be more accurate, we could rebalance nested BinaryExpr
        # according to binary_op precedence; as it is, transpiling just needs to
        # transpile purely right-to-left
        #     Precedence    Operator
        #     5             *  /  %  <<  >>  &  &^
        #     4             +  -  |  ^
        #     3             ==  !=  <  <=  >  >=
        #     2             &&
        #     1             ||
        x.expr = expr
    else
        x.expr = expr1
    end
    return x, i
end

function objectify(::Type{Vector{Expression}}, tokens, i, cmts)
    x = Expression[]
    while true
        expr, i = objectify(Expression, tokens, i, cmts)
        push!(x, expr)
        if tokens[i] == COM
            i += 1
            i = consumelinecmt!(expr, tokens, i, cmts)
        else
            break
        end
    end
    return x, i
end

mutable struct Selector
    Selector() = new()
    identifier::Identifier
end

function transpile(io, x::Selector, cmts)
    print(io, ".")
    transpile(io, x.identifier, cmts)
    return
end

mutable struct Index
    Index() = new()
    expr::Expression
end

function transpile(io, x::Index, cmts)
    print(io, "[")
    transpile(io, x.expr, cmts)
    print(io, "]")
    return
end

mutable struct Slice
    Slice() = new()
    expr1::Expression
    expr2::Expression
    expr3::Union{Nothing, Expression}
end

function transpile(io, x::Slice, cmts)
    print(io, "[")
    transpile(io, x.expr1, cmts)
    print(io, ":")
    transpile(io, x.expr2, cmts)
    print(io, "]")
    return
end

mutable struct TypeAssertion
    TypeAssertion() = new()
    type::Union{GoType, Keyword} # keyword for TypeSwitchGuard x.(type)
end

function transpile(io, x::TypeAssertion, cmts)
    print(io, "::")
    transpile(io, x.type, cmts)
    return
end

mutable struct Arguments
    Arguments() = new()
    type::GoType # only for make(type, args...)
    args::Vector{Expression}
    splat::Bool
end

function transpile(io, x::Arguments, cmts)
    print(io, "(")
    if x.type !== nothing
        transpile(io, x.type, cmts)
        print(io, ", ")
    end
    for (i, arg) in enumerate(x.args)
        i > 1 && print(io, ", ")
        transpile(io, arg, cmts)
    end
    if x.splat
        print(io, "...")
    end
    print(io, ")")
    return
end

mutable struct MethodExpr
    MethodExpr() = new()
    type::GoType
    methodname::Identifier
end

function transpile(io, x::MethodExpr, cmts)
    transpile(io, x.methodname, cmts)
    print(io, "(")
    transpile(io, x.type, cmts)
    print(io, ", ")
    return
end

mutable struct Conversion
    Conversion() = new()
    type::GoType
    expr::Expression
end

function transpile(io, x::Conversion, cmts)
    print(io, "convert(")
    transpile(io, x.type, cmts)
    print(io, ", ")
    transpile(io, x.expr, cmts)
    print(io, ")")
    return
end

abstract type AbstractElement end

mutable struct LiteralValue
    LiteralValue() = new()
    elements::Vector{AbstractElement}
end

function transpile(io, x::LiteralValue, cmts)
    print(io, "[")
    for (i, elem) in enumerate(x.elements)
        i > 1 && print(io, ", ")
        transpile(io, elem, cmts)
    end
    print(io, "]")
    return
end

function objectify(::Type{LiteralValue}, tokens, i, cmts)
    x = LiteralValue()
    @_assert tokens[i] == OCB
    i += 1
    x.elements = AbstractElement[]
    token = tokens[i]
    while token != CCB
        if token == COM
            i += 1
            if tokens[i] == CCB
                break
            end
            i = consumelinecmt!(length(x.elements) > 0 ? x.elements[end] : nothing, tokens, i, cmts)
        end
        elem, i = objectify(KeyedElement, tokens, i, cmts)
        push!(x.elements, elem)
        token = tokens[i]
    end
    return x, i + 1
end

const LiteralType = Union{StructType, ArrayType, SliceType, DynamicArrayType, MapType, TypeName}

function objectify(::Type{LiteralType}, tokens, i, cmts)
    token = tokens[i]
    if token == STRUCT
        return objectify(StructType, tokens, i, cmts)
    elseif token == OSB
        return objectify(ArrayTypes, tokens, i, cmts)
    elseif token == MAP
        return objectify(MapType, tokens, i, cmts)
    else
        return objectify(TypeName, tokens, i, cmts)
    end
end

const Key = Union{Identifier, Expression, LiteralValue}
const Element = Union{Expression, LiteralValue}

mutable struct KeyedElement <: AbstractElement
    KeyedElement() = new()
    key::Union{Key, Nothing}
    element::Element
end

function transpile(io, x::KeyedElement, cmts)
    outputcomments(io, x, cmts)
    if isdefined(x, :key) && x.key !== nothing
        transpile(io, x.key, cmts)
        print(io, "=")
    end
    transpile(io, x.element, cmts)
    return
end

function objectify(::Type{KeyedElement}, tokens, i, cmts)
    x = KeyedElement()
    i = consumecmts!(x, tokens, i, cmts)
    token = tokens[i]
    if token isa Identifier && tokens[i + 1] == COL
        x.key = token
        i += 2
    elseif token == OCB
        lit, i = objectify(LiteralValue, tokens, i, cmts)
        token = tokens[i]
        if token == COL
            x.key = lit
            i += 1
            @goto value
        else
            x.element = lit
            @goto done
        end
    else
        expr, i = objectify(Expression, tokens, i, cmts)
        token = tokens[i]
        if token == COL
            x.key = expr
            i += 1
            @goto value
        else
            x.element = expr
            @goto done
        end
    end
@label value
    token = tokens[i]
    if token == OCB
        x.element, i = objectify(LiteralValue, tokens, i, cmts)
    else
        x.element, i = objectify(Expression, tokens, i, cmts)
    end
@label done
    return x, i
end

mutable struct CompositeLit
    CompositeLit() = new()
    type::LiteralType
    value::LiteralValue
end

function transpile(io, x::CompositeLit, cmts)
    transpile(io, x.type, cmts)
    transpile(io, x.value, cmts)
    return
end

# forward declare Statement & Block since FunctionLit needs them
abstract type Statement end

mutable struct Block <: Statement
    Block() = new()
    statements::Vector{Statement}
end

mutable struct FunctionLit
    FunctionLit() = new()
    signature::Signature
    body::Block
end

function transpile(io, x::FunctionLit, cmts)
    transpile(io, x.signature, cmts)
    print(io, " -> ")
    transpile(io, x.body, cmts)
    return
end

const BasicLit = Union{NumericLiteral, RuneLiteral, StringLiteral, RawStringLiteral}
const Literal = Union{BasicLit, CompositeLit, FunctionLit}
const OperandName = Union{Identifier, QualifiedIdent}
const Operand = Union{Literal, OperandName, Expression}

mutable struct PrimaryExpr
    PrimaryExpr() = new()
    expr::Union{
        Operand,
        Conversion,
        MethodExpr,
        PrimaryExpr
    }
    extra::Union{
        Selector,
        Index,
        Slice,
        TypeAssertion,
        Arguments,
    }
end

function transpile(io, x::PrimaryExpr, cmts)
    transpile(io, x.expr, cmts)
    isdefined(x, :extra) && transpile(io, x.extra, cmts)
    return
end

function primaryexpr(tokens, i, cmts, parens_required, within_parens)
    x = PrimaryExpr()
    token = tokens[i]
    if token == OP
        i += 1
        x.expr, i = objectify(Expression, tokens, i, cmts, parens_required, true)
        @_assert tokens[i] == CP
        i += 1
    elseif token isa Identifier
        if tokens[i + 1] == DOT && tokens[i + 2] isa Identifier
            type, i = objectify(TypeName, tokens, i, cmts)
        else
            type = token
            i += 1
        end
        if type isa TypeName && tokens[i] == OCB && (!parens_required || parens_required == within_parens)
            x.expr = CompositeLit()
            x.expr.type = type
            @goto CompositeLiteralValue
        else
            x.expr = type
        end
    elseif token isa BasicLit
        x.expr = token
        i += 1
    elseif token == FUNC
        # FunctionLit
        x.expr = FunctionLit()
        x.expr.signature, i = objectify(Signature, tokens, i + 1, cmts)
        x.expr.body, i = objectify(Block, tokens, i, cmts)
    else
        # CompositeLit or Conversion
        type, i = objectify(GoType, tokens, i, cmts)
        if tokens[i] == OP
            # Conversion
            i += 1
            x.expr = Conversion()
            x.expr.type = type
            x.expr.expr, i = objectify(Expression, tokens, i, cmts)
            @_assert tokens[i] == CP
            i += 1
        else
            x.expr = CompositeLit()
            x.expr.type = type
@label CompositeLiteralValue
            x.expr.value, i = objectify(LiteralValue, tokens, i, cmts)
        end
    end
    return x, i
end

function objectify(::Type{PrimaryExpr}, tokens, i, cmts, parens_required=false, within_parens=false)
    x, i = primaryexpr(tokens, i, cmts, parens_required, within_parens)
    while true
        token = tokens[i]
        if token == DOT
            # Selector or TypeAssertion
            if tokens[i + 1] == OP
                i += 2
                # TypeAssertion
                x.extra = TypeAssertion()
                if tokens[i] == TYPE
                    x.extra.type = TYPE
                    i += 1
                else
                    x.extra.type, i = objectify(GoType, tokens, i, cmts)
                end
                token = tokens[i]
                if token == CP
                    i += 1
                end
                if token == COM
                    i += 1
                end
            else
                i += 1
                # Selector
                x.extra = Selector()
                x.extra.identifier = tokens[i]
                i += 1
            end
        elseif token == OSB
            # Index or Slice
            i += 1
            if tokens[i] == COL
                i += 1
                if tokens[i] == CSB
                    x.extra = Slice() # 6
                else
                    x.extra = Slice()
                    expr, i = objectify(Expression, tokens, i, cmts)
                    if tokens[i] == CSB
                        x.extra.expr2 = expr # 2
                    else
                        @_assert tokens[i] == COL
                        i += 1
                        x.extra.expr2 = expr # 4
                        x.extra.expr3, i = objectify(Expression, tokens, i, cmts)
                    end
                end
            else
                expr, i = objectify(Expression, tokens, i, cmts)
                if tokens[i] == CSB
                    # Index
                    x.extra = Index()
                    x.extra.expr = expr
                else
                    @_assert tokens[i] == COL
                    # Slice
                    x.extra = Slice()
                    x.extra.expr1 = expr
                    i += 1
                    if tokens[i] == CSB
                        # 3
                    else
                        x.extra.expr2, i = objectify(Expression, tokens, i, cmts)
                        if tokens[i] == CSB
                            # 1
                        else
                            @_assert tokens[i] == COL
                            i += 1
                            x.extra.expr3, i = objectify(Expression, tokens, i, cmts)
                        end
                    end
                end
            end
            @_assert tokens[i] == CSB
            i += 1
        elseif token == OP
            # Arguments
            x.extra = Arguments()
            i += 1
            if x.expr == MAKE
                # make(T, ...) is special because you can pass a GoType as 1st arg
                x.extra.type, i = objectify(GoType, tokens, i, cmts)
                if tokens[i] == COM
                    i += 1
                end
            elseif x.expr == NEW
                # new(T) is special because you can pass a GoType as 1st arg
                x.extra.type, i = objectify(GoType, tokens, i, cmts)
            end
            if tokens[i] != CP
                x.extra.args, i = objectify(Vector{Expression}, tokens, i, cmts)
                token = tokens[i]
                if token == DOTDOTDOT
                    x.extra.splat = true
                    i += 1
                    token = tokens[i]
                else
                    x.extra.splat = false
                end
            end
            if tokens[i] == COM
                i += 1
            end
            @_assert tokens[i] == CP
            i += 1
        end
        token = tokens[i]
        if token == DOT || token == OSB || token == OP
            oldx = x
            x = PrimaryExpr()
            x.expr = oldx
        else
            break
        end
    end
    return x, i
end

mutable struct UnaryExpr <: AbstractUnaryExpr
    UnaryExpr() = new()
    unary_op::Operator
    expr::Union{PrimaryExpr, UnaryExpr}
end

function objectify(::Type{UnaryExpr}, tokens, i, cmts, parens_required, within_parens)
    x = UnaryExpr()
    token = tokens[i]
    if unary_op(token)
        x.unary_op = token
        i += 1
        x.expr, i = objectify(UnaryExpr, tokens, i, cmts, parens_required, within_parens)
    else
        x.expr, i = objectify(PrimaryExpr, tokens, i, cmts, parens_required, within_parens)
    end
    return x, i
end

function transpile(io, x::UnaryExpr, cmts)
    if isdefined(x, :unary_op)
        transpile(io, x.unary_op, cmts)
    end
    transpile(io, x.expr, cmts)
    return
end

mutable struct BinaryExpr <: AbstractBinaryExpr
    BinaryExpr() = new()
    op::Operator
    expr1::Expression
    expr2::Expression
end

function transpile(io, x::BinaryExpr, cmts)
    transpile(io, x.expr1, cmts)
    print(io, " ")
    transpile(io, x.op, cmts)
    print(io, " ")
    transpile(io, x.expr2, cmts)
    return
end