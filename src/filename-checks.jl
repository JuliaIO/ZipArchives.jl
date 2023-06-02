using ArgCheck

function basic_name_check(name::String)
    @argcheck isvalid(name)
    @argcheck !contains(name, "\0")
    @argcheck !startswith(name, "/")
    parts = split(name, "/"; keepempty=false)
    for part in parts
        @argcheck part != ".."
    end
end

function windows_name_check(name::String)
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
        # TODO check for reserved DOS names maybe
    end
end