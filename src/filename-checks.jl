using ArgCheck

function basic_name_check(name::String)
    @argcheck isvalid(name)
    @argcheck !contains(name, "\0")
    @argcheck !startswith(name, "/")
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
        @argcheck !endswith(part, ".")
        @argcheck !endswith(part, " ")
        # TODO check for reserved DOS names maybe
        # From some testing on windows 11, the names seem "fine".
        # if they are written as absolute paths
    end
end