using GoTranspiler, Test

dir = "/Users/quinnj/go/src/compress/flate"

for file in readdir(dir; join=true)
    endswith(file, ".go") || continue
    @show file
    pkg, cmts = GoTranspiler.objectify(file)
end


file = "/Users/quinnj/go/src/compress/flate/example_test.go"
t = GoTranspiler.transpile(file)
