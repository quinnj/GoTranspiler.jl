macro _assert(cond)
    return esc(quote
        __cond__ = $cond
        if !__cond__
            @show $(__source__), tokens[max(1, i - 3):min(length(tokens), i + 3)]
            error("assertion error: " * $(string(cond)))
        end
    end)
end

abstract type Token end

abstract type Comment <: Token end

function consumecmts!(x, tokens, i, cmts)
    while i <= length(tokens)
        token = tokens[i]
        token isa Comment || break
        if x !== nothing
            push!(get!(cmts, x, Comment[]), token)
        end
        i += 1
    end
    return i
end

struct LineComment <: Comment
    value::String
end

function transpile(io, tok::LineComment, tokens, i)
    write(io, "#", tok.value)
    return i + 1
end

struct GeneralComment <: Comment
    value::String
end

function transpile(io, tok::GeneralComment, tokens, i)
    write(io, "#=", tok.value, "=#")
    return i + 1
end

struct Identifier <: Token
    value::String
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

# not a keyword, but special nonetheless
const MAKE = Identifier("make")

function transpile(io, tok::Keyword, tokens, i)

end

struct Operator <: Token
    value::String
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

binary_op(x)  = x == PIPEPIPE || x == ANDAND || rel_op(x) || add_op(x) || mul_op(x)
rel_op(x)     = x == EQEQ || x == NOTEQ || x == LT || x == LTEQ || x == GT || x == GTEQ
add_op(x)     = x == PLUS || x == MINUS || x == PIPE || x == POW
mul_op(x)     = x == MUL || x == DIV || x == MOD || x == LTLT || x == GTGT || x == AND || x == ANDPOW
unary_op(x)   = x == PLUS || x == MINUS || x == NOT || x == POW || x == MUL || x == AND || x == LTMINUS
assign_op(x) = x == EQ || x == PLUSEQ || x == MINUSEQ || x == PIPEEQ || x == POWEQ || x == MULEQ || x == DIVEQ || x == MODEQ || x == LTLTEQ || x == GTGTEQ || x == ANDEQ || x == ANDPOWEQ

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

struct NumericLiteral <: LiteralToken
    value::Number
end

struct RuneLiteral <: LiteralToken
    value::Char
end

struct StringLiteral <: LiteralToken
    value::String
end

# go objects
abstract type Statement end

mutable struct Block <: Statement
    Block() = new()
    statements::Vector{Statement}
end

function objectify(::Type{Block}, tokens, i, cmts)
    x = Block()
    token = tokens[i]
    @_assert token == OCB
    i += 1
    x.statements, i = objectify(Vector{Statement}, tokens, i, cmts)
    @_assert tokens[i] == CCB
    i += 1
    return x, i
end

function objectify(::Type{Vector{Statement}}, tokens, i, cmts)
    x = Statement[]
    while true
        stmt, i = objectify(Statement, tokens, i, cmts)
        push!(x, stmt)
        if tokens[i] == SEMI
            i += 1
        end
        tokens[i] == CCB && break
    end
    return x, i
end

