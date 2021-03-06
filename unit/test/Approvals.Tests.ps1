Set-StrictMode -Version Latest

# Remove any loaded version of this module so only the files
# imported below are being tested.
Get-Module VSTeam | Remove-Module -Force

# Load the modules we want to test and any dependencies
Import-Module $PSScriptRoot\..\..\src\team.psm1 -Force
Import-Module $PSScriptRoot\..\..\src\Approvals.psm1 -Force

# The InModuleScope command allows you to perform white-box unit testing on the 
# internal (non-exported) code of a Script Module.
InModuleScope Approvals {

   # Set the account to use for testing. A normal user would do this
   # using the Add-VSTeamAccount function.
   $VSTeamVersionTable.Account = 'https://test.visualstudio.com'

   Describe 'Approvals' {

      # Load the mocks to create the project name dynamic parameter
      . "$PSScriptRoot\mockProjectNameDynamicParamNoPSet.ps1"

      Context 'Get-VSTeamApproval handles exception' {
         
         # Arrange
         Mock _handleException -Verifiable
         Mock Invoke-RestMethod { throw 'testing error handling' }

         # Act
         Get-VSTeamApproval -ProjectName project
         
         It 'should return approvals' {

            # Assert
            Assert-VerifiableMock
         }
      }

      Context 'Get-VSTeamApproval' {
         Mock Invoke-RestMethod {            
            return @{
               count = 1
               value = @(
                  @{
                     id       = 1
                     revision = 1
                     approver = @{
                        id          = 'c1f4b9a6-aee1-41f9-a2e0-070a79973ae9'
                        displayName = 'Test User'
                     }
                  }
               )
            }}

         Get-VSTeamApproval -projectName project
         
         It 'should return approvals' {
            Assert-MockCalled Invoke-RestMethod -Exactly -Scope Context -Times 1 `
               -ParameterFilter { 
               $Uri -eq "https://test.vsrm.visualstudio.com/project/_apis/release/approvals/?api-version=$($VSTeamVersionTable.Release)"
            }
         }
      }

      Context 'Get-VSTeamApproval with AssignedToFilter' {
         Mock Invoke-RestMethod {
            # If this test fails uncomment the line below to see how the mock was called.
            # Write-Host $args

            return @{
               count = 1
               value = @(
                  @{
                     id       = 1
                     revision = 1
                     approver = @{
                        id          = 'c1f4b9a6-aee1-41f9-a2e0-070a79973ae9'
                        displayName = 'Test User'
                     }
                  }
               )
            }}
   
         Get-VSTeamApproval -projectName project -AssignedToFilter 'Chuck Reinhart'
            
         It 'should return approvals' {
            # With PowerShell core the order of the query string is not the 
            # same from run to run!  So instead of testing the entire string
            # matches I have to search for the portions I expect but can't
            # assume the order. 
            # The general string should look like this:
            # "https://test.vsrm.visualstudio.com/project/_apis/release/approvals/?api-version=$($VSTeamVersionTable.Release)&assignedtoFilter=Chuck%20Reinhart&includeMyGroupApprovals=true"
            Assert-MockCalled Invoke-RestMethod -Exactly -Scope Context -Times 1 `
               -ParameterFilter { 
               $Uri -like "*https://test.vsrm.visualstudio.com/project/_apis/release/approvals/*" -and
               $Uri -like "*api-version=$($VSTeamVersionTable.Release)*" -and
               $Uri -like "*assignedtoFilter=Chuck Reinhart*" -and
               $Uri -like "*includeMyGroupApprovals=true*"
            }
         }
      }

      # This makes sure the alias is working
      Context 'Get-Approval' {
         Mock _useWindowsAuthenticationOnPremise { return $true }
         Mock Invoke-RestMethod { return @{
               count = 1
               value = @(
                  @{
                     id       = 1
                     revision = 1
                     approver = @{
                        id          = 'c1f4b9a6-aee1-41f9-a2e0-070a79973ae9'
                        displayName = 'Test User'
                     }
                  }
               )
            }}
        
         Get-Approval -projectName project
        
         It 'should return approvals' {
            Assert-MockCalled Invoke-RestMethod -Exactly -Scope Context -Times 1 `
               -ParameterFilter { 
               $Uri -eq "https://test.vsrm.visualstudio.com/project/_apis/release/approvals/?api-version=$($VSTeamVersionTable.Release)"
            }
         }
      }

      Context 'Set-VSTeamApproval' {
         Mock Invoke-RestMethod { return @{
               id       = 1
               revision = 1
               approver = @{
                  id          = 'c1f4b9a6-aee1-41f9-a2e0-070a79973ae9'
                  displayName = 'Test User'
               }
            }}

         Set-VSTeamApproval -projectName project -Id 1 -Status Rejected -Force

         It 'should set approval' {
            Assert-MockCalled Invoke-RestMethod -Exactly -Scope Context -Times 1 `
               -ParameterFilter { 
               $Method -eq 'Patch' -and
               $Uri -eq "https://test.vsrm.visualstudio.com/project/_apis/release/approvals/1?api-version=$($VSTeamVersionTable.Release)"
            }
         }
      }

      Context 'Set-VSTeamApproval handles exception' {
         Mock _handleException -Verifiable
         Mock Invoke-RestMethod { throw 'testing error handling' }

         Set-VSTeamApproval -projectName project -Id 1 -Status Rejected -Force

         It 'should set approval' {
            Assert-MockCalled Invoke-RestMethod -Exactly -Scope Context -Times 1 `
               -ParameterFilter { 
               $Uri -eq "https://test.vsrm.visualstudio.com/project/_apis/release/approvals/1?api-version=$($VSTeamVersionTable.Release)"
            }
         }
      }

      Context 'Set-Approval' {
         Mock _useWindowsAuthenticationOnPremise { return $true }
         Mock Invoke-RestMethod { return @{
               id       = 1
               revision = 1
               approver = @{
                  id          = 'c1f4b9a6-aee1-41f9-a2e0-070a79973ae9'
                  displayName = 'Test User'
               }
            }}

         Set-Approval -projectName project -Id 1 -Status Rejected -Force
            
         It 'should set approval' {
            Assert-MockCalled Invoke-RestMethod -Exactly -Scope Context -Times 1 `
               -ParameterFilter { 
               $Method -eq 'Patch' -and
               $Uri -eq "https://test.vsrm.visualstudio.com/project/_apis/release/approvals/1?api-version=$($VSTeamVersionTable.Release)"
            }
         }
      }

      Context 'Show-VSTeamApproval' {
         Mock _showInBrowser -Verifiable
         
         Show-VSTeamApproval -projectName project -ReleaseDefinitionId 1

         It 'should open in browser' {
            Assert-VerifiableMock
         }
      }

      Context 'Get-VSTeamApproval TFS' {
         $VSTeamVersionTable.Account = 'http://localhost:8080/tfs/defaultcollection'
         
         Mock Invoke-RestMethod {
            # If this test fails uncomment the line below to see how the mock was called.
            #Write-Host $args

            return @{
               count = 1
               value = @(
                  @{
                     id       = 1
                     revision = 1
                     approver = @{
                        id          = 'c1f4b9a6-aee1-41f9-a2e0-070a79973ae9'
                        displayName = 'Test User'
                     }
                  }
               )
            }}

         Get-VSTeamApproval -projectName project -ReleaseIdsFilter 1 -AssignedToFilter 'Test User' -StatusFilter Pending
         
         It 'should return approvals' {
            # With PowerShell core the order of the query string is not the 
            # same from run to run!  So instead of testing the entire string
            # matches I have to search for the portions I expect but can't
            # assume the order. 
            # The general string should look like this:
            # "http://localhost:8080/tfs/defaultcollection/project/_apis/release/approvals/?api-version=$($VSTeamVersionTable.Release)&statusFilter=Pending&assignedtoFilter=Test User&includeMyGroupApprovals=true&releaseIdsFilter=1"
            Assert-MockCalled Invoke-RestMethod -Exactly -Scope Context -Times 1 `
               -ParameterFilter { 
               $Uri -like "*http://localhost:8080/tfs/defaultcollection/project/_apis/release/approvals/*" -and
               $Uri -like "*api-version=$($VSTeamVersionTable.Release)*" -and
               $Uri -like "*statusFilter=Pending*" -and
               $Uri -like "*assignedtoFilter=Test User*" -and
               $Uri -like "*includeMyGroupApprovals=true*" -and
               $Uri -like "*releaseIdsFilter=1*"
            }
         }
      }
   }
}