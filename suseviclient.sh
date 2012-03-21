#!/bin/bash - 
#===============================================================================
#
#          FILE:  suseviclient.sh
# 
#         USAGE:  ./suseviclient.sh <options>
# 
#   DESCRIPTION: Lightweight VMware ESXi management tool
# 
#       OPTIONS:  see ./suseviclient.sh --help
#  REQUIREMENTS:  bash,ssh and vncviewer
#          BUGS:  ---
#         NOTES:  ---
#        AUTHOR: Yury Tsarev, ytsarev@suse.cz
#       COMPANY: SUSE
#===============================================================================

#set -o nounset                              # Treat unset variables as an error



#kinda config section

[ -f ~/.suseviclientrc ] && . ~/.suseviclientrc

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
        [ ! -z $MASTERPID ] && kill $MASTERPID 
        if [ -n "$1" ];then
                exit $1
        else 
                exit 0
        fi
}

#generic helpers
yesno (){
        if [ -n "$globalyes" ]; then
                return 0
        fi
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
        done 
}

strip_chars() {
        echo "${1//[\'\"\,\!\@\#\$\%\^\&\*\(\)\/\?\[\]\:\>\<\{\}\|\\\'\;]/}"
}

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
        studio_before_filter
        tempfile=/tmp/buildimage-`date +%s`-$RANDOM
        curl -s -u "$1":"$2" -XPOST "http://$studioserver/api/v1/user/running_builds?appliance_id=$3&force=1&image_type=$format" > $tempfile
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
                if [[ $E = name && ! $nonameupdate -eq 1 ]];then
                        appliance_name="$C"
                        nonameupdate=1
                fi

                if [[ $E = arch ]]; then
                        arch="$C"
                fi


                if [[ $E = version ]]; then
                        version="$C"
                fi
                if [[ $E = image_type ]]; then
                        if [[ $C = "$format" ]]; then
                                type=$C
                        fi
                fi

                if [[ $E = download_url && $type = "$format" ]]; then
                        imagelink="$C"
                        unset type

                        #break loop to get latest image version
                        break
                fi

        done < $tempfile
        rm $tempfile
        unset tempfile
        if [[ -z $imagelink ]]; then 
                echo "Image is not ready"; cleanup
        else echo "Image is ready, we can upload it to server..."
        fi
}

imageupload() {

        #curl -u "$1":"$2" "$imagelink" | $ssh root@$esx_server "cat > /vmfs/volumes/$datastore/${name// /\ }/studio.iso" && echo "Image uploaded"

        if [ "$format" = "oemiso" ] ; then

                $ssh root@$esx_server "wget $imagelink -O  /vmfs/volumes/$datastore/${name// /\ }/studio.iso"
                if [ $? -eq 0 ]; then
                        echo "Image uploaded"
                else
                        echo "Image upload failure :("; cleanup
                fi

        elif [ "$format" = "vmx" ] ; then
                img_filename=$(basename $imagelink)
                tarname=$(echo $img_filename| sed -n 's/\(.*\)\.vmx.tar.gz/\1.vmx.tar/p')
                $ssh root@$esx_server "cd '/vmfs/volumes/$datastore/' && wget '$imagelink'"
                if [ $? -eq 0 ]; then
                        echo "Image uploaded"
                else
                        echo "Image upload failure :("; cleanup
                fi
                $ssh root@$esx_server "cd '/vmfs/volumes/$datastore/' && echo  \"Unpacking image, please wait...\" && gunzip '$img_filename'"
                realname=$($ssh root@$esx_server "cd '/vmfs/volumes/$datastore/' && tar -tf $tarname | sed -n 's/\///g;1p'")
                realfilename=$($ssh root@$esx_server "cd '/vmfs/volumes/$datastore/' && tar -tf $tarname |sed -n 's/.*\/\(.*\)\.vmdk/\1/p'")
                $ssh root@$esx_server "cd '/vmfs/volumes/$datastore/' &&  tar -xf $tarname && rm '$tarname' && mv '$realname' '$name' && chown root:root -R './$name' && cd './$name' && mv '$realfilename'.vmx '$name.vmx' && mv '$realfilename'.vmdk '$name.vmdk'" && echo "Image uploaded & unpacked"		
        fi

}


vmdk_convert ()
{
        $ssh root@$esx_server "cd '/vmfs/volumes/$datastore/$1/' && mv './$1.vmdk' './$1.vmdk.preconvert' && vmkfstools -i '$1.vmdk.preconvert' -d thin '$1.vmdk' && rm '$1.vmdk.preconvert'"
}	# ----------  end of function vmkd_convert  ----------



vmx_convert ()
{	 
        vnc_port
        vnc_conf
        pathtoconfig="/vmfs/volumes/$datastore/$name/$name.vmx"
        $ssh root@$esx_server "sed -i 's/virtualHW.version = \"4\"/virtualHW.version = \"7\"/g; s/ide0:0.*//g; s/$realfilename/$name/g' '$pathtoconfig'" 
        echo -e "$vnc_config\nethernet0.networkName = \"VM Network\"" | $ssh root@$esx_server "cat >> '$pathtoconfig'"

}	# ----------  end of function vmx_convert  ----------

