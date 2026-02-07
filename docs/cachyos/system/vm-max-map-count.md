# vm.max_map_count

[Arch news: increasing default vm.max_map_count](https://archlinux.org/news/increasing-the-default-vmmax_map_count-value/)

```bash
sudo sysctl -w vm.max_map_count=262144
```

Make permanent via `/etc/sysctl.d/` if needed.
