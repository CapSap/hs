# leaving some notes for myself so i remember what i did

## my goals:

- have a home server up and running, and backup photos from my phone
- install that 3d printer contoroller on the server

### Step 1: install OS

currently debating between debian or something else. decided on debian.
notes from installation:
I chose LVM and seperate paritions for /home, /var/ and /tmp
Post install steps were setting up ssh, moving over the host-setup script and running it (this installs docker and some basic firewall stuff)

### Step 2: deploy

on my desktop machine with ssh configured, run the deploy script
this will run commands on server machine (deploy the github repo) and get .env vars from my local machine and then add them to docker via docker secret

### notes

useful link
https://github.com/zilexa/Homeserver

# Some more detailed notes that help document my reasoning at the time

## setting up host machine

1.  install debian on host machine via usb iso. using LVM
    hostname = shelaria-s
    domain name?
    username = shelaria
    user password = ?40
    how to set up the partitions?
    using the gui- seperate /var /home /tmp
    installed ssh and xfce

2.  set up ssh so that i can remote into the machine
    i created a ssh key pair on client side, and copied over the pub key to server
    and reserved an ip address via the router settings, and mac address
    i can now ssh into server via the command ssh debian-box
    and i set something in the .bashrc on the server to change the shell prompt text colour

and i should disable ssh with password now. DONE

3. I've decided to use LVM and try and have most of the data on home. By default docker wants to use /var. It's possible to add a config that will point the docker daemon to use my own dir. Might need to create a symlink (more reading here: https://docs.docker.com/engine/daemon/)
   create /etc/docker/daemon.json
   and add
   {
   "data-root": "/mnt/docker-data"
   }

4. mv over the setup script and run it. this will: install docker and do some firewall setup

5. deploy via script
   the deploy script is finnally working!

6. now what?
   5a. try and get immich actually working
   next bottleneck is that /var has only 7. something gb and its where the docker volumes are stored. need lots of storage there.
   im deciding to use bind mounts

## Troubles with immich- bind mounts or docker volumes?

Before running anything I had to choose between docker volumnes and bind mounts. In the end I chose docker volumnes, and ran into an issue where i had only allocated 7gb to the /var partition and it filled up and things stopped working. I learned that bind mounts and volumes are really not that different and that i think id prefer these volumes to be manged by docker.
