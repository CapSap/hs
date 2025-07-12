# leaving some notes for myself so i remember what i did
## my goals:
 - install an OS
 - get docker running
 - backup photos on phone
 - install that 3d printer contoroller

### Step 1: install OS
currently debating between debian or something else.

### notes
useful link
    https://github.com/zilexa/Homeserver

# todos
 - set up the host machine
 - set up docker
 - run a container that syncs photos
 - backup these photos

# setting up host machine
 1. install debian on host machine via usb iso
    hostname = shelaria-s
    domain name? 
    username = shelaria
    user password = ?40
    how to set up the partitions?
        using the gui- seperate /var /home/ tmp
    installed ssh and xfce

   
 2. set up ssh so that i can remote into the machine
   i created a ssh key pair on client side, and copied over the pub key to server
   and reserved an ip address via the router settings, and mac address
   i can now ssh into server via the command ssh debian-box
   and i set something in the .bashrc on the server to change the shell prompt text colour

   and i should disable ssh with password now. DONE

 3. install docker

    

