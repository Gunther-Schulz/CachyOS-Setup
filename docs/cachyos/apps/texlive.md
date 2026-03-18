# TexLive

1. **Install:** `yay -S texlive-full`
   - If you get a file conflict on `/usr/bin/dvisvgm`, remove first: `sudo pacman -R asymptote texlive-binextra texlive-latex texlive-basic texlive-bin texlive-latexrecommended dvisvgm`, then retry.
   - If rsync fails with "file has vanished" (exit 24), the PKGBUILD needs the exit-24 tolerance patch.

2. **Verify:** `pdflatex --version`

3. **VS Code LaTeX Workshop (optional):** `sudo pacman -S perl-file-homedir perl-yaml-tiny`. Settings: `latexmk` with `-synctex=1 -interaction=nonstopmode -file-line-error -pdf`.

4. **Asymptote 404 on CachyOS:** `sudo pacman -S extra/asymptote` before `yay -S texlive-full`.
