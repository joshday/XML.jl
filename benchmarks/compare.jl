#= Compare current dev XML.jl against the last released version.

Usage:
    julia benchmarks/compare.jl [tag]

`tag` defaults to the latest git tag (e.g. v0.3.8).

This script:
1. Runs benchmarks using the current (dev) code
2. Checks out the release tag into a temp worktree
3. Runs the same benchmarks against that version
4. Prints a side-by-side comparison
=#

using BenchmarkTools, Serialization

BenchmarkTools.DEFAULT_PARAMETERS.seconds = 5
BenchmarkTools.DEFAULT_PARAMETERS.samples = 10000

const ROOT = dirname(@__DIR__)

const RELEASE_TAG = if length(ARGS) >= 1
    ARGS[1]
else
    tags = readlines(`git -C $ROOT tag --sort=version:refname`)
    filter!(t -> startswith(t, "v"), tags)
    last(tags)
end

const SMALL_FILE = joinpath(ROOT, "test", "data", "books.xml")
const SMALL_XML = read(SMALL_FILE, String)

# Generate medium file if needed
include(joinpath(ROOT, "benchmarks", "XMarkGenerator.jl"))
using .XMarkGenerator
const MEDIUM_FILE = joinpath(ROOT, "benchmarks", "data", "xmark.xml")
if !isfile(MEDIUM_FILE)
    mkpath(dirname(MEDIUM_FILE))
    @info "Generating XMark benchmark XML..."
    generate_xmark(MEDIUM_FILE, 1.0)
end
const MEDIUM_XML = read(MEDIUM_FILE, String)

#-----------------------------------------------------------------------------# Helpers
function _collect_tags!(out, node)
    for c in XML.children(node)
        if XML.nodetype(c) === XML.Element
            push!(out, XML.tag(c))
            _collect_tags!(out, c)
        end
    end
end

function bench_collect_tags(node)
    out = String[]
    _collect_tags!(out, node)
    out
end

#-----------------------------------------------------------------------------# Run dev benchmarks
println("="^60)
println("  XML.jl Benchmark Comparison")
println("  Current (dev) vs $RELEASE_TAG")
println("="^60)
println()

print("Running dev benchmarks...")
flush(stdout)

using XML

dev_results = Dict{String, BenchmarkTools.Trial}()

dev_small = parse(SMALL_XML, Node)
dev_medium = parse(MEDIUM_XML, Node)

dev_results["Parse (small)"] = @benchmark parse($SMALL_XML, Node)
dev_results["Parse (small, SS)"] = @benchmark parse($SMALL_XML, Node{SubString{String}})
dev_results["Parse (medium)"] = @benchmark parse($MEDIUM_XML, Node)
dev_results["Parse (medium, SS)"] = @benchmark parse($MEDIUM_XML, Node{SubString{String}})
dev_results["Write (small)"] = @benchmark XML.write($dev_small)
dev_results["Write (medium)"] = @benchmark XML.write($dev_medium)
dev_results["Read file (medium)"] = @benchmark read($MEDIUM_FILE, Node)
dev_results["Collect tags (small)"] = @benchmark bench_collect_tags($dev_small)
dev_results["Collect tags (medium)"] = @benchmark bench_collect_tags($dev_medium)

println(" done")

#-----------------------------------------------------------------------------# Run release benchmarks via temp worktree + separate process
print("Setting up $RELEASE_TAG worktree...")
flush(stdout)

worktree_dir = mktempdir()
run(pipeline(`git -C $ROOT worktree add $worktree_dir $RELEASE_TAG`, stdout=devnull, stderr=devnull))
println(" done")

release_results_file = joinpath(worktree_dir, "_results.jls")

release_script = joinpath(worktree_dir, "_bench.jl")
write(release_script, """
using Pkg
Pkg.activate(; temp=true)
Pkg.develop(path=$(repr(worktree_dir)))
Pkg.add("BenchmarkTools")
Pkg.add("Serialization")

using BenchmarkTools, Serialization, XML

BenchmarkTools.DEFAULT_PARAMETERS.seconds = 5
BenchmarkTools.DEFAULT_PARAMETERS.samples = 10000

small_xml = read($(repr(SMALL_FILE)), String)
medium_xml = read($(repr(MEDIUM_FILE)), String)
results = Dict{String, BenchmarkTools.Trial}()

results["Parse (small)"] = @benchmark parse(\$small_xml, Node)

try
    SSNode = Node{SubString{String}}
    results["Parse (small, SS)"] = @benchmark parse(\$small_xml, SSNode)
    results["Parse (medium, SS)"] = @benchmark parse(\$medium_xml, SSNode)
catch
end

results["Parse (medium)"] = @benchmark parse(\$medium_xml, Node)

small_node = parse(small_xml, Node)
medium_node = parse(medium_xml, Node)
results["Write (small)"] = @benchmark XML.write(\$small_node)
results["Write (medium)"] = @benchmark XML.write(\$medium_node)
results["Read file (medium)"] = @benchmark read($(repr(MEDIUM_FILE)), Node)

function _collect_tags!(out, node)
    for c in XML.children(node)
        if XML.nodetype(c) === XML.Element
            push!(out, XML.tag(c))
            _collect_tags!(out, c)
        end
    end
end
function bench_collect_tags(node)
    out = String[]
    _collect_tags!(out, node)
    out
end
results["Collect tags (small)"] = @benchmark bench_collect_tags(\$small_node)
results["Collect tags (medium)"] = @benchmark bench_collect_tags(\$medium_node)

serialize($(repr(release_results_file)), results)
""")

print("Running $RELEASE_TAG benchmarks...")
flush(stdout)
run(pipeline(`julia $release_script`, stdout=devnull, stderr=devnull))
release_results = deserialize(release_results_file)
println(" done")

# Cleanup worktree
run(pipeline(`git -C $ROOT worktree remove --force $worktree_dir`, stdout=devnull, stderr=devnull))

#-----------------------------------------------------------------------------# Compare
println()
println("-"^60)

all_keys = [
    "Parse (small)", "Parse (small, SS)",
    "Parse (medium)", "Parse (medium, SS)",
    "Write (small)", "Write (medium)",
    "Read file (medium)",
    "Collect tags (small)", "Collect tags (medium)",
]

for name in all_keys
    has_dev = haskey(dev_results, name)
    has_rel = haskey(release_results, name)
    has_dev || has_rel || continue

    println()
    println("  $name")

    if has_dev && has_rel
        dev_med = median(dev_results[name]).time / 1e6
        rel_med = median(release_results[name]).time / 1e6
        change = (dev_med / rel_med - 1) * 100

        pct = abs(round(change, digits=1))
        indicator = if change < -5
            "$(pct)% faster"
        elseif change > 5
            "$(pct)% slower"
        else
            "~same"
        end

        lpad_tag = lpad(RELEASE_TAG, 12)
        lpad_dev = lpad("dev", 12)
        println("    $lpad_tag  $(lpad(string(round(rel_med, digits=4), " ms"), 12))")
        println("    $lpad_dev  $(lpad(string(round(dev_med, digits=4), " ms"), 12))  ($indicator)")
    elseif has_dev
        dev_med = median(dev_results[name]).time / 1e6
        lpad_tag = lpad(RELEASE_TAG, 12)
        lpad_dev = lpad("dev", 12)
        println("    $lpad_tag  $(lpad("n/a", 12))")
        println("    $lpad_dev  $(lpad(string(round(dev_med, digits=4), " ms"), 12))")
    end
end

println()
println("="^60)
