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
    build = joinpath(@__DIR__, "build"),
)

# Deployment is handled by GitHub Actions using the modern Pages API
# (actions/upload-pages-artifact + actions/deploy-pages).
# No deploydocs() call needed — that pattern pushes to gh-pages branch
# which requires write permissions the GITHUB_TOKEN doesn't provide.