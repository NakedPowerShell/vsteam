Set-StrictMode -Version Latest

Get-Module VSTeam | Remove-Module -Force
Import-Module $PSScriptRoot\..\..\src\team.psm1 -Force
Import-Module $PSScriptRoot\..\..\src\teammembers.psm1 -Force
Import-Module $PSScriptRoot\..\..\src\teams.psm1 -Force

InModuleScope teammembers {
   $VSTeamVersionTable.Account = 'https://test.visualstudio.com'

   Describe "TeamMembers" {
      . "$PSScriptRoot\mockProjectNameDynamicParam.ps1"
        
      Context 'Get-VSTeamMember for specific project and team' {
         Mock Invoke-RestMethod { return @{value = 'teams'}}

         It 'Should return teammembers' {
            Get-VSTeamMember -ProjectName TestProject -TeamId TestTeam
            # Make sure it was called with the correct URI
            Assert-MockCalled Invoke-RestMethod -Exactly 1 -ParameterFilter {
               $Uri -eq "https://test.visualstudio.com/_apis/projects/TestProject/teams/TestTeam/members?api-version=$($VSTeamVersionTable.Core)"
            }
         }
      }

      Context 'Get-VSTeamMember for specific project and team, with top' {
         Mock Invoke-RestMethod { return @{value = 'teams'}}

         It 'Should return teammembers' {
            Get-VSTeamMember -ProjectName TestProject -TeamId TestTeam -Top 10
            # Make sure it was called with the correct URI
            Assert-MockCalled Invoke-RestMethod -Exactly 1 -ParameterFilter {
               $Uri -like "*https://test.visualstudio.com/_apis/projects/TestProject/teams/TestTeam/members*" -and
               $Uri -like "*api-version=$($VSTeamVersionTable.Core)*" -and
               $Uri -like "*`$top=10*"
            }
         }            
      }

      Context 'Get-VSTeamMember for specific project and team, with skip' {
         Mock Invoke-RestMethod { return @{value = 'teams'}}

         It 'Should return teammembers' {                
            Get-VSTeamMember -ProjectName TestProject -TeamId TestTeam -Skip 5
            # Make sure it was called with the correct URI
            Assert-MockCalled Invoke-RestMethod -Exactly 1 -ParameterFilter {
               $Uri -like "*https://test.visualstudio.com/_apis/projects/TestProject/teams/TestTeam/members*" -and
               $Uri -like "*api-version=$($VSTeamVersionTable.Core)*" -and
               $Uri -like "*`$skip=5*"
            }
         }
      }

      Context 'Get-VSTeamMember for specific project and team, with top and skip' {
         Mock Invoke-RestMethod { return @{value = 'teams'}}

         It 'Should return teammembers' {                
            Get-VSTeamMember -ProjectName TestProject -TeamId TestTeam -Top 10 -Skip 5
            # Make sure it was called with the correct URI
            Assert-MockCalled Invoke-RestMethod -Exactly 1 -ParameterFilter {
               $Uri -like "*https://test.visualstudio.com/_apis/projects/TestProject/teams/TestTeam/members*" -and
               $Uri -like "*api-version=$($VSTeamVersionTable.Core)*" -and
               $Uri -like "*`$top=10*" -and
               $Uri -like "*`$skip=5*"
            }
         }            
      }

      Context 'Get-VSTeamMember for specific team, fed through pipeline' {
         Mock Invoke-RestMethod { return @{value = 'teammembers'}}

         It 'Should return teammembers' {
            New-Object -TypeName PSObject -Prop @{projectname = "TestProject"; name = "TestTeam"} | Get-VSTeamMember
            
            Assert-MockCalled Invoke-RestMethod -Exactly 1 -ParameterFilter {
               $Uri -eq "https://test.visualstudio.com/_apis/projects/TestProject/teams/TestTeam/members?api-version=$($VSTeamVersionTable.Core)"                    
            }
         }
      }

      # Must be last because it sets $VSTeamVersionTable.Account to $null
      Context '_buildURL handles exception' {
         
         # Arrange
         $VSTeamVersionTable.Account = $null
         
         It 'should return approvals' {
         
            # Act
            { _buildURL -ProjectName project -TeamId 1 } | Should Throw
         }
      }
   }
}