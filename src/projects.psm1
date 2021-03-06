Set-StrictMode -Version Latest

# Load common code
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
. "$here\common.ps1"

# Apply types to the returned objects so format and type files can
# identify the object and act on it.
function _applyTypes {
   param($item)

   $item.PSObject.TypeNames.Insert(0, 'Team.Project')

   # Only returned for a single item
   if ($item.PSObject.Properties.Match('defaultTeam').count -gt 0 -and $null -ne $item.defaultTeam) {
      $item.defaultTeam.PSObject.TypeNames.Insert(0, 'Team.Team')
   }

   if ($item.PSObject.Properties.Match('_links').count -gt 0 -and $null -ne $item._links) {
      $item._links.PSObject.TypeNames.Insert(0, 'Team.Links')
   }
}

function _trackProjectProgress {
   param(
      [Parameter(Mandatory = $true)] $Resp,
      [string] $Title,
      [string] $Msg
   )

   $i = 0
   $x = 1
   $y = 10
   $status = $resp.status

   # Track status
   while ($status -ne 'failed' -and $status -ne 'succeeded') {
      $status = (_callAPI -Url $resp.url).status

      # oscillate back a forth to show progress
      $i += $x
      Write-Progress -Activity $title -Status $msg -PercentComplete ($i / $y * 100)

      if ($i -eq $y -or $i -eq 0) {
         $x *= -1
      }
   }
}

function Get-VSTeamProject {
   [CmdletBinding(DefaultParameterSetName = 'List')]
   param(
      [Parameter(ParameterSetName = 'List')]
      [ValidateSet('WellFormed', 'CreatePending', 'Deleting', 'New', 'All')]
      [string] $StateFilter = 'WellFormed',
      
      [Parameter(ParameterSetName = 'List')]
      [int] $Top = 100,
      
      [Parameter(ParameterSetName = 'List')]
      [int] $Skip = 0,
      
      [Parameter(ParameterSetName = 'ByID')]
      [Alias('ProjectID')]
      [string] $Id,
      
      [switch] $IncludeCapabilities
   )

   DynamicParam {
      _buildProjectNameDynamicParam -ParameterSetName 'ByName' -ParameterName 'Name'
   }

   process {
      # Bind the parameter to a friendly variable
      $ProjectName = $PSBoundParameters["Name"]

      if ($id) {
         $ProjectName = $id
      }

      if ($ProjectName) {
         $queryString = @{}
         if ($includeCapabilities.IsPresent) {
            $queryString.includeCapabilities = $true
         }

         # Call the REST API
         $resp = _callAPI -Area 'projects' -id $ProjectName `
            -Version $VSTeamVersionTable.Core `
            -QueryString $queryString
         
         # Apply a Type Name so we can use custom format view and custom type extensions
         _applyTypes -item $resp

         Write-Output $resp
      }
      else {
         try {
            # Call the REST API
            $resp = _callAPI -Area 'projects' `
               -Version $VSTeamVersionTable.Core `
               -QueryString @{
               stateFilter = $stateFilter
               '$top'      = $top
               '$skip'     = $skip
            }

            # Apply a Type Name so we can use custom format view and custom type extensions
            foreach ($item in $resp.value) {
               _applyTypes -item $item
            }

            Write-Output $resp.value
         }
         catch {
            # I catch because using -ErrorAction Stop on the Invoke-RestMethod
            # was still running the foreach after and reporting useless errors.
            # This casuses the first error to terminate this execution.
            _handleException $_
         }
      }
   }
}

function Show-VSTeamProject {
   [CmdletBinding(DefaultParameterSetName = 'ByName')]
   param(      
      [Parameter(ParameterSetName = 'ByID')]
      [Alias('ProjectID')]
      [string] $Id
   )

   DynamicParam {
      _buildProjectNameDynamicParam -ParameterSetName 'ByName' -ParameterName 'Name' -AliasName 'ProjectName'
   }

   process {
      _hasAccount

      # Bind the parameter to a friendly variable
      $ProjectName = $PSBoundParameters["Name"]

      if ($id) {
         $ProjectName = $id
      }

      _showInBrowser "$($VSTeamVersionTable.Account)/$ProjectName"
   }
}

