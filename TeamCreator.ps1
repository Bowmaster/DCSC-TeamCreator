param(
    [Parameter(Mandatory=$true)]
    [ValidateSet('U6','U8','U10','U12','U14')]
    [string]$Division,

    [Parameter(Mandatory=$true)]
    [int]$TeamCount,

    [Parameter(Mandatory=$true)]
    [ValidateSet('Coed','Male','Female')]
    [string]$ProcessGender,

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
    [ValidateScript({if (Test-Path $_ -Type Container) {
        $true
    }else{throw "Could not find directory $_ or $_ was not a directory but rather, a file"}})]
    [string]$OutputDirectory,

    [Parameter(Mandatory=$false)]
    [switch]$OutputObj
)
switch ($Division) {
    'U6' { $MaxPerDayPractices = 6 }
    'U8' { $MaxPerDayPractices = 2 }
    'U10' { $MaxPerDayPractices = 3 }
    'U12' { $MaxPerDayPractices = 2 }
    'U14' { $MaxPerDayPractices = 1 }
    Default { throw "Incorrect value for Division ($Division) was supplied"}
}
$StartNum = 0
$Teams = @()
$MaxPlayers = [math]::Ceiling(($Players.Count / $TeamCount))
$Coaches = Get-Content -Path $CoachInputFile | ConvertFrom-Csv
$Players = Get-Content -Path $PlayerInputFile | ConvertFrom-Csv
$Players = $Players | ? {$_.PlayerId -match '^[0-9]+$' -and [int]$_.PlayerId -ge 1000000}
if (-not $Players) {
   throw "No usable player data was found from $PlayerInputFile! Please check the file contents and try again."
}
if ($ProcessGender -eq "Coed") {
    # Nothing to do, this is easy as we don't have to filter anything
} elseif ($ProcessGender -eq "Male") {
    $ignoredPlayers = $Players | ? {$_.Gender -eq 'F'}
    $Players = $Players | ? {$_.Gender -eq 'M'}
} elseif ($ProcessGender -eq "Female") {
    $ignoredPlayers = $Players | ? {$_.Gender -eq 'M'}
    $Players = $Players | ? {$_.Gender -eq 'F'}
} else {
    throw "Couldn't figure out how to handle Gender here..."
}

if (-not $Players) {
    throw "Could not find any players after handling gender..."
}

$IneligibleCoaches = $Coaches | ? {$_.Email -in $ignoredPlayers.'Primary Contact Email' -or $_.Email -in $ignoredPlayers.'Secondary Contact Email'}
$HeadCoaches = $Coaches | ? {$_.'Team Personnel Role' -eq 'Head Coach'} | ? {$_.VolunteerId -notin $IneligibleCoaches.VolunteerId}
#$HeadCoaches | ? {$_.'Preferred Practice Day' -eq 'No Answer'} | % {$_.'Preferred Practice Day' = 'XX_No_Answer'}
$AssistantCoaches = $Coaches | ? {$_.'Team Personnel Role' -eq 'Assistant Coach' -and $_.UserId -notin $HeadCoaches.UserId} | ? {$_.VolunteerId -notin $IneligibleCoaches.VolunteerId}
Write-Host "HeadCoaches: $($HeadCoaches.'Team Personnel Name')"
Write-Host "AssistantCoaches: $($AssistantCoaches.'Team Personnel Name')"
timeout -1
for ($i = 1; $i -le $TeamCount; $i++) {
    $obj = New-Object PSObject
    $obj | Add-Member -MemberType NoteProperty -Name HeadCoachId -Value @($HeadCoaches | ? {$_.VolunteerID -notin $Teams.HeadCoachId})[0].VolunteerId
    $obj | Add-Member -MemberType NoteProperty -Name HeadCoachName -Value ($HeadCoaches | ? {$_.VolunteerID -eq $obj.HeadCoachId}).'Team Personnel Name'
    $obj | Add-Member -MemberType NoteProperty -Name HeadCoachEmail -Value ($HeadCoaches | ? {$_.VolunteerID -eq $obj.HeadCoachId}).Email
    $obj | Add-Member -MemberType NoteProperty -Name AssistantCoachId -Value $null
    $obj | Add-Member -MemberType NoteProperty -Name AssistantCoachName -Value $null
    $obj | Add-Member -MemberType NoteProperty -Name AssistantCoachEmail -Value $null
    $obj | Add-Member -MemberType NoteProperty -Name PracticeDay -Value $null
    $obj | Add-Member -MemberType NoteProperty -Name PreferredPracticeTime -Value ($HeadCoaches | ? {$_.VolunteerID -eq $obj.HeadCoachId}).'Preferred Practice Time'
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
    if ($obj.HeadCoachId) {
        $obj.TeamName = "$($obj.TeamName)-$($obj.HeadCoachName.Split(' ')[-1])$(if($obj.AssistantCoachName){"/$($obj.AssistantCoachName.Split(' ')[-1])"})"
    }
}

