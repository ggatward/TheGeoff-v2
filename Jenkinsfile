#!/usr/bin/env groovy

// Define the Git URL for this project
def gitUrl = 'git@github.com:ggatward/RHEL-SOE.git'

// Define the SOE MAJOR release. (Minor release will be derived from git tags)
def soeMajorVer = '1'

// FQDN of Satellite server
def satellite = 'sat62.core.home.gatwards.org'

// Satellite Organisation
def org = 'GatwardIT'

// Comma seperated list of locations that require the puppet environment.
def puppet_locs = 'Home'

// User that will be running hammer commands via ssh on Satellite
def sat_user = 'svc-jenkins'

// User that will be running r10k commands via ssh on Satellite
def r10k_user = 'svc-r10k'

// Do we want email notifictions of build results (true|false)?
def notifyEnabled = true

// Do we want/need to build and test PRODUCTION hosts after promotion?
def buildProd = true

// Define the vCenter server. If not required set values to ''
// If 'reboot_method' below is defined as 'vmware', Jenkins will attempt to reboot VMs via vCenter directly
def vmwHost = 'vcenter.lab.home.gatwards.org'


// ___ KICKSTART ___
// Are we including full kickstart hosts in the build (true/false)?
def buildKS = true

// Host definitions are a map containing hostname:reboot_method
// (reboot_method defines what controls reboot of our VMs: [sat6|vmware|manual])

// Hosts that will be kickstarted using the Dev Kickstart
def devKsHosts = [
  'soe-ks-7vmw.lab.home.gatwards.org':'vmware', 
  'soe-ks-6vmw.lab.home.gatwards.org':'sat6',
]
// Hosts that will be kickstarted using the Prod Kickstart
def prodKsHosts = [
  'soe-ks-7pvmw.lab.home.gatwards.org':'sat6', 
  'soe-ks-6pvmw.lab.home.gatwards.org':'vmware',
]

// ___ TEMPLATES ___
// Are we including VMware template images in the build? (true/false)
def buildTemplates = false

// Define the VMware environment for image creation - DataCenter, Cluster and Template Folder
def vmwDC = 'Home'
def vmwCluster = 'Lab'
def vmwTemplFolder = '/VM Templates'

// Hosts that will be kickstarted to become the Dev Templates (hostname:reboot_method)
def devTemplKsHosts = [
  'soe-tmpl-7.lab.home.gatwards.org':'vmware',
  'soe-tmpl-6.lab.home.gatwards.org':'vmware',
]
// Assigning RHEL versions to the Dev Template Kickstart hosts (hostname:Template_Name)
def devTemplKsVersions = [
  'soe-tmpl-7.lab.home.gatwards.org':'RHEL7_Server',
  'soe-tmpl-6.lab.home.gatwards.org':'RHEL6_Server',
]
// Hosts that will be deployed using the Dev Templates
def devTemplHosts = [
  'soe-img-7.lab.home.gatwards.org',
  'soe-img-6.lab.home.gatwards.org',
]
// Hosts that will be deployed using the Prod Templates
def prodTemplHosts = [
  'soe-img-7p.lab.home.gatwards.org',
  'soe-img-6p.lab.home.gatwards.org',
]


/////////////////////////////////////////////////////////////////////
// This is the start of the actual pipeline...
//     Should not need to configure anything below here.
/////////////////////////////////////////////////////////////////////

// String the common elements needed by the scripts into a single param for convenience
def sat_params = "${org} ${satellite} ${sat_user}"

// Variables that need to be referenced by multiple 'node' blocks need to be defined outside the blocks
def devHash = ''
def devHashShort = ''
def soeMinorVer = ''

