#!/bin/bash
#set -x

##########################################################################################################################################
##
## Script to install the latest Elastic Agent on macOS
## 
## Developed by Eric Ooi using code originally from Microsoft:
## https://raw.githubusercontent.com/microsoft/shell-intune-samples/master/Apps/Gimp/InstallGimp.sh
## Original Microsoft copyright is maintained below.
##
## Eric Ooi has added the following for the purpose of installing Elastic Agent:
##     * variables: fleeturl, enrolltoken, intel_url, apple_url
##     * functions: checkProfile, installTARGZ, checkCPU
##
##########################################################################################################################################

## Copyright (c) 2022 Eric Ooi. All rights reserved.
## Scripts are not supported under any Eric Ooi standard support program or service. The scripts are provided AS IS without warranty of any kind.
## Eric Ooi disclaims all implied warranties including, without limitation, any implied warranties of merchantability or of fitness for a
## particular purpose. The entire risk arising out of the use or performance of the scripts and documentation remains with you. In no event shall
## Eric Ooi, its authors, or anyone else involved in the creation, production, or delivery of the scripts be liable for any damages whatsoever
## (including, without limitation, damages for loss of business profits, business interruption, loss of business information, or other pecuniary
## loss) arising out of the use of or inability to use the sample scripts or documentation, even if Eric Ooi has been advised of the possibility
## of such damages.

## Copyright (c) 2020 Microsoft Corp. All rights reserved.
## Scripts are not supported under any Microsoft standard support program or service. The scripts are provided AS IS without warranty of any kind.
## Microsoft disclaims all implied warranties including, without limitation, any implied warranties of merchantability or of fitness for a
## particular purpose. The entire risk arising out of the use or performance of the scripts and documentation remains with you. In no event shall
## Microsoft, its authors, or anyone else involved in the creation, production, or delivery of the scripts be liable for any damages whatsoever
## (including, without limitation, damages for loss of business profits, business interruption, loss of business information, or other pecuniary
## loss) arising out of the use of or inability to use the sample scripts or documentation, even if Microsoft has been advised of the possibility
## of such damages.
## Feedback: neiljohn@microsoft.com

## User Defined variables

# Elastic Agent download URL
intel_url="<INSERT ELASTIC AGENT DOWNLOAD URL FOR INTEL-BASED MACOS>"
apple_url="<INSERT ELASTIC AGENT DOWNLOAD URL FOR APPLE-BASED MACOS>"

# Elastic Fleet URL
fleeturl="<INSERT YOUR ELASTIC FLEET URL>"

# Elastic Agent Enrollment Token
enrolltoken="<INSERT YOUR ELASTIC AGENT ENROLLMENT TOKEN>"

appname="Elastic Agent"
app="elastic-agent"
logandmetadir="/Library/Logs/Microsoft/IntuneScripts/elastic-agent"
processpath="/Library/Elastic/Agent/elastic-agent"
terminateprocess="true"
autoUpdate="true"

# Generated variables
tempdir=$(mktemp -d)
log="$logandmetadir/$appname.log"                                               # The location of the script log file
metafile="$logandmetadir/$appname.meta"                                         # The location of our meta file (for updates)

# Function to delay script if the specified process is running
waitForProcess () {

    #################################################################################################################
    #################################################################################################################
    ##
    ##  Function to pause while a specified process is running
    ##
    ##  Functions used
    ##
    ##      None
    ##
    ##  Variables used
    ##
    ##      $1 = name of process to check for
    ##      $2 = length of delay (if missing, function to generate random delay between 10 and 60s)
    ##      $3 = true/false if = "true" terminate process, if "false" wait for it to close
    ##
    ###############################################################
    ###############################################################

    processName=$1
    fixedDelay=$2
    terminate=$3

    echo "$(date) | Waiting for other [$processName] processes to end"
    while ps aux | grep "$processName" | grep -v grep &>/dev/null; do

        if [[ $terminate == "true" ]]; then
            echo "$(date) | + [$appname] running, terminating [$processpath]..."
            pkill -f "$processName"
            return
        fi

        # If we've been passed a delay we should use it, otherwise we'll create a random delay each run
        if [[ ! $fixedDelay ]]; then
            delay=$(( $RANDOM % 50 + 10 ))
        else
            delay=$fixedDelay
        fi

        echo "$(date) |  + Another instance of $processName is running, waiting [$delay] seconds"
        sleep $delay
    done
    
    echo "$(date) | No instances of [$processName] found, safe to proceed"

}

