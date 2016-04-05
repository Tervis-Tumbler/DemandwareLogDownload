#Requires -Version 5
#Requires –Modules Get-CharacterEncoding

filter Mixin-DemandWareLogFileMetaDataProperties {
    $_ | Add-Member -MemberType ScriptProperty -Name FileName -Value { $([System.IO.FileInfo]$This.URI).Name }
}

function Get-DemandwareLogFileMetaData {
    [CmdletBinding()]
    param(
        $DemandwareInstanceURI,
        $Credential
    )
    
    $DemandwareWebDavLogURI = "$DemandwareInstanceURI/on/demandware.servlet/webdav/Sites/Logs"
    $Result = Invoke-WebRequest -Uri $DemandwareWebDavLogURI -Credential $Credential

    $Template = @"
            <a href="/on/demandware.servlet/webdav/Sites/Logs/dbinit-sql"><tt>dbinit-sql</tt></a>
            <a href="/on/demandware.servlet/webdav/Sites/Logs/deprecation"><tt>deprecation</tt></a>
            <a href="{URI*:/on/demandware.servlet/webdav/Sites/Logs/analyticsengine-blade0-0-appserver-20160329.log}"><tt>analyticsengine-blade0-0-appserver-20160329.log</tt></a>
                        <td align="right"><tt>{[decimal]FileSize:0.1} kb</tt></td>
                        <td align="right"><tt>{[DateTime]LastModified:Tue, 29 Mar 2016 03:07:37 GMT}</tt></td>
            <a href="{URI*:/on/demandware.servlet/webdav/Sites/Logs/analyticsengine-blade1-2-appserver-20160329.log}"><tt>analyticsengine-blade1-2-appserver-20160329.log</tt></a>
                        <td align="right"><tt>{[decimal]FileSize:10.0} kb</tt></td>
                        <td align="right"><tt>{[DateTime]LastModified:Wed, 30 Mar 2016 21:56:10 GMT}</tt></td>
            <a href="{URI*:/on/demandware.servlet/webdav/Sites/Logs/analyticsengine-blade1-7-appserver-20160328.log}"><tt>analyticsengine-blade1-7-appserver-20160328.log</tt></a>
                    <td align="right"><tt>{[decimal]FileSize:202.7} kb</tt></td>
            <a href="{URI*:/on/demandware.servlet/webdav/Sites/Logs/api-blade0-0-appserver-20160329.log}"><tt>api-blade0-0-appserver-20160329.log</tt></a>
                    <td align="right"><tt>{[decimal]FileSize:8.8} kb</tt></td>
            <a href="{URI*:/on/demandware.servlet/webdav/Sites/Logs/custom-int_bronto-blade0-0-appserver-20160329.log}"><tt>custom-int_bronto-blade0-0-appserver-20160329.log</tt></a>
                    <td align="right"><tt>{[decimal]FileSize:227.9} kb</tt></td>
            <a href="{URI*:/on/demandware.servlet/webdav/Sites/Logs/custom-int_bronto-blade1-2-appserver-20160329.log}"><tt>custom-int_bronto-blade1-2-appserver-20160329.log</tt></a>
                    <td align="right"><tt>{[decimal]FileSize:23.3} kb</tt></td>
            <a href="{URI*:/on/demandware.servlet/webdav/Sites/Logs/jceProviderUsage-blade0-0-appserver.log}"><tt>jceProviderUsage-blade0-0-appserver.log</tt></a>
"@

    $DemandwareLogFilesMetaData = $result.Content | ConvertFrom-String -TemplateContent $Template
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
        
        $DemandwareLogFileCharacterEncoding = Get-FileCharacterEncoding -Path $DemandwareLogFileOnDisk
        if($DemandwareLogFileCharacterEncoding.EncodingName -ne "Unicode (UTF-8)") { 
            Throw @"
Appending to the end of a file instead of downloading the whole file is only supported for ASCII or UTF-8 character encoded files.
$DemandwareLogFileOnDisk's character encoding is $($DemandwareLogFileCharacterEncoding.EncodingName).
"@
        }
        $RangeIndexOfStartingByteWeNeedToAddToFileOnDisk = $DemandwareLogFileOnDisk.length

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
}


function Sync-DemandwareLogFile {
    [CmdletBinding()]
    param(
        $DemandwareInstanceURI,
        $Credential,
        $LogFileDestination
    )
    
    $DemandwareLogFilesMetaData = Get-DemandwareLogFileMetaData -DemandwareInstanceURI $DemandwareInstanceURI -Credential $Credential

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