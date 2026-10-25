# The tools nxnative's builds run (its README: "Pack an IPA"), plus uv for the Python packages.
# bin/setup installs them: brew bundle --file Brewfile
brew "uv"            # Python and the packages in .venv (pyproject.toml, uv.lock)
brew "xcodegen"      # the iOS projects nxnative generates, and NX Play's own
brew "zstd"
brew "spirv-cross"   # shaders: SPIR-V to Metal
brew "glslang"       # shaders of OpenGL games
cask "dotnet-sdk"    # nx_extract, which reads the NSPs (.NET 10)
