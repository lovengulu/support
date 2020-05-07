#!/bin/bash

#NVIDIA Driver installer for GPU cards
#Parttialy Based on instruction from: https://gist.github.com/wangruohui/df039f0dc434d6486f5d4d098aa52d07
#
#Instructions:
#run the script first time to perform the actions listed below in install_step1()
#reboot the system when instructed
#run the script once again and add parameter '--cont' to continue the install process with the actions listed in install_step2()
#
#The script will install the latest Nvidia driver. However, if earlier version is needed,
#set the parameter 'NVIDIA_DRIVER_VER' according the instructions below

# Known issues:
# - not running with '--dkms' (tested on rhel7). Kernel upgrade require returning this procedure again (or at least running the 'run' file).

#
# NVIDIA_DRIVER_VER
#
# Leave this parameter empty to let the script search the latest driver version
# or fill with a specific version to use.
# For example, if the device is "NVIDIA Corporation GT218 [GeForce 210]", later version may not work,
# so set the version to "340.108".
# for list of available versions consult: https://www.nvidia.com/en-us/drivers/unix/
NVIDIA_DRIVER_VER=""

# log of this script will be written to the following file
LOGFILE=/tmp/nvidia_install.log


function get_distro {
    if [ -e "/etc/redhat-release" ]; then
        echo "rhel"
    elif [ -e "/etc/SuSE-release" ]; then
        echo "sles"
    elif [ -e "/etc/os-release" ]; then
        cat /etc/os-release | grep '^ID=' | sed -e 's/.*=//' | tr -d '"'
    else
        echo "undef"
    fi
}

function get_os_version_id {
    cat /etc/os-release | grep VERSION_ID | sed -e 's/.*=//' | tr -d '"'
}

function is_nvidia_gpu_exists {
    # TODO: Confirm again that VGA is not needed to be in the lspci response
    #return $(lspci | grep VGA | grep -q "NVIDIA Corporation")
    return $(lspci | grep -q "NVIDIA Corporation")
}

function is_nvidia_driver_installed {
    return $(lsmod | grep -iq nvidia)
}

function is_nouveau_driver_installed {
    return $(lsmod | grep -iq nouveau)
}

function blacklist_nuovo_driver {
    local black_list_file=/etc/modprobe.d/blacklist-nouveau.conf
    if [ ! -f ${black_list_file} ]; then
        LOG "INFO: creating Blacklist for Nouveau Driver at ${black_list_file}"
        echo 'blacklist nouveau'         >> ${black_list_file}
        echo 'options nouveau modeset=0' >> ${black_list_file}
    else
        # TODO: add test the content of the file to confirm the content
        LOG  "INFO: Nouveau Blacklist file: $black_list_file already exists"
    fi
}

function LOG {
    DATE=$(date +%Y-%m-%d_%H:%M:%S)
    log_msg="$DATE - ${@:1}"
    echo $log_msg
    echo $log_msg >> $LOGFILE
}

function install_dependencies {
    # TODO: add curl
    # install the dependencies for the various distros
    local OS_DISTRO=$(get_distro)
    local OS_VER=$(get_os_version_id)

    if   [ "${OS_DISTRO}" == "rhel" ]; then
        yum install epel-release dkms libstdc++.i686 -y
        yum install dkms  -y
    elif [ "${OS_DISTRO}" == "ubuntu" ]; then
        apt-get install build-essential gcc-multilib dkms -y
        apt-get install curl -y
    elif [ "${OS_DISTRO}" == "FEDORA" ]; then
        dnf install dkms libstdc++.i686 kernel-devel -y
    else
        LOG "ERROR: unable to find the dependencies for distro: ${OS_DISTRO}"
        LOG "       Please resolve and run again"
        exit 1
    fi

    if [ "$?" -eq 0 ];then
        LOG "INFO: 'install_dependencies()' completed successfully"
    else
        LOG "WARN: 'install_dependencies()' did NOT completed successfully"
        LOG "       Please resolve and run again"
        exit 1
    fi
}

