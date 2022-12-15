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

function transpile(io, x::Block, cmts)
    outputcomments(io, x, cmts)
    println(io, "begin")
    transpile(io, x.statements, cmts)
    println(io, "end")
    return
end

function objectify(::Type{Vector{Statement}}, tokens, i, cmts)
    x = Statement[]
    token = tokens[i]
    while true
        (token == CCB || token == CASE || token == DEFAULT) && break
        stmt, i = objectify(Statement, tokens, i, cmts)
        if stmt === nothing
            i = consumecmts!(x, tokens, i, cmts)
            break
        end
        push!(x, stmt)
        token = tokens[i]
    end
    return x, i
end

function transpile(io, x::Vector{Statement}, cmts)
    for stmt in x
        transpile(io, stmt, cmts)
        println(io)
    end
    return
end

function objectify(::Type{Statement}, tokens, i, cmts)
    starti = i
    i = consumecmts!(nothing, tokens, i, cmts)
    token = tokens[i]
    # quick check if we tried parsing another statement, consumed comments
    # but then got to the end of the StatementList
    if token == CCB || token == CASE || token == DEFAULT
        return nothing, starti
    end
    if token == VAR || token == TYPE || token == CONST
        x, i = objectify(Declaration, tokens, i, cmts)
    elseif token == GO
        x, i = objectify(GoStmt, tokens, i, cmts)
    elseif token == RETURN
        x, i = objectify(ReturnStmt, tokens, i, cmts)
    elseif token == BREAK
        x, i = objectify(BreakStmt, tokens, i, cmts)
    elseif token == CONTINUE
        x, i = objectify(ContinueStmt, tokens, i, cmts)
    elseif token == GOTO
        x, i = objectify(GotoStmt, tokens, i, cmts)
    elseif token == FALLTHROUGH
        # FallthroughStmt
        i += 1
        x = FallthroughStmt()
    elseif token == IF
        x, i = objectify(IfStmt, tokens, i, cmts)
    elseif token == SWITCH
        x, i = objectify(SwitchStmt, tokens, i, cmts)
    elseif token == SELECT
        x, i = objectify(SelectStmt, tokens, i, cmts)
    elseif token == FOR
        x, i = objectify(ForStmt, tokens, i, cmts)
    elseif token == DEFER
        x, i = objectify(DeferStmt, tokens, i, cmts)
    elseif token == OCB
        # Block
        x, i = objectify(Block, tokens, i, cmts)
    elseif token isa Identifier && tokens[i + 1] == COL
        x, i = objectify(LabeledStmt, tokens, i, cmts)
    else
        # SimpleStmt
        x, i = objectify(SimpleStmt, tokens, i, cmts)
    end
    consumecmts!(x, tokens, starti, cmts)
    i = consumelinecmt!(x, tokens, i, cmts)
    return x, i
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

function transpile(io, x::ExpressionStmt, cmts)
    outputcomments(io, x, cmts)
    transpile(io, x.expr, cmts)
    return
end

mutable struct SendStmt <: SimpleStmt
    SendStmt() = new()
    channel::Expression
    expr::Expression
end

function transpile(io, x::SendStmt, cmts)
    outputcomments(io, x, cmts)
    print(io, "put!(")
    transpile(io, x.channel, cmts)
    print(io, ", ")
    transpile(io, x.expr, cmts)
    print(io, ")")
    return
end

mutable struct IncDecStmt <: SimpleStmt
    IncDecStmt() = new()
    expr::Expression
    operator::Operator # "++" or "--"
end

function transpile(io, x::IncDecStmt, cmts)
    outputcomments(io, x, cmts)
    transpile(io, x.expr, cmts)
    if x.operator == PLUSPLUS
        print(io, " += 1")
    else
        print(io, " -= 1")
    end
    return
end

mutable struct Assignment <: SimpleStmt
    Assignment() = new()
    lhs::Vector{Expression}
    op::Operator
    rhs::Vector{Expression}
end

function transpile(io, x::Assignment, cmts)
    outputcomments(io, x, cmts)
    for (i, y) in enumerate(x.lhs)
        i > 1 && print(io, ", ")
        transpile(io, y, cmts)
    end
    print(io, " ")
    transpile(io, x.op, cmts)
    print(io, " ")
    for (i, y) in enumerate(x.rhs)
        i > 1 && print(io, ", ")
        transpile(io, y, cmts)
    end
    return
