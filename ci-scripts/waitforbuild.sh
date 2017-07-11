#!/bin/bash -x

# Wait for VMs to build
#
# e.g ${WORKSPACE}/scripts/waitforbuild.sh 'hostname'

# Read in common parameter variables
ORG=$1
SATELLITE=$2
SAT_USER=$3

# Script-specific input
TEST_VM=$4

# we need to wait until all the test machines have been rebuilt by foreman
buildvm=true

WAIT=0
while [[ ${buildvm} = true ]]; do
  echo "Waiting 30 seconds"
  sleep 30
  ((WAIT+=30))
  echo -n "Checking if test server $TEST_VM has rebuilt... "
  status=$(ssh -q -l ${SAT_USER} ${SATELLITE} \
      "hammer host info --name $TEST_VM | \
       grep -e \"Managed.*yes\" -e \"Enabled.*yes\" -e \"Build.*no\" | wc -l")
  # Check if status is OK, ping reacts and SSH is there, then success!
  if [[ ${status} == 3 ]] && ping -c 1 -q $TEST_VM && nc -w 1 $TEST_VM 22; then
    # A PXE install takes at least 5 minutes. Detect if the VM simply rebooted without
    #   rebuilding and return a fail if it did.
    if [[ ${WAIT} -lt 300 ]]; then
      echo "Test server looks to have simply rebooted without rebuilding. Exiting."
      exit 1
    else
      echo "Success!"
      unset buildvm
    fi
  else
    echo "Not yet."
  fi
  if [[ ${WAIT} -gt 3600 ]]; then
    echo "Test servers still not rebuilt after 60 minutes. Exiting."
    exit 1
  fi
done