function Update-VSTeamProject {
   [CmdletBinding(DefaultParameterSetName = 'ByName', SupportsShouldProcess = $true, ConfirmImpact = "High")]
   param(
      [string] $NewName = '',
      [string] $NewDescription = '',
      [switch] $Force,
      [Parameter(ParameterSetName = 'ByID', ValueFromPipelineByPropertyName = $true)]
      [string] $Id
   )

   DynamicParam {
      _buildProjectNameDynamicParam -ParameterName 'Name' -AliasName 'ProjectName' -ParameterSetName 'ByName' -Mandatory $false
   }

   process {
      # Bind the parameter to a friendly variable
      $ProjectName = $PSBoundParameters["Name"]

      if ($id) {
         $ProjectName = $id
      }
      else {
         $id = (Get-VSTeamProject $ProjectName).id
      }

      if ($newName -eq '' -and $newDescription -eq '') {
         # There is nothing to do
         Write-Verbose 'Nothing to update'
         return
      }

      if ($Force -or $pscmdlet.ShouldProcess($ProjectName, "Update Project")) {

         # At the end we return the project and need it's name
         # this is used to track the final name.
         $finalName = $ProjectName

         if ($newName -ne '' -and $newDescription -ne '') {
            $finalName = $newName
            $msg = "Changing name and description"
            $body = '{"name": "' + $newName + '", "description": "' + $newDescription + '"}'
         }
         elseif ($newName -ne '') {
            $finalName = $newName
            $msg = "Changing name"
            $body = '{"name": "' + $newName + '"}'
         }
         else {
            $msg = "Changing description"
            $body = '{"description": "' + $newDescription + '"}'
         }

         # Call the REST API
         $resp = _callAPI -Area 'projects' -id $id `
            -Method Patch -ContentType 'application/json' -body $body -Version $VSTeamVersionTable.Core
         
         _trackProjectProgress -resp $resp -title 'Updating team project' -msg $msg

         # Return the project now that it has been updated
         return Get-VSTeamProject -Id $finalName
      }
   }
}

function Add-VSTeamProject {
   param(
      [parameter(Mandatory = $true)]
      [Alias('Name')]
      [string] $ProjectName,

      [ValidateSet('Agile', 'CMMI', 'Scrum')]
      [string] $ProcessTemplate = 'Scrum',

      [string] $Description,

      [switch] $TFVC
   )

   $srcCtrl = 'Git'
   $templateTypeId = ''

   switch ($ProcessTemplate) {
      'Agile' {
         $templateTypeId = 'adcc42ab-9882-485e-a3ed-7678f01f66bc'
      }
      'CMMI' {
         $templateTypeId = '27450541-8e31-4150-9947-dc59f998fc01'
      }
      # The default is Scrum
      Default {
         $templateTypeId = '6b724908-ef14-45cf-84f8-768b5384da45'
      }
   }

   if ($TFVC.IsPresent) {
      $srcCtrl = "Tfvc"
   }

   $body = '{"name": "' + $ProjectName + '", "description": "' + $Description + '", "capabilities": {"versioncontrol": { "sourceControlType": "' + $srcCtrl + '"}, "processTemplate":{"templateTypeId": "' + $templateTypeId + '"}}}'

   try {
      # Call the REST API
      $resp = _callAPI -Area 'projects' `
         -Method Post -ContentType 'application/json' -body $body -Version $VSTeamVersionTable.Core
      
      _trackProjectProgress -resp $resp -title 'Creating team project' -msg "Name: $($ProjectName), Template: $($processTemplate), Src: $($srcCtrl)"

      return Get-VSTeamProject $ProjectName
   }
   catch {
      _handleException $_
   }
}

function Remove-VSTeamProject {
   [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = "High")]
   param(
      [switch] $Force
   )

   DynamicParam {
      _buildProjectNameDynamicParam -ParameterName 'Name' -AliasName 'ProjectName'
   }

   Process {
      # Bind the parameter to a friendly variable
      $ProjectName = $PSBoundParameters["Name"]

      if ($Force -or $pscmdlet.ShouldProcess($ProjectName, "Delete Project")) {
         # Call the REST API
         $resp = _callAPI -Area 'projects' -Id (Get-VSTeamProject $ProjectName).id `
            -Method Delete -Version $VSTeamVersionTable.Core
         
         _trackProjectProgress -resp $resp -title 'Deleting team project' -msg "Deleting $ProjectName"

         Write-Output "Deleted $ProjectName"
      }
   }
}

function Clear-VSTeamDefaultProject {
   [Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSUseDeclaredVarsMoreThanAssignments", "")]
   [CmdletBinding()]
   param()
   DynamicParam {
      # Only add these options on Windows Machines
      if (_isOnWindows) {
         $ParameterName = 'Level'

         # Create the dictionary
         $RuntimeParameterDictionary = New-Object System.Management.Automation.RuntimeDefinedParameterDictionary

         # Create the collection of attributes
         $AttributeCollection = New-Object System.Collections.ObjectModel.Collection[System.Attribute]

         # Create and set the parameters' attributes
         $ParameterAttribute = New-Object System.Management.Automation.ParameterAttribute
         $ParameterAttribute.Mandatory = $false
         $ParameterAttribute.HelpMessage = "On Windows machines allows you to store the default project at the process, user or machine level. Not available on other platforms."

         # Add the attributes to the attributes collection
         $AttributeCollection.Add($ParameterAttribute)

         # Generate and set the ValidateSet
         if (_testAdministrator) {
            $arrSet = "Process", "User", "Machine"
         }
         else {
            $arrSet = "Process", "User"
         }

         $ValidateSetAttribute = New-Object System.Management.Automation.ValidateSetAttribute($arrSet)

         # Add the ValidateSet to the attributes collection
         $AttributeCollection.Add($ValidateSetAttribute)

         # Create and return the dynamic parameter
         $RuntimeParameter = New-Object System.Management.Automation.RuntimeDefinedParameter($ParameterName, [string], $AttributeCollection)
         $RuntimeParameterDictionary.Add($ParameterName, $RuntimeParameter)
         return $RuntimeParameterDictionary
      }
   }

   begin {
      if (_isOnWindows) {
         # Bind the parameter to a friendly variable
         $Level = $PSBoundParameters[$ParameterName]
      }
   }

   process {
      if (_isOnWindows) {
         if (-not $Level) {
            $Level = "Process"
         }
      }
      else {
         $Level = "Process"
      }

      # You always have to set at the process level or they will Not
      # be seen in your current session.
      $env:TEAM_PROJECT = $null

      if (_isOnWindows) {
         [System.Environment]::SetEnvironmentVariable("TEAM_PROJECT", $null, $Level)
      }

      $VSTeamVersionTable.DefaultProject = ''
      $Global:PSDefaultParameterValues.Remove("*:projectName")

      Write-Output "Removed default project"
   }
}

function Set-VSTeamDefaultProject {
   [Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSUseDeclaredVarsMoreThanAssignments", "")]
   [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = "Low")]
   param([switch] $Force)
   DynamicParam {
      $dp = _buildProjectNameDynamicParam -ParameterName "Project"

      # Only add these options on Windows Machines
      if (_isOnWindows) {
         $ParameterName = 'Level'

         # Create the collection of attributes
         $AttributeCollection = New-Object System.Collections.ObjectModel.Collection[System.Attribute]

         # Create and set the parameters' attributes
         $ParameterAttribute = New-Object System.Management.Automation.ParameterAttribute
         $ParameterAttribute.Mandatory = $false
         $ParameterAttribute.HelpMessage = "On Windows machines allows you to store the default project at the process, user or machine level. Not available on other platforms."

         # Add the attributes to the attributes collection
         $AttributeCollection.Add($ParameterAttribute)

         # Generate and set the ValidateSet
         if (_testAdministrator) {
            $arrSet = "Process", "User", "Machine"
         }
         else {
            $arrSet = "Process", "User"
         }

         $ValidateSetAttribute = New-Object System.Management.Automation.ValidateSetAttribute($arrSet)

         # Add the ValidateSet to the attributes collection
         $AttributeCollection.Add($ValidateSetAttribute)

         # Create and return the dynamic parameter
         $RuntimeParameter = New-Object System.Management.Automation.RuntimeDefinedParameter($ParameterName, [string], $AttributeCollection)
         $dp.Add($ParameterName, $RuntimeParameter)
      }
      
      return $dp
   }

   begin {
      # Bind the parameter to a friendly variable
      $Project = $PSBoundParameters["Project"]

      if (_isOnWindows) {
         $Level = $PSBoundParameters[$ParameterName]
      }
   }

   process {
      if ($Force -or $pscmdlet.ShouldProcess($Project, "Set-VSTeamDefaultProject")) {
         if (_isOnWindows) {
            if (-not $Level) {
               $Level = "Process"
            }

            # You always have to set at the process level or they will Not
            # be seen in your current session.
            $env:TEAM_PROJECT = $Project
            $VSTeamVersionTable.DefaultProject = $Project

            [System.Environment]::SetEnvironmentVariable("TEAM_PROJECT", $Project, $Level)
         }

         $Global:PSDefaultParameterValues["*:projectName"] = $Project
      }
   }
}

Set-Alias Get-Project Get-VSTeamProject
Set-Alias Show-Project Show-VSTeamProject
Set-Alias Update-Project Update-VSTeamProject
Set-Alias Add-Project Add-VSTeamProject
Set-Alias Remove-Project Remove-VSTeamProject
Set-Alias Clear-DefaultProject Clear-VSTeamDefaultProject
Set-Alias Set-DefaultProject Set-VSTeamDefaultProject

Export-ModuleMember `
   -Function Get-VSTeamProject, Show-VSTeamProject, Update-VSTeamProject, Add-VSTeamProject, Remove-VSTeamProject, Clear-VSTeamDefaultProject, Set-VSTeamDefaultProject `
   -Alias Get-Project, Show-Project, Update-Project, Add-Project, Remove-Project, Clear-DefaultProject, Set-DefaultProject

# Check to see if the user stored the default project in an environment variable
if ($null -ne $env:TEAM_PROJECT) {
   # Make sure the value in the environment variable still exisits. 
   if (Get-VSTeamProject | Where-Object ProjectName -eq $env:TEAM_PROJECT) {
      Set-VSTeamDefaultProject -Project $env:TEAM_PROJECT
   }
}