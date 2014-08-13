using JSON

function obj(;metadata={}, kwargs...)
    dic = [k=>v for (k, v) in kwargs]
    dic[:metadata] = metadata
    dic
end

function code_cell(input::Vector, outputs, prompt_number=1)
    obj(cell_type="code",
        collapsed=false,
        input=input,
        language="julia",
        outputs=outputs,
        prompt_number=prompt_number)
end
code_cell(input::String, outputs=Dict[]) = code_cell(split(input, "\n"), outputs)

function markdown_cell(source::Vector)
    obj(cell_type="markdown",
        source=source)
end
markdown_cell(source::String) = markdown_cell(split(source, "\n"))

function header_cell(level::Int, header::String)
    obj(cell_type="heading",
        level=level,
        source=split(header, "\n"))
end

function output(;typ="pyout", prompt_number=1, 
                kwargs...)
    obj(output_type=typ,
        prompt_number=prompt_number;
        kwargs...)
end

output(op::String, pnum) = output(text=split(op, "\n"), prompt_number=pnum)
output(op::Vector, pnum) = output(text=op, prompt_number=pnum)

function worksheet(cells::Vector)
    obj(cells=cells)
end

function notebook(name, cells, language="Julia")
    [:metadata=>[:language=>language, :name=>name],
     :nbformat=>3, :nbformat_minor=>0,
     :worksheets=>[worksheet(cells)]]
end

function text(pd::Dict)
    if pd["t"] == "Space"
        return  " "
    end
    if pd["t"] == "Str"
        pd["c"]
    end
end

text(pd::String) = pd
text(pd::Vector) = join(map(text, pd), "")

function markdown(blocks)
    inp = Any[[:unMeta=>Dict()]]
    push!(inp, blocks)
    pandoc(JSON.json(inp), :json, :markdown)
end

function code_cells(block, prompt_number)
    # "c" of "CodeBlock"
    txt = block[2]
    lines = split(txt, "\n")
    cells = Dict[]
    codebuffer = String[]
    outputbuffer = String[]
    readingoutput = false
    leadblank_re = Regex(string("^", repeat(" ", length("julia>")), " (.*)\$"))
    local pnum=prompt_number
    function push_cell!()
        cell = code_cell(codebuffer, [output(outputbuffer, pnum)], pnum)
        push!(cells, cell)
        pnum += 1
        codebuffer = String[]
        outputbuffer = String[]
    end
    for line in lines
        m1=match(r"^\s*julia>\s*(.*)$", line)
        m2=match(leadblank_re, line)
        code = nothing
        if m1 != nothing
            code = m1.captures[1]
        elseif !readingoutput && m2 != nothing
            code = m2.captures[1]
        elseif !readingoutput && strip(line) == ""
            code = ""
        end
        if code != nothing
            if readingoutput
                push_cell!()
                readingoutput=false
            end
            push!(codebuffer, code)
        else
            readingoutput = true
            push!(outputbuffer, line)
        end
    end
    if (length(codebuffer) != 0)
        push_cell!()
    end
    pnum, cells
end

# Parse a rst string into a list of cells
function parse_rst(rst::String)
    pandoc_metadata, document =
        JSON.parse(pandoc(rst, :markdown, :json))
    pandoc_metadata, document
    shift!(document)
    mdbuffer = Dict[]
    cells = Dict[]
    pnumber = 0 # Prompt number
    for block in document
        if !in(block["t"], ["Header", "CodeBlock"])
            push!(mdbuffer, block)
        end
        push!(cells, markdown_cell(markdown(mdbuffer)))
        empty!(mdbuffer)
        if block["t"] == "Header"
            level  = block["c"][1]
            header = text(block["c"][3])
            push!(cells, header_cell(level, header))
        end
        if block["t"] == "CodeBlock"
            pnumber, c_cells = code_cells(block["c"], pnumber+1)
            append!(cells, c_cells)
        end
    end
    push!(cells, markdown_cell(markdown(mdbuffer)))
    empty!(mdbuffer)
    cells
end

# A super-simple pandoc interface from dcjones/Judo.jl
#
# Args:
#   input: Input string.
#   infmt: Input format.
#   outfmt: Output format.
#   args: Additional arguments appended to the pandoc command.
#
# Returns:
#   A string containing the output from pandoc.
#
function pandoc(input::String, infmt::Symbol, outfmt::Symbol, args::String...; pandoc_bin="pandoc")
    cmd = ByteString[pandoc_bin,
                     "--from=$(string(infmt))",
                     "--to=$(string(outfmt))"]
    for arg in args
        push!(cmd, arg)
    end
    pandoc_out, pandoc_in, proc = readandwrite(Cmd(cmd))
    write(pandoc_in, input)
    close(pandoc_in)
    readall(pandoc_out)
end


function name(file)
    replace(file, r".[a-z]{3,5}$", "")
end

function transform(input_file,
                   output_file=nothing,
                   title=nothing,
                   pandoc_bin="pandoc")
    input = readall(open(input_file))
    cells = parse_rst(input)
    if title==nothing
        title = name(input_file)
    end
    nb = notebook(title, cells);
    f = output_file == nothing ? STDOUT : open(output_file, "w")
    write(f, JSON.json(nb))
    close(f)
end

##########
# Script #
##########
using ArgParse

argsettings = ArgParseSettings()

@add_arg_table argsettings begin
    "input_file"
       help = "Input ReST file"
       required = true
    "output_file"
       required = false
    "--title"
       help = "Title of the notebook"
       default = nothing
    "--pandoc"
       help = "Path to Pandoc binary"
       default = "pandoc"
end

function main()
    args = parse_args(argsettings)
    transform(args["input_file"], args["output_file"],
              args["title"], args["pandoc"])
end

main()