function objectify(::Type{Statement}, tokens, i, cmts)
    starti = i
    i = consumecmts!(nothing, tokens, i, cmts)
    token = tokens[i]
    if token == VAR || token == TYPE || token == CONST
        x, i = objectify(Declaration, tokens, i, cmts)
    elseif token == GO
        # GoStmt
        i += 1
        x = GoStmt()
        x.expr, i = objectify(Expression, tokens, i, cmts)
    elseif token == RETURN
        # ReturnStmt
        i += 1
        x = ReturnStmt()
        if tokens[i] != SEMI
            x.exprs, i = objectify(Vector{Expression}, tokens, i, cmts)
        end
    elseif token == BREAK
        # BreakStmt
        i += 1
        x = BreakStmt()
        token = tokens[i]
        if token isa Identifier
            x.label = token
            i += 1
        end
    elseif token == CONTINUE
        # ContinueStmt
        i += 1
        x = ContinueStmt()
        token = tokens[i]
        if token isa Identifier
            x.label = token
            i += 1
        end
    elseif token == GOTO
        # GotoStmt
        i += 1
        x = GotoStmt()
        x.label = tokens[i]
        i += 1
    elseif token == FALLTHROUGH
        # FallthroughStmt
        i += 1
        x = FallthroughStmt()
    elseif token == IF
        # IfStmt
        x, i = objectify(IfStmt, tokens, i, cmts)
    elseif token == SWITCH
        # SwitchStmt
        i += 1
        init = switch = nothing
        if tokens[i] != OCB
            expr, i = objectify(SimpleStmt, tokens, i, cmts, true)
            if tokens[i] == SEMI
                init = expr
                switch, i = objectify(Expression, tokens, i + 1, cmts, true)
            else
                switch = expr.expr
            end
        end
        if switch isa Expression && switch.expr isa PrimaryExpr && isdefined(switch.expr.expr, :extra) && switch.expr.expr.extra isa TypeAssertion && switch.expr.expr.extra.type == TYPE
            # TODO: make sure to check above conditional?
            x = TypeSwitchStmt()
            x.cases = TypeCaseClause[]
        else
            x = ExprSwitchStmt()
            x.cases = ExprCaseClause[]
        end
        if init !== nothing
            x.init = init
        end
        if switch !== nothing
            x.switch = switch
        end
        @_assert tokens[i] == OCB
        i += 1
        token = tokens[i]
        while token != CCB
            if token == DEFAULT
                case = nothing
                i += 1
            else
                @_assert token == CASE
                if x isa ExprSwitchStmt
                    case, i = objectify(Vector{Expression}, tokens, i, cmts)
                else
                    case, i = objectify(Vector{GoType}, tokens, i, cmts)
                end
            end
            @_assert tokens[i] == COL
            i += 1
            stmts, i = objectify(Vector{Statement}, tokens, i, cmts)
            clause = x isa ExprSwitchStmt ? ExprCaseClause() : TypeCaseClause()
            clause.case = case
            clause.stmts = stmts
            push!(x.cases, clause)
            token = tokens[i]
        end
        i += 1
    elseif token == SELECT
        # SelectStmt
        i += 1
        x = SelectStmt()
        x.comms = CommClause[]
        @_assert tokens[i] == OCB
        i += 1
        token = tokens[i]
        while token != CCB
            clause = CommClause()
            if token == DEFAULT
                clause.case = nothing
                i += 1
            else
                @_assert token == CASE
                i += 1
                #TODO: this isn't quite restrictive enough, but then again, we're not
                # really worried about being restrictive since that's the go compiler's job :D
                clause.case, i = objectify(SimpleStmt, tokens, i, cmts)
            end
            @_assert tokens[i] == COL
            i += 1
            clause.stmts, i = objectify(Vector{Statement}, tokens, i, cmts)
            token = tokens[i]
        end
        i += 1
    elseif token == FOR
        # ForStmt
        i += 1
        x = ForStmt()
        if tokens[i] == OCB
            x.cond = nothing
        else
            forclause = rangeclause = false
            starti = i
            while tokens[i] != OCB
                if tokens[i] == SEMI
                    forclause = true
                    break
                elseif tokens[i] == RANGE
                    rangeclause = true
                    break
                end
                i += 1
            end
            i = starti
            if !forclause && !rangeclause
                # single Condition Expression
                x.cond, i = objectify(Expression, tokens, i, cmts, true)
            elseif forclause
                # ForClause
                x.cond = ForClause()
                if tokens[i] == SEMI
                    i += 1
                    if tokens[i] == SEMI
                        i += 1
                        if tokens[i] == OCB
                            x.cond = nothing
                        else
                            x.cond.post, i = objectify(SimpleStmt, tokens, i, cmts, true)
                        end
                    else
                        x.cond.cond, i = objectify(SimpleStmt, tokens, i, cmts, true)
                        if tokens[i] != OCB
                            x.cond.post, i = objectify(SimpleStmt, tokens, i, cmts, true)
                        end
                    end
                else
                    x.cond.init, i = objectify(SimpleStmt, tokens, i, cmts, true)
                    @_assert tokens[i] == SEMI
                    i += 1
                    if tokens[i] == SEMI
                        i += 1
                        if tokens[i] != OCB
                            x.cond.post, i = objectify(SimpleStmt, tokens, i, cmts, true)
                        end
                    else
                        x.cond.cond, i = objectify(SimpleStmt, tokens, i, cmts, true)
                        @_assert tokens[i] == SEMI
                        i += 1
                        if tokens[i] != OCB
                            x.cond.post, i = objectify(SimpleStmt, tokens, i, cmts, true)
                        end
                    end
                end
            else
                # RangeClause
                exprs, i = objectify(Vector{Expression}, tokens, i, cmts)
                @_assert tokens[i] == EQ || tokens[i] == COLEQ
                i += 1
                @_assert tokens[i] == RANGE
                i += 1
                x.cond = RangeClause()
                x.cond.vars = exprs
                x.cond.range, i = objectify(Expression, tokens, i, cmts, true)
            end
            @_assert tokens[i] == OCB
            i == 1
        end
        x.body, i = objectify(Block, tokens, i, cmts)
    elseif token == DEFER
        # DeferStmt
        i += 1
        x = DeferStmt()
        x.expr, i = objectify(Expression, tokens, i, cmts)
    elseif token == OCB
        # Block
        x, i = objectify(Block, tokens, i, cmts)
    elseif token isa Identifier && tokens[i + 1] == COL
        # LabeledStmt
        x = LabeledStmt()
        x.label = token
        i += 1
        x.statement, i = objectify(Statement, tokens, i, cmts)
    else
        # SimpleStmt
        x, i = objectify(SimpleStmt, tokens, i, cmts)
    end
    consumecmts!(x, tokens, starti, cmts)
    return x, i