end

mutable struct ShortVarDecl <: SimpleStmt
    ShortVarDecl() = new()
    lhs::Vector{Identifier}
    rhs::Vector{Expression}
end

function transpile(io, x::ShortVarDecl, cmts)
    outputcomments(io, x, cmts)
    for (i, y) in enumerate(x.lhs)
        i > 1 && print(io, ", ")
        transpile(io, y, cmts)
    end
    print(io, " = ")
    for (i, y) in enumerate(x.rhs)
        i > 1 && print(io, ", ")
        transpile(io, y, cmts)
    end
    return
end

mutable struct GoStmt <: Statement
    GoStmt() = new()
    expr::Expression
end

function objectify(::Type{GoStmt}, tokens, i, cmts)
    @_assert tokens[i] == GO
    i += 1
    x = GoStmt()
    x.expr, i = objectify(Expression, tokens, i, cmts)
    return x, i
end

function transpile(io, x::GoStmt, cmts)
    outputcomments(io, x, cmts)
    println(io, "Threads.@spawn begin")
    transpile(io, x.expr, cmts)
    println(io)
    println(io, "end")
    return
end

mutable struct ReturnStmt <: Statement
    ReturnStmt() = new()
    exprs::Vector{Expression}
end

function objectify(::Type{ReturnStmt}, tokens, i, cmts)
    @_assert tokens[i] == RETURN
    i += 1
    x = ReturnStmt()
    if tokens[i] != SEMI && !(tokens[i] isa LineComment)
        x.exprs, i = objectify(Vector{Expression}, tokens, i, cmts)
    end
    return x, i
end

function transpile(io, x::ReturnStmt, cmts)
    outputcomments(io, x, cmts)
    print(io, "return")
    if isdefined(x, :exprs) && !isempty(x.exprs)
        print(io, " ")
        len = length(x.exprs)
        for (i, expr) in enumerate(x.exprs)
            transpile(io, expr, cmts)
            i == len || print(io, ", ")
        end
    end
    print(io)
    return
end

mutable struct BreakStmt <: Statement
    BreakStmt() = new()
    label::Identifier
end

function objectify(::Type{BreakStmt}, tokens, i, cmts)
    @_assert tokens[i] == BREAK
    i += 1
    x = BreakStmt()
    if tokens[i] isa Identifier
        x.label = tokens[i]
        i += 1
    end
    return x, i
end

function transpile(io, x::BreakStmt, cmts)
    outputcomments(io, x, cmts)
    if isdefined(x, :label) && x.label !== nothing
        print(io, "@goto ", x.label)
    else
        print(io, "break")
    end
    return
end

mutable struct ContinueStmt <: Statement
    ContinueStmt() = new()
    label::Identifier
end

function objectify(::Type{ContinueStmt}, tokens, i, cmts)
    @_assert tokens[i] == CONTINUE
    i += 1
    x = ContinueStmt()
    if tokens[i] isa Identifier
        x.label = tokens[i]
        i += 1
    end
    return x, i
end

function transpile(io, x::ContinueStmt, cmts)
    outputcomments(io, x, cmts)
    if isdefined(x, :label) && x.label !== nothing
        print(io, "@goto ", x.label)
    else
        print(io, "continue")
    end
    return
end

mutable struct GotoStmt <: Statement
    GotoStmt() = new()
    label::Identifier
end

function objectify(::Type{GotoStmt}, tokens, i, cmts)
    @_assert tokens[i] == GOTO
    i += 1
    x = GotoStmt()
    x.label = tokens[i]
    i += 1
    return x, i
end

function transpile(io, x::GotoStmt, cmts)
    outputcomments(io, x, cmts)
    print(io, "@goto ")
    transpile(io, x.label, cmts)
    return
end

mutable struct FallthroughStmt <: Statement
    FallthroughStmt() = new()
end

function transpile(io, x::FallthroughStmt, cmts)
    outputcomments(io, x, cmts)
    @warn "fallthrough not supported in Julia; use an appropriate @goto instead"
    print(io, "fallthrough")
    return
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