// Only 1 concurrent build is allowed at a time.
// Newer builds are pulled off the queue first. When a build reaches the
// milestone at the end of the lock, all jobs started prior to the current
// build that are still waiting for the lock will be aborted
lock(resource: 'Deployment', inversePrecedence: true){
  node('soe') {
    wrap([$class: 'AnsiColorBuildWrapper', colorMapName: "xterm"]) {
      // Wipe the workspace so we are building completely clean
      deleteDir()

      // Notify the relevent parties that the build has started (Only if NOT user initiated)
      if(user.toString() == 'SYSTEM') { 
        notifyStarted(notifyEnabled)
      }

      // This initial checkout is light-weight so we can determine our current branch
      checkout scm
      devHash = sh(returnStdout: true, script:"git rev-parse HEAD")
      devHashShort = devHash[0..6]

      stage('Checkout') { 
        // Now we can do a full checkout including cleaning our workspace (we can't do that with the lightweight checkout)
        checkout([$class: 'GitSCM', branches: [[name: "*/${BRANCH_NAME}"]], 
          doGenerateSubmoduleConfigurations: false, 
          extensions: [[$class: 'CleanBeforeCheckout']], 
          submoduleCfg: [], 
          userRemoteConfigs: [[url: gitUrl]]
        ])

        // Checkout from the 'tests' repo into 'tests' dir in our workspace
//        checkout poll: false, scm: [$class: 'GitSCM', branches: [[name: '*/master']], 
//          doGenerateSubmoduleConfigurations: false, 
//          extensions: [[$class: 'RelativeTargetDirectory', relativeTargetDir: 'tests']], 
//          submoduleCfg: [], 
//          userRemoteConfigs: [[url: 'git@github.com:ggatward/soe-tests.git']]
//        ]

        // Extract the latest tag so we can build the version (Default to 0 if no tags present)
        def lastTagMinor = sh(returnStdout: true, script:"git describe --tags \$(git rev-list --tags --max-count=1) | cut -f2 -d.").trim()
        if (lastTagMinor == '') {
          lastTagMinor = '0'
        }

        if (BRANCH_NAME == 'development') {
          // Increment minor version.
          int lastTagMinorInt = lastTagMinor as Integer
          int MinorVer = (lastTagMinorInt + 1)
          soeMinorVer = MinorVer as String

          version = soeMajorVer + "." + soeMinorVer + "-" + currentBuild.number.toString().padLeft(3,'0')
          echo 'Building development SOE version ' + version + "-git-" + devHashShort
        } else {
          version = soeMajorVer + "." + lastTagMinor
          echo 'Deploying production SOE version ' + version
        }

        // Set a default jobstatus. This variable is used to trap the return code from shell scripts.
        def jobstatus = 0

        // Set other variables used in the pipeline based on the Git branch we are in.
        if (BRANCH_NAME == 'development') {
          templTestHosts = devTemplHosts
        } else {
          templTestHosts = prodTemplHosts
        }
      }

      // Push kickstart artefacts to Satellite. 
      // The artefacts should be marked as either dev or prod within the Git branch.
      stage('Push Kickstarts') {
        jobstatus = sh(returnStatus: true, script:". ci-scripts/pushkickstarts.sh ${sat_params} kickstarts")
        if (jobstatus != 0) {
          notifyFailed()
          error 'Exiting due to script errors'
        }
      }


      // Push puppet modules to Satellite via r10k. The puppet environment uses the current Git branch in the name.
      stage('Deploy Puppet Modules') {
        jobstatus = sh(returnStatus: true, script:". ci-scripts/r10kdeploy.sh ${sat_params} RHEL_SOE_${BRANCH_NAME} ${r10k_user} ${puppet_locs}")
        if (jobstatus != 0) {
          notifyFailed()
          error 'Exiting due to script errors'
        }
      }

      // stash the project so far so we can unstash to each parallel branch
      stash name: 'RHEL_SOE'
    }
  } // end of node

  // If this is the MASTER branch and we have set buildProd to 'false' we need to cleanly exit here.
  if (BRANCH_NAME == 'master') {
    if (buildProd == false) {
      echo "Production build/test not requested"
      return
    }
  }
  try {
    // ** Parallel execution example from https://jenkins.io/doc/pipeline/examples : 'Parallel From List'
    stage('Build VMs') {
      // Define an empty array to hold our parallel tasks
      def rebuildInParallel = [:]
      def jobResults = [:]

      // If we are building full KS hosts, loop through the defined hosts and add parallel tasks for each
      if (buildKS) {
        if (BRANCH_NAME == 'development') {
          for (host in devKsHosts.keySet()) {
            def bootMethod = devKsHosts.get(host) 
        
            // Convert into a step and add it to the map as the value.
            def stepName = "Kickstarting ${host}"
            rebuildInParallel[stepName] = ksRebuildSteps(sat_params, host, bootMethod, vmwHost)
          }
        } else {
          for (host in prodKsHosts.keySet()) {
            def bootMethod = prodKsHosts.get(host)

            // Convert into a step and add it to the map as the value.
            def stepName = "Kickstarting ${host}"
            rebuildInParallel[stepName] = ksRebuildSteps(sat_params, host, bootMethod, vmwHost)
          }
        }
      }

      // If we are building Template hosts, loop through the defined hosts and add parallel tasks for each
      if (buildTemplates) {
        if (BRANCH_NAME == 'development') {
          for (host in devTemplKsHosts.keySet()) {
            def bootMethod = devTemplKsHosts.get(host)

            // Convert into a step and add it to the map as the value.
            def stepName = "Rebuilding Template ${host}"
            rebuildInParallel[stepName] = templRebuildSteps(sat_params, host, bootMethod, vmwHost)
          }
        } // End of 'if development...'
      }   // End of 'build templates'
      // Run the parallel tasks. The steps within the rebuild are defined in the '***RebuildSteps' function(s)
      parallel rebuildInParallel
    }     // End of 'Build Test VMs' stage


    // If we are building Template hosts, perform the image cloning steps next
    if (buildTemplates) {
      if (BRANCH_NAME == 'development') {
        stage('VMWare Templating') {
          // Define an empty array to hold our parallel tasks
          def cloneInParallel = [:]
          def jobResults = [:]

          for (host in devTemplKsHosts.keySet()) {
            // Pull the defined RHEL version for this host
            for (h in devTemplKsVersions.keySet()) {
              if (h == host) {
                rhelVer = devTemplKsVersions.get(h)
              }
            }
          
            // Convert into a step 
            def stepName = "Cloning ${host}"
            cloneInParallel[stepName] = cloneSteps(sat_params, host, rhelVer, vmwHost, vmwDC, vmwCluster, vmwTemplFolder)
          }

          // Run the parallel tasks. The steps within the rebuild are defined in the '***RebuildSteps' function(s)
          parallel cloneInParallel

        } // End of 'VMware Templating' stage

        stage('Deploy VMs') {
          // Define an empty array to hold our parallel tasks
          def deployInParallel = [:]
          def jobResults = [:]

          for (int i = 0; i < devTemplHosts.size(); i++) {
            def host = devTemplHosts.get(i)

            // Convert into a step 
            def stepName = "Deploying ${host}"
            deployInParallel[stepName] = deploySteps(sat_params, host, vmwHost, vmwDC, vmwCluster, vmwTemplFolder)
          }

          // Run the parallel tasks. The steps within the rebuild are defined in the '***RebuildSteps' function(s)
          parallel deployInParallel

        } // End of 'Deploy VMs' stage
      }   // End of 'if development...'
    }   // End of 'Build Templates' block


    stage('Functional Tests') {
      // Define an empty array to hold our parallel tasks
      def testInParallel = [:]
      def jobResults = [:]

      // If we are building full KS hosts, loop through the defined hosts and add parallel tasks for each
      if (buildKS) {
        if (BRANCH_NAME == 'development') {
          for (host in devKsHosts.keySet()) {
            // Convert into a step and add it to the map as the value, with a name for the parallel step as the key.
            def stepName = "Testing ${host}"
            testInParallel[stepName] = testSteps(sat_params, host)
          }
        } else {
          for (host in prodKsHosts.keySet()) {
            // Convert into a step and add it to the map as the value, with a name for the parallel step as the key.
            def stepName = "Testing ${host}"
            testInParallel[stepName] = testSteps(sat_params, host)
          }
        }
      }

      // If we are building Template hosts, loop through the defined hosts and add parallel tasks for each
      if (buildTemplates) {
        for (int i = 0; i < templTestHosts.size(); i++) {
          def host = templTestHosts.get(i)

          // Convert into a step and add it to the map as the value, with a name for the parallel step as the key.
          def stepName = "Testing ${host}"
          testInParallel[stepName] = testSteps(sat_params, host)
        }
      }

      // Run the parallel tasks. The steps within the rebuild are defined in the '***RebuildSteps' function(s)
      parallel testInParallel


    } // End of 'Functional Tests' stage
  }
  finally {
    node('soe') {
      wrap([$class: 'AnsiColorBuildWrapper', colorMapName: "xterm"]) {
        // Wipe the workspace so we are building completely clean
        deleteDir()

        // Unstash the test results for each test host
        if (buildKS) {
          if (BRANCH_NAME == 'development') {
            for (host in devKsHosts.keySet()) {
              unstash "testresults_${host}"
            }
          } else {
            for (host in prodKsHosts.keySet()) {
              unstash "testresults_${host}"
            }
          }
        }

        // Unstash the test results for each test host
        if (buildTemplates) {
          for (int i = 0; i < templTestHosts.size(); i++) {
            def host = templTestHosts.get(i)
            unstash "testresults_${host}"
          }
        }


      // Try to display the converted JUnit tests
//        junit allowEmptyResults: true, testResults: 'test_results/*.xml'


        // Process the aggregated TAP results
        step([$class: 'TapPublisher', 
          discardOldReports: true, 
          enableSubtests: false, 
          failIfNoResults: true, 
          failedTestsMarkBuildAsFailure: true, 
          flattenTapResult: false, 
          includeCommentDiagnostics: false, 
          outputTapToConsole: true, 
          planRequired: true, 
          showOnlyFailures: false, 
          skipIfBuildNotOk: true, 
          stripSingleParents: false, 
          testResults: 'test_results/*.tap', 
          todoIsFailure: false, 
          validateNumberOfTests: true, 
          verbose: true,
        ])
      }
    }
  } 
  // If we got here we can add an icon to the build history to show success so far
  manager.addBadge('success.gif',"Passed all tests")

} // Release 'Deployment' lock

