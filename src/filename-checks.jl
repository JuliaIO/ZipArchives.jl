using ArgCheck

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

function norm_name(name::AbstractString)::String
    s1 = join(
        split(
            name,
            '/';
            keepempty=false
        ),
        '/'
    )
    if endswith(name, '/')
        s1*'/'
    else
        s1
    end
end


# name is expected to be already normed and basic checked.
function check_name_used(name::String, used_names_lower::Set{String}, used_dir_names_lower::Set{String})::Bool
    # basic_name_check(name)
    # @assert norm_name(name) == name
    @argcheck name ∉ used_names_lower
    if !endswith(name, '/')
        @argcheck name ∉ used_dir_names_lower
    end
    # also any of the parent directories implied by name must not be files.
    pos::Int = 1
    while true
        i = findnext('/', name, pos)
        isnothing(i) && break
        parent_name = @view(name[begin:i-1])
        @show parent_name
        @argcheck parent_name ∉ used_names_lower
        pos = i+1
    end
end

# name is expected to be already normed, but might not be checked.
function add_name_used!(name::String, used_names_lower::Set{String}, used_dir_names_lower::Set{String})::Nothing
    # @assert norm_name(name) == name
    push!(name, used_names_lower)
    # also any of the parent directories implied by name must added to used_dir_names_lower.
    pos::Int = 1
    while true
        i = findnext('/', name, pos)
        isnothing(i) && break
        parent_name = name[begin:i-1]
        @show parent_name
        push!(used_dir_names_lower, parent_name)
        pos = i+1
    end
end
