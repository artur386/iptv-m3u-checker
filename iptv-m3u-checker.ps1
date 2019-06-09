param (
    [Parameter(Mandatory = $true)][string]$Path,
    [switch]$Multioutput = $false,
    [switch]$OutLogs = $false,
    [switch]$OnlyWorking = $false,
    [switch]$version = $false,
    [string]$LogPath = $("C:\Logs\Log_" + $(Get-Date -UFormat "%H%M%d%m%y") + ".log"),
    [int32]$Thread = $((Get-CIMInstance -Class 'CIM_Processor').NumberOfLogicalProcessors * (Get-CIMInstance -Class 'CIM_Processor').NumberOfCores)
)


class Playlist
{
    [System.IO.FileSystemInfo]$filesysteminfo
    [string]$uri
    [string]$name
    [string]$ext
    [string]$suffixTrue = "_working"
    [string]$suffixFalse = "_notWorking"
    [int32]$playlistsNumber = 0
    [int32]$chanelNumbers = 0
    [int32]$chanelTrue = 0
    [int32]$chanelFalse = 0
    [int32]$thread = 1
    [bool]$outLogs = $false
    [bool]$valid = $false
    [bool]$validContent = $false
    [bool]$updateStatus = $false
    [String[]]$contentLines
    [String[]]$contentString
    [PSObject[]]$medialist
    [PSObject[]]$testedList

    Playlist([System.IO.FileInfo]$inputFile, $Thread, $OutLogs, $playlistsNumber)
    {
        $this.filesysteminfo = $inputFile
        $this.outLogs = $OutLogs
        $this.thread = $Thread
        $this.playlistsNumber = $playlistsNumber
        if (Test-Path($this.filesysteminfo.FullName))
        {
            $this.uri = $inputFile.FullName
            $this.name = $inputFile.BaseName
            $this.ext = $inputFile.Extension
            $this.Open()
            $this.Cut()
            if ($this.valid)
            {
                $this.chanelNumbers = $this.medialist.Count
            }
        }
    }


    [void] RunTest()
    {
        if (!$this.valid)
        {
            break
        }
        $RunspaceCollection = @()
        $qwinstaResults = New-Object System.Collections.ArrayList
        $RunspacePool = [RunspaceFactory]::CreateRunspacePool(1, $this.thread)
        $RunspacePool.Open()
        $ScriptBlock =
        {
            param(
                [string]$Time,
                [string[]]$Attributes,
                [string]$Name,
                [string]$Uri
            )

            [string]$ErrorMessage = ""

            try
            {
                ffprobe.exe -loglevel -8 -rw_timeout 100000 -i $Uri
            }
            Catch
            {
                $ErrorMessage = $_.Exception.Message
                $Status = $false
                Break
            }
            finally
            {
                if ($?)
                {
                    $Status = $true
                }
                else
                {
                    $Status = $false
                }
            }
 
            return New-Object PSObject -Property @{
                Time         = $Time
                Attributes   = $Attributes
                Name         = $Name
                Uri          = $Uri
                Status       = $Status
                ErrorMessage = $ErrorMessage
            }
        }

        Foreach ($item in $this.medialist)
        {
            $Powershell = [PowerShell]::Create().AddScript($ScriptBlock).AddArgument($item.Time).AddArgument($item.Attributes).AddArgument($item.Name).AddArgument($item.Uri)
            $Powershell.RunspacePool = $RunspacePool
            [Collections.Arraylist]$RunspaceCollection += New-Object -TypeName PSObject -Property @{
                Runspace   = $PowerShell.BeginInvoke()
                PowerShell = $PowerShell  
            }
        }

        While ($RunspaceCollection)
        {
            Foreach ($Runspace in $RunspaceCollection.ToArray())
            {
                If ($Runspace.Runspace.IsCompleted)
                {
                    [void]$qwinstaResults.Add($Runspace.PowerShell.EndInvoke($Runspace.Runspace))
                    $this.chanelNumbers--
                    if ($qwinstaResults[-1].Status)
                    {
                        $this.chanelTrue++
                        if (!$this.validContent) 
                        {
                            $this.validContent = $true
                        }
                    }
                    else
                    {
                        $this.chanelFalse++
                    }
                    $this.PrintStatus()
                    $Runspace.PowerShell.Dispose()
                    $RunspaceCollection.Remove($Runspace)
			
                }
            }
        }

        foreach ($item in $qwinstaResults)
        {
            $this.testedList += New-Object PSObject -Property @{
                Time         = $item[0].Time
                Attributes   = $item[0].Attributes
                Name         = $item[0].Name
                Uri          = $item[0].Uri
                Status       = $item[0].Status
                ErrorMessage = $item[0].ErrorMessage
            }
        }
    }

