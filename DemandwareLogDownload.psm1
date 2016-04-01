#Requires -Version 5
filter Mixin-DemandWareLogFileProperties {
    $_ | Add-Member -MemberType ScriptProperty -Name FileName -Value { $([System.IO.FileInfo]$DemandwareLogFile.URI).Name }
}

function Get-DemandwareLogFile {
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

    $DemandwareLogFiles = $result.Content | ConvertFrom-String -TemplateContent $Template
    $DemandwareLogFiles | Mixin-DemandWareLogFileProperties
    $DemandwareLogFiles
}


function Sync-DemandwareLogFile {
    [CmdletBinding()]
    param(
        $DemandwareInstanceURI,
        $Credential,
        $LogFileDestination
    )
    
    $DemandwareLogFiles = Get-DemandwareLogFile -DemandwareInstanceURI $DemandwareInstanceURI -Credential $Credential

    Foreach ($DemandwareLogFile in $DemandwareLogFiles) {
        $PathToDemandwareLogFileOnDisk = "$LogFileDestination\$($DemandwareLogFile.FileName)"
        $URIOfDemandwareLogFile = "$DemandwareInstanceURI$($DemandwareLogFile.URI)"

        $DemandwareLogFileOnDisk = Get-Item $PathToDemandwareLogFileOnDisk -ErrorAction SilentlyContinue

        if ( -not $DemandwareLogFileOnDisk) {
            Write-Debug "File not found on disk $PathToDemandwareLogFileOnDisk, downloading file"
        
            Invoke-WebRequest -Uri $URIOfDemandwareLogFile -Credential $Credential |
            Select -ExpandProperty Content |
            Out-File $PathToDemandwareLogFileOnDisk -NoNewline
        
            $NewlyCreatedDemandwareLogFile = Get-Item $PathToDemandwareLogFileOnDisk
            $NewlyCreatedDemandwareLogFile.LastWriteTime = $DemandwareLogFile.LastModified

        } else {

            if ($DemandwareLogFileOnDisk.LastWriteTime -lt $DemandwareLogFile.LastModified) {      
                Write-Debug "File found on disk and is old $PathToDemandwareLogFileOnDisk $URIOfDemandwareLogFile $($File.length) $($DemandwareLogFile.LastModified)"

                # Powershell Out-* commandlets default to UTF-16 using two bytes for each character, demandware's servers are storing the logs in an encoding which uses one byte per character
                $LengthOfUTF16EncodedFileOnDisk = $DemandwareLogFileOnDisk.length
                $LenghtOfFileContentAsIfStoredOnDemandware = $LengthOfUTF16EncodedFileOnDisk/2

                # -1 because http range header usese a zero-indexed range, requesting the 2nd byte to the end of the file would be 1-, 1st byte to end 0-
                $RangeIndexOfStartingByteWeNeedToAddToFileOnDisk = $LenghtOfFileContentAsIfStoredOnDemandware-1
            
                $WebRequest = [System.Net.WebRequest]::Create($URIOfDemandwareLogFile)
                $WebRequest.AddRange($RangeIndexOfStartingByteWeNeedToAddToFileOnDisk) 
                $WebRequest.Credentials = $Credential.GetNetworkCredential()
                $WebResponse = $WebRequest.GetResponse()
                $WebResponseStream = $WebResponse.GetResponseStream()
                $StreamReader = new-object System.IO.StreamReader $WebResponseStream
                $ResponeData = $StreamReader.ReadToEnd()
                $ResponeData | Out-File -Append $DemandwareLogFileOnDisk -NoNewline

                Write-Debug $ResponeData

                $NewlyCreatedDemandwareLogFile = Get-Item $PathToDemandwareLogFileOnDisk
                $NewlyCreatedDemandwareLogFile.LastWriteTime = $DemandwareLogFile.LastModified
            }
        }
    }
}