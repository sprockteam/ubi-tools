# Easy UBNT
A collection of tools to make managing UBNT software easier!

## UniFi Installer
A Bash script used to guide an administrator through a recommended installation or upgrade of the UniFi Controller controller software.

### How to Begin
Download the script,
```console
wget https://raw.githubusercontent.com/sprockteam/easy-ubnt/master/unifi-installer.sh -O unifi-installer.sh
```
then execute the script using bash, use `sudo` if not logged in as root.
```console
sudo bash unifi-installer.sh
```

Optionally you can make the script executable.
```console
chmod +x unifi-installer.sh
./unifi-installer.sh
```

### Advanced Features
You can trace each command of the script to see what it's doing by using the -x option.
```console
bash unifi-installer.sh -x
```
