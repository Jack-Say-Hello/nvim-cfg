# 💤 LazyVim

A starter template for [LazyVim](https://github.com/LazyVim/LazyVim).
Refer to the [documentation](https://lazyvim.github.io/installation) to get started.

# 📌 install

```
sudo snap install nvim --classic
```

#   Q&A

1. ERROR: ld.so: object 'libeagleaudithook.so' from /etc/ld.so.preload cannot be preloaded (cannot open shared object file): ignored.

- sudo nvim /etc/ld.so.preload
- delete libeagleaudithook.so
