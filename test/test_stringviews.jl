using Test, XML, StringViews

@testset "XMLStringViewsExt" begin
    mktempdir() do dir
        tmpfile = joinpath(dir, "simple.xml")
        xml_content = """<?xml version="1.0"?><root><child id="1">hello</child><child id="2">world</child></root>"""
        write(tmpfile, xml_content)

        @testset "mmap" begin
            doc = XML.mmap(tmpfile, LazyNode)
            @test nodetype(doc) === Document
            ch = children(doc)
            @test length(ch) == 2  # declaration + root

            decl = ch[1]
            @test nodetype(decl) === Declaration

            root = ch[2]
            @test nodetype(root) === Element
            @test tag(root) == "root"

            root_children = children(root)
            @test length(root_children) == 2
            @test tag(root_children[1]) == "child"
            @test tag(root_children[2]) == "child"
            @test value(children(root_children[1])[1]) == "hello"
            @test value(children(root_children[2])[1]) == "world"
        end

        @testset "mmap attributes" begin
            doc = XML.mmap(tmpfile, LazyNode)
            root = children(doc)[2]
            child1 = children(root)[1]
            @test child1["id"] == "1"
            child2 = children(root)[2]
            @test child2["id"] == "2"
        end

        @testset "parse StringView" begin
            sv = StringView(Vector{UInt8}(xml_content))
            doc = parse(sv, LazyNode)
            @test nodetype(doc) === Document
            root = children(doc)[2]
            @test tag(root) == "root"
            @test length(children(root)) == 2
        end

        @testset "mmap with complex document" begin
            tmpfile2 = joinpath(dir, "complex.xml")
            complex_xml = """<?xml version="1.0"?>
<catalog>
  <book id="bk101">
    <title>XML Developer's Guide</title>
    <price>44.95</price>
  </book>
  <!-- a comment -->
  <![CDATA[some raw data]]>
</catalog>"""
            write(tmpfile2, complex_xml)

            doc = XML.mmap(tmpfile2, LazyNode)
            root = last(c for c in children(doc) if nodetype(c) === Element)
            @test tag(root) == "catalog"

            ch = children(root)
            book = first(c for c in ch if nodetype(c) === Element)
            @test tag(book) == "book"
            @test book["id"] == "bk101"

            title = first(c for c in children(book) if nodetype(c) === Element && tag(c) == "title")
            @test simple_value(title) == "XML Developer's Guide"

            comments = [c for c in ch if nodetype(c) === Comment]
            @test length(comments) == 1
            @test value(comments[1]) == " a comment "

            cdatas = [c for c in ch if nodetype(c) === CData]
            @test length(cdatas) == 1
            @test value(cdatas[1]) == "some raw data"
        end
    end
end
