using Documenter
using Testimonial

makedocs(
    sitename = "Testimonial.jl",
    format = Documenter.HTML(
        prettyurls = true,
        canonical = "https://sashakile.github.io/Testimonial.jl",
    ),
    modules = [Testimonial],
    pages = [
        "Home" => "index.md",
        "CLI Reference" => "cli.md",
        "API Reference" => "api.md",
        "Architecture" => "architecture.md",
        "Configuration" => "configuration.md",
    ],
    warnonly = [:missing_docs],
)

deploydocs(
    repo = "github.com/sashakile/Testimonial.jl.git",
    push_preview = true,
)