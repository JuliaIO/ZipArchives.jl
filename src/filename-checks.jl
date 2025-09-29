
function basic_name_check(name::String)::Nothing
    @argcheck !isempty(name)
    @argcheck isvalid(name)
    @argcheck !startswith(name, "/")
    @argcheck !contains(name, "//")
    @argcheck !contains(name, '\0')
    @argcheck !contains(name, '\\')
    @argcheck !contains(name, ':')
    @argcheck !contains(name, '"')
    @argcheck !contains(name, '*')
    @argcheck !contains(name, '<')
    @argcheck !contains(name, '>')
    @argcheck !contains(name, '?')
    @argcheck !contains(name, '|')
    @argcheck !contains(name, '\x7f')
    @argcheck all(>('\x1f'), name)
    parts = split(name, "/"; keepempty=false)
    for part in parts
        # @argcheck part != "."
        # @argcheck part != ".."
        @argcheck !endswith(part, ".")
        @argcheck !endswith(part, " ")
        # TODO check for reserved DOS names maybe
        # From some testing on windows 11, the names seem "fine".
        # if they are written as absolute paths with a prefix of \\?\
    end
end

# The zip format seems to allow an empty base file name at the top level.
# Other base file name cannot be empty.
# Any directory name can be just a "/".
# For example "a///b.txt" is the following path ("a/", "/", "/", "b.txt")
# But there is no path for a file ("a/", ""), 
# because the path "a/" is an empty directory 
# or a place to store metadata about "a/"
# Then on extract on windows the empty "/" turn into "_".
# that is why I check !contains(name, "//")
# Any entry name that ends in a "/" is always interpreted as 
# a directory entry.
# used_stripped_dir_names are the path to all directories with the trailing "/" removed
function check_name_used(name::String, used_names::Set{String}, used_stripped_dir_names::Set{String})::Nothing
    # basic_name_check(name)
    data = codeunits(name)
    @argcheck name ∉ used_names
    if !endswith(name, '/')
        @argcheck name ∉ used_stripped_dir_names
    end
    # also any of the parent directories implied by name must not be files.
    pos::Int = 1
    while true
        i = findnext('/', name, pos)
        isnothing(i) && break
        parent_data = @view(data[begin:i-1])
        # need to rstrip because of repeated '/'
        if isempty(parent_data) || parent_data[end] != UInt8('/')
            # this effectively rstrips all '/'
            parent_name = bytes2string(parent_data)
            # @show parent_name
            @argcheck parent_name ∉ used_names
        end
        pos = i+1
    end
end

function add_name_used!(name::String, used_names::Set{String}, used_stripped_dir_names::Set{String})::Nothing
    data = codeunits(name)
    push!(used_names, name)
    # also any of the parent directories implied by name must added to used_stripped_dir_names.
    pos::Int = 1
    while true
        i = findnext('/', name, pos)
        isnothing(i) && break
        parent_data = @view(data[begin:i-1])
        # need to rstrip because of repeated '/'
        if isempty(parent_data) || parent_data[end] != UInt8('/')
            # this effectively rstrips all '/'
            parent_name = bytes2string(parent_data)
            # @show parent_name
            push!(used_stripped_dir_names, parent_name)
        end     
        pos = i+1
    end
end
