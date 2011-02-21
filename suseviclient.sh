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
	echo -e "\nPowerstate\tVMID\tVM Label\t\t\t\tConfig file"
	echo -e "----------\t----\t--------\t\t\t\t-----------"
	allvms=`$ssh root@$esx_server "vim-cmd vmsvc/getallvms"`
	tempfile=/tmp/vmlist-control-`date +%s`-$RANDOM
	echo "$allvms" | sed '1d;s/\.vmx\s.*vmx-[0-9]*/\.vmx/g' | sort -n  > $tempfile
	while read line
	do
	
#More straightforward solution but it's too slow:(
#	 lvmid=`echo $line | awk '/[0-9]/ {print $1}'`
#	 pwstate=`$ssh root@$esx_server "vim-cmd vmsvc/power.getstate $lvmid | tail -1" < /dev/null`

#Faster one
	 name=`echo $line | grep -o "\ [A-Za-z0-9].*\[" | sed 's/\s*\[//;s/^\s//'`
	 $ssh root@$esx_server "/usr/lib/vmware/bin/vmdumper  -l| grep \"$name\" > /dev/null" < /dev/null 
	 pwstate=$?
	 if [ $pwstate -eq 0 ]
	 then
	 finallist=$finallist"\033[32mPowered on\033[0m\t$line\n"
	 else
	 finallist=$finallist"\033[31mPowered off\033[0m\t$line\n"
	 fi 
	 
	done < $tempfile
	finallist=`echo "$finallist"|sort`
	echo -e "$finallist"
	rm $tempfile
 #       echo -e "\nDatastore 2 (ISO Images):\n"
#	$ssh root@$esx_server "cd /vmfs/volumes && ls -hC datastore2/*.iso"
        } 

usage() {
echo  "Tool to create and control virtual machines on ESX(i) servers
Options:
-s <ip or domain name of ESX server>
-c Create new vm
   -n <label> for the new virtual machine
   -m <size> of RAM in megabytes
   -d <size> of hard disk (M/G)
   --iso <path> to ISO image in format of <datastore>/path/to/image.iso (optional)
-l List all guests
--dslist List all datastores
--dsbrowse List files on specified datastore
--status <vmid> Get parametres of VM
--poweron <vmid> Power On VM
   --bios Launch a VM's BIOS after start	
--poweroff <vmid> Power Off VM
--vnc <vmid> Connect to VM via VNC
--addvnc <vmid> Add VNC support to an existing VM ( guest need to be restarted to take effect)
--snapshotlist <vmid> Get list of snapshots for current VM
--snapshot <vmid> --snapname <snapshot label> Make snapshot of current VM status
--revert <vmid> --snapname <snapshot label> Revert from snapshot
--remove <vmid> Delete VM
--help This help
"
}


# Create and register VM

askname (){
echo "Please enter a label for the new virtual machine:"
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
	$ssh root$esx_server "grep bios\.forceSetupOnce '/vmfs/volumes/$datastore/$name/$name.vmx' && sed -i s/bios\.forceSetupOnce.*/bios\.forceSetupOnce=TRUE/g '/vmfs/volumes/$datastore/$name/$name.vmx'" > /dev/null
	$ssh root$esx_server "grep bios\.forceSetupOnce '/vmfs/volumes/$datastore/$name/$name.vmx' || echo \"$biosonce_config\" >> '/vmfs/volumes/$datastore/$name/$name.vmx' && vim-cmd vmsvc/reload $1" > /dev/null
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
vnc_port=`$ssh root@$esx_server "find /vmfs/volumes/datastore?/ -iname *.vmx -exec grep vnc\.port {} \;" | awk '{print $3}' | sed s/\"//g | sort | tail -1`
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
	uniq=`$ssh root@$esx_server "vim-cmd vmsvc/snapshot.get $1|grep 'Snapshot Name'"`
	echo $uniq |grep -o ": $2" > /dev/null
	if [ $? -eq 1 ]
	then 
	$ssh root@$esx_server "vim-cmd vmsvc/snapshot.create $1 \"$2\" \"  \" 1" > /dev/null
	echo "Snapshot \"$2\" created"
	else
	echo "Snapshotname \"$2\" already exists" 
	fi
}

revert(){
	#vmid2name $1
	#vmid2datastore $1
# I know it's quite ugly, I'll optimize it later:)
#   snaplevel=`$ssh root@$esx_server "grep displayName '/vmfs/volumes/$datastore/$name/$name.vmsd' | grep \"\"$2\"\" |egrep -o \"snapshot.?\" | grep -o '[0-9]'"`
snaplevel=`$ssh root@$esx_server "vim-cmd vmsvc/snapshot.get $1 | grep '$2' | egrep -o '\-*'| wc -c"`
   
   if [ ! $snaplevel -eq 0 ]
   then
   snaplevel=$(( $snaplevel/2-1)) 
   $ssh root@$esx_server "vim-cmd vmsvc/snapshot.revert $1 suppressPowerOff $snaplevel" > /dev/null
   echo "Reverted to snapshot: $2"
   else
   echo "No snapshot with specified name: $2"
   fi
   

}