    [void] PrintStatus()
    {
        $tempStatus = @{
            Nb      = [string]::Format("{0,4}", $this.playlistsNumber)
            Name    = [string]::Format("{0,34}", $this.name)
            Valid   = [string]::Format("{0,7}", $this.valid)
            ChNum   = [string]::Format("{0,8}", $this.chanelNumbers)
            ChTrue  = [string]::Format("{0,9}", $this.chanelTrue)
            ChFalse = [string]::Format("{0,12}", $this.chanelFalse)
        }

        [int32]$x = 0
        [int32]$y = 9 + $this.playlistsNumber
        if (!$this.updateStatus)
        {
            if ($tempStatus.Name.Length -gt 34)
            {
                $tempStatus.Name = $($tempStatus.Name.Substring(0, 31) + "...")
            }

            [System.Console]::SetCursorPosition($x, $y)
            Write-Host -Object $([string]::Format("{0,4} |{1,34} |{2,7} |{3,8} |{4,9} |{5,12} |", " ", " ", " ", " ", " ", " ")) -NoNewline -ForegroundColor White
            $this.updateStatus = $true
            [System.Console]::SetCursorPosition($x, $y)
            Write-Host -Object $tempStatus.Nb -ForegroundColor Yellow -NoNewline
            
            $x = [System.Console]::CursorLeft + 2
            [System.Console]::SetCursorPosition($x, $y)
            Write-Host -Object $tempStatus.Name -ForegroundColor Yellow -NoNewline
            
            $x = [System.Console]::CursorLeft + 2
            [System.Console]::SetCursorPosition($x, $y)
            Write-Host -Object $tempStatus.Valid -ForegroundColor DarkYellow -NoNewline
            
            $x = [System.Console]::CursorLeft + 2
            [System.Console]::SetCursorPosition($x, $y)
            Write-Host -Object $tempStatus.ChNum -ForegroundColor Yellow -NoNewline
            
            $x = [System.Console]::CursorLeft + 2
            [System.Console]::SetCursorPosition($x, $y)
            Write-Host -Object $tempStatus.ChTrue -ForegroundColor Green -NoNewline
            
            $x = [System.Console]::CursorLeft + 2
            [System.Console]::SetCursorPosition($x, $y)
            Write-Host -Object $tempStatus.ChFalse -ForegroundColor Red -NoNewline


        }
        if ($this.updateStatus)
        {
            $x = 51
            [System.Console]::SetCursorPosition($x, $y)
            Write-Host -Object $tempStatus.ChNum -ForegroundColor Yellow -NoNewline
            
            $x += 10
            [System.Console]::SetCursorPosition($x, $y)
            Write-Host -Object $tempStatus.ChTrue -ForegroundColor Green -NoNewline
            
            $x += 11
            [System.Console]::SetCursorPosition($x, $y)
            Write-Host -Object $tempStatus.ChFalse -ForegroundColor Red -NoNewline

        }
        
        [System.Console]::SetCursorPosition(0, $(10 + $this.playlistsNumber))
    }


    [string[]] GetTrue([bool]$AddHeader)
    {
        [string[]]$tempList = @()
        if ($AddHeader)
        {
            $tempList += "#EXTM3U"
        }
        foreach ($item in $($this.testedList | Where { $_.Status -eq $true }))
        {
            [string]$tempArgs = ""
            if ($item.Attributes.Count -gt 0)
            {
                $tempArgs = $($item.Attributes -join " ").Trim()
            }
            [string[]]$tempList += [String]::Format("#EXTINF:{0} {1},{2}`n{3}", $item.Time, $tempArgs, $item.Name, $item.Uri)
        }
        return $tempList
    }

    [string[]] GetFalse([bool]$AddHeader)
    {
        [string[]]$tempList = @()
        if ($AddHeader)
        {
            $tempList += "#EXTM3U"
        }
        foreach ($item in $($this.testedList | Where { $_.Status -eq $false }))
        {
            [string]$tempArgs = ""
            if ($item.Attributes.Count -gt 0)
            {
                $tempArgs = $($item.Attributes -join " ").Trim()
            }
            [string[]]$tempList += [String]::Format("#EXTINF:{0} {1},{2}`n{3}", $item.Time, $tempArgs, $item.Name, $item.Uri)
        }
        return $tempList
    }



