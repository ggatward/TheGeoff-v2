#!/bin/bash

# Instruct Satellite to rebuild the given VM


# Read in common parameter variables
ORG=$1
SATELLITE=$2
SAT_USER=$3

# Script-specific input
TEST_VM=$4
BOOT_METHOD=$5


# Reset the build flag - if it is already yes, set to no first to reset satellite token
ssh -q -l ${SAT_USER} ${SATELLITE} "hammer host update --id $TEST_VM --build no"
ssh -q -l ${SAT_USER} ${SATELLITE} "hammer host update --id $TEST_VM --build yes"


# We have (currently) 3 methods for rebooting the test VMs:
#  - sat6    : Sat6 is integrated to the virtualisation plaform and can reboot VMs via hammer
#  - vmware  : No Sat6/VMware integration but Jenkins can reboot via vCenter
#  - manual  : No integration at all - VMs must be manually rebooted by a human
# 
# Sat6 method:
if [ "$BOOT_METHOD" == "sat6" ]; then
  _PROBED_STATUS=$(ssh -q -l ${SAT_USER} ${SATELLITE} "hammer host status --id $TEST_VM" | grep Power | cut -f2 -d: | tr -d ' ')

  # different hypervisors report power status with different words. parse and get a single word per status
  # - KVM uses running / shutoff
  # - VMware uses poweredOn / poweredOff
  # - libvirt uses up / down
  # add others as you come across them and please submit to https://github.com/ggatward/soe-ci-pipeline

  case "${_PROBED_STATUS}" in
    running)
      _STATUS=On
     ;;
    poweredOn)
      _STATUS=On
      ;;
    up)
      _STATUS=On
      ;;
    on)
      _STATUS=On
      ;;
    shutoff)
      _STATUS=Off
      ;;
    poweredOff)
      _STATUS=Off
      ;;
    down)
      _STATUS=Off
      ;;
    off)
      _STATUS=Off
      ;;
    *)
      echo "can not parse power status, please review $0"
      exit 1
  esac

  if [[ ${_STATUS} == 'On' ]]; then
    # Try --force. This may not work reliably (or at all) for VMware so try both ways
    ssh -q -l ${SAT_USER} ${SATELLITE} "hammer host stop --id $TEST_VM --force"
    sleep 2
    ssh -q -l ${SAT_USER} ${SATELLITE} "hammer host stop --id $TEST_VM"
    sleep 30
    ssh -q -l ${SAT_USER} ${SATELLITE} "hammer host start --id $TEST_VM"
  elif [[ ${_STATUS} == 'Off' ]]; then
    ssh -q -l ${SAT_USER} ${SATELLITE} "hammer host start --id $TEST_VM"
  else
    echo "Host $TEST_VM is neither running nor shutoff. No action possible!"
    exit 1
  fi
elif [ "$BOOT_METHOD" == "vmware" ]; then
  # Jenkins->vCenter method
  # We handle this via Jenkins plugin, so exit cleanly here to hand control back
  exit 0
else
  # MANUAL method
  echo "###########################################"
  echo "#  PLEASE REBOOT $TEST_VM MANUALLY NOW    #"
  echo "#                                         #"
  echo "# WAITING FOR 5 MINUTES BEFORE CONTINUING #"
  echo "###########################################"
  sleep 300
fi