function transpile(io, x::IfStmt, cmts, printend=true)
    outputcomments(io, x, cmts)
    print(io, "if ")
    if isdefined(x, :stmt)
        print(io, "(")
        transpile(io, x.stmt, cmts)
        print(io, "; ")
    end
    transpile(io, x.cond, cmts)
    if isdefined(x, :stmt)
        print(io, ")")
    end
    println(io)
    # TODO: indent
    transpile(io, x.iftrue.statements, cmts)
    if isdefined(x, :ifelse)
        if x.ifelse isa IfStmt
            print(io, "else")
            # TODO: indent
            transpile(io, x.ifelse, cmts, false)
        elseif x.ifelse isa Block && !isempty(x.ifelse.statements)
            println(io, "else")
            # TODO: indent
            transpile(io, x.ifelse.statements, cmts)
        end
    end
    printend && println(io, "end")
    return
end

mutable struct ExprCaseClause <: AbstractGoType
    ExprCaseClause() = new()
    case::Union{Vector{Expression}, Nothing}
    stmts::Vector{Statement}
end

abstract type SwitchStmt <: Statement end

mutable struct ExprSwitchStmt <: SwitchStmt
    ExprSwitchStmt() = new()
    init::SimpleStmt
    switch::Expression
    cases::Vector{ExprCaseClause}
end

function transpile(io, x::ExprSwitchStmt, cmts)
    outputcomments(io, x, cmts)
    isdefined(x, :init) && transpile(io, x.init, cmts)
    first = true
    for case in x.cases
        if first
            print(io, "if ")
            first = false
        else
            if case.case === nothing
                println(io, "else")
            else
                print(io, "elseif ")
            end
        end
        if case.case !== nothing
            if isdefined(x, :switch)
                # switch x { ... }
                transpile(io, x.switch, cmts)
                print(io, " == ")
            end
            if length(case.case) > 1
                print(io, "(")
            end
            for (i, c) in enumerate(case.case)
                i > 1 && print(io, "; ")
                transpile(io, c, cmts)
            end
            if length(case.case) > 1
                print(io, ")")
            end
            println(io)
        end
        transpile(io, case.stmts, cmts)
    end
    println(io, "end")
    return
end

mutable struct TypeSwitchGuard <: AbstractGoType
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

mutable struct TypeCaseClause <: AbstractGoType
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

function objectify(::Type{SwitchStmt}, tokens, i, cmts)
    @_assert tokens[i] == SWITCH
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
        starti = i
        i = consumecmts!(nothing, tokens, i, cmts)
        token = tokens[i]
        if token == DEFAULT
            case = nothing
            i += 1
        else
            @_assert token == CASE
            i += 1
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
        consumecmts!(clause, tokens, starti, cmts)
        push!(x.cases, clause)
        token = tokens[i]
    end
    i += 1
    return x, i
end

mutable struct RecvStmt <: AbstractGoType
    RecvStmt() = new()
    vars::Union{Vector{Expression}, Vector{Identifier}}
    recvexpr::Expression
end

function transpile(io, x::RecvStmt, cmts)
    outputcomments(io, x, cmts)
    for (i, var) in enumerate(x.vars)
        i > 1 && print(io, ", ")
        transpile(io, var, cmts)
    end
    print(io, " = ")
    transpile(io, x.recvexpr, cmts)
    return
end

mutable struct CommClause <: AbstractGoType
    CommClause() = new()
    case::Union{SendStmt, RecvStmt, Nothing}
    stmts::Vector{Statement}
end

function transpile(io, x::CommClause, cmts)
    outputcomments(io, x, cmts)
    if x.case === nothing
        println(io, "@default begin")
    elseif x.case isa SendStmt
        println(io, "@send begin")
        transpile(io, x.case, cmts)
        println(io)
    elseif x.case isa RecvStmt
        println(io, "@recv begin")
        transpile(io, x.case, cmts)
        println(io)
    end
    transpile(io, x.stmts, cmts)
    println(io, "end")
    return
end

mutable struct SelectStmt <: Statement
    SelectStmt() = new()
    comms::Vector{CommClause}
end

function transpile(io, x::SelectStmt, cmts)
    outputcomments(io, x, cmts)
    println(io, "@select begin")
    for comm in x.comms
        transpile(io, comm, cmts)
    end
    println(io, "end")
    return