// Approval & Promotion are only relevant if we are running the dev branch
if (BRANCH_NAME == 'development') {
  stage('Approval') {
    def userInput = true
    def didTimeout = false
    try {
      milestone()
      notifyPromoteReady()
      timeout(time:1, unit:'DAYS') {
//      timeout(time:1, unit:'HOURS') {
//      timeout(time:10, unit:'MINUTES') {
        userInput = input(message: 'Approve promotion?')
      }
    } catch(err) { // Timeout or Abort selected
      def appUser = err.getCauses()[0].getUser()
      if('SYSTEM' == appUser.toString()) {  // SYSTEM means timeout.
        didTimeout = true
        echo 'Approval timeout reached, or superseded by newer build'
      } else {
        userInput = false
        echo "Aborted by: [${appUser}]"
      }
    }
    if (didTimeout) {
      currentBuild.result = 'ABORTED'
      throw new hudson.AbortException('Approval Timeout')
    } else if (userInput == false) {
      currentBuild.result = 'ABORTED'
      throw new hudson.AbortException('Manually Aborted')
    } else {
      // If we approve promotion we will pass this milestone. Any jobs older than this one 
      // still waiting for promotion will be aborted
      milestone()
    }
  }
  
  stage('Promotion') {
    node('soe') {
      wrap([$class: 'AnsiColorBuildWrapper', colorMapName: "xterm"]) {
        // create a lock so only one promote can run at a time
        lock(resource: 'Promotion', inversePrecedence: true) { 
          // Checkout the master branch 
          checkout([$class: 'GitSCM', branches: [[name: "master"]],
            doGenerateSubmoduleConfigurations: false,
            extensions: [[$class: 'CleanBeforeCheckout']],
            submoduleCfg: [],
            userRemoteConfigs: [[url: gitUrl]]
          ])

          def jobstatus = 0

          // The above gives us an 'untracked' master (detached HEAD). Checkout master to reattach
          sh 'git checkout master'

          // new we can merge our development branch into master
          def user = user.toString()
          sh "git merge ${devHash}"

          // Next we need to manipulate the artefacts to 'productionise' them
          jobstatus = sh(returnStatus: true, script:". ci-scripts/promote.sh ${devHashShort} ${soeMajorVer} ${soeMinorVer}")
          if (jobstatus != 0) {
            notifyFailed()
            error 'Exiting due to script errors'
          }

          // Finally we need to commit the finished master branch and push back to git
          sh "git commit -a -m 'dev-to-prod replacements'"
          sh "git push"
          sh "git tag -a v${soeMajorVer}.${soeMinorVer} -m 'Promotion'"
          sh "git push --tags"

          // And to make the display nice we will add the tag to the dev build history
          manager.addBadge('green.gif',"v${soeMajorVer}.${soeMinorVer}")


        } // Release 'Promotion' lock
      }
    }     // End Node
  }       // End Stage
}



