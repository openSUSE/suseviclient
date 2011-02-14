#!/bin/bash

# setting SSH Control Master
control_master() {
CONTROL=/tmp/ssh-control-`date +%s`-$RANDOM
ssh  -NfM -S $CONTROL root@$esx_server
MASTERPID=`ps -aef | grep "ssh -NfM -S $CONTROL" | grep -v grep | awk {'print $2'}`
ssh="ssh -S $CONTROL"
scp="scp -o ControlPath=\"$CONTROL\""
}

cleanup() {
[ ! -z $MASTERPID ] && kill $MASTERPID && exit
}

initial_info() {
	echo -e "\nGuest List:\n"
	$ssh root@$esx_server "vim-cmd vmsvc/getallvms"
        echo -e "\nDatastore 2 (ISO Images):\n"
	$ssh root@$esx_server "cd /vmfs/volumes && ls -hC datastore2/*.iso"
        } 

usage() {
echo  "Tool to create and control virtual machines on ESX(i) servers
Options:
-s <ip or domain name of ESX server>
-c Create new vm
   -m <size> of RAM in megabytes
   -d <size> of hard disk (M/G)
   --iso <path> to ISO image on shnell.suse.de(CD-ARCHIVE) or datastore2 (optional)
-l List all guests
--status <vmid> Get parametres of VM
--poweron <vmid> Power On VM
   --bios Launc a VM's BIOS after start	
--poweroff <vmid> Power Off VM
--vnc <vmid> Connect to VM via VNC
--snapshot <vmid> Make snapshot of current VM status
--revert <vmid> Revert from snapshot
--remove <vmid> Delete VM
--addvnc <vmid> Add VNC support to an existing VM
--help This help
"
}


# Create and register VM

askname (){
echo "Please enter virtual machine name:"
read name
}