foreach ($team in ($Teams)) {
    $row = $HeadCoaches | ? {$team.HeadCoachId -eq $_.VolunteerId}
    if ($row) {
        switch -wildcard ($row.'Preferred Practice Day'.ToLower()) {
            "mon*" { $eligibleCoachPractice = @('Monday') }
            "tues*" { $eligibleCoachPractice = @('Tuesday') }
            "wed*" { $eligibleCoachPractice = @('Wednesday') }
            "thur*" { $eligibleCoachPractice = @('Thursday') }
            Default { $eligibleCoachPractice = @('Monday','Tuesday','Wednesday','Thursday') }
        }
    } else {
        $eligibleCoachPractice = @('Monday','Tuesday','Wednesday','Thursday')
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
    $playerObj = $_
    $_ | Add-Member -MemberType NoteProperty -Name ParentFullName -Value "$($_.'Parent FirstName') $($_.'Parent LastName')" -Force
    if ([string]::IsNullOrWhiteSpace($_.'Secondary Contact FirstName') -eq $false -and $_.'Secondary Contact FirstName' -ne 'No Answer') {
        $_ | Add-Member -MemberType NoteProperty -Name SecondaryContactFullName -Value "$($_.'Secondary Contact FirstName') $($_.'Secondary Contact LastName')" -Force
    }
    $_ | Add-Member -MemberType NoteProperty -Name PlayerFullName -Value $_.'Player Name' -Force
    Write-Verbose "Processing $($_.PlayerFullName), $($_.'Date Of Birth')"
    $_ | Add-Member -MemberType NoteProperty -Name AgeInDays -Value ((Get-Date) - [datetime]($_.'Date Of Birth')).Days -Force
    $_ | Add-Member -MemberType NoteProperty -Name NewTeamName -Value $null -Force
    $returningProp = ($_.PSObject.Properties | ? {$_.Name.StartsWith('New or Returning')}).Name
    if ($_.'Recent Team' -ne 'NA' -or $_.$returningProp -eq 'Returning') {
        $_.$returningProp = 'Returning'
    } else {
        $_.$returningProp = 'New'
    }
    $practiceProp = ($_.PSObject.Properties | ? {$_.Name.StartsWith('Days you CANNOT Practice')}).Name
    $_ | Add-Member -MemberType NoteProperty -Name EligiblePracticeDays -Value @('Monday','Tuesday','Wednesday','Thursday')
    if ([string]::IsNullOrWhiteSpace($practiceProp)) {
        Write-Warning "No Practice Day property found for Player $($_.'Player Name')"
        $noPracticeDays = 'No Answer'
    } else {
        if (-not $_.$practiceProp) {
            Write-Host "Player $($playerObj.'Player Name') is showing an empty value for Practice day field '$practiceProp'" -ForegroundColor Red
            Write-Host "Please verify their practice availability manually" -ForegroundColor Red
            $noPracticeDays = 'No Answer'
        } else {
            try {
                $noPracticeDays = $_.$practiceProp.Split(',')
            }
            catch {
                Write-Host "Unable to determine the eligible Practice Days for player $($playerObj.'Player Name'), please verify their practice day manually!!" -ForegroundColor Red
                $noPracticeDays = 'No Answer'
            }
        }
        foreach ($day in $noPracticeDays) {
            if ($day -eq 'No Answer') {
                # Any day is ok
                continue
            } else {
                $_.EligiblePracticeDays = $_.EligiblePracticeDays | ? {$_ -ne $day}
            }
        }
    }
}
$Players = $Players | Sort-Object -Property AgeInDays
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

$Output | ConvertTo-Csv | Out-File $(Join-Path $OutputDirectory "$Division-$ProcessGender-TeamData-$((Get-Date).ToFileTime()).csv") -Force
if ($OutputObj) {
    $Var = New-Variable -Name "DCSC$($Division)Team" -Value $Teams -PassThru -Force
    $Var.Value
}