///////////////////////////////////////////////////////////////////////////////
//
///////////////////////////////////////////////////////////////////////////////

// Steps for rebuilding a Kickstart host
//    - Full Kickstart (defined by Satellite host group membership)
def ksRebuildSteps(sat_params, host, bootMethod, vmwHost) {
  return {
    node('soe') {
      wrap([$class: 'AnsiColorBuildWrapper', colorMapName: "xterm"]) {
        // Wipe the workspace so we are building completely clean
        deleteDir()

        echo("Building ${host}...")
        // Extract our stashed git repos to the new workspace
        unstash 'RHEL_SOE'
        jobstatus = sh(returnStatus: true, script:". ci-scripts/buildtestvms.sh ${sat_params} ${host} ${bootMethod}")
        if (jobstatus != 0) {
          notifyFailed()
          error 'Exiting due to script errors'
        }
        // If we are using Jenkins to reboot via vCenter we do that bit here...
        if (bootMethod == 'vmware') {
          withCredentials([usernamePassword(credentialsId: 'JenkinsVmw', usernameVariable: 'vmwuser', passwordVariable: 'vmwpass')]) {
            ansiblePlaybook(
              colorized: true,
              credentialsId: '99b1cb01-3542-4059-bbc3-1d01cb5f942e',
              installation: 'Ansible',
              inventory: 'ci-scripts/ansible/hosts',
              playbook: 'ci-scripts/ansible/reboot_vmware.yml',
              sudoUser: null,
              extraVars: [
                host: "${host}",
                vmwhost: "${vmwHost}",
                vmwuser: "${vmwuser}",
                vmwpass: [value: "${vmwpass}", hidden: true],
              ])
          }
        }

        jobstatus = sh(returnStatus: true, script:". ci-scripts/waitforbuild.sh ${sat_params} ${host}")
        if (jobstatus != 0) {
          notifyFailed()
          error 'Exiting due to script errors'
        }
      }
    }
  }
}

