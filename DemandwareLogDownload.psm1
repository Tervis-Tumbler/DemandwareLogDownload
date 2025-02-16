﻿#Requires -Version 5
#Requires –Modules Get-CharacterEncoding

filter Mixin-DemandWareLogFileMetaDataProperties {
    $_ | Add-Member -MemberType ScriptProperty -Name FileName -Value { $([System.IO.FileInfo]$This.URI).Name }
}

function Get-DemandwareLogFileMetaData {
    [CmdletBinding()]
    param(
        $DemandwareInstanceURI,
        $Credential,
        [switch]$ParseMetaDataWithSelectString = $false
    )
    
    $DemandwareWebDavLogURI = "$DemandwareInstanceURI/on/demandware.servlet/webdav/Sites/Logs"
    $Result = Invoke-WebRequest -Uri $DemandwareWebDavLogURI -Credential $Credential

    if ($ParseMetaDataWithSelectString) {
        $Template = Get-Content $PSScriptRoot\DemandwareLogFileMetaDataTemplate.txt | Out-String
        $DemandwareLogFilesMetaData = $result.Content | ConvertFrom-String -TemplateContent $Template
    } else {
    
        $Tables = @($Result.ParsedHtml.getElementsByTagName("TABLE"))

        $DemandwareLogFilesMetaData = foreach ($Table in $Tables) {
            $Rows = @($Table.Rows)
            foreach ($Row in $Rows[1..$Rows.Length]) {
                $Cells = @($Row.cells)
                [pscustomobject][ordered]@{
                    URI = $("/" + $($Cells[0].childNodes | where tagname -match "A" | select -ExpandProperty pathname));
                    Size = $Cells[1].innerText.Trim();
                    LastModified = [datetime]$Cells[2].innerText.Trim();
                }
            }
        }
        $DemandwareLogFilesMetaData = $DemandwareLogFilesMetaData | where {$_.size}
    }

    $DemandwareLogFilesMetaData | Mixin-DemandWareLogFileMetaDataProperties
    $DemandwareLogFilesMetaData
}

function Invoke-DemandWareLogFileDownload {
    param(
        $DemandwareLogFileMetaData,
        $DemandwareInstanceURI,
        $Credential,
        $PathToDemandwareLogFileOnDisk
    )
        $URIOfDemandwareLogFile = "$DemandwareInstanceURI$($DemandwareLogFileMetaData.URI)"
        
        Invoke-WebRequest -Uri $URIOfDemandwareLogFile -Credential $Credential |
        Select -ExpandProperty Content |
        Out-File $PathToDemandwareLogFileOnDisk -Encoding ascii -NoNewline #Should be UTF-8 but currently there is no support for supression the BOM which breaks java/logstash
        
        $NewlyCreatedDemandwareLogFile = Get-Item $PathToDemandwareLogFileOnDisk
        $NewlyCreatedDemandwareLogFile.LastWriteTime = $DemandwareLogFileMetaData.LastModified
}

