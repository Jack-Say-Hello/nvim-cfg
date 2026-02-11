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

2. Snacks: No supported finder found: fd

```
sudo apt install fd-find
```

3. Snacks: Failed to delete: cmd: gio trash
```
sudo apt install libglib2.0-bin
```


# 🧰 SKILL

## 1. nfs mount

### 1.1 host pc cfg

```

sudo vim /etc/exports 
/2T/dir/pwd 10.xxx.guest.ip(rw,sync,no_subtree_check,all_squash,anonuid=1003,anongid=1003)

sudo exportfs -ra
```

### 1.2 guest pc cfg

```
showmount -e host-ip

sudo mount host-ip:/host-dir-pwd gust-mount-dir
```


```

```
