#!/bin/bash -x

# Push BATS tests to test VMs
#
# e.g ${WORKSPACE}/scripts/pushtests.sh 'hostname'

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

# copy our tests to the test servers
echo "Setting up ssh keys for test server $TEST_VM"
ssh-keygen -R $TEST_VM

ssh_opts="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null"

# Copy Jenkins' SSH key to the newly created server(s)
if [ $(sed -e 's/^.*release //' -e 's/\..*$//' /etc/redhat-release) -ge 7 ]; then
  # Only starting with RHEL 7 does ssh-copy-id support -o parameter
  setsid ssh-copy-id ${ssh_opts} root@$TEST_VM
else # Workaround for RHEL 6 and before
  setsid ssh ${ssh_opts} root@$TEST_VM 'true'
  setsid ssh-copy-id root@$TEST_VM
fi

echo "Installing bats and rsync on test server $TEST_VM"
if ssh ${ssh_opts} root@$TEST_VM "yum install -y bats rsync"; then
  echo "copying tests to test server $TEST_VM"
  rsync --delete -va -e "ssh ${ssh_opts}" tests/bats_tests root@$TEST_VM:
else
  echo "Couldn't install rsync and bats on '$TEST_VM'."
  exit 1
fi

echo "Installing pytest on test server $TEST_VM"
if ssh ${ssh_opts} root@$TEST_VM "yum install -y pytest python-psutil"; then
  rsync --delete -va -e "ssh ${ssh_opts}" tests/unit_tests root@$TEST_VM:
else
  echo "Couldn't install pytest on '$TEST_VM'."
  exit 1
fi


# Define which host-group the host is in for custom testing
HOST_GROUP=$(ssh ${ssh_opts} root@$TEST_VM "grep Group /etc/soe-release" | cut -f1 -d/ | awk '{print $3}')
RHELVER=$(ssh ${ssh_opts} root@$TEST_VM "grep Built /etc/soe-release" | awk '{ print $11 }' | cut -f1 -d.)

# execute the tests in parallel on all test servers
mkdir -p test_results
echo "Starting TAPS tests on test server $TEST_VM"
if [ -z "${HOST_GROUP}" ]; then
  ssh ${ssh_opts} root@$TEST_VM \
    'cd bats_tests ; bats -t *.bats' > test_results/$TEST_VM.tap &
else
  ssh ${ssh_opts} root@$TEST_VM \
    "cd bats_tests ; bats -t *.bats ${HOST_GROUP}/*.bats" > test_results/$TEST_VM.tap &
fi

# wait until all backgrounded processes have exited
wait


## jUnit (pytest) Testing

# We need to set a few environment vars on the test host to set up the unit tests.
# AUTH_TYPE = POSIX|AD|IPA
# HOMEDIRS  = LOCAL|AUTOFS

# pytest syntax change between RHEL6 and 7
if [ $RHELVER -eq 6 ]; then
  ssh ${ssh_opts} root@$TEST_VM \
    "cd unit_tests ; py.test-2.6 --junitxml=${TEST_VM}.xml --junitprefix=${TEST_VM}" &
else
  ssh ${ssh_opts} root@$TEST_VM \
    "cd unit_tests ; py.test --junit-xml=${TEST_VM}.xml --junit-prefix=${TEST_VM}" &
fi

# wait until all backgrounded processes have exited
wait

# Pull the test results back
rsync -va -e "ssh ${ssh_opts}" root@$TEST_VM:unit_tests/*.xml test_results/

exit 0
