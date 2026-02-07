# Conda / Mamba

**Install:** `yay -S miniconda3`.

**Mamba (faster than conda):**
```bash
sudo /opt/miniconda3/bin/conda install -n base conda-forge::mamba
```
Use `conda activate`; for other ops use `mamba` (env create, install, remove, search, clean).

**Common:** `mamba env create -f environment.yml`, `mamba env update --prefix ~/.conda/envs/pycad -f environment.yml`, `mamba install -n myenv package_name`, `mamba env list`, `conda activate myenv`.