snapshotremove(){
	
if [ ! -z $3 ]
then
$ssh root@$esx_server "vim-cmd vmsvc/snapshot.removeall $1"
else
snaplevel=`$ssh root@$esx_server "vim-cmd vmsvc/snapshot.get $1 | grep '$2' | egrep -o '\-*'| wc -c"`
   
   if [ ! $snaplevel -eq 0 ]
   then
   snaplevel=$(( $snaplevel/2-1)) 
   $ssh root@$esx_server "vim-cmd vmsvc/snapshot.remove $1 1 $snaplevel" > /dev/null
   echo "Removed snapshot: $2"
   else
   echo "No snapshot with specified name: $2"
   fi
fi   

}

snapshotlist(){

   $ssh root@$esx_server "vim-cmd vmsvc/snapshot.get $1"

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
	pwstate=`$ssh root@$esx_server "vim-cmd vmsvc/power.getstate $1"| tail -1`
}

addvnc() {
  vmid2name $1
   vmid2datastore $1
    vnc_check=`$ssh root$esx_server "egrep 'RemoteDisplay.vnc.enabled = \"?True\"?' '/vmfs/volumes/$datastore/$name/$name.vmx'"`
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
    $ssh root$esx_server "echo -e \"$vnc_config\" >> 'vmfs/volumes/$datastore/$name/$name.vmx' && vim-cmd vmsvc/reload $1"
    fi
}

dslist() {
 $ssh root@$esx_server "vim-cmd hostsvc/datastore/listsummary" | grep name | awk {'print $3'} | sed 's/",*//g' 	
}

dsbrowse() {
 $ssh root@$esx_server "ls -1 /vmfs/volumes/$1" 	
}

eval set -- `getopt -n$0 -a  --longoptions="iso: vnc: help status: poweron: poweroff: snapshot: snapshotremove: all revert: remove: addvnc: bios dslist dsbrowse: snapshotlist: snapname:" "hcln:s:m:d:" "$@"` || usage 
[ $# -eq 0 ] && usage

while [ $# -gt 0 ]
do
	    case "$1" in
             -s)  esx_server=$2;shift;;
             -m)  ram=$2;shift;;
	     -d)  disk=$2;shift;;
	     -n) name=$2; echo $name;shift;;
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
	     --dslist) dslist="1";shift;;
	     --dsbrowse) dsbrowse="$2";shift;;
	     --snapshotlist) snapshotlist_vmid="$2";shift;;
	     --snapname) snapname="$2";shift;;
	     --snapshotremove) snapshotremove_vmid="$2";shift;;
	     --all) all="1";snapname="anything";shift;;
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
	[ $? -eq 1 ] && echo "ISO image does not exist on datastore" && cleanup
fi

if [[ ! -z $create_new  && -n $esx_server && -n $ram && -n $disk && -n $name ]]
	then
#	askname
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

#dslist execution
if [[  -n $esx_server && ! -z $dslist ]] 
then  dslist ; cleanup
fi

#dslist execution
if [[  -n $esx_server && ! -z $dsbrowse ]] 
then  dsbrowse $dsbrowse ; cleanup
fi

#snapshotlist execution
if [[  -n $esx_server && ! -z $snapshotlist_vmid ]] 
then  snapshotlist $snapshotlist_vmid; cleanup
fi

#snapshotremove execution
if [[  -n $esx_server && ! -z $snapshotremove_vmid && ! -z $snapname ]] 
then  snapshotremove $snapshotremove_vmid "$snapname" $all; cleanup
fi

if [[  -n $esx_server && ! -z $vnc ]] 
then  vmid2name $vnc && get_vnc_port && vnc_connect ; cleanup
fi

if [[  -n $esx_server && ! -z $snap_vmid && ! -z $snapname ]] 
then snapshot $snap_vmid "$snapname"; cleanup
fi

if [[  -n $esx_server && ! -z $revert_vmid  && ! -z $snapname ]] 
then revert $revert_vmid $snapname; cleanup
fi

if [[  -n $esx_server && ! -z $remove_vmid ]]
then remove $remove_vmid; cleanup
fi

if [[  -n $esx_server && ! -z $addvnc_vmid ]]
then addvnc $addvnc_vmid; cleanup
fi

cleanup
usage
