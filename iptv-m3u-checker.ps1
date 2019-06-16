<#
.SYNOPSIS
    IPTV-PLAYLIST-CHECKER to checking playlist iptv
 
.DESCRIPTION
    
 
.PARAMETER Thread
    Number of Background Thread running in same time.
 
.PARAMETER UseFFProbe
    -UseFFProbe testing url with ffprobe.
  
.EXAMPLE
     iptv-m3u-checker.ps1 -Path "C:\iptv.m3u"
 
.EXAMPLE
     iptv-m3u-checker.ps1 -Path "C:\iptv.m3u" -Thread 32 -OnlyWorking
 
.INPUTS
    None
 
.OUTPUTS
    None
 
.NOTES
    Author:  Artur P.
#>

param (
    # Path to file
    [Parameter(Mandatory = $true)]
    [string]$Path,

    # to join readed playlists and save it into one file
    [switch]$SingleOutput = $false,

    # to use ffprobe for checking url
    [switch]$UseFFProbe = $false,

    # not working yet 
    [switch]$OutLogs = $false,

    # save only working playlists
    [switch]$OnlyWorking = $false,

    # not working yet 
    [switch]$version = $false,

    # not working yet 
    [string]$LogPath = $("C:\Logs\Log_" + $(Get-Date -UFormat "%Y%m%d%H%M%S") + ".log"),

    # numbers of running Threades into background
    [int32]$Thread = [int32]$((Get-CIMInstance -Class 'CIM_Processor').NumberOfLogicalProcessors * (Get-CIMInstance -Class 'CIM_Processor').NumberOfCores),

    # how many time file is checked if return error.
    [int32]$ErrorRepeat = 2
)

