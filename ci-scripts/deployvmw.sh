#!/bin/bash

# Instruct Satellite to rebuild the given VM


# Read in common parameter variables
ORG=$1
SATELLITE=$2
SAT_USER=$3

# Script-specific input
TEST_VM=$4


# Gather facts about the existing VM
# TODO - need to cater for the case where the VM does not already exist
ssh -q -l ${SAT_USER} ${SATELLITE} "hammer host info --name $TEST_VM" > host_profile
LOC=$(cat host_profile | grep 'Location' | cut -f2 -d: | tr -d ' ')
HOSTGROUP=$(cat host_profile | grep 'Host Group' | cut -f2 -d: | tr -d ' ')
IP=$(cat host_profile | grep IP: | cut -f2 -d: | tr -d ' ')
SUBNET=$(cat host_profile | grep Subnet | cut -f2 -d: | tr -d ' ')
DOMAIN=$(cat host_profile | grep Domain | cut -f2 -d: | tr -d ' ')
OS=$(cat host_profile | grep 'Operating System' | cut -f2 -d: | sed -e 's/^[[:space:]]*//')
IMAGE=$(cat host_profile | grep Image | cut -f2 -d: | sed -e 's/^[[:space:]]*//')
LOCATION=$(cat host_profile | grep Location | cut -f2 -d: | sed -e 's/^[[:space:]]*//')
CRESOURCE=$(cat host_profile | grep 'Compute Resource' | cut -f2 -d: | sed -e 's/^[[:space:]]*//')
CPROFILE=$(cat host_profile | grep 'Compute Profile' | cut -f2 -d: | sed -e 's/^[[:space:]]*//')


# Delete the existing host - we can't 'rebuild' a vm deployed from an image
ssh -q -l ${SAT_USER} ${SATELLITE} "hammer host delete --name $TEST_VM"

#cat << EOF > /tmp/hammer_no_timeout.yml
#:foreman:
#  :request_timeout: 300
#EOF


#hammer -c /tmp/hammer_no_timeout.yml host create \
#--name=soe-img-6.lab.home.gatwards.org --hostgroup=LAB-RHEL6-LIB-IMAGE \
#--compute-profile='RHEL6 Dev' --ip=172.22.4.207 --operatingsystem='RHEL Server 6.9' \
#--compute-resource=vSphere --provision-method=image --subnet=Lab --location=Home \
#--organization=GatwardIT --domain=lab.home.gatwards.org --compute-attributes='start=1'

#hammer -c /tmp/hammer_no_timeout.yml host create \
#--name=soe-img-7.lab.home.gatwards.org --hostgroup=LAB-RHEL7-LIB-IMAGE \
#--compute-profile='RHEL7 Dev' --ip=172.22.4.208 --operatingsystem='RHEL Server 7.3' \
#--compute-resource=vSphere --provision-method=image --subnet=Lab --location=Home \
#--organization=GatwardIT --domain=lab.home.gatwards.org --compute-attributes='start=1'


# Create a new VM from the image
# (Currently relies on a compute profile being made that defines the dev image and other VM params)
# This command won't return until the template clone is complete, so requires the :request_timeout:
#   in the hammer cli config set appropriately
ssh -q -l ${SAT_USER} ${SATELLITE} "hammer host create --name=${TEST_VM} \
 --hostgroup='${HOSTGROUP}' --compute-resource='${CRESOURCE}' --compute-profile='${CPROFILE}' \
 --ip=${IP} --domain=${DOMAIN} --subnet='${SUBNET}' --operatingsystem='${OS}' \
 --location='${LOC}' --organization='${ORG}' \
 --provision-method=image --compute-attributes='start=1'"


