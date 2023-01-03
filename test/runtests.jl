using GoTranspiler, Test

dir = "/Users/quinnj/go/src/compress/gzip"

for file in readdir(dir; join=true)
    endswith(file, ".go") || continue
    @show file
    GoTranspiler.transpile(file, nothing)
end


file = "/Users/quinnj/go/src/compress/flate/deflate.go"
t = GoTranspiler.transpile(file, nothing);