Begin
{
    class Chanel
    {
        [int32]$Nb
        [string]$Attributes
        [string]$Name
        [string]$Url
        [string]$Message
        [bool]$Status

        Chanel ([string]$Attributes, [string]$Name, [string]$Url, [int32]$Nb)
        {
            $this.Nb = $Nb
            $this.Attributes = $Attributes
            $this.Name = $Name
            $this.Url = $Url
            $this.Status = $null
        }

        [void] SetStatus ([bool]$Status)
        {
            $this.Status = $Status
        }
        [bool] GetStatus ()
        {
            return $this.Status
        }
        [void] SetMessage ([string]$Message)
        {
            $this.Message = $Message
        }
        [string] GetMessage ()
        {
            return $this.Message
        }
        [int32] GetNb ()
        {
            return $this.Nb
        }
        [string] GetUrl ()
        {
            return $this.Url
        }
        [string] GetChanel()
        {
            return [string]::Format("#EXTINF:{0},{1}`n{2}`n", $this.Attributes, $this.Name, $this.Url)
        }
    }


    class Playlist
    {
        [System.IO.FileSystemInfo]$playlistFile
        [int32]$ProbeMethod
        [int32]$nb
        [int32]$totalChanelsNumber
        [int32]$trueChNumber
        [int32]$falseChNumber
        [int32]$ErrorRepeat
        [int32]$timeOut
        [int32]$thread
        [DateTime]$CreateTime
        [DateTime]$ProbeTime
        [INT]$TotalTime
        [int]$itemInPool
        [string]$trueOutPath
        [string]$falseOutPath
        [bool]$validContent
        [System.Collections.ArrayList]$Chanels
        $xyPos = @{
            x = 0
            y = 9
        }


        Playlist([System.IO.FileInfo]$File, [int]$Thread = $((Get-CIMInstance -Class 'CIM_Processor').NumberOfCores + 1), [int]$playlistsNumber, [int]$ErrorRepeat = 3, [int]$ProbeMethod = 1)
        {
            $this.playlistFile = $File
            $this.CreateTime = Get-Date
            $this.trueOutPath = [System.IO.Path]::Combine($this.playlistFile.DirectoryName, "iptv-Working", $this.playlistFile.Name)
            $this.falseOutPath = [System.IO.Path]::Combine($this.playlistFile.DirectoryName, "iptv-NotWorking", $this.playlistFile.Name)
            $this.ErrorRepeat = $ErrorRepeat
            $this.ProbeMethod = $ProbeMethod
            $this.thread = $Thread
            $this.timeOut = 3000
            $this.nb = $playlistsNumber
            $this.itemInPool = 0
            $this.validContent = $null
            $this.xyPos.y += $this.nb
            $this.Chanels = New-Object System.Collections.ArrayList
        }

        [void] SetProbeMethod([int]$ProbeMethod)
        {
            $this.ProbeMethod = $ProbeMethod
        }
        [int32] GetProbeMethod()
        {
            return $this.ProbeMethod
        }
        [void] SetTotalTime()
        {
            $this.TotalTime = [int]$(New-TimeSpan -Start $this.CreateTime -End $this.ProbeTime).TotalSeconds
        }
        [string] GetTime()
        {
            $local:tempTime = New-TimeSpan -Seconds $this.TotalTime
            return  [string]::format("{0:d2}:{1:d2}:{2:d2}", [int]$tempTime.Hours, [int]$tempTime.Minutes, [int]$tempTime.Seconds)
        }

        [string] GetPrintOut ()
        {
            return [string]::Format(
                "|{0,3} |{1,34} |{2,8} |{3,10} |{4,10} |{5,10} |{6,10} | {7,14}  |",
                $($this.nb + 1),
                $this.playlistFile.BaseName,
                $this.validContent,
                $this.totalChanelsNumber,
                $this.itemInPool,
                $this.trueChNumber,
                $this.falseChNumber,
                $this.GetTime()
            )
        }

        [void] Parser()
        {
            [string]$local:content = ([System.IO.File]::ReadAllText($this.playlistFile.FullName)).Replace("`r", "")

            ForEach ($Match in ($content | Select-String -Pattern "(?m)#EXTINF:(.*?)\s*\,\s*(.*)\s*\n[\n\s]*(\w+:\/\/\S+)" -AllMatches).Matches)
            {
                [void]$this.Chanels.Add([Chanel]::new(
                        $Match.Groups[1].Value,
                        $Match.Groups[2].Value,
                        $Match.Groups[3].Value,
                        $this.totalChanelsNumber
                    )
                )
                $this.totalChanelsNumber++
                $this.RefreshScreen($this.totalChanelsNumber, 15)
                $this.ProbeTime = Get-Date
                $this.SetTotalTime()
            }
            if ($this.Chanels.Count -gt 0)
            {
                $this.validContent = $true
            }
            else
            {
                $this.validContent = $false
            }
            $this.RefreshScreen($this.totalChanelsNumber, 1)
        }

    
        [void] ProbeIt()
        {
            if ($this.validContent)
            {
                $ffScriptBlock = {
                    Param(
                        [int32]$method,
                        [int32]$nb,
                        [int32]$timeout,
                        [int32]$errCounter,
                        [string]$url
                    )
                    [bool]$local:rStatus = $null
                    [string]$local:Message = [string]::Empty()
                    if ($method -eq 1)
                    {
                        while ([bool]$errCounter)
                        {
                            try
                            {
                                $request = [System.Net.WebRequest]::Create($url)
                                $request.timeout = $timeout
                                $resp = $request.GetResponse()
                                if ([int]$resp.StatusCode -eq 200)
                                {
                                    $rStatus = $true
                                }
                                else
                                {
                                    $rStatus = $false
                                }
                                if ([int]$resp.ContentLength -gt 0 -and [int]$resp.ContentLength -lt 230)
                                {
                                    $sr = new-object System.IO.StreamReader ($resp.GetResponseStream())
                                    $Message = $sr.ReadToEnd()
                                    $sr.Close()
                                }
                                else
                                {
                                    $Message = [string]$($resp.Headers | ConvertTo-Json)
                                }
                            }
                            catch
                            {
                                $Message = $_.Exception.Message
                                $rStatus = $false
                            }
                            finally
                            {
                                $resp.Close()
                                if (!$rStatus)
                                {
                                    $errCounter--
                                }
                                else
                                {
                                    $errCounter = 0
                                }
                            }
                        }
                    }
                    elseif ($method -eq 2)
                    {
                        while ([bool]$errCounter)
                        {
                            $Message = ffprobe.exe -hide_banner -timeout $timeout -v 32 -i $url 2>&1
                            $rStatus = $?
                            if (!$rStatus)
                            {
                                $errCounter--
                            }
                            else
                            {
                                $errCounter = 0
                            }
                        }                            
                    }
                    return New-Object PSObject -Property @{
                        Nb      = $nb
                        Status  = $rStatus
                        Message = $Message
                    }
                }
                [int]$step = 650
                [int]$start = 0
                [int]$stop = $step - 1
                [int]$chanelCount = $this.Chanels.Count
                $runspaces = New-Object System.Collections.ArrayList
                $pool = [RunspaceFactory]::CreateRunspacePool(1, $this.thread)
                $pool.Open()
                Do
                {                      
                    foreach ($ch in ($this.Chanels[[int]$start..[int]$stop]))
                    {
                        $pwsh = [PowerShell]::Create().AddScript($ffScriptBlock).AddArgument($this.GetProbeMethod()).AddArgument($ch.GetNb()).AddArgument($this.timeOut).AddArgument($this.ErrorRepeat).AddArgument($ch.GetUrl())
                        $pwsh.RunspacePool = $pool
                        [System.Collections.ArrayList]$runspaces += New-Object -TypeName PSObject -Property @{
                            Pipe   = $pwsh
                            Status = $pwsh.BeginInvoke()
                        }
                        $this.itemInPool++
                        $this.totalChanelsNumber--
                        $this.RefreshScreen($this.totalChanelsNumber, 5)
                    }
                    
                    while ([bool]$runspaces)
                    {
                        Foreach ($runThread in $runspaces.ToArray())
                        {
                            If ($runThread.Status.IsCompleted)
                            {
                                $ReturnetData = $runThread.Pipe.EndInvoke($runThread.Status)
                                $this.itemInPool--
                                $this.Chanels[$ReturnetData.Nb].SetStatus([bool]$ReturnetData.Status)
                                $this.Chanels[$ReturnetData.Nb].SetMessage([string]$ReturnetData.Message)
                                $this.ProbeTime = Get-Date
                                $this.SetTotalTime()
                                if ([bool]$ReturnetData.Status)
                                {
                                    $this.trueChNumber++
                                }
                                else
                                {    
                                    $this.falseChNumber++
                                }
                                $this.RefreshScreen($this.totalChanelsNumber, 5)
                                Remove-Variable ReturnetData
                                $runThread.Pipe.Dispose()
                                $runspaces.Remove($runThread)
                            }
                        }                
                        $this.RefreshScreen($this.totalChanelsNumber, 1)
                    }
                    $start += $step
                    $stop += $step
                    if ($chanelCount -le $stop)
                    {
                        $stop = $chanelCount 
                    }

                } while ([bool]$this.totalChanelsNumber)
                $pool.Dispose()
                $pool.Close() 
            }
        }

        [void] RefreshScreen([int]$inNumber, [int]$interval = 5)
        {
            if (![bool]$($inNumber % $interval))
            {   
                [System.Console]::SetCursorPosition($this.xyPos.x, $this.xyPos.y)
                Write-Host -Object $this.GetPrintOut() -NoNewLine
            }
        }


        [string] GetTrue ([bool]$AddHeader)
        {
            $tempList = [System.Text.StringBuilder]::new()
            if ($AddHeader)
            {
                $tempList.AppendLine("#EXTM3U")
            }
            foreach ($trChan in $($this.Chanels | Where { ($_.GetStatus()) -eq $true }))
            {
                $tempList.AppendLine($trChan.GetChanel())
            }
            return $tempList.ToString()
        }
        [string] GetFalse ([bool]$AddHeader)
        {
            $tempList = [System.Text.StringBuilder]::new()
            if ($AddHeader)
            {
                $tempList.AppendLine("#EXTM3U")
            }
            foreach ($faChan in $($this.Chanels | Where { ($_.GetStatus()) -eq $false }))
            {
                $tempList.AppendLine($faChan.GetChanel())
            }
            return $tempList.ToString()
        }
    }

    if (![bool]$UseFFProbe)
    {
        [int32]$ProbeMethod = 1
    }
    else
    {
        [int32]$ProbeMethod = 2
    }

    $menu = @"
   ------------------------------------------------------------------------------
    IPTV PLAYLIST CHECKER
   ------------------------------------------------------------------------------

Playlists:

+----+-----------------------------------+---------+-----------+-----------+-----------+-----------+-----------------+
| Nb.|               Name                |  Valid  |  Find CH  |  In Pool  |  Working  |   Death   |  Running Time:  |
+----+-----------------------------------+---------+-----------+-----------+-----------+-----------+-----------------+
"@
    [System.Console]::CursorVisible = $false
    clear-host
    [System.Console]::SetCursorPosition(0, 0)
    Write-Host -Object $menu -NoNewLine

}

