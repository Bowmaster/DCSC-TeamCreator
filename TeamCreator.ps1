param(
    [Parameter(Mandatory=$true)]
    [ValidateSet('U6','U8','U10','U12','U14')]
    [string]$Division,
    [Parameter(Mandatory=$true)]
    [int]$TeamCount,
    [Parameter(Mandatory=$true)]
    [ValidateScript({if (Test-Path $_) {
        $true
    }else{throw "Could not find file $_"}})]
    [string]$PlayerInputFile,
    [Parameter(Mandatory=$true)]
    [ValidateScript({if (Test-Path $_) {
        $true
    }else{throw "Could not find file $_"}})]
    [string]$CoachInputFile,
    [Parameter(Mandatory=$true)]
    [string]$OutputFile
)
switch ($Division) {
    'U6' { $MaxPerDayPractices = 6 }
    'U8' { $MaxPerDayPractices = 2 }
    'U10' { $MaxPerDayPractices = 2 }
    'U12' { $MaxPerDayPractices = 2 }
    'U14' { $MaxPerDayPractices = 1 }
    Default { throw "Incorrect value for Division ($Division) was supplied"}
}
$StartNum = 0
$Teams = @()
$Players = Get-Content -Path $PlayerInputFile | ConvertFrom-Csv
$Players = $Players | sort -Property AgeInDays
$MaxPlayers = [math]::Ceiling(($Players.Count / $TeamCount))
$Coaches = Get-Content -Path $CoachInputFile | ConvertFrom-Csv
$HeadCoaches = $Coaches | ? {$_.'Team Personnel Role' -eq 'Head Coach'}
$HeadCoaches | ? {$_.'Preferred Practice Day' -eq 'No Answer'} | % {$_.'Preferred Practice Day' = 'XX_No_Answer'}
$AssistantCoaches = $Coaches | ? {$_.'Team Personnel Role' -eq 'Assistant Coach'}
for ($i = 1; $i -le $TeamCount; $i++) {
    $obj = New-Object PSObject
    $obj | Add-Member -MemberType NoteProperty -Name HeadCoachId -Value @($HeadCoaches | ? {$_.VolunteerID -notin $Teams.HeadCoachId})[0].VolunteerId
    $obj | Add-Member -MemberType NoteProperty -Name HeadCoachName -Value ($HeadCoaches | ? {$_.VolunteerID -eq $obj.HeadCoachId}).'Team Personnel Name'
    $obj | Add-Member -MemberType NoteProperty -Name HeadCoachEmail -Value ($HeadCoaches | ? {$_.VolunteerID -eq $obj.HeadCoachId}).Email
    $obj | Add-Member -MemberType NoteProperty -Name AssistantCoachId -Value $null
    $obj | Add-Member -MemberType NoteProperty -Name AssistantCoachName -Value $null
    $obj | Add-Member -MemberType NoteProperty -Name AssistantCoachEmail -Value $null
    $obj | Add-Member -MemberType NoteProperty -Name PracticeDay -Value $null
    $obj | Add-Member -MemberType NoteProperty -Name TeamName -Value "Team$(($i + $StartNum).ToString().PadLeft(2,'0'))"
    $obj | Add-Member -MemberType NoteProperty -Name Players -Value @()
    $obj | Add-Member -MemberType ScriptProperty -Name PlayerNames -Value {$this.Players.PlayerFullName | Sort-Object}
    $obj | Add-Member -MemberType ScriptProperty -Name PlayerCount -Value {$this.Players.Count}
    $preferredAssistant = ($HeadCoaches | ? {$_.VolunteerId -eq $obj.HeadCoachId -and $_.'Preferred Assistant Coach?(Head Coach)' -ne 'No Answer'}).'Preferred Assistant Coach?(Head Coach)'
    if ($preferredAssistant) {
        $obj.AssistantCoachId = ($AssistantCoaches | ? {$_.'Team Personnel Name' -eq $preferredAssistant}).VolunteerId
    } else {
        $obj.AssistantCoachId = @($AssistantCoaches | ? {$_.VolunteerID -notin $Teams.AssistantCoachId -and $_.'Preferred Assistant Coach?(Head Coach)' -eq 'No Answer' -and $_.'Team Personnel Name' -notin @($HeadCoaches.'Preferred Assistant Coach?(Head Coach)')})[0].VolunteerId
    }
    $obj.AssistantCoachName = ($AssistantCoaches | ? {$_.VolunteerID -eq $obj.AssistantCoachId}).'Team Personnel Name'
    $obj.AssistantCoachEmail = ($AssistantCoaches | ? {$_.VolunteerID -eq $obj.AssistantCoachId}).Email
    $Teams += $obj
}