#vmware 
initial_info() {

        if [ -t 1 ] ; then
                COL_GREEN="\033[32m"
                COL_RED="\033[31m"
                COL_OFF="\033[0m"
        fi

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
                relpath=$(echo $line | sed -n 's/.*] \(.*\)\.vmx.*/\1.vmx/p')	 
                $ssh root@$esx_server "/usr/lib/vmware/bin/vmdumper  -l| grep \"$resolved_ds/$relpath\" > /dev/null" < /dev/null 
                pwstate=$?
                if [ $pwstate -eq 0 ]
                then
                        finallist=$finallist"${COL_GREEN}Powered on${COL_OFF}	$line\n"
                else
                        finallist=$finallist"${COL_RED}Powered off${COL_OFF}	$line\n"
                fi 

        done < $tempfile
        finallist=`echo -n "$finallist"|sort`
        echo -ne "$finallist"
        rm $tempfile


} 

usage() {
        echo  "
Tool to create and control virtual machines on ESXi servers

VM creation:
------------
-s <ip or domain name of ESX server>
-c Create new vm
-n <label> for the new virtual machine
-m <size> of RAM in megabytes. Can be omitted. Default is 512 MB
-d <size> of hard disk (M/G). Can be omitted. Default is 5 GB
--ds <datastore name> where VM will be created (optional)
--network <name> connect VM network adapter to specified virtual network(optional)
--vncpass <password> set password to access vm console via vnc. Use this if you need non-interactive VM creation.
--novncpass omits setting vnc password so no authorization will be required


--iso <path> to ISO image in format of <datastore>/path/to/image.iso
--vmdk <path> to VMDK image in format of <datastore>/path/to/image.iso  
--studio <appliance_id> Deploy appliance from SUSE Studio server, see studio options below

VM modification:
----------------
-e <vmid> <param to change> Edit existing VM. Available parameters for editing:
          -n <label> Change label
          --iso <path> Connect another iso image
          --network <name> Switch to another virtual network
          --vncpass <password> Change VNC passord
          --vncpass -i interactively change password with checks
          --novncpass remove password enabling connection without authentication
        
Cloning:
--------
--clone <vmid> Clone the specified VM. Can be extended with -n <label> and --ds <datastore> options
 	  --toserver <esxi server> clone to *another* ESXi server. Do NOT use this option when cloning within one server

Exporting:
----------
--export <vmid> <local_directory> Export VM from ESXi to local desktop to use with VMWare desktop products(Workstation/Player)   

Generic management:
------------------- 
-l List all guests
--dslist List all datastores
--dsbrowse List files on specified datastore
--status <vmid> Get parametres of VM
--poweron <vmid> Power On VM
--bios Launch a VM's BIOS after start
--autoyast <network path> (http/ftp/nfs) to autoyast xml control file
--poweroff <vmid> Power Off VM
--reset <vmid> Reset VM
--vnc <vmid> Connect to VM via VNC
--showvncport <vmid> Print VNC port assigned to specified VM 
--addvnc <vmid> Add VNC support to an existing VM ( guest need to be restarted to take effect)
--remove <vmid> Delete VM

Snapshot management:
--------------------
--snapshotlist <vmid> Get list of snapshots for current VM
--snapshot <vmid> --snapname <snapshot label> Make snapshot of current VM status
		  If --snapname is not specified the label will default to \"snapshot\$timestamp\" 
--snapshotremove <vmid> --snapname <snapshot label> Remove a snapshot with specified name
--snapshotremove <vmid> --snapid <snapshot_id> Remove a snapshot with specified ID
--snapshotremove <vmid> --all Remove all snapshots for specidied VM
--revert <vmid> --snapname <snapshot label> Revert to snapshot by name
--revert <vmid> --snapid <snapshot id> Revert to snapshot by ID


SUSE Studio specific options:
-----------------------------
--studioserver <custom.server.com> Custom suse studio server ( if option is omitted susestudio.com is a default)
--apiuser <api_user> your SUSE Studio user (see http://susestudio.com/user/show_api_key )
--apikey <api_key> your SUSE Studio api key
--appliances Get appliance list from SUSE Studio
--buildimage <appliance_id> Build Preload ISO of specified appliance for deployment 
--buildstatus <appliance_id> Get info on running builds of specified appliance
--format <image format> specify oemiso or vmx here
--help This help

Network Management:
-------------------

--networks <vmid> list networks used by VM
--vswitches list virtual switches
--nics list network adapters available on ESXi server
--vswitchadd <name> Create virtual switch with default corresponding network port group
--vswitchremove <name> Remove virtual switch

Configuration file:
--------------------
You can specify frequently used options in configuration file of ~/.suseviclientrc 
Example of such a config file with comments:

#Default ESXi server to work with
esx_server=\"thessalonike.suse.de\"

#SUSE Studio API user
apiuser=\"studiouser\"

#SUSE Studio API key
apikey=\"studioapikey\"

#Custom SUSE Studio server
studioserver=\"istudio.suse.de\"

All specified directives in config file are easily overridable by the related command control option.
"
}


# Create and register VM

register_vm () {
        if [[ ! -z $studio ]]; then
                if [[ ! -z $apiuser && ! -z $apikey ]];then

                        [ $format = "oemiso" ] && $ssh root@$esx_server "mkdir \"/vmfs/volumes/$datastore/$name\"" && iso="$datastore/$name/studio.iso"

                        imageupload "$apiuser" "$apikey" ;
                        [ $format = "vmx" ] && vmdk_convert "$name" && vmx_convert && $ssh root@$esx_server "vim-cmd solo/registervm '/vmfs/volumes/$datastore/$name/$name.vmx'" && echo "Virtual machine \"$name\" created" && cleanup
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
scsi0:0.fileName = \"$name.vmdk\""

        if [ -n "$iso" ];then
                iso_config="
ide1:0.present = \"true\"
ide1:0.deviceType = \"cdrom-image\"
ide1:0.filename = \"/vmfs/volumes/$iso\"
ide1:0.startConnected = \"TRUE\""
        else
                iso_config=""
        fi

        network_config="
ethernet0.present= \"true\"
ethernet0.startConnected = \"true\"
ethernet0.virtualDev = \"e1000\"
ethernet0.networkName = \"$network_name\""

        $ssh root@$esx_server "[[ ! -d  \"/vmfs/volumes/$datastore/$name\" ]] &&  mkdir \"/vmfs/volumes/$datastore/$name\""

        echo "$config$iso_config$network_config$vnc_config" | $ssh root@$esx_server "cat > '/vmfs/volumes/$datastore/$name/$name.vmx'"

        #Create an empty scsci disk of if vmdk specified copy it to the vm's dir
        if [ -n "$vmdk" ];then
                $ssh root@$esx_server "vmkfstools -i '/vmfs/volumes/$vmdk' -d thin '/vmfs/volumes/$datastore/$name/$name.vmdk'"
        else
                $ssh root@$esx_server "cd '/vmfs/volumes/$datastore/$name' && vmkfstools -c $disk -a lsilogic '$name.vmdk' "
        fi

        if [ $? -ne 0 ] ; then
                echo "Virtual disk creation failure"; 
                $ssh root@$esx_server "rm -rf '/vmfs/volumes/$datastore/$name/'"
                cleanup 
        fi

        $ssh root@$esx_server "vim-cmd solo/registervm '/vmfs/volumes/$datastore/$name/$name.vmx'"
        if [ $? -eq 0 ] ; then
                echo "Virtual machine \"$name\" created"
        fi
}


# getting the vmid of current vm
get_vmid() {
        vmid=$($ssh root@$esx_server "vim-cmd vmsvc/getallvms | grep '$name' | awk '{print \$1}'")
}

vmid2name(){
        name=$($ssh root@$esx_server "vim-cmd vmsvc/get.summary $1 | grep name " | sed -n 's/name = "\(.*\)",/\1/p' | sed 's/^[ \t]*//;s/[ \t]*$//')
        if [ -z "$name" ]; then
                return 1
        fi
}

vmid2datastore(){
        datastore=$($ssh root@$esx_server "vim-cmd vmsvc/get.config $1 | grep vmPathName| grep -o '\"\[.*\]' |egrep -o '[A-Za-z0-9-]+'")
}

vmid2relpath(){
        relpath=$($ssh root@$esx_server "vim-cmd vmsvc/get.config $1 | grep vmPathName | sed 's/.*] //g; s/\",.*//g'")
}

relpath2vmdkpath(){
        #TODO:extend to the case of multiple disks
        vmdkpath=$($ssh root@$esx_server "grep -i \.vmdk '/vmfs/volumes/$datastore/$relpath' | sed -n 's/.*\"\(.*\)\.vmdk.*/\1.vmdk/p' | head -1")
        vmdkpath="$(dirname "$relpath")/$vmdkpath"
}


vnc_connect(){
        vncpassword=""
        passwd_counter=1
        connect=1 
        while [ $connect ]; do

                if [ $passwd_counter -gt 3 ];then
                        cleanup
                fi

                output=$(echo "$vncpassword"|vncviewer -autopass -encodings 'hextile zlib copyrect' $esx_server:$vnc_conn_port 2>&1)
                echo $output| egrep -q "Performing standard VNC authentication"
                if [[ $? -eq 0 && $vncpassword = "" ]];then
                        stty_orig=`stty -g`
                        stty -echo
                        echo "Enter VNC password:"

                        read vncpassword

                        stty $stty_orig
                        output="suseviclient-vncrestart"
                        passwd_counter=$(($passwd_counter+1))
                fi

                echo $output| egrep -q "(VNC connection failed|Unable to connect to VNC server)"

                if [ $? -eq 0 ]; then
                        echo "VNC connection failed" 
                fi

                echo $output| egrep -q "(Unknown message type|Zero size rect|suseviclient-vncrestart|Rect too large)"
                if [ $? -eq 1 ]; then
                        connect=""
                fi

        done

}

vnc_port(){
        tempfile=/tmp/dslist-`date +%s`-$RANDOM

        $ssh root@$esx_server "vim-cmd  vmsvc/getallvms| grep -o '\[.*\]' |egrep -o '[A-Za-z0-9-]+' |sort |uniq" > $tempfile

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
        if [ $no_vnc_password -eq 1 ]; then
                vnc_password=""
                return 0
        fi
        if [ -z "$vnc_password" ];then
                stty_orig=`stty -g`
                stty -echo
                echo "Enter new VNC password:"

                read vncp1

                echo "Repeat VNC password:"

                read vncp2

                stty $stty_orig

                if [ "$vncp1" = "$vncp2" ];
                then echo "VNC passwords match."
                        vnc_password=$vncp2
                else
                        echo "Passwords do not match"
                        vnc_pass
                fi
        fi
}

get_vnc_port(){

        vnc_conn_port=`$ssh root@$esx_server "grep vnc\.port '/vmfs/volumes/$datastore/$relpath'" | awk '{print $3}' | sed s/\"//g`

        if [ ! -z "$vnc_conn_port" ] ; then
                return 0
        else
                echo "vnc is not enabled on this virtual machine. Please try --addvnc feature."; return 1
        fi
}

power_on() {


        if [ ! -z $bios_once ] 
        then
                vmid2datastore $1
                vmid2relpath $1
                biosonce_config="bios.forceSetupOnce = \"TRUE\""
                $ssh root@$esx_server "grep bios\.forceSetupOnce '/vmfs/volumes/$datastore/$relpath' && sed -i s/bios\.forceSetupOnce.*/bios\.forceSetupOnce=TRUE/g '/vmfs/volumes/$datastore/$relpath'" > /dev/null
                $ssh root@$esx_server "grep bios\.forceSetupOnce '/vmfs/volumes/$datastore/$relpath' || echo \"$biosonce_config\" >> '/vmfs/volumes/$datastore/$relpath' && vim-cmd vmsvc/reload $1" > /dev/null
        fi

        output=$($ssh root@$esx_server "nohup vim-cmd vmsvc/power.on $1 2>&1 < /dev/null &")
        if [ $? -eq 0 ] ; then
                echo "VM powered on"
        else
                echo "$output" | sed -n 's/msg = "\(.*\)".*/\1/p'; return 1
        fi
	
	sleep 1
        message=$($ssh root@$esx_server "vim-cmd vmsvc/message $1| head -1 | sed 's/Virtual machine message \(.*\):/\1/g'" )
        if [[ $message != "No message." ]];then
                $ssh root@$esx_server "vim-cmd vmsvc/message $1 $message 2"
        fi

        if [ -n "$autoyast" ];then
                test -f ./vnc.rb || echo "Can't find vnc.rb, sorry: no autoyast string will be passed"
                vmid2datastore $1
                vmid2relpath $1
                get_vnc_port
                ./vnc.rb "$esx_server" "$vnc_conn_port" test "netsetup=dhcp autoyast=$autoyast"
        fi

}

power_off() {
        output=$(ssh root@$esx_server "vim-cmd vmsvc/power.off $1 2>&1")
        if [ $? -eq 0 ] ; then
                echo "VM powered off"; return 0
        else
                echo "$output" | sed -n 's/msg = "\(.*\)".*/\1/p' ; return 1
        fi
}


reset() {

        output=$(ssh root@$esx_server "vim-cmd vmsvc/power.reset $1 2>&1")
        if [ $? -eq 0 ] ; then
                echo "VM resetted"; return 0
        else
                echo "$output" | sed -n 's/msg = "\(.*\)".*/\1/p' ; return 1
        fi

}

snapshotcheck(){
        output=$($ssh root@$esx_server "vim-cmd vmsvc/snapshot.get $1")
        echo $output | grep -q "|-ROOT"
        if [ $? -eq 1 ];then
                return 2
        fi

        if [ -n "$2" ];then
                echo $output | grep -q "$2"
                if [ $? -eq 0 ];then
                        echo "Snapshot \"$snapname\" created"; return 0
                else
                        return 1
                fi
        fi
}

snapshot() {
        uniq=`$ssh root@$esx_server "vim-cmd vmsvc/snapshot.get $1|grep 'Snapshot Name'"`
        echo $uniq |grep -o ": $2" > /dev/null
        if [ $? -eq 1 ]
        then 
                echo "Creating snapshot \"$snapname\"..."
                $ssh root@$esx_server "vim-cmd vmsvc/snapshot.create $1 \"$2\" \"  \" 1" > /dev/null
                while true;do
                        snapshotcheck "$1" "$2" && break
                        sleep 10s
                done
        else
                echo "Snapshotname \"$2\" already exists" 
        fi
}

snapid2snapname(){
	snaplist=$(snapshotlist $1)
	echo "$snaplist"|grep -E -A1 "\-*$2\)"| sed -n 's/-*Snapshot Name\s*: \(.*\)/\1/p'
}

revert(){
	snapname="$2"
	if [ -n "$snapid" ];then
		snapname=$(snapid2snapname $1 $snapid)
	fi
		
	if [ -z "$snapname" ];then
		echo "There is no snapshot with ID: $snapid"
		cleanup
	fi

        snaplevel=`$ssh root@$esx_server "vim-cmd vmsvc/snapshot.get $1 | grep '$snapname' | egrep -o '\-*'| wc -c"`

        if [ ! $snaplevel -eq 0 ]
        then
                snaplevel=$(( $snaplevel/2-1)) 
                $ssh root@$esx_server "vim-cmd vmsvc/snapshot.revert $1 suppressPowerOff $snaplevel" > /dev/null
                echo "Reverted to snapshot: $snapname"
        else
                echo "No snapshot with specified name: $snapname"
        fi


}

snapshotremove(){
        if [ ! -z $3 ]
        then
                $ssh root@$esx_server "vim-cmd vmsvc/snapshot.removeall $1" > /dev/null
                echo "Removing all snapshots..."
                while true;do
                        snapshotcheck "$1"
                        if [ $? -eq 2 ];then
                                echo "All snapshots removed"; break
                        fi
                        sleep 10s
                done
        else	
		snapname="$2"
		if [ -n "$snapid" ];then
			snapname=$(snapid2snapname $1 $snapid)
		fi
		
		if [ -z "$snapname" ];then
			echo "There is no snapshot with ID: $snapid"
			cleanup
		fi
                snaplevel=$($ssh root@$esx_server "vim-cmd vmsvc/snapshot.get $1 | grep '$snapname' | egrep -o '\-*'| wc -c")

                if [ ! $snaplevel -eq 0 ]
                then
                        snaplevel=$(( $snaplevel/2-1)) 
                        $ssh root@$esx_server "vim-cmd vmsvc/snapshot.remove $1 1 $snaplevel" > /dev/null
                        while true;do
                                snapshotcheck "$1" "$snapname"
                                if [[ $? -eq 1 || $? -eq 2 ]];then
                                        echo "Snapshot \"$snapname\" removed"; break
                                fi
                                sleep 10s
                        done
                else
                        echo "No snapshot with specified name: $2"
                fi
        fi   

}

snapshotlist(){

        output=$($ssh root@$esx_server "vim-cmd vmsvc/snapshot.get $1")
        echo "$output" | grep -q "|-ROOT"
        if [ $? -eq 1 ];then
                echo "No snaphots created for this VM"
        else
        	tempfile=/tmp/snapshotlist-`date +%s`-$RANDOM

        	echo "$output" > $tempfile

		snapcounter=1

        	while read line 
        	do
			echo $line | grep -q '|-'
			if [ $? -eq 0 ];then
				line=$(echo $line | sed "s/|-/$snapcounter)/")
				((snapcounter++))
			fi
			echo $line
        	done < $tempfile

        	rm -f $tempfile
        fi
}


clone(){
        powerstate $1

        if [[ "$pwstate" = "Powered on"  ]]; then
                echo "You should switch the VM off before cloning. Please make a correct shutdown of the running OS or try '--poweroff $1'"
                cleanup
        fi

        #yesno "This operation will remove all snapshots from the source Virtual Machine! Are you sure to proceed?"

        #echo "Removing all snapshots..." 
        #$ssh root@$esx_server "vim-cmd vmsvc/snapshot.removeall $1" > /dev/null

        #while true;do
        #	snapshotcheck $1
        #	if [ $? -eq 2 ];then
        #	break
        #	fi
        #	sleep 5s
        #done
        target_datastore="$datastore"

        vmid2datastore $1
        vmid2relpath $1 
        oldname=$(vmid2name $1; echo $name)
        if [ -z "$name" ];then
                name="Clone of $oldname "$(date +"%d-%m-%Y %T")
        fi

        relpath2vmdkpath

        $ssh root@$esx_server "mkdir '/vmfs/volumes/$target_datastore/$name' && vmkfstools -d thin -i '/vmfs/volumes/$datastore/$vmdkpath' '/vmfs/volumes/$target_datastore/$name/$name.vmdk' && cp '/vmfs/volumes/$datastore/$relpath' '/vmfs/volumes/$target_datastore/$name/$name.vmx'"
	
	clone_failed="0"
        if [ -n "$to_server" ]; then
		ssh="$ssh -t" # we need a terminal allocation for scp
                $ssh root@$esx_server "scp -r '/vmfs/volumes/$target_datastore/$name' 'root@$to_server:/vmfs/volumes/$target_datastore/'"
	        if [ $? -eq 0 ] ; then
                	echo "$name virtual machine transferred to $to_server"
               	else
                	echo "Secure copy(scp) of VM to $to_server failed"; clone_failed="1"
                fi
		$ssh root@$esx_server "cd '/vmfs/volumes/$target_datastore/$name' && rm ./* && cd .. && rmdir './$name'" # yes, i'm afraid of scripting rm -rf in any forms
                #here we are switching the server for the first time, no ssh master yet
                ssh='ssh'
                esx_server="$to_server"
        fi
	
	if [ "$clone_failed" != "1" ]; then
        vnc_port
        $ssh root@$esx_server "sed -i 's/displayname = \".*\"/displayname = \"$name\"/gI;s/\".*\.vmdk\"/\"$name.vmdk\"/g;s/RemoteDisplay.vnc.port = .*/RemoteDisplay.vnc.port = \"$vnc_port\"/gI' '/vmfs/volumes/$target_datastore/$name/$name.vmx'"
        $ssh root@$esx_server "vim-cmd solo/registervm '/vmfs/volumes/$target_datastore/$name/$name.vmx' && echo '\"$oldname\" was successfuly cloned to \"$name\"'"
	fi
}

remove() {
        powerstate $1

        vmid2name $1 || exit
        if [[ "$pwstate" = "Powered on"  ]]; then
                echo "You should switch the VM off before removal: try '--poweroff $1' first"
                return 1
        fi

        if yesno "Do you really want to delete $name ?" ; then
                output=$($ssh root@$esx_server "vim-cmd vmsvc/destroy $1 2>&1")
                if [ $? -eq 0 ] ; then
                        echo "$name virtual machine removed"; return 0
                else
                        echo "$output" | sed -n 's/msg = "\(.*\)".*/\1/p'; return 1
                fi
        fi
}

powerstate(){
        pwstate=$($ssh root@$esx_server "vim-cmd vmsvc/power.getstate $1 2>&1")
        if [ $? -eq 0 ] ; then
                pwstate=$(echo "$pwstate"|tail -1)
        else
                echo "$pwstate" | sed -n 's/msg = "\(.*\)".*/\1/p'; cleanup
        fi
}

vnc_conf(){
        if [ -n "$vnc_password" ] 
        then
                vnc_config="
RemoteDisplay.vnc.enabled = \"True\"
RemoteDisplay.vnc.port = \"$vnc_port\"
RemoteDisplay.vnc.password = \"$vnc_password\""
        else
                vnc_config="
RemoteDisplay.vnc.enabled = \"True\"
RemoteDisplay.vnc.port = \"$vnc_port\""
        fi
}
addvnc() {
        vmid2name $1
        vmid2datastore $1
        vmid2relpath $1
        vnc_check=`$ssh root@$esx_server "egrep 'RemoteDisplay.vnc.enabled = \"?True\"?' '/vmfs/volumes/$datastore/$relpath'"`
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

                $ssh root@$esx_server "echo -e \"$vnc_config\" >> 'vmfs/volumes/$datastore/$relpath' && vim-cmd vmsvc/reload $1"
        fi
}

dslist() {
        if [ -n "$vmfsonly" ]; then
                $ssh root@$esx_server "vim-cmd hostsvc/datastore/listsummary" | grep VMFS -B7 | grep name | sed -n 's/name = "\(.*\)",/\1/gp' |sed 's/^[ \t]*//;s/[ \t]*$//'|sort
        else
                $ssh root@$esx_server "vim-cmd hostsvc/datastore/listsummary" | grep name | awk {'print $3'} | sed 's/",*//g' | sort
        fi
}

dsbrowse() {

        $ssh root@$esx_server "ls -1 /vmfs/volumes/$1/" 	
}

export2desktop(){
        vmid2name $1 || cleanup
        vmid2datastore $1
        vmid2relpath $1
        relpath2vmdkpath
        export_dir=$name"_export"
        local_export_dir=${local_export_dir:-"./"}
        $ssh root@$esx_server "cd '/vmfs/volumes/$datastore/$(dirname "$relpath")' && mkdir './$export_dir' && vmkfstools -i '/vmfs/volumes/$datastore/$vmdkpath' -d 2gbsparse './$export_dir/$name.vmdk' && cp '/vmfs/volumes/$datastore/$relpath' './$export_dir' && sed -i 's/\".*\.vmdk\"/\"$name.vmdk\"/g' './$export_dir/$(basename "$relpath")'"
        $scp -r "root@$esx_server:'/vmfs/volumes/$datastore/$(dirname "$relpath")/$export_dir'" "$local_export_dir"
        $ssh root@$esx_server "rm -rf '/vmfs/volumes/$datastore/$(dirname "$relpath")/$export_dir'"
}

#virtual switch management

vswitcheslist()
{
        $ssh root@$esx_server "esxcfg-vswitch -l"
}

niclist()
{
        $ssh root@$esx_server "esxcfg-nics -l"
}

networks()
{
        nets=$($ssh root@$esx_server "vim-cmd vmsvc/get.networks $1 | sed -n 's/name = \"\(.*\)\",/\1/gp' | sed 's/^[ \t]*//;s/[ \t]*$//'")
        echo "$nets"| while read line
do
        counter=${counter:-1}
        echo "$counter) \"$line\""
        counter=$(($counter+1))
done
}

vswitchadd()
{
        $ssh root@$esx_server "esxcfg-vswitch -a $1 && esxcfg-vswitch -A \"$1 Network\" $1" && echo "Virtual switch \"$1\" created"
}

vswitchremove()
{
        $ssh root@$esx_server "esxcfg-vswitch -d $1"
}

portgroupcheck()
{
        $ssh root@$esx_server "esxcfg-vswitch -C \"$1\""
}

#Some before checks
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

        if [ $(portgroupcheck "$network_name") = 0 ];then
                echo "Virtual network \"$network_name\" does not exist"; cleanup
        fi

}


