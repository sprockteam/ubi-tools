# Easy UBNT
A collection of tools to make managing UBNT software easier!

### Who would benefit from this project?
* System administrators who are experienced with Linux but would prefer a "cheatsheet" so they don't have to learn or re-learn the recommended way to install UBNT software whenever they need to deploy or re-deploy servers.
* System administrators with limited Linux experience.
* End-users who want an easy way to install and manage UBNT software.

### How to begin
You can run the script this way:
```console
wget https://raw.githubusercontent.com/sprockteam/easy-ubnt/master/easy-ubnt.sh -O easy-ubnt.sh
sudo bash easy-ubnt.sh
```

For convenience, the script is also available using a short link:
```console
wget sprocket.link/eubnt -O easy-ubnt.sh && sudo bash easy-ubnt.sh
```

### Dev branch
You can run the latest development version of the script this way:
```console
wget https://raw.githubusercontent.com/sprockteam/easy-ubnt/development/easy-ubnt.sh -O easy-ubnt.sh
sudo bash easy-ubnt.sh
```

Or for convenience, you can run the dev version this way:
```console
wget sprocket.link/eubntdev -O easy-ubnt.sh && sudo bash easy-ubnt.sh
```

### Quick mode
You can run the script to quickly deploy a server this way:
```console
wget sprocket.link/eubnt -qO easy-ubnt.sh && sudo bash easy-ubnt.sh -aqd unifi.fqdn.com
```

### More script options
You can automatically skip the license screen:
```console
sudo bash easy-ubnt.sh -a
```

You can set the domain name to use when setting up Let's Encrypt:
```console
sudo bash easy-ubnt.sh -d domain.com
```

You can disable the UFW firewall:
```console
sudo bash easy-ubnt.sh -f off
```

You can see an explanation of the script options:
```console
sudo bash easy-ubnt.sh -h
```

You can run the script in "quick" mode to accept the default answers to questions:
```console
sudo bash easy-ubnt.sh -q
```

**Note:** Even in quick mode, some questions may require a user response.

You can get verbose output of commands during script run:
```console
sudo bash easy-ubnt.sh -v
```

You can trace each command on the screen to see what the script is doing:
```console
sudo bash easy-ubnt.sh -x
```

### Script Logging
The last 10 logs are saved in `/var/log/easy-ubnt` and the latest script log is symlinked as `latest.log`:
```console
more /var/log/easy-ubnt/latest.log
```