// Steps for rebuilding a gold template host
//    - Basic Kickstart (defined by Satellite host group membership)
//    - Convert to Template
//    - Deploy template to required environments (uses user_post script to customise image)
def templRebuildSteps(sat_params, host, bootMethod, vmwHost) {
  return {
    node('soe') {
      wrap([$class: 'AnsiColorBuildWrapper', colorMapName: "xterm"]) {
        // Wipe the workspace so we are building completely clean
        deleteDir()

        echo("Building ${host}...")
        // Extract our stashed git repos to the new workspace
        unstash 'RHEL_SOE'
        jobstatus = sh(returnStatus: true, script:". ci-scripts/buildtestvms.sh ${sat_params} ${host} ${bootMethod}")
        if (jobstatus != 0) {
          notifyFailed()
          error 'Exiting due to script errors'
        }

        // If we are using Jenkins to reboot via vCenter we do that bit here...
        if (bootMethod == 'vmware') {
          withCredentials([usernamePassword(credentialsId: 'JenkinsVmw', usernameVariable: 'vmwuser', passwordVariable: 'vmwpass')]) {
            ansiblePlaybook(
              colorized: true,
              credentialsId: '99b1cb01-3542-4059-bbc3-1d01cb5f942e',
              installation: 'Ansible',
              inventory: 'ci-scripts/ansible/hosts',
              playbook: 'ci-scripts/ansible/reboot_vmware.yml',
              sudoUser: null,
              extraVars: [
                host: "${host}",
                vmwhost: "${vmwHost}",
                vmwuser: "${vmwuser}",
                vmwpass: [value: "${vmwpass}", hidden: true],
              ])
          }
        }

        jobstatus = sh(returnStatus: true, script:". ci-scripts/waitforbuild.sh ${sat_params} ${host}")
        if (jobstatus != 0) {
          notifyFailed()
          error 'Exiting due to script errors'
        }

        // Login to the built host and run the 'sysprep' script to anonymise it
        withCredentials([[$class: 'UsernamePasswordMultiBinding', credentialsId: 'SOE_ROOT',
          usernameVariable: 'USERNAME', passwordVariable: 'ROOTPASS']]) {
          jobstatus = sh(returnStatus: true, script:". ci-scripts/sysprep.sh ${sat_params} ${host} ${ROOTPASS}")
          if (jobstatus != 0) {
            notifyFailed()
            error 'Exiting due to script errors'
          }
        }
      }
    }
  }
}

