# Swappiness

Reduce aggressive swap usage (default 150 → 10).

```bash
sudo sysctl vm.swappiness=10
echo "vm.swappiness = 10" | sudo tee /etc/sysctl.d/99-swappiness.conf
```

Improves responsiveness when RAM is plentiful.
