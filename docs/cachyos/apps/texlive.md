# TexLive

`yay -S texlive-full`. `sudo pacman -S perl-file-homedir perl-yaml-tiny` for LaTeX Workshop (VS Code). Verify: `tex --version`.

**LaTeX Workshop (VS Code):** Use `latexmk` with `-synctex=1 -interaction=nonstopmode -file-line-error -pdf` in settings.

**Asymptote 404 on CachyOS:** Install from Arch extra first: `sudo pacman -S extra/asymptote`, then `yay -S texlive-full`.