# Function to check which macOS CPU processor is in use
checkCPU () {

    #################################################################################################################
    #################################################################################################################
    ##
    ##  Simple function to check which CPU is used and set weburl variable accordingly
    ##
    ###############################################################
    ###############################################################

    

    echo "$(date) | Checking CPU type"

    ## Note, Rosetta detection code from https://derflounder.wordpress.com/2020/11/17/installing-rosetta-2-on-apple-silicon-macs/
    OLDIFS=$IFS
    IFS='.' read osvers_major osvers_minor osvers_dot_version <<< "$(/usr/bin/sw_vers -productVersion)"
    IFS=$OLDIFS

    if [[ ${osvers_major} -ge 11 ]]; then

        # Check macOS CPU type to determine which installer to download

        processor=$(/usr/sbin/sysctl -n machdep.cpu.brand_string | grep -o "Intel")
        
        if [[ -n "$processor" ]]; then
            echo "$(date) | Intel processor detected. Will download and install x86_64 version."
            weburl=$intel_url
        else
            echo "$(date) | Apple processor detected. Will download and install aarch64 version."
            weburl=$apple_url
        fi
        
        echo "$(date) | Download URL: $weburl"
    fi

}

# Function to update the last modified date for this app
fetchLastModifiedDate() {

    #################################################################################################################
    #################################################################################################################
    ##
    ##  This function takes the following global variables and downloads the URL provided to a temporary location
    ##
    ##  Functions
    ##
    ##      none
    ##
    ##  Variables
    ##
    ##      $logandmetadir = Directory to read nand write meta data to
    ##      $metafile = Location of meta file (used to store last update time)
    ##      $weburl = URL of download location
    ##      $tempfile = location of temporary DMG file downloaded
    ##      $lastmodified = Generated by the function as the last-modified http header from the curl request
    ##
    ##  Notes
    ##
    ##      If called with "fetchLastModifiedDate update" the function will overwrite the current lastmodified date into metafile
    ##
    ###############################################################
    ###############################################################

    ## Check if the log directory has been created
    if [[ ! -d "$logandmetadir" ]]; then
        ## Creating Metadirectory
        echo "$(date) | Creating [$logandmetadir] to store metadata"
        mkdir -p "$logandmetadir"
    fi

    # generate the last modified date of the file we need to download
    lastmodified=$(curl -sIL "$weburl" | grep -i "last-modified" | awk '{$1=""; print $0}' | awk '{ sub(/^[ \t]+/, ""); print }' | tr -d '\r')

    if [[ $1 == "update" ]]; then
        echo "$(date) | Writing last modifieddate [$lastmodified] to [$metafile]"
        echo "$lastmodified" > "$metafile"
    fi

}

# Function to check if "Elastic Agent Onboarding" system profile is installed
function checkProfile() {

    #################################################################################################################
    #################################################################################################################
    ##
    ##  This function checks if the "Elastic Agent Onboarding" macOS system profile is installed prior to the 
    ##  download and installation of Elastic Agent itself
    ##
    ###############################################################
    ###############################################################

    echo "$(date) | Check if 'Elastic Agent Onboarding' system profile is installed"

    profiles -P | grep "Elastic Agent Onboarding" > /dev/null 2>&1

    if [ $? == 0 ]; then
        echo "$(date) | 'Elastic Agent Onboarding' system profile is installed"
    else
        echo "$(date) | 'Elastic Agent Onboarding' system profile is not yet installed, exiting"
        exit 1;
    fi
}

