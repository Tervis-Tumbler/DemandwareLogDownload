# DemandwareLogDownload
PowerShell module to download log files for a demandware environment including the abiltity to download only the deltas of logs as they grow over time.

#Example
```PowerShell
$Credential = Get-Credential "<DemandwareBusinessMangaerAccountWithWebDAVAccess>"
$DemandwareInstanceURI = "https://<NameOfYourEnvironment>.demandware.net"
$LogFileDestination = "\\path\to\Logs\Production\Demandware"

Sync-DemandwareLogFile -Credential $Credential -DemandwareInstanceURI $DemandwareInstanceURI -LogFileDestination $LogFileDestination
```
