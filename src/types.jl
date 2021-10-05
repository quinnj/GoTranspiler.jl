abstract type Token end

abstract type CommentToken <: Token end

struct LineComment <: CommentToken
    value::String
end

struct GeneralComment <: CommentToken
    value::String
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

struct NumericLiteral <: Token
    value::String
end

struct RuneLiteral <: Token
    value::Char
end

struct StringLiteral <: Token
    value::String
end

# go objects
abstract type Statement end

struct Block
    statements::Vector{Statement}
end

struct QualifiedIdent
    package::Identifier
    identifier::Identifier
end

const TypeName = Union{Identifier, QualifiedIdent}

abstract type AbstractType end

# const TypeLit = Union{ArrayType, StructType, PointerType, FunctionType, InterfaceType, SliceType, MapType, ChannelType}
# we use AbstractType instead of TypeLit to break the cyclic dependency
const GoType = Union{TypeName, AbstractType}

struct ArrayType <: AbstractType
    len::Expression
    type::GoType
end

struct SliceType <: AbstractType
    type::GoType
end

struct EmbeddedField
    type::GoType
end

const Tag = String

struct FieldDecl
    field::Union{Pair{Vector{Identifier}, AbstractType}, EmbeddedField}
    tag::Union{Nothing, Tag}
end

struct StructType <: AbstractType
    fields::Vector{FieldDecl}
end

struct PointerType <: AbstractType
    type::GoType
end

struct MapType <: AbstractType
    key::GoType
    value::GoType
end

struct ChannelType <: AbstractType
    send::Bool
    receive::Bool
    type::GoType
end

struct ParameterDecl
    identifiers::Vector{Identifier}
    variadic::Bool
    type::GoType
end

struct Parameters
    params::Vector{ParameterDecl}
end

struct Result
    result::Union{Parameters, AbstractType}
end

struct Signature
    params::Parameters
    result::Result
end

struct FunctionType <: AbstractType
    signature::Signature
end

struct MethodSpec
    methodname::Identifier
    signature::Signature
end

struct InterfaceType <: AbstractType
    methodset::Vector{Union{InterfaceType, MethodSpec}}
end

abstract type AbstractExpression end
abstract type AbstractUnaryExpr <: AbstractExpression end
abstract type AbstractBinaryExpr <: AbstractExpression end

struct Expression
    expr::Union{AbstractUnaryExpr, AbstractBinaryExpr}
end

struct Selector
    identifier::Identifier
end

struct Index
    expr::Expression
end

struct Slice
    expr1::Expression
    expr2::Expression
    expr3::Union{Nothing, Expression}
end

struct TypeAssertion
    type::GoType
end

struct Arguments
    args::Union{Vector{Expression}, Tuple{GoType, Vector{Expression}}}
    splat::Bool
end

struct MethodExpr
    type::GoType
    methodname::Identifier
end

struct Conversion
    type::GoType
    expr::Expression
end

abstract type AbstractElement end

struct LiteralValue
    elements::Vector{AbstractElement}
end

# TODO: LiteralType also supports "[" "..." "]" ElementType
const LiteralType = Union{StructType, ArrayType, SliceType, MapType, TypeName}

const Key = Union{Identifier, Expression, LiteralValue}
const Element = Union{Expression, LiteralValue}

struct KeyedElement <: AbstractElement
    key::Union{Key, Nothing}
    element::Element
end

struct CompositeLit
    type::LiteralType
    value::LiteralValue
end

const BasicLit = Union{NumericLiteral, RuneLiteral, StringLiteral}
const Literal = Union{BasicLit, CompositeLit, FunctionLit}
const OperandName = Union{Identifier, QualifiedIdent}
const Operand = Union{Literal, OperandName, Expression}

struct PrimaryExpr
    expr::Union{
        Operand,
        Conversion,
        MethodExpr,
        Tuple{PrimaryExpr, Selector},
        Tuple{PrimaryExpr, Index},
        Tuple{PrimaryExpr, Slice},
        Tuple{PrimaryExpr, TypeAssertion},
        Tuple{PrimaryExpr, Arguments},
    }
end

struct UnaryExpr <: AbstractUnaryExpr
    expr::Union{PrimaryExpr, Tuple{Operator, UnaryExpr}}
end

struct BinaryExpr <: AbstractBinaryExpr
    op::Operator
    expr1::Expression
    expr2::Expression
end

struct FunctionDecl
    name::Identifier
    signature::Signature
    body::Block
end

struct MethodDecl
    receiver::Parameters
    name::Identifier
    signature::Signature
    body::Block
end

struct ConstSpec
    identifiers::Vector{Identifier}
    type::Union{Nothing, GoType}
    expressions::Vector{Expression}
end

struct ConstDecl
    consts::Vector{ConstSpec}
end

struct AliasDecl
    name::Identifier
    type::GoType
end

struct TypeDef
    name::Identifier
    type::GoType
end

const TypeSpec = Union{AliasDecl, TypeDef}

struct TypeDecl
    typespecs::Vector{TypeSpec}
end

struct VarSpec
    identifiers::Vector{Identifier}
    type::Union{Nothing, GoType}
    expressions::Vector{Expression}
end

struct VarDecl
    varspecs::Vector{VarSpec}
end

struct ShortVarDecl
    identifiers::Vector{Identifier}
    expressions::Vector{Expression}
end

struct Declaration <: Statement
    decl::Union{ConstDecl, TypeDecl, VarDecl}
end

struct LabeledStmt <: Statement
    label::Identifier
    statement::Statement
end

const TopLevel = Union{Delcaration, FunctionDecl, MethodDecl}

struct Import
    package::Identifier
    path::String
end

struct Package
    name::Identifier
    imports::Vector{Import}
    toplevels::Vector{TopLevel}
end