# Function to download app
function downloadApp () {

    #################################################################################################################
    #################################################################################################################
    ##
    ##  This function takes the following global variables and downloads the URL provided to a temporary location
    ##
    ##  Functions
    ##
    ##      waitForCurl (Pauses download until all other instances of Curl have finished)
    ##      downloadSize (Generates human readable size of the download for the logs)
    ##
    ##  Variables
    ##
    ##      $appname = Description of the App we are installing
    ##      $weburl = URL of download location
    ##      $tempfile = location of temporary DMG file downloaded
    ##
    ###############################################################
    ###############################################################

    echo "$(date) | Starting downlading of [$appname]"

    # wait for other downloads to complete
    waitForProcess "curl -f"

    #download the file
    echo "$(date) | Downloading $appname [$weburl]"

    cd "$tempdir"
    curl -f -s --connect-timeout 30 --retry 5 --retry-delay 60 --compressed -L -J -O "$weburl"
    if [ $? == 0 ]; then

            # We have downloaded a file, we need to know what the file is called and what type of file it is
            tempSearchPath="$tempdir/*"
            for f in $tempSearchPath; do
                tempfile=$f
            done

            case $tempfile in

            *.pkg|*.PKG)
                packageType="PKG"
                ;;

            *.zip|*.ZIP)
                packageType="ZIP"
                ;;
            
            *.tar.gz|*.TAR.GZ)
                packageType="TARGZ"
                ;;

            *.dmg|*.DMG)
                

                # We have what we think is a DMG, but we don't know what is inside it yet, could be an APP or PKG
                # Let's mount it and try to guess what we're dealing with...
                echo "$(date) | Found DMG, looking inside..."

                # Mount the dmg file...
                volume="$tempdir/$appname"
                echo "$(date) | Mounting Image [$volume] [$tempfile]"
                hdiutil attach -quiet -nobrowse -mountpoint "$volume" "$tempfile"
                if [ "$?" = "0" ]; then
                    echo "$(date) | Mounted succesfully to [$volume]"
                else
                    echo "$(date) | Failed to mount [$tempfile]"
                    
                fi

                if  [[ $(ls "$volume" | grep -i .app) ]] && [[ $(ls "$volume" | grep -i .pkg) ]]; then

                    echo "$(date) | Detected both APP and PKG in same DMG, exiting gracefully"

                else

                    if  [[ $(ls "$volume" | grep -i .app) ]]; then 
                        echo "$(date) | Detected APP, setting PackageType to DMG"
                        packageType="DMG"
                    fi 

                    if  [[ $(ls "$volume" | grep -i .pkg) ]]; then 
                        echo "$(date) | Detected PKG, setting PackageType to DMGPKG"
                        packageType="DMGPKG"
                    fi 

                fi

                # Unmount the dmg
                echo "$(date) | Un-mounting [$volume]"
                hdiutil detach -quiet "$volume"
                ;;

            *)
                # We can't tell what this is by the file name, lets look at the metadata
                echo "$(date) | Unknown file type [$f], analysing metadata"
                metadata=$(file "$tempfile")
                if [[ "$metadata" == *"Zip archive data"* ]]; then
                    packageType="ZIP"
                    mv "$tempfile" "$tempdir/install.zip"
                    tempfile="$tempdir/install.zip"
                fi

                if [[ "$metadata" == *"xar archive"* ]]; then
                    packageType="PKG"
                    mv "$tempfile" "$tempdir/install.pkg"
                    tempfile="$tempdir/install.pkg"
                fi

                if [[ "$metadata" == *"bzip2 compressed data"* ]] || [[ "$metadata" == *"zlib compressed data"* ]] ; then
                    packageType="DMG"
                    mv "$tempfile" "$tempdir/install.dmg"
                    tempfile="$tempdir/install.dmg"
                fi
                ;;
            esac

            if [[ ! $packageType ]]; then
                echo "Failed to determine temp file type [$metadata]"
                rm -rf "$tempdir"
            else
                echo "$(date) | Downloaded [$app] to [$tempfile]"
                echo "$(date) | Detected install type as [$packageType]"
            fi
         
    else
    
         echo "$(date) | Failure to download [$weburl] to [$tempfile]"

         exit 1
    fi

}

# Function to check if we need to update or not
function updateCheck() {

    #################################################################################################################
    #################################################################################################################
    ##
    ##  This function takes the following dependencies and variables and exits if no update is required
    ##
    ##  Functions
    ##
    ##      fetchLastModifiedDate
    ##
    ##  Variables
    ##
    ##      $appname = Description of the App we are installing
    ##      $tempfile = location of temporary DMG file downloaded
    ##      $volume = name of volume mount point
    ##      $app = name of Application directory under /Applications
    ##
    ###############################################################
    ###############################################################


    echo "$(date) | Checking if we need to install or update [$appname]"

    ## Is the app already installed?
    if [ -e "/Library/Elastic/Agent/$app" ]; then
    
    # App is installed, if its updates are handled by MAU we should quietly exit
    if [[ $autoUpdate == "true" ]]; then
        echo "$(date) | [$appname] is already installed and handles updates itself, exiting"
        exit 0;
    fi

    # App is already installed, we need to determine if it requires updating or not
        echo "$(date) | [$appname] already installed, let's see if we need to update"
        fetchLastModifiedDate

        ## Did we store the last modified date last time we installed/updated?
        if [[ -d "$logandmetadir" ]]; then

            if [ -f "$metafile" ]; then
                previouslastmodifieddate=$(cat "$metafile")
                if [[ "$previouslastmodifieddate" != "$lastmodified" ]]; then
                    echo "$(date) | Update found, previous [$previouslastmodifieddate] and current [$lastmodified]"
                    update="update"
                else
                    echo "$(date) | No update between previous [$previouslastmodifieddate] and current [$lastmodified]"
                    echo "$(date) | Exiting, nothing to do"
                    exit 0
                fi
            else
                echo "$(date) | Meta file [$metafile] not found"
                echo "$(date) | Unable to determine if update required, updating [$appname] anyway"

            fi
            
        fi

    else
        echo "$(date) | [$appname] not installed, need to download and install"
    fi

}