foreach ($team in ($Teams)) {
    $row = $HeadCoaches | ? {$team.HeadCoachId -eq $_.VolunteerId}
    switch -wildcard ($row.'Preferred Practice Day'.ToLower()) {
        "mon*" { $eligibleCoachPractice = @('Monday') }
        "tues*" { $eligibleCoachPractice = @('Tuesday') }
        "wed*" { $eligibleCoachPractice = @('Wednesday') }
        "thur*" { $eligibleCoachPractice = @('Thursday') }
        Default { $eligibleCoachPractice = @('Monday','Tuesday','Wednesday','Thursday') }
    }
    foreach ($day in $eligibleCoachPractice) {
        if (($Teams.PracticeDay | ? {$_ -eq $day}).Count -le $MaxPerDayPractices) {
            $team.PracticeDay = $day
        }
    }
    if (-not $team.PracticeDay) {
        Write-Warning "A suitable practice day could not be found for team $($team.TeamName), coach $($team.HeadCoachName)"
    }
}

$Players | % {
    $_ | Add-Member -MemberType NoteProperty -Name ParentFullName -Value "$($_.'Parent FirstName') $($_.'Parent LastName')" -Force
    if ([string]::IsNullOrWhiteSpace($_.'Secondary Contact FirstName') -eq $false -and $_.'Secondary Contact FirstName' -ne 'No Answer') {
        $_ | Add-Member -MemberType NoteProperty -Name SecondaryContactFullName -Value "$($_.'Secondary Contact FirstName') $($_.'Secondary Contact LastName')" -Force
    }
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
            $_.EligiblePracticeDays = $_.EligiblePracticeDays | ? {$_ -ne $day}
        }
    }
}

for ($i = 0; $i -lt $Players.Count; $i++) {
    if ($Players[$i].NewTeamName) {
        Write-Warning "Skipping player $($Players[$i].PlayerFullName) as they are already assigned to $($Players[$i].NewTeamName)"
    } else {
        $emails = @()
        $eligibleTeams = $null
        if ($Players[$i].'Primary Contact Email' -ne 'No Answer') {
            $emails += $Players[$i].'Primary Contact Email'
        }
        if ($Players[$i].'Primary Contact Email' -ne 'No Answer') {
            $emails += $Players[$i].'Secondary Contact Email'
        }
        $eligibleTeams = $Teams | ? {$_.HeadCoachEmail -in $emails -or $_.AssistantCoachEmail -in $emails}
        if (-not $eligibleTeams) {
            $eligibleTeams = @()
            $contactNames = @()
            $contactNames += $Players[$i].ParentFullName
            if ($Players[$i].SecondaryContactFullName) {
                $contactNames += $Players[$i].SecondaryContactFullName
            }
            $eligibleTeams += $Teams | ? {$_.HeadCoachName -in $contactNames -or $_.AssistantCoachName -in $contactNames}
        }
        if (-not $eligibleTeams) {
            $eligibleTeams = @()
            foreach ($day in $Players[$i].EligiblePracticeDays) {
                #$eligibleTeams += $Teams | ? {$_.PracticeDay -eq $day -and $_.Players.Count -lt $MaxPlayers}
                $eligibleTeams += $Teams | ? { $_.PracticeDay -eq $day }
            }
        }
        if (-not $eligibleTeams) {
            Write-Error "No eligible day, based on requested practice date, found for $($Players[$i].PlayerFullName)"
            continue
        } else {
            #$et = ($eligibleTeams | Sort-Object {Get-Random})[0]
            #$et = @(($eligibleTeams | Sort-Object -Property PlayerCount)[0..2] | Sort-Object {Get-Random})[0]
            # Check for siblings
            $et = @($eligibleTeams | Sort-Object -Property PlayerCount)[0]
            $siblings = $Players | ? {$_.UserID -eq $Players[$i].UserId}
            if ($siblings.count -gt 1) {
                Write-Warning "The following suspected siblings were found: $($siblings.PlayerFullName -join ', '), ensuring they're on the same team."
                $siblings | % {
                    $et.Players += $_
                    $_.NewTeamName = $et.TeamName
                }
            } else {
                # No Siblings
                $et.Players += $Players[$i]
                $Players[$i].NewTeamName = $et.TeamName
            }
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
foreach ($player in ($Players | Sort-Object -Property NewTeamName)) {
    #$playerTeam = $Teams | ? {$_.TeamName -eq $player.NewTeamName}
    $Output += [PSCustomObject]@{
        TeamName = $player.NewTeamName
        PlayerID = $player.PlayerID
        VolunteerID = $null
        VolunteerTypeID = $null
        'Player Name' = $player.'Player Name'
        'Team Personnel Name' = $null
        'Team Personnel Role' = $null
    }
}
foreach ($team in $Teams) {
    $Output += [PSCustomObject]@{
        TeamName = $team.TeamName
        PlayerID = $null
        VolunteerID = $team.HeadCoachId
        VolunteerTypeID = 5414
        'Player Name' = $null
        'Team Personnel Name' = $team.HeadCoachName
        'Team Personnel Role' = 'Head Coach'
    }
    if ($team.AssistantCoachId) {
        $Output += [PSCustomObject]@{
            TeamName = $team.TeamName
            PlayerID = $null
            VolunteerID = $team.AssistantCoachId
            VolunteerTypeID = 5416
            'Player Name' = $null
            'Team Personnel Name' = $team.AssistantCoachName
            'Team Personnel Role' = 'Assistant Coach'
        }
    }
}
#$Output
#$Teams
#$Players

$Output | ConvertTo-Csv | Out-File $OutputFile -Force
