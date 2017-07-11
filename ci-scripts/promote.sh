#!/bin/bash

devHash=$1
majVer=$2
minVer=$3

# Promote content from _dev_ to _prod_

# Replace all instances of SOE_dev_ with SOE_ in each .erb file (snippet call entry + snippet names)
sed -i 's/dev_Server_SOE/Server_SOE/g' kickstarts/*.erb 


# Create version file - read latest git tag, tag+1
# Read current tag list so we can increment the version
#tag=$(git describe $(git rev-list --tags --max-count=1))

#tagver=$(( $(echo $tag | cut -f2 -d.) + 1 ))

#echo tagver=$tagver
TAG="v${majVer}.${minVer}"

# Update the SOE release file with the new version
if [ $(grep -c "SOE SOEVERSION" kickstarts/snp_Server_SOE-soe_release_file.erb) -eq 1 ]; then
  sed -i "s/SOE SOEVERSION/SOE $TAG/" kickstarts/snp_Server_SOE-soe_release_file.erb
else
  sed -i "s/SOE v[0-9]\{0,2\}.[0-9]\{0,3\}/SOE $TAG/" kickstarts/snp_Server_SOE-soe_release_file.erb
fi

# Clean out the workspace ready for the push phases
#rm -rf ${WORKSPACE}/soe
#mv ${WORKSPACE}/soemaster ${WORKSPACE}/soe