register_vm () {
config="
config.version = \"8\"
virtualHW.version= \"7\"
guestOS = \"sles11\"
memsize = \"$ram\"
displayname = \"$name\"
scsi0.present = \"TRUE\"
scsi0.virtualDev = \"lsilogic\"
scsi0:0.present = \"TRUE\"
scsi0:0.fileName = \"$name.vmdk\"
ide1:0.present = \"true\"
ide1:0.deviceType = \"cdrom-image\"
ide1:0.filename = \"/vmfs/volumes/$iso\"
ide1:0.startConnected = \"TRUE\"
ethernet0.present= \"true\"
ethernet0.startConnected = \"true\"
ethernet0.virtualDev = \"e1000\"
ethernet0.networkName = \"VM Network\"
RemoteDisplay.vnc.enabled = \"True\"
RemoteDisplay.vnc.port = \"$vnc_port\"
RemoteDisplay.vnc.password = \"$vnc_password\""

echo "$config" > "/tmp/$name.vmx"
$ssh root@$esx_server "mkdir \"/vmfs/volumes/datastore1/$name\" && 
cd /vmfs/volumes/datastore1/${name// /\ } && 
vmkfstools -c $disk -a lsilogic '$name.vmdk' "
$scp "/tmp/$name.vmx" root@$esx_server:"/vmfs/volumes/datastore1/${name// /\ }/" 2>&1>/dev/null
rm -f "/tmp/$name.vmx"
$ssh root@$esx_server "vim-cmd solo/registervm /vmfs/volumes/datastore1/${name// /\ }/${name// /\ }.vmx"
}


# getting the vmid of current vm
get_vmid() {
vmid=$($ssh root@$esx_server "vim-cmd vmsvc/getallvms | grep '$name' | awk '{print \$1}'")
}

vmid2name(){
name=`$ssh root@$esx_server "vim-cmd vmsvc/get.summary $1 | grep name " | awk 'BEGIN { FS="\""; } { print $2; }'| cut -c 1-32`

}

vmid2datastore(){
	datastore=`$ssh root@$esx_server "vim-cmd vmsvc/get.datastores $1" | head -1| awk '{print $2}'`
}

power_on() {
	if [ ! -z $bios_once ] 
	then
	biosonce_config="bios.forceSetupOnce = \"TRUE\""
	vmid2name $1
	vmid2datastore $1
	$ssh root$esx_server "grep bios\.forceSetupOnce '/vmfs/volumes/$datastore/$name/$name.vmx' && sed -i s/bios\.forceSetupOnce.*/bios\.forceSetupOnce=TRUE/g '/vmfs/volumes/$datastore/$name/$name.vmx'"
	$ssh root$esx_server "grep bios\.forceSetupOnce '/vmfs/volumes/$datastore/$name/$name.vmx' || echo \"$biosonce_config\" >> '/vmfs/volumes/$datastore/$name/$name.vmx' && vim-cmd vmsvc/reload $1"
	fi
ssh root@$esx_server "vim-cmd vmsvc/power.on $1"
}

power_off() {
ssh root@$esx_server "vim-cmd vmsvc/power.off $1"
}


vnc_connect(){
get_vnc_port
vncviewer $esx_server:$vnc_conn_port
}


vnc_port(){
vnc_port=`$ssh root@$esx_server "find /vmfs/volumes/datastore?/ -iname *.vmx -exec grep vnc\.port {} \;" | awk '{print $3}' | tail -1 | sed s/\"//g`
[ -z $vnc_port ] && vnc_port="5900"
((vnc_port++))
}

vnc_pass(){

stty_orig=`stty -g`
stty -echo
echo "Enter new VNC password:"

read vncp1

echo "Repeat VNC password:"

read vncp2

stty $stty_orig

if [ $vncp1 = $vncp2 ];
then echo "VNC password successuly changed."
          vnc_password=$vncp2
  else
	  echo "Passwords do not match"
	  vnc_pass
fi

}

get_vnc_port(){

vnc_conn_port=`$ssh root@$esx_server "find /vmfs/volumes/datastore?/'$name' -iname \*.vmx -exec grep vnc\.port {} \;" | awk '{print $3}' | sed s/\"//g`

}

snapshot() {
        echo "Please enter a snapshot name:"
	read snap_name
        echo "Please enter a snapshot description:"
	read snap_desc
	$ssh root@$esx_server "vim-cmd vmsvc/snapshot.create $1 \"$snap_name\" \"$snap_desc\" 1" 
	
}

revert(){

   $ssh root@$esx_server "vim-cmd vmsvc/snapshot.get $1"
   echo "Please enter snapshot level for revert:"
   read snap_level
   echo "Please enter snapshot index for revert:"
   read snap_index
   $ssh root@$esx_server "vim-cmd vmsvc/snapshot.revert $1 suppressPowerOff $snap_level $snap_index"

}

remove() {
        vmid2name $1
	vmid2datastore $1
	if [ ! -z "$name" ] 
        then $ssh root$esx_server "vim-cmd vmsvc/unregister $1 && rm -i /vmfs/volumes/${datastore// /\ }/${name// /\ }/* && rmdir \"/vmfs/volumes/datastore1/$name/\""
	else echo "Wrong vmid"
	fi
}

powerstate(){
	pwstate=`$ssh root$esx_server "vim-cmd vmsvc/power.getstate $1"| tail -1`
}

addvnc() {
  vmid2name $1
   vmid2datastore $1
    vnc_check=`$ssh root$esx_server "cat 'vmfs/volumes/$datastore/$name/$name.vmx' | grep \"RemoteDisplay.vnc.enabled = True\""`
    if [ ! -z "$vnc_check" ]
    then echo "VNC is already enabled on this machine"
    else
    powerstate $1
    if [ "$pwstate" = "Powered on" ] 
    then 
    echo "Please power off this VM before adding VNC support"; cleanup; 
    fi   
   vnc_port
    vnc_pass
 
vnc_config="RemoteDisplay.vnc.enabled = \"True\"
RemoteDisplay.vnc.port = \"$vnc_port\"
RemoteDisplay.vnc.password = \"$vnc_password\""
    $ssh root$esx_server "echo \"$vnc_config\" >> 'vmfs/volumes/$datastore/$name/$name.vmx' && vim-cmd vmsvc/reload $1"
    fi
}
set -- `getopt -n$0  -u -a  --longoptions="iso: vnc: help status: poweron: poweroff: snapshot: revert: remove: addvnc: bios" "hcln:s:m:d:" "$@"` || usage 
[ $# -eq 0 ] && usage

while [ $# -gt 0 ]
do
	    case "$1" in
             -s)  esx_server=$2;shift;;
             -m)  ram=$2;shift;;
	     -d)  disk=$2;shift;;
	     -n)  name=$2; echo $name;shift;;
	     -c)  create_new="1";;
	     -l)  list="1";;
	     --iso) iso="$2";shift;;
	     --status) ssh root@$esx_server "vim-cmd vmsvc/get.summary $2" ;shift; exit;;
	     --bios) bios_once="1";shift;;
	     --poweron) power_on_vmid=$2;shift;;
	     --poweroff) power_off $2;shift;;
	     --snapshot) snap_vmid=$2;shift;;
	     --revert) revert_vmid=$2;shift;;
	     --remove) remove_vmid=$2;shift;;
	     --vnc) vnc="$2";shift;;
	     --addvnc) addvnc_vmid="$2";shift;;
             -h)        ;;
	     --help)  ;;
	     --)        shift;break;;
	     -*)        usage;;
	      *)         break;;        
            esac
 shift
done

[ ! -z $esx_server ] && control_master 

[[ -n $esx_server && ! -z $list ]] && initial_info && cleanup

### iso file check
if [ ! -z $iso ] 
then	ssh root@$esx_server test -e /vmfs/volumes/$iso
	[ $? -eq 1 ] && echo "ISO image does not exist on Datastore" && cleanup
fi

if [[ ! -z $create_new  && -n $esx_server && -n $ram && -n $disk ]]
	then
	askname
	vnc_pass
	vnc_port
	register_vm	
	cleanup
	fi

#power on and bios up
if [ ! -z $power_on_vmid ]
	then
		power_on $power_on_vmid
fi


if [[  -n $esx_server && ! -z $vnc ]] 
then  vmid2name $vnc && get_vnc_port && vnc_connect ; cleanup
fi

if [[  -n $esx_server && ! -z $snap_vmid ]] 
then snapshot $snap_vmid; cleanup
fi

if [[  -n $esx_server && ! -z $revert_vmid ]] 
then revert $revert_vmid; cleanup
fi

if [[  -n $esx_server && ! -z $remove_vmid ]]
then remove $remove_vmid; cleanup
fi

if [[  -n $esx_server && ! -z $addvnc_vmid ]]
then addvnc $addvnc_vmid; cleanup
fi

cleanup
usage