end

function objectify(::Type{SelectStmt}, tokens, i, cmts)
    @_assert tokens[i] == SELECT
    i += 1
    x = SelectStmt()
    x.comms = CommClause[]
    @_assert tokens[i] == OCB
    i += 1
    token = tokens[i]
    while token != CCB
        starti = i
        i = consumecmts!(nothing, tokens, i, cmts)
        token = tokens[i]
        if token == CASE
            i += 1
            case, i = objectify(SimpleStmt, tokens, i, cmts)
        elseif token == DEFAULT
            case = nothing
            i += 1
        else
            case, i = objectify(SimpleStmt, tokens, i, cmts)
        end
        @_assert tokens[i] == COL
        i += 1
        stmts, i = objectify(Vector{Statement}, tokens, i, cmts)
        clause = CommClause()
        clause.case = case
        clause.stmts = stmts
        consumecmts!(clause, tokens, starti, cmts)
        push!(x.comms, clause)
        token = tokens[i]
    end
    i += 1
    return x, i
end

mutable struct ForClause <: AbstractGoType
    ForClause() = new()
    init::SimpleStmt
    cond::SimpleStmt
    post::SimpleStmt
end

mutable struct RangeClause <: AbstractGoType
    RangeClause() = new()
    vars::Vector{Expression}
    range::Expression
end

mutable struct ForStmt <: Statement
    ForStmt() = new()
    cond::Union{Expression, ForClause, RangeClause, Nothing}
    body::Block
end

function objectify(::Type{ForStmt}, tokens, i, cmts)
    @_assert tokens[i] == FOR
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
                        @_assert tokens[i] == SEMI
                        i += 1
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
    return x, i
end

function transpile(io, x::ForStmt, cmts)
    if x.cond === nothing
        println(io, "while true")
        transpile(io, x.body.statements, cmts)
    elseif x.cond isa Expression
        print(io, "while ")
        transpile(io, x.cond, cmts)
        println(io)
        transpile(io, x.body.statements, cmts)
    elseif x.cond isa RangeClause
        print(io, "for ")
        print(io, "(")
        len = length(x.cond.vars)
        for (i, var) in enumerate(x.cond.vars)
            transpile(io, var, cmts)
            i == len || print(io, ", ")
        end
        print(io, ") in ")
        transpile(io, x.cond.range, cmts)
        println(io)
        transpile(io, x.body.statements, cmts)
    else
        @assert x.cond isa ForClause
        if isdefined(x.cond, :init)
            transpile(io, x.cond.init, cmts)
            println(io)
        end
        print(io, "while ")
        if isdefined(x.cond, :cond)
            transpile(io, x.cond.cond, cmts)
        else
            print(io, "true")
        end
        println(io)
        transpile(io, x.body.statements, cmts)
        if isdefined(x.cond, :post)
            transpile(io, x.cond.post, cmts)
            println(io)
        end
    end
    println(io, "end")
    return
end

mutable struct DeferStmt <: Statement
    DeferStmt() = new()
    expr::Expression
end

function objectify(::Type{DeferStmt}, tokens, i, cmts)
    @_assert tokens[i] == DEFER
    i += 1
    x = DeferStmt()
    x.expr, i = objectify(Expression, tokens, i, cmts)
    return x, i
end

function transpile(io, x::DeferStmt, cmts)
    outputcomments(io, x, cmts)
    @warn "DeferStmt not supported in Julia: $x"
    print(io, "@defer ")
    transpile(io, x.expr, cmts)
    print(io)
    return
end

mutable struct LabeledStmt <: Statement
    LabeledStmt() = new()
    label::Identifier
    statement::Statement
end

function objectify(::Type{LabeledStmt}, tokens, i, cmts)
    x = LabeledStmt()
    x.label = tokens[i]
    i += 1
    @_assert tokens[i] == COL
    i += 1
    x.statement, i = objectify(Statement, tokens, i, cmts)
    return x, i
end

function transpile(io, x::LabeledStmt, cmts)
    outputcomments(io, x, cmts)
    print(io, "@label ")
    transpile(io, x.label, cmts)
    println(io)
    transpile(io, x.statement, cmts)
    return
end