    [void] Cut()
    {
        foreach ($media in $([regex]::Matches($this.contentString, "\#EXTINF\:(\-1|\d+)\s*(.*)\,\s*(.*)[\r\n]+\s*([\S]*)")))
        {   
            $media = @{
                Time         = $media.Groups[1].Value
                Attributes   = $media.Groups[2].Value.Trim().Split(" ")
                Name         = $media.Groups[3].Value
                Uri          = $media.Groups[4].Value
                Status       = $null
                ErrorMessage = $null
            }
            
            $this.medialist += New-Object -TypeName PSObject -Property $media
        }
        if ($this.medialist.Count -gt 0)
        {
            $this.valid = $true
        }
        else
        {
            $this.valid = $false
        }

    }
    [void] Open()
    {
        foreach ($line in [IO.File]::ReadAllLines($this.uri))
        {
            # if (!$this.valid)
            # {
            #     if ($line.Trim() -match "#EXTM3U")
            #     {
            #         $this.valid = $true
            #         continue
            #     }
            #     else 
            #     {
            #         continue
            #     }
                
            # }
            # else
            # {   
            if (![string]::IsNullOrWhiteSpace($line))
            {
                $this.contentLines += $line.Trim()
                continue
            }
            # }
            
        }
        $this.contentString = $this.contentLines -join "`n"

    }
}

# write-host $Multioutput
# exit
$menu = @"
   ------------------------------------------------------------------------------
    IPTV PLAYLIST CHECKER
   ------------------------------------------------------------------------------

Playlists:

-----+-----------------------------------+--------+---------+----------+-------------+
 Nb. |               Name                | Valid  | Ch.Num  | Working  | NotWorking  |
-----+-----------------------------------+--------+---------+----------+-------------+
"@
[System.Console]::CursorVisible = $false
clear-host
Write-Host -Object $menu -NoNewLine

if ($OutLogs)
{
    New-Item -Path $LogPath -Force
}
[System.Array]$inputs = $null
$PlayLists = New-Object System.Collections.ArrayList
try
{
    $inputs += Get-ChildItem -Path $Path
}
catch
{
    Write-Error -Message $_.Exception.Message
    break
}
finally
{
    for ($i = 0; $i -lt $inputs.Count; $i++)
    {
        [void]$PlayLists.Add([Playlist]::new($inputs[$i], $Thread, $OutLogs, $i))
        $PlayLists[-1].PrintStatus()
        Write-Host -Object "-----+-----------------------------------+--------+---------+----------+-------------+" -NoNewline
    }
}

try
{
    foreach ($item in $PlayLists)
    {
        $item.RunTest()
    }
}
catch
{
    Write-Error -Message $_.Exception.Message
    break
}
finally
{
    if ($Multioutput)
    {
        foreach ($item in $PlayLists)
        {
            if ($item.ValidContent)
            {
                [IO.File]::WriteAllLines([System.IO.Path]::Combine($item.filesysteminfo.DirectoryName, $($item.filesysteminfo.BaseName + $item.suffixTrue + $item.filesysteminfo.Extension)), $item.GetTrue($true))
            }
            if (!$OnlyWorking)
            {
                [IO.File]::WriteAllLines([System.IO.Path]::Combine($item.filesysteminfo.DirectoryName, $($item.filesysteminfo.BaseName + $item.suffixFalse + $item.filesysteminfo.Extension)), $item.GetFalse($true))
            }
        }
    }
    else #SingleOutput
    {
        [string[]]$tempTrue = @()
        $tempTrue += "#EXTM3U"
        [string[]]$tempFalse = @()
        $tempFalse += "#EXTM3U"

        foreach ($item in $PlayLists)
        {
            if ($item.ValidContent)
            {
                $tempTrue += $item.GetTrue($false)
            }
            $tempFalse += $item.GetFalse($false)
        }
        if ($tempTrue.Count -gt 1)
        {
            [IO.File]::WriteAllLines([System.IO.Path]::Combine($(Get-Location), $($(Get-Date -UFormat "%H%M%d%m%y") + '_working.m3u')), $tempTrue)
        }
        if (!$OnlyWorking)
        {
            [IO.File]::WriteAllLines([System.IO.Path]::Combine($(Get-Location), $($(Get-Date -UFormat "%H%M%d%m%y") + '_notWorking.m3u')), $tempFalse)
        }
    }
    [System.Console]::SetCursorPosition(0, $($PlayLists.Count + 11))
    [System.Console]::CursorVisible = $true
}