end

mutable struct QualifiedIdent
    QualifiedIdent() = new()
    package::Identifier
    identifier::Identifier
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

abstract type AbstractExpression end
abstract type AbstractUnaryExpr <: AbstractExpression end
abstract type AbstractBinaryExpr <: AbstractExpression end

mutable struct Expression
    Expression() = new()
    expr::Union{AbstractUnaryExpr, AbstractBinaryExpr}
end

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
        else
            break
        end
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

mutable struct ArrayType <: AbstractType
    ArrayType() = new()
    len::Expression
    type::GoType
end

mutable struct SliceType <: AbstractType
    SliceType() = new()
    type::GoType
end

const ArrayTypes = Union{ArrayType, SliceType}

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

function objectify(::Type{FieldDecl}, tokens, i, cmts)
    x = FieldDecl()
    i = consumecmts!(x, tokens, i, cmts)
    x.names, i = objectify(Vector{Identifier}, tokens, i, cmts)
    x.type, i = objectify(GoType, tokens, i, cmts)
    if tokens[i] isa StringLiteral
        x.tag = token
        i += 1
    end
    return x, i
end

mutable struct StructType <: AbstractType
    StructType() = new()
    fields::Vector{FieldDecl}
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
        if tokens[i] == SEMI
            i += 1
        end
    end
    return x, i + 1
end

mutable struct PointerType <: AbstractType
    PointerType() = new()
    type::GoType
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
        else
            x.receive = true
            x.send = true
        end
        i += 1
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

mutable struct Parameters
    Parameters() = new()
    params::Vector{ParameterDecl}
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
                param.identifiers, i = objectify(Vector{Identifier}, tokens, i, cmts)
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

function objectify(::Type{Signature}, tokens, i, cmts)
    x = Signature()
    i = consumecmts!(x, tokens, i, cmts)
    x.params, i = objectify(Parameters, tokens, i, cmts)
    token = tokens[i]
    if token == OP
        x.result, i = objectify(Parameters, tokens, i, cmts)
    elseif token != OCB && token != SEMI && token != DOT
        x.result, i = objectify(GoType, tokens, i, cmts)
    end
    return x, i
end

mutable struct FunctionType <: AbstractType
    FunctionType() = new()
    signature::Signature
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

function objectify(::Type{InterfaceType}, tokens, i, cmts)
    x = InterfaceType()
    token = tokens[i]
    @_assert token == INTERFACE
    i += 1
    token = tokens[i]
    @_assert token == OCB
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

mutable struct Selector
    Selector() = new()
    identifier::Identifier
end

mutable struct Index
    Index() = new()
    expr::Expression
end

mutable struct Slice
    Slice() = new()
    expr1::Expression
    expr2::Expression
    expr3::Union{Nothing, Expression}
end

mutable struct TypeAssertion
    TypeAssertion() = new()
    type::Union{GoType, Keyword} # keyword for TypeSwitchGuard x.(type)
end

mutable struct Arguments
    Arguments() = new()
    type::GoType # only for make(type, args...)
    args::Vector{Expression}
    splat::Bool
end

mutable struct MethodExpr
    MethodExpr() = new()
    type::GoType
    methodname::Identifier
end

mutable struct Conversion
    Conversion() = new()
    type::GoType
    expr::Expression
end

abstract type AbstractElement end

mutable struct LiteralValue
    LiteralValue() = new()
    elements::Vector{AbstractElement}
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
        end
        elem, i = objectify(KeyedElement, tokens, i, cmts)
        push!(x.elements, elem)
        token = tokens[i]
    end
    return x, i + 1