# Install TARGZ Function
function installTARGZ () {

    #################################################################################################################
    #################################################################################################################
    ##
    ##  This function takes the following global variables and installs the TARGZ file into /Library
    ##
    ##  Functions
    ##
    ##      isAppRunning (Pauses installation if the process defined in global variable $processpath is running )
    ##      fetchLastModifiedDate (Called with update flag which causes the function to write the new lastmodified date to the metadata file)
    ##
    ##  Variables
    ##
    ##      $appname = Description of the App we are installing
    ##      $tempfile = location of temporary DMG file downloaded
    ##      $volume = name of volume mount point
    ##      $app = name of Application directory under /Applications
    ##
    ###############################################################
    ###############################################################


    # Check if app is running, if it is we need to wait.
    waitForProcess "$processpath" "300" "$terminateprocess"

    echo "$(date) | Installing $appname"

    # Change into temp dir
    cd "$tempdir"
    if [ "$?" = "0" ]; then
      echo "$(date) | Changed current directory to $tempdir"
    else
      echo "$(date) | failed to change to $tempfile"
      if [ -d "$tempdir" ]; then rm -rf $tempdir; fi
       exit 1
    fi

    # Untar files in temp dir
    tar -xzvf "$tempfile"
    
    if [ "$?" = "0" ]; then
      echo "$(date) | $tempfile untar'd"
    else
      echo "$(date) | failed to untar $tempfile"
      if [ -d "$tempdir" ]; then rm -rf $tempdir; fi
      exit 1
    fi

    cd "${tempfile%.*.*}"

    echo "$(pwd)"

    # Install Elastic Agent with fleeturl and enrolltoken values
    ./elastic-agent install -f --url=$fleeturl --enrollment-token=$enrolltoken

    # Checking if the app was installed successfully
    if [ "$?" = "0" ]; then
        if [[ -a "/Library/Elastic/Agent/$app" ]]; then

            echo "$(date) | $appname Installed"
            echo "$(date) | Cleaning Up"
            rm -rf "$tempfile"

            # Update metadata
            fetchLastModifiedDate update

            #echo "$(date) | Fixing up permissions"
            #sudo chown -R root:wheel "/Applications/$app"
            echo "$(date) | Application [$appname] succesfully installed"
            exit 0
        else
            echo "$(date) | Failed to install $appname"
            exit 1
        fi
    else

        # Something went wrong here, either the download failed or the install Failed
        # intune will pick up the exit status and the IT Pro can use that to determine what went wrong.
        # Intune can also return the log file if requested by the admin
        
        echo "$(date) | Failed to install $appname"
        if [ -d "$tempdir" ]; then rm -rf $tempdir; fi
        exit 1
    fi
}

# Function to start logging
function startLog() {

    ###################################################
    ###################################################
    ##
    ##  start logging - Output to log file and STDOUT
    ##
    ####################
    ####################

    if [[ ! -d "$logandmetadir" ]]; then
        ## Creating Metadirectory
        echo "$(date) | Creating [$logandmetadir] to store logs"
        mkdir -p "$logandmetadir"
    fi

    exec &> >(tee -a "$log")
    
}

# Function to delay until the user has finished setup assistant.
waitForDesktop () {
  until ps aux | grep /System/Library/CoreServices/Dock.app/Contents/MacOS/Dock | grep -v grep &>/dev/null; do
    delay=$(( $RANDOM % 50 + 10 ))
    echo "$(date) |  + Dock not running, waiting [$delay] seconds"
    sleep $delay
  done
  echo "$(date) | Dock is here, lets carry on"
}

###################################################################################
###################################################################################
##
## Begin Script Body
##
#####################################
#####################################

# Initiate logging
startLog

echo ""
echo "##############################################################"
echo "# $(date) | Logging install of [$appname] to [$log]"
echo "############################################################"
echo ""

# Check if Elastic Agent Onboarding system profile is installed
checkProfile

# Check CPU type
checkCPU

# Test if we need to install or update
updateCheck

# Wait for Desktop
waitForDesktop

# Download app
downloadApp

# Install TARGZ file
if [[ $packageType == "TARGZ" ]]; then
    installTARGZ
fi