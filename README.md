# DemandwareLogDownload
PowerShell module to download log files for a demandware environment including the abiltity to download only the deltas of logs as they grow over time.


#Setup
* Ensure you have [Windows Management Framework 5](https://www.microsoft.com/en-us/download/details.aspx?id=50395) installed
* `git clone https://github.com/Tervis-Tumbler/DemandwareLogDownload.git` into one of the paths in `$env:PSModulePath`
 
#Example
```PowerShell
$Credential = Get-Credential "<DemandwareBusinessMangaerAccountWithWebDAVAccess>"
$DemandwareInstanceURI = "https://<NameOfYourEnvironment>.demandware.net"
$LogFileDestination = "\\path\to\Logs\Production\Demandware"

Sync-DemandwareLogFile -Credential $Credential -DemandwareInstanceURI $DemandwareInstanceURI -LogFileDestination $LogFileDestination
```
