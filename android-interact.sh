#!/bin/bash
set -x
# File: android-interact.sh
# Date: Wed Nov 29 02:19:00 2017 -0800
# Author: Yuxin Wu

function ensure_user {
    if [ $USERHASH ];then
        echo  "USERHASH var found"
    else
        echo "USERHASH var not found"
        exit 1
    fi
}

function sudo {
   adb shell "su -c '$*'"
}

function adbpull {
    path=$1
    filename=$2
    adb shell "su -c 'cd $path && busybox tar czf - $filename 2>/dev/null|busybox base64'"|base64 -di|tar xzf -

    [[ -e $d ]] || {
        >&2 echo "Failed to download file/directory: $path/$filename"
        exit 1
    }

}

PROG_NAME=`python -c "import os, sys; print(os.path.realpath(sys.argv[1]))" "$0"`
PROG_DIR=`dirname "$PROG_NAME"`
cd "$PROG_DIR"

source compatibility.sh

# Please check that your path is the same, since this might be different among devices
RES_DIR="/mnt/sdcard/tencent/MicroMsg"
MM_DIR="/data/data/com.tencent.mm"

#echo "Starting rooted adb server..."
#adb root

if [[ $1 == "uin" ]]; then
    #	adb pull $MM_DIR/shared_prefs/system_config_prefs.xml 2>/dev/null
        adbpull $MM_DIR/shared_prefs system_config_prefs.xml
	uin=$($GREP 'default_uin' system_config_prefs.xml | $GREP -o 'value=\"\-?[0-9]*' | cut -c 8-)
	[[ -n $uin ]] || {
		>&2 echo "Failed to get wechat uin. You can try other methods, or report a bug."
		exit 1
	}
	rm system_config_prefs.xml
	echo "Got wechat uin: $uin"
elif [[ $1 == "imei" ]]; then
	imei=$(adb shell dumpsys iphonesubinfo | $GREP 'Device ID' | $GREP -o '[0-9]+')
	[[ -n $imei ]] || {
		imei=$(adb shell service call iphonesubinfo 1 | awk -F "'" '{print $2}' | sed 's/[^0-9A-F]*//g' | tr -d '\n')
	}
	[[ -n $imei ]] || {
		>&2 echo "Failed to get imei. You can try other methods mentioned in README, or report a bug."
		exit 1
	}
	echo "Got imei: $imei"
elif [[ $1 == "db" || $1 == "res" || $1 == "avt" ]]; then
	echo "Looking for user dir name..."
	sleep 1  	# sometimes adb complains: device not found
        if [ $1 == "res" ]; then
            userdir=$RES_DIR
        else
            userdir="$MM_DIR/MicroMsg"
        fi
	# look for dirname which looks like md5 (32 alpha-numeric chars)
	userList=$(sudo ls $userdir | cut -f 4 -d ' ' | sed 's/[^0-9a-z]//g' \
		| awk '{if (length() == 32) print}')
	numUser=$(echo "$userList" | wc -l)
        ensure_user
        chooseUser=$USERHASH
        parentdir="$userdir/$chooseUser"
	# [[ -n $parentdir ]] || {
	# 	>&2 echo "Could not find user. Please check whether your target dir is $parentdir"
	#  	exit 1
	# }
	echo "Found $numUser user(s). User chosen: $chooseUser"

	if [[ $1 == "res" ]]; then
		mkdir -p resource; cd resource
		echo "Pulling resources... "
		for d in avatar image2 voice2 emoji video sfs; do
			adb shell "cd $parentdir &&
								 busybox tar czf - $d 2>/dev/null | busybox base64" |
					base64 -di | tar xzf -

			[[ -d $d ]] || {
				>&2 echo "Failed to download resource directory: $parentdir/$d"
				exit 1
			}
		done
		cd ..
		echo "Resource pulled at ./resource"
		echo "Total size: $(du -sh resource | cut -f1)"
	elif [[ $1 == "db" ]]; then
	        echo "Pulling database file..."
                adbpull $parentdir  EnMicroMsg.db
        else
	        echo "Pulling avatar file..."
		mkdir -p avatar
                adbpull $parentdir avatar
		echo "Avatar pulled at ./avatar"
		echo "Total size: $(du -sh avatar | cut -f1)"
	fi
elif [[ $1 == "db-decrypt" ]]; then
	set -e
	echo "Getting uin..."
	$0 uin | tail -n1 | $GREP -o '\-?[0-9]*' | tee /tmp/uin
	echo "Getting imei..."
	$0 imei | tail -n1 | $GREP -o '[0-9]*' | tee /tmp/imei
#	echo "Getting db..."
#	$0 db
	echo "Decrypting db..."
	imei=$(cat /tmp/imei)
	uin=$(cat /tmp/uin)
	if [[ -z $imei || -z $uin ]]; then
		>&2 echo "Failed to get imei or uin. See README for manual methods."
		exit 1
	fi
	./decrypt-db.py EnMicroMsg.db $imei $uin
	rm /tmp/{uin,imei}
	echo "Done. See decrypted.db"
else
	echo "Usage: $0 <res|db-decrypt>"
	exit 1
fi

