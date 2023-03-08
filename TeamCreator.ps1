param(
    [Parameter(Mandatory=$true)]
    [int]$TeamCount,
    [Parameter(Mandatory=$true)]
    [ValidateScript({if (Test-Path $_) {
        $true
    }else{throw "Could not find file $_"}})]
    [string]$InputFile,
    [Parameter(Mandatory=$true)]
    [string]$OutputFile
)
#$TeamCount = 2
$StartNum = 0
$Teams = @()
for ($i = 1; $i -le $TeamCount; $i++) {
    $Teams += [PSCustomObject]@{
        TeamName = "Team$(($i + $StartNum).ToString().PadLeft(2,'0'))"
        Players = @()
    }
}
$Players = Get-Content -Path $InputFile | ConvertFrom-Csv
$Players = $Players | sort -Property AgeInDays
$Players | % {
    $_ | Add-Member -MemberType NoteProperty -Name ParentFullName -Value "$($_.'Parent FirstName') $($_.'Parent LastName')" -Force
    $_ | Add-Member -MemberType NoteProperty -Name PlayerFullName -Value $_.'Player Name' -Force
    $_ | Add-Member -MemberType NoteProperty -Name AgeInDays -Value ((Get-Date) - [datetime]$_.'Date Of Birth').Days -Force
    $_ | Add-Member -MemberType NoteProperty -Name NewTeamName -Value $null -Force
    $returningProp = ($_.PSObject.Properties | ? {$_.Name.StartsWith('New or Returning')}).Name
    if ($_.'Recent Team' -ne 'NA' -or $_.$returningProp -eq 'Returning') {
        $_.$returningProp = 'Returning'
    } else {
        $_.$returningProp = 'New'
    }
    $practiceProp = ($_.PSObject.Properties | ? {$_.Name.StartsWith('Days you CANNOT Practice')}).Name
    $_ | Add-Member -MemberType NoteProperty -Name EligiblePracticeDays -Value @('Monday','Tuesday','Wednesday','Thursday')
    $noPracticeDays = $_.$practiceProp.Split(',')
    foreach ($day in $noPracticeDays) {
        if ($day -eq 'No Answer') {
            # Any day is ok
            continue
        } else {
            $_.EligiblePracticeDays = $_.EligiblePracticeDays | ? {$_ -ne '$day'}
        }
    }
}
$iTeam = 0
for ($i = 0; $i -lt $Players.Count; $i++) {
    if ($Players[$i].NewTeamName) {
        Write-Warning "Skipping player $($Players[$i].PlayerFullName) as they are already assigned to $($Players[$i].NewTeamName)"
    } else {
        $Teams[$iTeam].Players += $Players[$i]
        $Players[$i].NewTeamName = $Teams[$iTeam].TeamName
        if (($iTeam + 1) -eq $Teams.Count) {
            $iTeam = 0
        } elseif (($iTeam + 1) -gt $Teams.Count) {
            throw "Out of range exception for value of 'iTeams': Current = $iTeam; Max = $($Teams.Count)"
        } else {
            $iTeam++
        }
    }
}

$TotalPlayers = 0
$Teams | % {
    $TotalPlayers = $TotalPlayers + $_.Players.Count
    if (($_.Players.PlayerFullName | Select-Object -Unique).Count -eq $_.Players.Count) {
        Write-Host "No duplicate player names found on $($_.TeamName)" -ForegroundColor Green
    } else {
        Write-Error "Duplicate players were found on $($_.TeamName), please review!"
    }
}
if ($TotalPlayers -eq $Players.Count) {
    Write-Host "Correct match of assigned players vs total players found for the division." -ForegroundColor Green
}

if (-not $Players.NewTeamName) {
    Write-Error "There seems to be users not assigned to a team:"
    $Players | ? {[string]::IsNullOrWhiteSpace($_.NewTeamName)} | Select-Object -Property PlayerFullName | ft -a
} else {
    Write-Host "All players have been validated as assigned to a team!" -ForegroundColor Green
    $Teams | % {
        Write-Host "$($_.TeamName) has $($_.Players.Count) player(s) assigned." -ForegroundColor Cyan
    }
}

$Output = @()
foreach ($player in $Players) {
    $Output += [PSCustomObject]@{
        TeamName = $player.NewTeamName
        PlayerID = $player.PlayerID
        'VolunteerID' = $null
        'VolunteerTypeID' = $null
        'Player Name' = $player.'Player Name'
        'Team Personnel Name' = $null
        'Team Personnel Role' = $null
    }
}
$Output | ConvertTo-Csv | Out-File $OutputFile -Force