studio_before_filter ()
{
        if [[ ! $format =~ "(oemiso|vmx)" ]] ; then
                echo "--format should be specified as oemiso or vmx"; exit;
        fi


}	# ----------  end of function studio_before_filter  ----------

status()
{
        $ssh root@$esx_server "vim-cmd vmsvc/get.summary $status_id"| grep -E '(powerState|toolsStatus|hostName|ipAddress|name =|vmPathName|memorySizeMB|guestMemoryUsage|hostMemoryUsage)' | sed 's/^[ \t]*//;s/[ \t]*$//'
        $ssh root@$esx_server "vim-cmd vmsvc/device.getdevices $status_id|grep ISO" | sed 's/summary =/ISO =/g;s/^[ \t]*//;s/[ \t]*$//'
}

showvncport()
{
        vmid2datastore $1
        vmid2relpath $1
        get_vnc_port
        if [ $? -eq 0 ];then
                echo $vnc_conn_port; return 0
        else 
                return 1
        fi
}

#edit existing VM

editiso()
{
        vmid2datastore $1
        vmid2relpath $1
        $ssh root@$esx_server "grep -iq \.iso '/vmfs/volumes/$datastore/$relpath'"
        if [ $? -eq 0 ];then
                iso=${iso//\//\\/}
                $ssh root@$esx_server "sed -i 's/\.filename = \".*\.iso\"/\.filename = \"\/vmfs\/volumes\/$iso\"/' '/vmfs/volumes/$datastore/$relpath'"
                if [ $? -eq 0 ];then
                        echo "Successfuly changed ISO to $iso"
                fi
        else
                iso_config="
ide1:0.present = \"true\"
ide1:0.deviceType = \"cdrom-image\"
ide1:0.filename = \"/vmfs/volumes/$iso\"
ide1:0.startConnected = \"TRUE\""
                echo "$iso_config" | $ssh root@$esx_server "cat >> '/vmfs/volumes/$datastore/$relpath'"
                if [ $? -eq 0 ];then
                        echo "Successfuly added ISO: $iso"
                fi
        fi
}

editname()
{
        vmid2datastore $1
        vmid2relpath $1
        $ssh root@$esx_server "sed -i 's/displayname = \".*\"/displayname = \"$name\"/' '/vmfs/volumes/$datastore/$relpath'"
        if [ $? -eq 0 ];then
                echo "Successfuly changed name to \"$name\""
        fi
}

editnetwork()
{
        if [ $(portgroupcheck "$network_name") = 0 ];then
                echo "Virtual network \"$network_name\" does not exist"; cleanup
        fi

        vmid2datastore $1
        vmid2relpath $1

        $ssh root@$esx_server "sed -i 's/ethernet\(.\)\.networkName = \"VM Network\"/ethernet\1\.networkName = \"$network_name\"/' '/vmfs/volumes/$datastore/$relpath'"

        if [ $? -eq 0 ];then
                echo "Successfuly changed network to \"$network_name\""
        fi
}

editvncpass()
{
        vmid2datastore $1
        vmid2relpath $1
        get_vnc_port $1

        if [ $? -eq 1 ]; then
                cleanup 1
        fi

        if [ "$vnc_password" = '-i' ];then
                vnc_password=''
                vnc_pass
        fi

        if [ $no_vnc_password -eq 1 ]; then
                $ssh root@$esx_server "sed -i '/RemoteDisplay\.vnc\.password.*/d;/RemoteDisplay\.vnc\.key.*/d' '/vmfs/volumes/$datastore/$relpath'"
        else
                $ssh root@$esx_server "grep -q 'RemoteDisplay.vnc.password' '/vmfs/volumes/$datastore/$relpath'"
                if [ $? -eq 0 ]; then
                        $ssh root@$esx_server "sed -i 's/RemoteDisplay.vnc.password = \".*\"/RemoteDisplay.vnc.password = \"$vnc_password\"/' '/vmfs/volumes/$datastore/$relpath'"
                else
                        $ssh root@$esx_server "sed -i '/RemoteDisplay.vnc.port = \".*\"/ a\
                                RemoteDisplay.vnc.password = \"$vnc_password\"' '/vmfs/volumes/$datastore/$relpath'"
                fi
        fi

        if [ $? -eq 0 ];then
                echo "VNC password successfuly changed."
        fi 
}

eval set -- `getopt -n$0 -a  --longoptions="vncpass: novncpass ds: iso: vmdk: vnc: help status: poweron: poweroff: reset: snapshot: snapshotremove: all revert: clone: remove: addvnc: bios dslist vmfs dsbrowse: snapshotlist: snapname: snapid: apiuser: apikey: appliances buildimage: buildstatus: studio: studioserver: format: export: networks: vswitches nics vswitchadd: vswitchremove: network: autoyast: showvncport: toserver:" "hclyn:s:m:d:e:" "$@"` || usage 
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
     -e)  edit_vmid="$2";shift;;
     -y)  globalyes="1";;
     --vncpass) vnc_password="$2";shift;;
     --novncpass) no_vnc_password=1;;
     --iso) iso="$2";shift;;
     --vmdk) vmdk="$2";shift;;
     --status) status_id="$2";shift;;
     --bios) bios_once="1";shift;;
     --poweron) power_on_vmid=$2;shift;;
     --poweroff) power_off $2 ;exit;;
     --reset) reset $2; exit;;
     --snapshot) snap_vmid=$2;shift;;
     --revert) revert_vmid=$2;shift;;
     --remove) remove_vmid=$2;shift;;
     --vnc) vnc="$2";shift;;
     --addvnc) addvnc_vmid="$2";shift;;
     --dslist) dslist="1";;
     --vmfs) vmfsonly="1";;
     --dsbrowse) dsbrowse="$2";shift;;
     --snapshotlist) snapshotlist_vmid="$2";shift;;
     --snapname) snapname="$2";shift;;
     --snapid) snapid="$2";shift;;
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
     --format) format="$2";shift;;
     --clone) clone_id="$2";shift;;
     --export) export_id="$2";shift;local_export_dir="$3";shift;;
     --vswitches) vswitcheslist="1";shift;;
     --nics) niclist="1";shift;;
     --networks) networks_id="$2";shift;;
     --vswitchadd) vswitch_add_name="$2";shift;;
     --vswitchremove) vswitch_remove_name="$2";shift;;
     --network) network_name="$2";shift;;
     --autoyast) autoyast="$2";shift;;
     --showvncport) showvncport_vmid="$2";shift;;
     --toserver) to_server="$2";shift;;
     -h) usage; exit ;;
     --help) usage; exit ;;
     --)        shift;break;;
     -*)        usage;;
     *)         break;;        
     esac
     shift
