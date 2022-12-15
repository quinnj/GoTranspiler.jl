module GoTranspiler

import Base: ==
using JuliaFormatter

abstract type AbstractGoType end

include("tokens.jl")
include("types.jl")
include("expressions.jl")
include("statements.jl")
include("toplevel.jl")

str(bytes, pos, len) = unsafe_string(pointer(bytes, pos), len)

function transpile(dir, outdir)
    isdir(dir) || throw(ArgumentError("must pass valid directory name; to transpile single file, call `transpilefile(file)`"))
    for (root, dirs, files) in walkdir(dir)
        @sync begin
            for dir in dirs
                suboutdir = joinpath(outdir, dir)
                @async transpile(joinpath(root, dir), suboutdir)
            end
            for file in files
                endswith(file, ".go") || continue
                Threads.@spawn transpilefile(joinpath(root, file), outdir)
            end
        end
    end
    return
end

function transpilefile(file, outdir)
    pkg, cmts = objectify(file)
    open(joinpath(outdir, basename(file) * ".jl"), "w+") do io
        transpile(io, pkg, cmts)
    end
end

function objectify(file::String)
    tokens = tokenize(file)
    return objectify(tokens)
end

function objectify(tokens)
    cmts = Dict{Any, Vector{Comment}}()
    return objectify(Package, tokens, 1, cmts), cmts
end

struct Transpiled
    code::String
    pkg::Package
    cmts::Dict{Any, Vector{Comment}}
end

function transpile(file::String, out=IOBuffer())
    pkg, cmts = objectify(file)
    if out === nothing
        out = splitext(file)[1] * ".jl"
    end
    io = out isa String ? open(out, "w+") : out
    transpile(io, pkg, cmts)
    out isa String && close(io)
    code = out isa String ? out : String(take!(io))
    try
        if isfile(out)
            format_file(code)
        else
            format_text(code)
        end
    catch e
        @error "error formatting" exception=(e, catch_backtrace())
    end
    return Transpiled(code, pkg, cmts)
end

end # module
