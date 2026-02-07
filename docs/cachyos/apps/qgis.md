# QGIS

**LTR via Conda (recommended):**
```bash
conda create -n qgis python=3.9
conda activate qgis
conda install -c conda-forge qgis=3.40
```
Optional CUDA: `conda install cuda-cudart cuda-version=12` (match driver; 12.x if driver supports 13.x).

**Desktop file (XWayland, light theme):** Create `~/.local/share/applications/qgis-ltr.desktop` with `Exec=env QT_QPA_PLATFORM=xcb QT_QPA_PLATFORMTHEME=gtk2 /path/to/qgis/bin/qgis %F`, correct Icon/TryExec paths, `StartupWMClass=QGIS3`. Then `chmod +x` and `update-desktop-database ~/.local/share/applications`.

**Native:** `pacman -S qgis` plus deps: `python-gdal python-j2cli python-psycopg2 python-owslib python-lxml mariadb-libs arrow cfitsio podofo libheif poppler`. Light mode: `env QT_QPA_PLATFORMTHEME=gtk2 qgis` or desktop file with that env.
