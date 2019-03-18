# Easy UBNT
A collection of tools to make managing UBNT software easier!

### Who would benefit from this project?
* System administrators who are experienced with Linux but would prefer a "cheatsheet" so they don't have to learn or re-learn the recommended way to install UBNT software whenever they need to deploy or re-deploy servers.
* System administrators with limited Linux experience.
* End-users who want an easy way to install and manage UBNT software.

### How to begin
You can easily run the script the first time like this:
```console
wget -qO- sprocket.link/eubntrc | sudo bash
```

If you'd prefer, you can also run the script this way:
```console
wget https://raw.githubusercontent.com/sprockteam/easy-ubnt/v0.6.0-rc.1/easy-ubnt.sh -O easy-ubnt.sh
sudo bash easy-ubnt.sh
```

### Script options
You can automatically skip the license screen by using the -a option.
```console
sudo bash easy-ubnt.sh -a
```

You can run the script in "quick" mode to bypass most of the question prompts.
```console
sudo bash easy-ubnt.sh -q
```

**Note:** Even in quick mode, some questions may require a user response.

You can get verbose output of commands during script run by using the -v option.
```console
sudo bash easy-ubnt.sh -v
```

You can trace each command of the script to see what it's doing by using the -x option.
```console
sudo bash easy-ubnt.sh -x
```

### Script Logging
The last 5 logs are saved in `/var/log/easy-ubnt` and the latest script log is symlinked as `latest.log`.
```console
cat /var/log/easy-ubnt/latest.log | more
```
