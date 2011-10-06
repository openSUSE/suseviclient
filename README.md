SUSE VI Client
==============

Lightweight tool for ESXi management from Linux box.


Features
--------

-VM creation and provisioning from

* ISO 
* VMDK
* SUSE Studio
* PXE 

-Cloning

-Snapshotting

-Virtual network management

-VM control through VNC

-Exporting to VMware Workstation/Player

How does it work?
-----------------

It wraps and automates so called ESXi 'Tech Support Mode' which is effectively ssh server and number of special(poor documented) VMware  management commands.

Currently it well tested with ESXi 4.0/4.1. It should also work with ESX, but not it was not covered by testing.

ESXi 5.0 support is planned but not yet tested/implemented.

Examples
--------

cat > ~/.suseviclientrc << EOF

esx_server="esxi.example.com"

studioserver="susestudio.com"

apiuser="your_user"

apikey="your_key"

EOF

1) Create VM of 512MB RAM and 8GB disk with ISO attached, poweron, connect to VM console:

suseviclient.sh -c -n "ISO Example" -m 512 -d 8G --iso datastore1/path/to/image.iso
Enter new VNC password:
Repeat VNC password:

* List existing VMs

suseviclient.sh -l

Powerstate      VMID    VM Label                                Config file


Powered on       16     SLES4VMware 32bit      [datastore1] SLES4VMware 32bit/SLES4VMware 32bit.vmx

Powered on       32     SLES4VMware 64bit      [datastore1] SLES4VMware 64bit/SLES4VMware 64bit.vmx

Powered off      64     ISO Example            [datastore1] ISO Example/ISO Example.vmx

* Power on VM

suseviclient.sh --poweron 64

Where 64 is VM id.

* Connect to VM console

suseviclient.sh --vnc 64

2) Create VM from VMDK image( includes automated conversion of desktop vmdk to server version):

suseviclient.sh -c -n "VMDK Example" --vmdk datastore1/path/to/image.vmdk

3) Create VM from SUSE Studio appliance

suseviclient.sh -c -n "Appliance Deployment" --studio $appliance_id

4) Create VM from PXE 

suseviclient.sh -c -n "PXE Example" -m 512 -d 5G

This will create blank VM with network attached. If PXE is enabled in your network it should be possible to perform a network boot after the VM is powered on.

For full list of possible options see suseviclient.sh --help

Installation
------------

Just download and  put suseviclient.sh somewhere in the $PATH for you convenience.

Shell version of suseviclient introduces no dependencies except of bash, ssh and vncviewer which can be found on almost any Linux desktop.


On the ESXi server side you have to enable ssh access, see: 

*http://kb.vmware.com/selfservice/microsites/search.do?language=en_US&cmd=displayKC&externalId=1003677 for ESXi 4.0
*http://kb.vmware.com/selfservice/microsites/search.do?language=en_US&cmd=displayKC&externalId=1017910 for ESXi 4.1/5.0

It's recommended to upload you ssh key to the server to not to enter password each time as passing management command through client.
The root fs on ESXi is not permanent storage, so it's recommended to put the key on some connected datastore and automate the key copy on next reboot.

Assuming that you "datastore1" connected to ESXi server, do this

1. mkdir /vmfs/volumes/datastore1/.ssh/ and place your ssh key there

2. echo "cp -r /vmfs/volumes/datastore1/.ssh/ /" >> /etc/rc.local

That's it. It's all you need to start using suseviclient.

All .rb files are additional modules( like web interface) and will be described separately.

Web Interface
-------------

Web fronted is available with webfrontend.rb currently under initial development state but already fucntional.

It is built with 

* Sinatra ( http://www.sinatrarb.com/ ) ruby framework ( so please '#gem install sinatra' if you want to try) 
* NoVNC ( VNC client using HTML5 WebSockets, Canvas,  http://kanaka.github.com/noVNC/ ) to allow access to VMs consoles.