def cloneSteps(sat_params, host, rhelVer, vmwHost, vmwDC, vmwCluster, vmwTemplFolder) {
  return {
    node('soe') {
      wrap([$class: 'AnsiColorBuildWrapper', colorMapName: "xterm"]) {
        // Wipe the workspace so we are building completely clean
        deleteDir()
        unstash 'RHEL_SOE'

        // Delete the old template first (uses vSphere plugin)
        vSphere buildStep: [$class: 'Delete',
          failOnNoExist: false,
          vm: "${rhelVer}_Dev_Template"], serverName: 'vcenter_server'

        // We can't clone a VM without a snapshot, so lets take one, after deleting the existing one
        vSphere buildStep: [$class: 'DeleteSnapshot', 
          consolidate: false, 
          failOnNoExist: false, 
          snapshotName: "${host}-snap", 
          vm: "${host}"], serverName: 'vcenter_server'

        vSphere buildStep: [$class: 'TakeSnapshot',
          description: 'Post KS snapshot',
          includeMemory: false,
          snapshotName: "${host}-snap",
          vm: "${host}"], serverName: 'vcenter_server'

        // Now we clone the built VM and then convert that clone into a template.
        // We do this with an Ansible play as the vsphere plugin doesnt work properly.
        // (Ultimately we could run all vSphere actions via ansible but currently
        // snapshots don't work 100% via ansible)
        withCredentials([usernamePassword(credentialsId: 'JenkinsVmw',
          usernameVariable: 'vmwuser', passwordVariable: 'vmwpass')]) {
          ansiblePlaybook(
            colorized: true, 
            credentialsId: '99b1cb01-3542-4059-bbc3-1d01cb5f942e', 
            installation: 'Ansible', 
            inventory: 'ci-scripts/ansible/hosts', 
            playbook: 'ci-scripts/ansible/create_template.yml', 
            sudoUser: null,
            extraVars: [
              host: "${host}",
              template: "${rhelVer}_Dev_Template",
              vmwhost: "${vmwHost}",
              vmwdc: "${vmwDC}",
              vmwcluster: "${vmwCluster}",
              vmwfolder: "${vmwTemplFolder}",
              vmwuser: "${vmwuser}",
              vmwpass: [value: "${vmwpass}", hidden: true],
            ])
        }

        // Redeploy template test VM  (redeploy buildbot3/4 but need to fix MAC address?)

      }
    }
  }
}


// Function to deploy VMs from our template images
def deploySteps(sat_params, host, vmwHost, vmwDC, vmwCluster, vmwTemplFolder) {
  return {
    node('soe') {
      wrap([$class: 'AnsiColorBuildWrapper', colorMapName: "xterm"]) {
        // Wipe the workspace so we are building completely clean
        deleteDir()
        unstash 'RHEL_SOE'

        // Reprovision VMs via Satellite
        jobstatus = sh(returnStatus: true, script:". ci-scripts/deployvmw.sh ${sat_params} ${host}")
        if (jobstatus != 0) {
          notifyFailed()
          error 'Exiting due to script errors'
        }


      }
    }
  }
}


