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