done

[ ! -z $esx_server ] && control_master 

[[ -n $esx_server && ! -z $list ]] && initial_info && cleanup

# iso file check
if [[ -n $esx_server && ! -z "$iso" ]];then	
        $ssh root@$esx_server "test -e '/vmfs/volumes/$iso'"
        [ $? -eq 1 ] && echo "ISO image does not exist on datastore" && cleanup
fi

# vmdk file check
if [[ -n $esx_server &&  -n $vmdk ]]; then
        $ssh root@$esx_server "test -e '/vmfs/volumes/$vmdk'"
        [ $? -eq 1 ] && echo "VMDK image does not exist on datastore" && cleanup
fi

#Reasonable defaults
datastore=${datastore:-datastore1}
studioserver=${studioserver:-susestudio.com} #susestudio.com is default server
format=${format:-vmx} #default image format is vmx
ram=${ram:-512}
disk=${disk:-5G}
network_name=${network_name:-"VM Network"}
no_vnc_password=${no_vnc_password:-0} #Usually we want VNC password to be set

if [ ! -z $studio ] ; then
        checkimage "$apiuser" "$apikey" "$studio"

        if [ $format = "vmx" ] ; then
                if [ $arch = "i586" ] ; then
                        arch="i686"
                fi
                appliance_name=${appliance_name// /_}
                appliance_name=$(strip_chars "$appliance_name")
                short_name="$appliance_name-$version"
                name=${name:-$appliance_name.$arch-$version}
        fi


fi

#strip all potential insecure characters from vm name
name=$(strip_chars "$name")

if [[ ! -z $create_new  && -n $esx_server && -n $ram && -n $disk && -n $name ]]
then
        before_filter
        vnc_pass
        vnc_port
        vnc_conf
        register_vm	
        cleanup
fi

#edit
if [[ -n $esx_server && -n $edit_vmid ]];then
        powerstate $edit_vmid

        if [[ "$pwstate" = "Powered on"  ]]; then
                echo "You should switch the VM off before configuration change. Please make a correct shutdown of the running OS or try '--poweroff $edit_vmdid'"
                cleanup
        fi

        if [ -n "$iso" ]; then
                editiso $edit_vmid;
        fi

        if [ -n "$name" ]; then
                editname $edit_vmid;
        fi

        if [[ -n "$network_name" && "$network_name" != "VM Network" ]];then
                editnetwork $edit_vmid
        fi
        
        if [[ -n "$vnc_password" || $no_vnc_password -eq 1 ]]; then
                editvncpass $edit_vmid
        fi

        $ssh root@$esx_server "vim-cmd vmsvc/reload $edit_vmid"

        cleanup
fi

#clone

if [[ -n $esx_server && -n $clone_id ]];then
        clone $clone_id; cleanup
fi

#export
if [[ -n $esx_server && -n $export_id ]];then
        export2desktop $export_id; cleanup
fi
#power on and bios up
if [ ! -z $power_on_vmid ]
then
        power_on $power_on_vmid; cleanup
fi

#dslist execution
if [[  -n $esx_server && ! -z $dslist ]] 
then dslist ; cleanup
fi

#dsbrowse execution
if [[  -n $esx_server && ! -z $dsbrowse ]] 
then  dsbrowse $dsbrowse ; cleanup
fi

#snapshotlist execution
if [[  -n $esx_server && ! -z $snapshotlist_vmid ]] 
then  snapshotlist $snapshotlist_vmid; cleanup
fi

#snapshotremove execution
if [[  -n $esx_server && ! -z $snapshotremove_vmid ]];then  
   if [[ -n $snapname || -n $snapid ]];then
	snapshotremove $snapshotremove_vmid "$snapname" $all; cleanup
   fi
fi

if [[  -n $esx_server && ! -z $vnc ]] 
then  vmid2name $vnc && vmid2datastore $vnc && vmid2relpath $vnc && get_vnc_port && vnc_connect ; cleanup
fi

#snapshot
if [[  -n $esx_server && ! -z $snap_vmid ]]
then snapname=${snapname:-$(echo "snapshot"$(date +"%d-%m-%Y %T"))}; snapshot $snap_vmid "$snapname"; cleanup
fi
#snapshot revert
if [[  -n $esx_server && ! -z $revert_vmid ]];then 
   if [[ -n $snapname || -n $snapid ]];then
	revert $revert_vmid "$snapname"; cleanup
   fi
fi

if [[  -n $esx_server && ! -z $remove_vmid ]]
then remove $remove_vmid; cleanup
fi

if [[  -n $esx_server && ! -z $addvnc_vmid ]]
then addvnc $addvnc_vmid; cleanup
fi

#studio
if [[ -n $apiuser &&  -n $apikey && ! -z $appliances ]]
then appliances "$apiuser" "$apikey";  exit
fi

if [[ -n $apiuser &&  -n $apikey && ! -z $buildimage ]]
then buildimage "$apiuser" "$apikey" "$buildimage"; exit
fi

if [[ -n $apiuser &&  -n $apikey && ! -z $buildstatus ]]
then buildstatus "$apiuser" "$apikey" "$buildstatus"; exit
fi

#status
if [ -n "$status_id" ];then
        status
        cleanup
fi

if [ -n "$showvncport_vmid" ];then
        showvncport $showvncport_vmid && cleanup
        cleanup 1
fi
#network

if [ -n "$networks_id" ];then
        echo "Network Port Group(s): "
        networks $networks_id
        cleanup
fi 
if [ -n "$vswitcheslist" ];then
        vswitcheslist; cleanup
fi

if [ -n "$niclist" ];then
        niclist; cleanup
fi


if [ -n "$vswitch_add_name" ];then
        vswitchadd $vswitch_add_name
        cleanup
fi 

if [ -n "$vswitch_remove_name" ];then
        vswitchremove $vswitch_remove_name
        cleanup
fi 

usage
cleanup
