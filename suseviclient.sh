#!/bin/bash - 
#===============================================================================
#
#          FILE:  suseviclient.sh
# 
#         USAGE:  ./suseviclient.sh 
# 
#   DESCRIPTION: Lightweight VMware ESXi management tool
# 
#       OPTIONS:  ---
#  REQUIREMENTS:  ---
#          BUGS:  ---
#         NOTES:  ---
#        AUTHOR: Yury Tsarev, ytsarev@suse.cz
#       COMPANY: SUSE
#===============================================================================

#set -o nounset                              # Treat unset variables as an error



#kinda config section

#Default datastore to work with
datastore="datastore1"

# end of config section

# setting SSH Control Master
control_master() {
CONTROL=/tmp/ssh-control-`date +%s`-$RANDOM
ssh  -NfM -S $CONTROL root@$esx_server || exit
MASTERPID=`ps -aef | grep "ssh -NfM -S $CONTROL" | grep -v grep | awk {'print $2'}`
ssh="ssh -S $CONTROL"
scp="scp -o ControlPath=\"$CONTROL\""
}

cleanup() {
[ ! -z $MASTERPID ] && kill $MASTERPID && exit
}


yesno (){
while true
do
echo "$*"
echo "Please answer by entering (y)es or (n)o:"
read ANSWER
case "$ANSWER" in
[yY] | [yY][eE][sS] )
return 0
;;
[nN] | [nN][oO] )
return 1
;;
* )
echo "I cannot understand you over here."
;;
esac
done }

#studio 

rdom () { local IFS=\> ; read -d \< E C ;}

appliances() {
tempfile=/tmp/applist-`date +%s`-$RANDOM
curl -s -u "$1":"$2" "http://$studioserver/api/v1/user/appliances" > $tempfile
if [[ $? != 0 ]];then echo "Can't connect to specified studio server";rm -f $tempfile; exit; fi
while rdom; do
   if [[ $E = id ]]; then
	if [[ -z $flag ]]; then  
	echo "ApplianceID: "$C
        flag=1
        else 
	#echo "ParentID:"$C
	unset flag
	fi	
   fi
   if [[ $E = build ]]; then
   flag=1
   fi
   if [[ $E = name ]]; then
	if [[ -z $nflag ]]; then
	echo "Appliance Name: "$C
	nflag=1
	else
	echo "System template: "$C
	unset nflag
	fi
   fi
   if [[ $E = appliance ]]; then
	   echo -e "---------------"

   fi
   
   if [[ $E = arch ]]; then
	   echo "Architecture: "$C

   fi
   
   if [[ $E = edit_url ]]; then
	   echo "URL: "$C

   fi
   
  if [[ $E = estimated_raw_size ]]; then
	   echo "Size: "$C
  fi
  
  if [[ $E = estimated_compressed_size ]]; then
	   echo "Compressed size: "$C
  fi
  
  if [[ $E = message ]]; then
	   echo $C
  fi
  
done < $tempfile
rm -f $tempfile
unset tempfile
}

buildimage() {
tempfile=/tmp/buildimage-`date +%s`-$RANDOM
curl -s -u "$1":"$2" -XPOST "http://$studioserver/api/v1/user/running_builds?appliance_id=$3&force=1&image_type=oemiso" > $tempfile
if [[ $? != 0 ]];then echo "Can't connect to specified studio server";rm -f $tempfile; exit; fi
while rdom; do
if [[ $E = id ]]; then
echo "Build started with id "$C
fi

if [[ $E = message ]]; then
   echo $C
fi

done < $tempfile

rm $tempfile
unset tempfile

}

