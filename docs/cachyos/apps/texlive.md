# TexLive

1. **Install:** `yay -S texlive-full`
   - If you get a file conflict on `/usr/bin/dvisvgm`, remove the standalone package first: `sudo pacman -R dvisvgm`, then retry.

2. **Verify:** `pdflatex --version`

3. **VS Code LaTeX Workshop (optional):** `sudo pacman -S perl-file-homedir perl-yaml-tiny`. Settings: `latexmk` with `-synctex=1 -interaction=nonstopmode -file-line-error -pdf`.

4. **Asymptote 404 on CachyOS:** `sudo pacman -S extra/asymptote` before `yay -S texlive-full`.
