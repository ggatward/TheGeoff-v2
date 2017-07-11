#!/bin/bash -x

# Prepare RHEL hosts to become VM Templates
#
# e.g ${WORKSPACE}/scripts/sysprep.sh 'hostname'

# Read in common parameter variables
ORG=$1
SATELLITE=$2
SAT_USER=$3

# Script-specific input
TEST_VM=$4
ROOTPASS=$5

# Setup the Root password for test host - passed to us from the Jenkins Credential Store
export ROOTPASS
export SSH_ASKPASS=./ci-scripts/askpass.sh
export DISPLAY=nodisplay

# Setup SSH for the test server
echo "Setting up ssh keys for test server $TEST_VM"
ssh-keygen -R $TEST_VM

ssh_opts="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null"

echo "Unconfiguring Network"
ssh ${ssh_opts} root@$TEST_VM "rm -f /etc/udev/rules.d/70-persistent-net.rules"

# Find the interface name for the host
iface=$(ssh ${ssh_opts} root@$TEST_VM "ip route get 8.8.8.8 | grep 'via' | awk '{ print \$5 }'")

ssh ${ssh_opts} root@$TEST_VM \
  "echo -e \"DEVICE=${iface}\nBOOTPROTO=none\nONBOOT=yes\" >/etc/sysconfig/network-scripts/ifcfg-${iface}"

# May also need to update these files, but it seems they may not exist (yet) on our builds
#/etc/sysconfig/networking/devices/ifcfg-${iface}
#/etc/sysconfig/networking/profiles/default/ifcfg-${iface}


echo "Unsubscribing from Satellite"
#ssh ${ssh_opts} root@$TEST_VM "subscription-manager unsubscribe --all"
#ssh ${ssh_opts} root@$TEST_VM "subscription-manager unregister"
ssh ${ssh_opts} root@$TEST_VM "subscription-manager clean"
ssh ${ssh_opts} root@$TEST_VM "yum -y remove katello-ca-consumer*"

# We can't remove the SSH keys as we still need to login remotely later!
echo "Powering off"
ssh ${ssh_opts} root@$TEST_VM "shutdown -h +1"

# Finally we need to sleep for at least a minute to allow the VM to power off
sleep 70