function Invoke-DemandWarePartialLogFileDownload {
    param(
        $DemandwareLogFileMetaData,
        $DemandwareInstanceURI,
        $Credential,
        $PathToDemandwareLogFileOnDisk
    )
    $URIOfDemandwareLogFile = "$DemandwareInstanceURI$($DemandwareLogFileMetaData.URI)"
        
    $DemandwareLogFileCharacterEncoding = Get-Item $DemandwareLogFileOnDisk | Get-FileCharacterEncoding
    if($DemandwareLogFileCharacterEncoding.EncodingName -ne "Unicode (UTF-8)") { 
        Throw @"
Appending to the end of a file instead of downloading the whole file is only supported for ASCII or UTF-8 character encoded files.
$DemandwareLogFileOnDisk's character encoding is $($DemandwareLogFileCharacterEncoding.EncodingName).
"@
    }

    $RangeIndexOfStartingByteWeNeedToAddToFileOnDisk = $DemandwareLogFileOnDisk.length
    $HeadResult = Invoke-WebRequest -Uri $URIOfDemandwareLogFile -Credential $Credential -Method Head
    $DemandwareLogFileTotalBytesOnServer = [int]$HeadResult.Headers.'Content-Length'

    if ($RangeIndexOfStartingByteWeNeedToAddToFileOnDisk -lt $DemandwareLogFileTotalBytesOnServer) {
        
        $WebRequest = [System.Net.WebRequest]::Create($URIOfDemandwareLogFile)
        $WebRequest.AddRange($RangeIndexOfStartingByteWeNeedToAddToFileOnDisk) 
        $WebRequest.Credentials = $Credential.GetNetworkCredential()
        $WebResponse = $WebRequest.GetResponse()
        $WebResponseStream = $WebResponse.GetResponseStream()
        $StreamReader = new-object System.IO.StreamReader $WebResponseStream
        $ResponeData = $StreamReader.ReadToEnd()
        if ($ResponeData) {
            $ResponeData | Out-File -Append $DemandwareLogFileOnDisk -Encoding ascii -NoNewline

            $ResponeData | Format-List * | Out-String -Stream | Write-Verbose

            $NewlyCreatedDemandwareLogFile = Get-Item $PathToDemandwareLogFileOnDisk
            $NewlyCreatedDemandwareLogFile.LastWriteTime = $DemandwareLogFileMetaData.LastModified
        } else { throw "ResponseData came back empty for the requested range" }
    } elseif ($RangeIndexOfStartingByteWeNeedToAddToFileOnDisk -eq $DemandwareLogFileTotalBytesOnServer) {
        $DemandwareLogFile = Get-Item $PathToDemandwareLogFileOnDisk
        $DemandwareLogFile.LastWriteTime = $DemandwareLogFileMetaData.LastModified
    } else {
        Throw "The file on Disk was bigger than the size of the file on the server"
    }    
}


function Sync-DemandwareLogFile {
    [CmdletBinding()]
    param(
        $DemandwareInstanceURI,
        $Credential,
        $LogFileDestination
    )
    
    $DemandwareLogFilesMetaData = Get-DemandwareLogFileMetaData -DemandwareInstanceURI $DemandwareInstanceURI -Credential $Credential
    #$DemandwareLogFilesMetaData = $DemandwareLogFilesMetaData | where {
    #    $_.FileName -match "customerror-" -or
    #    $_.FileName -match "error-" -or
    #    $_.FileName -match "custom-int_bronto-" -or
    #    $_.FileName -match "jobs-" -or
    #    $_.FileName -match "service-taxware-"
    #}

    Foreach ($DemandwareLogFileMetaData in $DemandwareLogFilesMetaData) {
        $PathToDemandwareLogFileOnDisk = "$LogFileDestination\$($DemandwareLogFileMetaData.FileName)"
        $URIOfDemandwareLogFile = "$DemandwareInstanceURI$($DemandwareLogFileMetaData.URI)"

        $DemandwareLogFileOnDisk = Get-Item $PathToDemandwareLogFileOnDisk -ErrorAction SilentlyContinue

        if ( -not $DemandwareLogFileOnDisk) {
            Write-Verbose "$(Get-Date): File not found on disk $PathToDemandwareLogFileOnDisk, downloading file"
            Invoke-DemandWareLogFileDownload -DemandwareLogFileMetaData $DemandwareLogFileMetaData -DemandwareInstanceURI $DemandwareInstanceURI -Credential $Credential -PathToDemandwareLogFileOnDisk $PathToDemandwareLogFileOnDisk
        } elseif ($DemandwareLogFileOnDisk.LastWriteTime -lt $DemandwareLogFileMetaData.LastModified) {                  
            Write-Verbose "$(Get-Date): File found on disk and is old $PathToDemandwareLogFileOnDisk $URIOfDemandwareLogFile $($DemandwareLogFileOnDisk.length) DemandwareLogFileOnDisk.LastWriteTime: $($DemandwareLogFileOnDisk.LastWriteTime) DemandwareLogFileMetaData.LastModified: $($DemandwareLogFileMetaData.LastModified)"
            Invoke-DemandWarePartialLogFileDownload -DemandwareLogFileMetaData $DemandwareLogFileMetaData -DemandwareInstanceURI $DemandwareInstanceURI -Credential $Credential -PathToDemandwareLogFileOnDisk $PathToDemandwareLogFileOnDisk
        }
    }
}