buildstatus() {

tempfile=/tmp/buildimage-`date +%s`-$RANDOM
curl -s -u "$1":"$2" "http://$studioserver/api/v1/user/running_builds?appliance_id=$3" > $tempfile
if [[ $? != 0 ]];then echo "Can't connect to specified studio server";rm -f $tempfile; exit; fi
while rdom; do
if [[ $E = id ]]; then
echo "Build id: "$C
fi

if [[ $E = state ]]; then
   echo "State: "$C
fi

if [[ $E = percent ]]; then
   echo "Percents done: "$C
fi

if [[ $E = time_elapsed ]]; then
   echo "Time elapsed: $(( $C/60 )) minutes"
fi

if [[ $E = message ]]; then
   echo "Current action: "$C
fi

done < $tempfile

rm $tempfile
unset tempfile
	
}

checkimage() {
tempfile=/tmp/checkimage-`date +%s`-$RANDOM	
curl -s -u "$1":"$2" "http://$studioserver/api/v1/user/appliances/$3" > $tempfile
while rdom; do
if [[ $E = image_type ]]; then
 if [[ $C = "oemiso" ]]; then
 type=$C
 fi
fi

if [[ $E = download_url && $type = "oemiso" ]]; then
 oemisolink="$C"
 unset type
 
fi

done < $tempfile
rm $tempfile
unset tempfile
if [[ -z $oemisolink ]]; then 
echo "Image is not ready"; cleanup
else echo "Image is ready, we can upload it to server..."
fi
}

imageupload() {

curl -u "$1":"$2" "$oemisolink" | $ssh root@$esx_server "cat > /vmfs/volumes/$datastore/${name// /\ }/studio.iso" && echo "Image uploaded"
	
}

#vmware 
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
	 resolved_ds=$(echo $line| grep -o '\[.*\]' |egrep -o '[A-Za-z0-9-]+')
	 resolved_ds=$($ssh root@$esx_server "cd /vmfs/volumes/$resolved_ds;pwd -P"< /dev/null) 
	 
	 $ssh root@$esx_server "/usr/lib/vmware/bin/vmdumper  -l| grep \"$resolved_ds/${name// /\ }/${name// /\ }.vmx\" > /dev/null" < /dev/null 
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


        } 