end

# TODO: LiteralType also supports "[" "..." "]" ElementType
const LiteralType = Union{StructType, ArrayType, SliceType, MapType, TypeName}

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

function objectify(::Type{KeyedElement}, tokens, i, cmts)
    x = KeyedElement()
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

mutable struct FunctionLit
    FunctionLit() = new()
    signature::Signature
    body::Block
end

const BasicLit = Union{NumericLiteral, RuneLiteral, StringLiteral}
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

mutable struct BinaryExpr <: AbstractBinaryExpr
    BinaryExpr() = new()
    op::Operator
    expr1::Expression
    expr2::Expression
end

mutable struct ConstSpec
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
    if token != EQ
        # type
        x.type, i = objectify(GoType, tokens, i, cmts)
    end
    token = tokens[i]
    if token == EQ
        # assignments
        x.expressions, i = objectify(Vector{Expression}, tokens, i + 1, cmts)
    end
    return x, i
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
    return x, i
end

mutable struct AliasDecl
    AliasDecl() = new()
    name::Identifier
    type::GoType
end

mutable struct TypeDef
    TypeDef() = new()
    name::Identifier
    type::GoType
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
    return x, i
end

mutable struct VarSpec
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
    return x, i
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
            if tokens[i] == SEMI
                i += 1
            end
        end
        i += 1
    else
        varspec, i = objectify(VarSpec, tokens, i, cmts)
        push!(x.varspecs, varspec)
    end
    return x, i
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

mutable struct LabeledStmt <: Statement
    LabeledStmt() = new()
    label::Identifier
    statement::Statement
end

abstract type SimpleStmt <: Statement end

function objectify(::Type{SimpleStmt}, tokens, i, cmts, parens_required=false)
    token = tokens[i]
    # Expression
    starti = i
    expr, i = objectify(Expression, tokens, i, cmts, parens_required)
    token = tokens[i]
    if token == LTMINUS
        # SendStmt
        i += 1
        x = SendStmt()
        x.channel = expr
        x.expr, i = objectify(Expression, tokens, i, cmts, parens_required)
    elseif token == PLUSPLUS || token == MINUSMINUS
        # IncDecStmt
        x = IncDecStmt()
        x.expr = expr
        x.operator = token
        i += 1
    elseif token == COM
        i = starti
        exprs, i = objectify(Vector{Expression}, tokens, i, cmts)
        if tokens[i] == COLEQ
            x = ShortVarDecl()
            x.lhs = Identifier[ident(y) for y in exprs]
        else
            x = Assignment()
            x.lhs = exprs
            x.op = tokens[i]
        end
        i += 1
        x.rhs, i = objectify(Vector{Expression}, tokens, i, cmts)
    elseif assign_op(token)
        # Assignment
        x = Assignment()
        x.lhs = [expr]
        x.op = token
        x.rhs, i = objectify(Vector{Expression}, tokens, i + 1, cmts)
    elseif token == COLEQ
        # ShortVarDecl
        x = ShortVarDecl()
        x.lhs = [ident(expr)]
        x.rhs, i = objectify(Vector{Expression}, tokens, i + 1, cmts)
    else
        x = ExpressionStmt()
        x.expr = expr
    end
    return x, i
end

mutable struct ExpressionStmt <: SimpleStmt
    ExpressionStmt() = new()
    expr::Expression
end

mutable struct SendStmt <: SimpleStmt
    SendStmt() = new()
    channel::Expression
    expr::Expression
end

mutable struct IncDecStmt <: SimpleStmt
    IncDecStmt() = new()
    expr::Expression
    operator::Operator # "++" or "--"
end

mutable struct Assignment <: SimpleStmt
    Assignment() = new()
    lhs::Vector{Expression}
    op::Operator
    rhs::Vector{Expression}
end

mutable struct ShortVarDecl <: SimpleStmt
    ShortVarDecl() = new()
    lhs::Vector{Identifier}
    rhs::Vector{Expression}
end

mutable struct GoStmt <: Statement
    GoStmt() = new()
    expr::Expression
end

mutable struct ReturnStmt <: Statement
    ReturnStmt() = new()
    exprs::Vector{Expression}
end

mutable struct BreakStmt <: Statement
    BreakStmt() = new()
    label::Identifier
end

mutable struct ContinueStmt <: Statement
    ContinueStmt() = new()
    label::Identifier
end

mutable struct GotoStmt <: Statement
    GotoStmt() = new()
    label::Identifier
end