Process
{
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
            [void]$PlayLists.Add([Playlist]::new($inputs[$i], $Thread, $i, $ErrorRepeat, $ProbeMethod))
            $PlayLists[-1].RefreshScreen(1, -1)
            [System.Console]::SetCursorPosition($PlayLists[-1].xyPos.x, $($PlayLists[-1].xyPos.y + 1))
            Write-Host -Object "+----+-----------------------------------+---------+-----------+-----------+-----------+-----------+-----------------+" -NoNewline
            $PlayLists[-1].Parser()
        }
    }
    [int]$AllTimes = 0
    [int]$AllWork = 0
    [int]$AllNotWork = 0
    foreach ($item in $PlayLists)
    {
        $item.ProbeIt()
        $AllTimes += (New-TimeSpan $item.CreateTime $item.ProbeTime).TotalSeconds
        $AllWork += $item.trueChNumber
        $AllNotWork += $item.falseChNumber
    }
    $totTime = New-TimeSpan -Seconds $AllTimes
    [System.Console]::SetCursorPosition(75, $($PlayLists.Count + 10))
    Write-Host -Object $([string]::Format("|{0,10} |{1,10} |       {2:d2}:{3:d2}:{4:d2}  |", [int]$AllWork, $AllNotWork, [int]$totTime.Hours, [int]$totTime.Minutes, [int]$totTime.Seconds)) -NoNewline
    [System.Console]::SetCursorPosition(75, $($PlayLists.Count + 11))
    Write-Host -Object "+-----------+-----------+-----------------+" -NoNewline
} 
End
{
    if (!$SingleOutput)
    {
        foreach ($item in $PlayLists)
        {
            if ($item.ValidContent)
            {
                if (![bool]$(Test-Path -Path $(split-path $item.trueOutPath -Parent)))
                {
                    New-Item -Path $(split-path $item.trueOutPath -Parent) -ItemType Directory -Force
                }
                [IO.File]::WriteAllText($item.trueOutPath, $item.GetTrue($true))
            }
            if (!$OnlyWorking)
            {
                if (![bool]$(Test-Path -Path $(split-path $item.falseOutPath -Parent)))
                {
                    New-Item -Path $(split-path $item.falseOutPath -Parent) -ItemType Directory -Force
                }
                [IO.File]::WriteAllText($item.falseOutPath, $item.GetFalse($true))
            }
        }
    }
    else #SingleOutput
    {
        [string]$trueMultiPath = [System.IO.Path]::Combine($(Get-Location), "iptv-Working", $($(Get-Date -UFormat "%Y%m%d%H%M%S") + ".m3u"))
        $tempTrue = [System.Text.StringBuilder]::new()
        [void]$tempTrue.AppendLine("#EXTM3U")
        
        foreach ($item in $PlayLists)
        {
            if ($item.ValidContent)
            {
                [void]$tempTrue.AppendLine($item.GetTrue($false))
            }
        }

        if (![bool]$(Test-Path -Path $(split-path $trueMultiPath -Parent)))
        {
            New-Item -Path $(split-path $trueMultiPath -Parent) -ItemType Directory -Force
        }
        [IO.File]::WriteAllText($trueMultiPath, $tempTrue.ToString())

        if (!$OnlyWorking)
        {
            [string]$falseMultiPath = [System.IO.Path]::Combine($(Get-Location), "iptv-NotWorking", $($(Get-Date -UFormat "%Y%m%d%H%M%S") + ".m3u"))
            $tempFalse = [System.Text.StringBuilder]::new()
            [void]$tempFalse.AppendLine("#EXTM3U")

            foreach ($item in $PlayLists)
            {
                if ($item.ValidContent)
                {
                    [void]$tempFalse.AppendLine($item.GetFalse($false))
                }
            }
            if (![bool]$(Test-Path -Path $(split-path $falseMultiPath -Parent)))
            {
                New-Item -Path $(split-path $falseMultiPath -Parent) -ItemType Directory -Force
            }
            [IO.File]::WriteAllText($falseMultiPath, $tempFalse.ToString())
        }
    }
    [System.Console]::SetCursorPosition(0, $($PlayLists.Count + 13))
    [System.Console]::CursorVisible = $true
}

