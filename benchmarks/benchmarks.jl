using XML
using XML: Element, nodetype, tag, children
using EzXML: EzXML
using XMLDict: XMLDict
using LightXML: LightXML
using BenchmarkTools
using DataFrames
using UnicodePlots

include("XMarkGenerator.jl")
using .XMarkGenerator

BenchmarkTools.DEFAULT_PARAMETERS.seconds = 10
BenchmarkTools.DEFAULT_PARAMETERS.samples = 20000

#-----------------------------------------------------------------------------# Test data
# Small file (~120 lines)
small_file = joinpath(@__DIR__, "..", "test", "data", "books.xml")
small_xml = read(small_file, String)

# Medium file (generated XMark auction XML, ~14 MB)
medium_file = joinpath(@__DIR__, "data", "xmark.xml")
if !isfile(medium_file)
    mkpath(dirname(medium_file))
    @info "Generating XMark benchmark XML..."
    generate_xmark(medium_file, 1.0)
end
medium_xml = read(medium_file, String)

df = DataFrame(kind=String[], name=String[], bench=BenchmarkTools.Trial[])

macro add_benchmark(kind, name, expr...)
    esc(:(let
        @info string($kind, " - ", $name)
        bench = @benchmark $(expr...)
        push!(df, (; kind=$kind, name=$name, bench))
    end))
end

const SSNode = Node{SubString{String}}

#-----------------------------------------------------------------------------# Parse (small)
@add_benchmark "Parse (small)" "XML.jl" parse($small_xml, Node)
@add_benchmark "Parse (small)" "XML.jl (SS)" parse($small_xml, SSNode)
@add_benchmark "Parse (small)" "EzXML" EzXML.parsexml($small_xml)
@add_benchmark "Parse (small)" "LightXML" LightXML.parse_string($small_xml)
@add_benchmark "Parse (small)" "XMLDict" XMLDict.xml_dict($small_xml)

#-----------------------------------------------------------------------------# Parse (medium)
@add_benchmark "Parse (medium)" "XML.jl" parse($medium_xml, Node)
@add_benchmark "Parse (medium)" "XML.jl (SS)" parse($medium_xml, SSNode)
@add_benchmark "Parse (medium)" "EzXML" EzXML.parsexml($medium_xml)
@add_benchmark "Parse (medium)" "LightXML" LightXML.parse_string($medium_xml)
@add_benchmark "Parse (medium)" "XMLDict" XMLDict.xml_dict($medium_xml)

#-----------------------------------------------------------------------------# Write (small)
@add_benchmark "Write (small)" "XML.jl" XML.write(o) setup=(o = parse(small_xml, Node))
@add_benchmark "Write (small)" "EzXML" sprint(print, o) setup=(o = EzXML.parsexml(small_xml))
@add_benchmark "Write (small)" "LightXML" LightXML.save_file(o, f) setup=(o = LightXML.parse_string(small_xml); f = tempname()) teardown=(LightXML.free(o); rm(f, force=true))

#-----------------------------------------------------------------------------# Write (medium)
@add_benchmark "Write (medium)" "XML.jl" XML.write(o) setup=(o = parse(medium_xml, Node))
@add_benchmark "Write (medium)" "EzXML" sprint(print, o) setup=(o = EzXML.parsexml(medium_xml))
@add_benchmark "Write (medium)" "LightXML" LightXML.save_file(o, f) setup=(o = LightXML.parse_string(medium_xml); f = tempname()) teardown=(LightXML.free(o); rm(f, force=true))

#-----------------------------------------------------------------------------# Read from file
@add_benchmark "Read file" "XML.jl" read($medium_file, Node)
@add_benchmark "Read file" "EzXML" EzXML.readxml($medium_file)
@add_benchmark "Read file" "LightXML" LightXML.parse_file($medium_file)

#-----------------------------------------------------------------------------# Collect element tags
function xml_collect_tags(node)
    out = String[]
    _xml_collect_tags!(out, node)
    out
end
function _xml_collect_tags!(out, node)
    for c in children(node)
        if nodetype(c) === Element
            push!(out, tag(c))
            _xml_collect_tags!(out, c)
        end
    end
end

function ezxml_collect_tags(node::EzXML.Node)
    out = String[]
    _ezxml_collect_tags!(out, node)
    out
end
function _ezxml_collect_tags!(out, node::EzXML.Node)
    for child in EzXML.eachelement(node)
        push!(out, child.name)
        _ezxml_collect_tags!(out, child)
    end
end

function lightxml_collect_tags(root::LightXML.XMLElement)
    out = String[]
    _lightxml_collect_tags!(out, root)
    out
end
function _lightxml_collect_tags!(out, el::LightXML.XMLElement)
    for child in LightXML.child_elements(el)
        push!(out, LightXML.name(child))
        _lightxml_collect_tags!(out, child)
    end
end

@add_benchmark "Collect tags (small)" "XML.jl" xml_collect_tags(o) setup=(o = parse(small_xml, Node))
@add_benchmark "Collect tags (small)" "EzXML" ezxml_collect_tags(o.root) setup=(o = EzXML.parsexml(small_xml))
@add_benchmark "Collect tags (small)" "LightXML" lightxml_collect_tags(LightXML.root(o)) setup=(o = LightXML.parse_string(small_xml)) teardown=(LightXML.free(o))

@add_benchmark "Collect tags (medium)" "XML.jl" xml_collect_tags(o) setup=(o = parse(medium_xml, Node))
@add_benchmark "Collect tags (medium)" "EzXML" ezxml_collect_tags(o.root) setup=(o = EzXML.parsexml(medium_xml))
@add_benchmark "Collect tags (medium)" "LightXML" lightxml_collect_tags(LightXML.root(o)) setup=(o = LightXML.parse_string(medium_xml)) teardown=(LightXML.free(o))

#-----------------------------------------------------------------------------# Results
function plot_group(df, kind)
    g = groupby(df, :kind)
    haskey(g, (;kind)) || return
    sub = g[(;kind)]
    x = map(row -> "$(row.name)", eachrow(sub))
    y = map(x -> median(x).time / 1e6, sub.bench)
    display(barplot(x, y, title = "$kind — median time (ms)", border=:none, width=50))
    println()
end

println("\n", "="^60)
println("  BENCHMARK RESULTS")
println("="^60, "\n")

for kind in unique(df.kind)
    plot_group(df, kind)
end
