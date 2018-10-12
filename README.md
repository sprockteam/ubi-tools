# Easy UBNT
A collection of tools to make managing UBNT software easier!

## UniFi Installer
A Bash script used to guide an administrator through a recommended installation or upgrade of the UniFi Controller controller software.

### How to Begin
```console
wget https://raw.githubusercontent.com/sprockteam/easy-ubnt/master/unifi-installer.sh -O unifi-installer.sh
sudo bash unifi-installer.sh
```

### Tracing the Script
You can trace each command of the script to see what it's doing by using the -x option:
```console
sudo bash unifi-installer.sh -x
```