function install_step1 {
    OS_DISTRO=$(get_distro)
    OS_VER=$(get_os_version_id)

    LOG "INFO: starting Nvidia drivers install script"
    LOG "INFO: Identified OS distribution: ${OS_DISTRO}-${OS_VER}"

    #TODO: fix here to support other distros
    if [ "${OS_DISTRO}" != "rhel" ]; then
        LOG "ERROR: Currently supporting RHEL only. your OS distribution is ${OS_DISTRO}"
        #exit 1
    fi

    if ! $(is_nvidia_gpu_exists); then
        LOG "WARN: Unable to find Nvidia GPU. exiting"
        exit 1
    fi

    if $(is_nvidia_driver_installed); then
        LOG "INFO: Found Nvidia drivers. Nothing to do."
        exit 0
    fi

    if $(is_nouveau_driver_installed); then
        LOG "INFO: Found nouveau drivers as follows:"
        found_nouveau=$(lsmod | grep -i nouveau | sed "s/^/      /")
        LOG "${found_nouveau}"
    fi

    install_dependencies
    blacklist_nuovo_driver

    if [ "${OS_DISTRO}" == "rhel" ]; then
        LOG "INFO: running 'dracut --force'"
        dracut --force
        ret_code=$?
        LOG "INFO: 'dracut' completed with error code: ${ret_code}"
        if [ "${ret_code}" -eq 0 ];then
            LOG "INFO: 'dracut' completed successfully"
        else
            LOG "INFO: Please resolve the error manually."
            LOG "      After resolving, please reboot the system and run this script again"
            LOG "      to continue this install procedure."
        fi
    elif [ "${OS_DISTRO}" == "ubuntu" ]; then
        if [ $(echo ${OS_VER} | awk -F. '{print $1}') -ge 16 ]; then
            update-initramfs -u
            ret_code=$?
            LOG "INFO: 'update-initramfs' completed with error code: ${ret_code}"
        fi
    fi

    if [ "${ret_code}" -eq 0 ];then
        LOG "INFO: action completed successfully"
    else
        LOG "INFO: Please resolve the error manually."
        LOG "      After resolving, please reboot the system and run this script again"
        LOG "      to continue this install procedure."
    fi
}

function install_step2 {
    nvidia_drivers_page_url='https://www.nvidia.com/en-us/drivers/unix/'
    if [ -z "${NVIDIA_DRIVER_VER}" ]; then
        # figure out the latest vers
        results=$(curl ${nvidia_drivers_page_url} | grep 'Latest Long Lived Branch Version' | sed -e "s%<[^>]*>%%g" |uniq )
        if [ $(echo "${results}" | wc -l) -eq 1 ];then
             NVIDIA_DRIVER_VER=$(echo "${results}" | sed "s/.*Latest Long Lived Branch Version://" | sed "s/[[:space:]]//g")
        else
            LOG "ERROR: Unable to find the latest NVIDIA driver from ${nvidia_drivers_page_url}"
            LOG "       Please locate manually the needed driver and set NVIDIA_DRIVER_VER accordingly"
            exit 1
        fi
    fi

    LOG "INFO: Downloading Nvidia drivers ver ${NVIDIA_DRIVER_VER}"
    NVIDIA_DRIVER_DOWNLOAD_URL="http://us.download.nvidia.com/XFree86/Linux-x86_64/${NVIDIA_DRIVER_VER}/NVIDIA-Linux-x86_64-${NVIDIA_DRIVER_VER}.run"
    cd /tmp
    run_filename=$(basename ${NVIDIA_DRIVER_DOWNLOAD_URL})
    wget ${NVIDIA_DRIVER_DOWNLOAD_URL} --output-document ${run_filename}
    if [ "$?" -ne "0" ]; then
        LOG "ERROR: Unable to download file from ${NVIDIA_DRIVER_DOWNLOAD_URL}"
        LOG "Please resolve and try again"
        exit 1
    fi
    chmod a+x ${run_filename}

    # TODO: it is better to run with '--dkms' so this installs is not lost on kernel upgrade. Unable to get it to work on Centos.
    ./${run_filename}  --dkms -s
    # ./${run_filename}  -s
    ret_code=$?
    LOG "INFO: '${run_filename}' completed with error code: ${ret_code}"
    if [ "${ret_code}" -ne 0 ];then
        LOG "ERROR: Issue fount while running ${run_filename} from Nvidia. Please resolve manually"
        exit 1
    fi

    LOG "Will now run 'nvidia-smi' to verify drivers installed correctly"
    nvidia-smi
    ret_code=$?
    LOG "INFO: 'nvidia-smi' completed with error code: ${ret_code}"
    if [ "${ret_code}" -ne 0 ];then
        LOG "ERROR: Issue fount while running 'nvidia-smi' from Nvidia. Please resolve manually"
        exit 1
    fi

    LOG "INFO: install_step2() completed successfully"
}

#######  MAIN ############

if [ -z "$1" ]; then
     install_step1
     LOG "INFO: Please reboot the system and run \"$0 --cont\" to continue this install procedure"
elif [ $(echo $1 | grep '\-cont') ]; then
     install_step2
     LOG "INFO: install procedure completed successfully."
     LOG "      It is suggested to confirm again by rebooting and running 'nvidia-smi' once again"
fi




function my_scratch_area {
    lspci | grep VGA | grep "NVIDIA Corporation" ; echo $?

    lsmod  | grep -i ^nvidia
    lsmod  | grep -i ^nouveau

    nvidia-smi

    ls -ltr /usr/lib /usr/lib64 | grep -i nvidia
    rpm -qa | grep -i nvidia
    yum list | grep -i nvidia

}

