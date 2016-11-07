<#
.SYNOPSIS
    Gets all shares on requested servers, checks all folders for NTFS Permissions"
.DESCRIPTION
    Used by ITSO to find security ACL for a top secret audit
.PARAMETER Servers
    Array of servers which host file shares 
.PARAMETER Accounts
    Array of accounts to search access for must be in HOME\$account format, if you need to input spaces, put in single quotes ie 'HOME\Domain Admins' 
.PARAMETER NTFSSecurityModulepath 
    Requires NTFSSecurity PS Module to work https:\\ntfssecurity.codeplex.com
.PARAMETER Logpath 
#>
param (
[parameter(mandatory = $true)][string[]]$Servers,
[parameter(mandatory = $true)][string[]]$Accounts,
[parameter(mandatory = $true)][string]$Logpath = "C:\",
            [string]$NTFSSecurityModulePath = ""
)
#Import NTFSSecurity module
Import-Module $ntfssecuritymodulepath 

#Build Log File
$date = ((Get-Date -format o).substring(0,19) -replace ":")
$logfile = "Find-NTFSPerms" + $date + ".log"
$log =  $logpath + "\" + $logfile



Function Get-SharesToSearch {
param (
[string[]]$Servers
)
#Create empty array to contain results
$sharestosearch = @()

#Check each server in array
foreach ($Server in $Servers)
{
    #Have to use net view dos command as the hitachi doesn't support wmi, do some string manipulation to get nice results
    $shares = (net view $Server) | % { if($_.IndexOf(' Disk ') -gt 0){ $_.Split('      ')[0] } } 
    
    #For each loop to make these actually usable later 
    ForEach ($share in $shares) {

    #add server and share together
    $fullsharename = "\\" + $server + "\" + $share 
    
    #add to array to pass to rest of script
    $sharestosearch += $fullsharename 
    }

}
$sharestosearch
}
[scriptblock]$findpermsfunction = {
Function Get-ChildItemCheckPerms {
param (
[parameter(mandatory = $true)][string]$destination,
[parameter(mandatory = $true)][string[]]$accounts,
[parameter(mandatory = $true)][string]$logpath = "C:\"
)

#Import NTFSSecurity module
Import-Module NTFSSecurity 

#write to console 
#write-host "Checking NTFS Access on $destination" -ForegroundColor Cyan 
#write to log
Add-Content -value "Checking NTFS Access on $destination" -path $log


#Sloppily Get all folders in that share in one giantic array, add any errors to $accessdenied variable
$Folders = Get-ChildItem2 -path $destination -recurse -directory -EA SilentlyContinue -Errorvariable +accessdenied
    
    #For each loop to check each folder
    Foreach ($folder in $folders) {
    #commented out write to host
    #write-host "Checking $folder" 

        #For Each loop to check each account
        ForEach ($account in $accounts){

            #Get the NTFS Access using NTFSSecurity Module, select only account name that matches account name exactly
            $ntfsaccess = Get-NTFSAccess $folder | where {$_.account.accountname -eq $account}

                #If Account match was found
                If ($ntfsaccess -ne $null) {

                    #write to host
                    #write-host "$account had access to $folder on $destination" -ForegroundColor green
                    #Write to log
                    Add-Content -value "$account had access to $folder on $destination" -path $log
               }
           }
       }
#If there were any access errors
If ($accessdenied -ne $null) {
    #Write Each error to log
    ForEach ($accessdeniederror in $accessdenied){
    #write to host
    #write-host  "$acccessdeniederror encountered on $destination" -ForegroundColor red 
    #write to log 
    Add-Content -Value "$acccessdeniederror encountered on $destination" -path $log 
}
}
}
}
#call function which finds shares
$sharestosearch = Get-SharesToSearch -Servers $Servers

#for each, log what will be traversed
ForEach ($share in $sharestosearch) {
Add-Content "Will search $share" -path $log
} 

#For Each share, check account using function
ForEach ($share in $sharestosearch){
    $subfolders = Get-Childitem -path $share -directory 
        ForEach ($folder in $subfolders) {
            $foldername = $folder.fullname
            #Max Concurrent Jobs to run
            $Jobs = 50
            #Do loop to keep jobs @ 100 max
            Do
                {
                $Job = (Get-Job -State Running | measure).count
               } Until ($Job -le $Jobs)
            #Create job with $findpermsfuction in intializationscript to allow job to access.  
            Start-Job -Name $foldername -InitializationScript {$findpermsfunction} -ArgumentList ($log,$foldername,$accounts) -ScriptBlock { 
                    #Rebuild variable inside scritblock
                    $log = $args[0]
                    $destination = $args[1]
                    $accounts = $args[2]                 
                    Get-ChildItemCheckPerms -accounts $accounts -log $log -destination $destination
                    }
                                            }
Get-Job -State Completed | Remove-Job
    }


Wait-Job -State Running
Get-Job -State Completed | Remove-Job
Get-Job