// Function defining our TAPS testing
def testSteps(sat_params, host) {
  return {
    node('soe') {
      wrap([$class: 'AnsiColorBuildWrapper', colorMapName: "xterm"]) {
        // Wipe the workspace so we are building completely clean
        deleteDir()

        echo("Testing ${host}...")
        // Extract our stashed git repos to the new workspace
        unstash 'RHEL_SOE'

        // Get the build host root password from the Jenkins Credential Store
        // Use that to run the bats tests (needs root ssh)
        withCredentials([[$class: 'UsernamePasswordMultiBinding', credentialsId: 'SOE_ROOT',
          usernameVariable: 'USERNAME', passwordVariable: 'ROOTPASS']]) {
            jobstatus = sh(returnStatus: true, script:". ci-scripts/pushtests.sh ${sat_params} ${host} ${ROOTPASS}")
            if (jobstatus != 0) {
              notifyFailed()
              error "Exiting due to script errors (jobstatus = ${jobstatus})"
            }
          }
        // Archive the test results for aggregation later
        stash includes: 'test_results/*.tap,test_results/*.xml', name: "testresults_${host}"
      }
    }
  }
}


/////////////////////////////////////////////////////////////////////////////////////
/////////////////////////////////////////////////////////////////////////////////////
// Define functions used within pipeline

def notifyStarted(notifyEnabled) {
  if (notifyEnabled) {
    emailext ( 
      body: "<p>Started running SOE build</p>",
      subject: "Jenkins Build Started: Job \'${env.JOB_NAME} [${env.BUILD_NUMBER}]\'",
      recipientProviders: [[$class: 'CulpritsRecipientProvider'], [$class: 'DevelopersRecipientProvider'], [$class: 'RequesterRecipientProvider']], 
      replyTo: 'noreply@example.com', 
      mimeType: 'text/html'
    )
  }
}

def notifyPromoteReady() {
  emailext ( 
    body: "Job '${env.JOB_NAME} [${env.BUILD_NUMBER}]' has completed successfully and is now eligible for promotion.</p><p>Please go to this link to approve: <a href='${env.BUILD_URL}..'>${env.JOB_NAME} [${env.BUILD_NUMBER}]</a></p>",
    subject: "SUCCESSFUL: Job '${env.JOB_NAME} [${env.BUILD_NUMBER}]'",
    recipientProviders: [[$class: 'CulpritsRecipientProvider'], [$class: 'DevelopersRecipientProvider'], [$class: 'RequesterRecipientProvider']], 
    replyTo: 'noreply@example.com', 
    mimeType: 'text/html'
  )
}

def notifyComplete() {
  emailext ( 
    body: "Job '${env.JOB_NAME} [${env.BUILD_NUMBER}]' has been promoted to production successfully</p>",
    subject: "COMPLETED: Job '${env.JOB_NAME} [${env.BUILD_NUMBER}]'",
    recipientProviders: [[$class: 'CulpritsRecipientProvider'], [$class: 'DevelopersRecipientProvider'], [$class: 'RequesterRecipientProvider']], 
    replyTo: 'noreply@example.com', 
    mimeType: 'text/html'
  )
}

def notifyFailed() {
  emailext (
    attachLog: true,
    body: "<p>Job '${env.JOB_NAME} [${env.BUILD_NUMBER}]' has failed.</p><p>Please go to this link: <a href='${env.BUILD_URL}'>${env.JOB_NAME} [${env.BUILD_NUMBER}]</a></p>",
    subject: "FAILED: Job '${env.JOB_NAME} [${env.BUILD_NUMBER}]'",
    recipientProviders: [[$class: 'CulpritsRecipientProvider'], [$class: 'DevelopersRecipientProvider'], [$class: 'RequesterRecipientProvider']], 
    replyTo: 'noreply@example.com', 
    mimeType: 'text/html'
  )
}
