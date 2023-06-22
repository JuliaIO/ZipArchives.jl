using ArgCheck

function basic_name_check(name::String)::Nothing
    @argcheck !isempty(name)
    @argcheck isvalid(name)
    @argcheck !startswith(name, "/")
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
    lowercase(join(
        split(
            name,
            '/';
            keepempty=false
        ),
        '/'
    ))
end