mutable struct FallthroughStmt <: Statement
    FallthroughStmt() = new()
end

mutable struct IfStmt <: Statement
    IfStmt() = new()
    stmt::SimpleStmt
    cond::Expression
    iftrue::Block
    ifelse::Union{IfStmt, Block}
end

function objectify(::Type{IfStmt}, tokens, i, cmts)
    @_assert tokens[i] == IF
    i += 1
    x = IfStmt()
    sstmt, i = objectify(SimpleStmt, tokens, i, cmts, true)
    if tokens[i] == SEMI
        x.stmt = sstmt
        x.cond, i = objectify(Expression, tokens, i + 1, cmts, true)
    else
        x.cond = sstmt.expr
    end
    x.iftrue, i = objectify(Block, tokens, i, cmts)
    if tokens[i] == ELSE
        i += 1
        if tokens[i] == IF
            x.ifelse, i = objectify(IfStmt, tokens, i, cmts)
        else
            x.ifelse, i = objectify(Block, tokens, i, cmts)
        end
    end
    return x, i
end

mutable struct ExprCaseClause
    ExprCaseClause() = new()
    case::Union{Vector{Expression}, Nothing}
    stmts::Vector{Statement}
end

abstract type SwitchStmt end

mutable struct ExprSwitchStmt <: SwitchStmt
    ExprSwitchStmt() = new()
    init::SimpleStmt
    switch::Expression
    cases::Vector{ExprCaseClause}
end

mutable struct TypeSwitchGuard
    TypeSwitchGuard() = new()
    var::Union{Identifier, Nothing}
    expr::PrimaryExpr
end

function objectify(::Type{Vector{GoType}}, tokens, i, cmts)
    type, i = objectify(GoType, tokens, i, cmts)
    x = GoType[type]
    while tokens[i] == COM
        type, i = objectify(GoType, tokens, i + 1, cmts)
        push!(x, type)
    end
    return x, i
end

mutable struct TypeCaseClause
    TypeCaseClause() = new()
    case::Union{Vector{GoType}, Nothing}
    stmts::Vector{Statement}
end

mutable struct TypeSwitchStmt <: SwitchStmt
    TypeSwitchStmt() = new()
    init::SimpleStmt
    switch::TypeSwitchGuard
    cases::Vector{TypeCaseClause}
end

mutable struct RecvStmt
    RecvStmt() = new()
    vars::Union{Vector{Expression}, Vector{Identifier}}
    recvexpr::Expression
end

mutable struct CommClause
    CommClause() = new()
    case::Union{SendStmt, RecvStmt, Nothing}
    stmts::Vector{Statement}
end

mutable struct SelectStmt <: Statement
    SelectStmt() = new()
    comms::Vector{CommClause}
end

mutable struct ForClause
    ForClause() = new()
    init::SimpleStmt
    cond::SimpleStmt
    post::SimpleStmt
end

mutable struct RangeClause
    RangeClause() = new()
    vars::Vector{Expression}
    range::Expression
end

mutable struct ForStmt <: Statement
    ForStmt() = new()
    cond::Union{Expression, ForClause, RangeClause, Nothing}
    body::Block
end

mutable struct DeferStmt <: Statement
    DeferStmt() = new()
    expr::Expression
end

mutable struct FunctionDecl
    FunctionDecl() = new()
    name::Identifier
    signature::Signature
    body::Block
end

mutable struct MethodDecl
    MethodDecl() = new()
    receiver::Parameters
    name::Identifier
    signature::Signature
    body::Block
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
    return x, i
end

function objectify(::Type{Vector{TopLevel}}, tokens, i, cmts)
    x = TopLevel[]
    while i <= length(tokens)
        tl, i = objectify(TopLevel, tokens, i, cmts)
        i > length(tokens) && break
        if tokens[i] == SEMI
            i += 1
        end
    end
    return x, i
end

mutable struct Import
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
    return x, i + 1
end

function objectify(::Type{Vector{Import}}, tokens, i, cmts)
    x = Import[]
    i = consumecmts!(x, tokens, i, cmts)
    token = tokens[i]
    @_assert token == IMPORT
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
            if token == SEMI
                i += 1
                token = tokens[i]
            end
        end
        i += 1
    else # single import
        imp, i = objectify(Import, tokens, i, cmts)
        push!(x, imp)
    end
    return x, i
end

mutable struct Package
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
    @_assert tokens[i] == SEMI
    i += 1
    x.toplevels, i = objectify(Vector{TopLevel}, tokens, i, cmts)
    return x
end