usage() {
echo  "Tool to create and control virtual machines on ESX(i) servers
Options:
-s <ip or domain name of ESX server>
-c Create new vm
   -n <label> for the new virtual machine
   -m <size> of RAM in megabytes
   -d <size> of hard disk (M/G)
   --ds <datastore name> where VM will be created (optional)
   --iso <path> to ISO image in format of <datastore>/path/to/image.iso (optional)
   --studio <appliance_id> Deploy appliance from SUSE Studio server (optional), see studio options below
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

--studioserver Custom suse studio server ( if option is ommited susestudio.com is a default)
--apiuser your SUSE Studio user (see http://susestudio.com/user/show_api_key )
--apikey  your SUSE Studio api key
--appliances Get appliance list from SUSE Studio
--buildimage <appliance_id> Build Preload ISO of specified appliance for deployment 
--buildstatus <appliance_id> Get info on running builds of specified appliance
--help This help
"
}


# Create and register VM

askname (){
echo "Please enter a label for the new virtual machine:"
read name
}

register_vm () {
if [[ ! -z $studio ]]; then
	if [[ ! -z $apiuser && ! -z apikey ]];then
	checkimage "$apiuser" "$apikey" "$studio"; 
	$ssh root@$esx_server "mkdir \"/vmfs/volumes/$datastore/$name\""
	imageupload "$apiuser" "$apikey" ;
	iso="$datastore/$name/studio.iso"
	else
	echo "Please provide studio apiuser and apikey"; exit
	fi
fi
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
${vnc_config}"

echo "$config" > "/tmp/$name.vmx"
$ssh root@$esx_server "[[ ! -d  \"/vmfs/volumes/$datastore/$name\" ]] &&  mkdir \"/vmfs/volumes/$datastore/$name\""
$ssh root@$esx_server " 
cd /vmfs/volumes/$datastore/${name// /\ } && 
vmkfstools -c $disk -a lsilogic '$name.vmdk' "
$scp "/tmp/$name.vmx" root@$esx_server:"/vmfs/volumes/$datastore/${name// /\ }/" 2>&1>/dev/null
rm -f "/tmp/$name.vmx"
$ssh root@$esx_server "vim-cmd solo/registervm /vmfs/volumes/$datastore/${name// /\ }/${name// /\ }.vmx"
echo "Virtual machine \"$name\" created"
}


# getting the vmid of current vm
get_vmid() {
vmid=$($ssh root@$esx_server "vim-cmd vmsvc/getallvms | grep '$name' | awk '{print \$1}'")
}

vmid2name(){
name=`$ssh root@$esx_server "vim-cmd vmsvc/get.summary $1 | grep name " | awk 'BEGIN { FS="\""; } { print $2; }'| cut -c 1-32`
if [ -z $name ]; then
 return 1
fi
}

vmid2datastore(){
	datastore=$($ssh root@$esx_server "vim-cmd vmsvc/get.config $1 | grep vmPathName| grep -o '\"\[.*\]' |egrep -o '[A-Za-z0-9-]+'")
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
vncviewer -encodings 'hextile zlib copyrect' $esx_server:$vnc_conn_port
}


vnc_port(){
tempfile=/tmp/dslist-`date +%s`-$RANDOM

$ssh root$esx_server "vim-cmd  vmsvc/getallvms| grep -o '\[.*\]' |egrep -o '[A-Za-z0-9-]+' |sort |uniq" > $tempfile

while read line 
do
 searchpath="${searchpath} /vmfs/volumes/$line/"
done < $tempfile

rm -f $tempfile

vnc_port=`$ssh root@$esx_server "find $searchpath -iname *.vmx -exec grep vnc\.port {} \;" | awk '{print $3}' | sed s/\"//g | sort | tail -1`
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

if [ "$vncp1" = "$vncp2" ];
then echo "VNC password successfuly changed."
          vnc_password=$vncp2
  else
	  echo "Passwords do not match"
	  vnc_pass
fi

}

get_vnc_port(){

vnc_conn_port=`$ssh root@$esx_server "find /vmfs/volumes/$datastore/'$name' -iname \*.vmx -exec grep vnc\.port {} \;" | awk '{print $3}' | sed s/\"//g`

}

snapshot() {
	uniq=`$ssh root@$esx_server "vim-cmd vmsvc/snapshot.get $1|grep 'Snapshot Name'"`
	echo $uniq |grep -o ": $2" > /dev/null
	if [ $? -eq 1 ]
	then 
	$ssh root@$esx_server "vim-cmd vmsvc/snapshot.create $1 \"$2\" \"  \" 1" > /dev/null
	echo -e "Snapshot \"$2\" creation process started.\nPlease check its status with --snapshotlist option after a few minutes."
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
        vmid2name $1 || exit
#	vmid2datastore $1
#	if [ ! -z "$name" ] 
#        then $ssh root$esx_server "vim-cmd vmsvc/unregister $1 && rm -i /vmfs/volumes/${datastore// /\ }/${name// /\ }/* && rmdir \"/vmfs/volumes/$datastore/$name/\""
#	else echo "Wrong vmid"
#	fi
	if yesno "Do you really want to delete $name ?" ; then
		
	$ssh root$esx_server "vim-cmd vmsvc/destroy $1" && echo "$name virtual machine removed"
	fi
}

powerstate(){
	pwstate=`$ssh root@$esx_server "vim-cmd vmsvc/power.getstate $1"| tail -1`
}

vnc_conf(){
			if [ -n "$vnc_password" ] 
			then
				vnc_config="RemoteDisplay.vnc.enabled = \"True\"
RemoteDisplay.vnc.port = \"$vnc_port\"
RemoteDisplay.vnc.password = \"$vnc_password\""
			else
				vnc_config="RemoteDisplay.vnc.enabled = \"True\"
RemoteDisplay.vnc.port = \"$vnc_port\""
		fi
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
   vnc_conf

    $ssh root$esx_server "echo -e \"$vnc_config\" >> 'vmfs/volumes/$datastore/$name/$name.vmx' && vim-cmd vmsvc/reload $1"
    fi
}

dslist() {
 $ssh root@$esx_server "vim-cmd hostsvc/datastore/listsummary" | grep name | awk {'print $3'} | sed 's/",*//g' 	
}

dsbrowse() {
	
 $ssh root@$esx_server "ls -1 /vmfs/volumes/$1/" 	
}

before_filter() {

remainder=$(($ram%4))
	if [[ $remainder -ne 0 ]]; then
		echo "Error: Memory size $ram not a multiple of 4"; exit;
	fi

ssh root@$esx_server test -e "/vmfs/volumes/${datastore// /\ }"
if [ $? -eq 1 ]; then
	echo "Error: Datastore $datastore does not exist"; cleanup
fi
	
ssh root@$esx_server test -e "/vmfs/volumes/${datastore// /\ }/${name// /\ }"
if [ $? -eq 0 ]; then
	echo "Error: Virtual Machine with such name already exists"; cleanup
fi

}

eval set -- `getopt -n$0 -a  --longoptions="ds: iso: vnc: help status: poweron: poweroff: snapshot: snapshotremove: all revert: remove: addvnc: bios dslist dsbrowse: snapshotlist: snapname: apiuser: apikey: appliances buildimage: buildstatus: studio: studioserver:" "hcln:s:m:d:" "$@"` || usage 
[ $# -eq 0 ] && usage

while [ $# -gt 0 ]
do
	    case "$1" in
             -s)  esx_server=$2;shift;;
             -m)  ram=$2;shift;;
	     -d)  disk=$2;shift;;
	     -n) name=$2;shift;;
	     -c)  create_new="1";;
	     -l)  list="1";;
	     --iso) iso="$2";shift;;
	     --status) ssh root@$esx_server "vim-cmd vmsvc/get.summary $2"| grep -E '(powerState|toolsStatus|hostName|ipAddress|name =|vmPathName|memorySizeMB|guestMemoryUsage|hostMemoryUsage)' ;shift; exit;;
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
	     --apiuser) apiuser="$2";shift;;
	     --apikey) apikey="$2";shift;;
	     --appliances) appliances="1";;
	     --buildimage) buildimage="$2";shift;;
	     --buildstatus) buildstatus="$2";shift;;
	     --studio) studio="$2";shift;;
	     --studioserver) studioserver="$2";shift;;
	     --ds) datastore="$2";shift;;
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
	before_filter
	vnc_pass
	vnc_port
	vnc_conf
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
then  vmid2name $vnc && vmid2datastore $vnc && get_vnc_port && vnc_connect ; cleanup
fi

if [[  -n $esx_server && ! -z $snap_vmid && ! -z $snapname ]] 
then snapshot $snap_vmid "$snapname"; cleanup
fi

if [[  -n $esx_server && ! -z $revert_vmid  && ! -z $snapname ]] 
then revert $revert_vmid "$snapname"; cleanup
fi

if [[  -n $esx_server && ! -z $remove_vmid ]]
then remove $remove_vmid; cleanup
fi

if [[  -n $esx_server && ! -z $addvnc_vmid ]]
then addvnc $addvnc_vmid; cleanup
fi

#studio
studioserver=${studioserver:-susestudio.com} #susestudio.com is default server
if [[ -n $apiuser &&  -n $apikey && ! -z $appliances ]]
then appliances "$apiuser" "$apikey";  exit
fi

if [[ -n $apiuser &&  -n $apikey && ! -z $buildimage ]]
then buildimage "$apiuser" "$apikey" "$buildimage"; exit
fi

if [[ -n $apiuser &&  -n $apikey && ! -z $buildstatus ]]
then buildstatus "$apiuser" "$apikey" "$buildstatus"; exit
fi

cleanup
usage
