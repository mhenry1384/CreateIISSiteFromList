Import-Module $PSScriptRoot\CreateIISSiteFromList -Verbose -Force

Remove-Website "FOO2016-Portal 668"
CreateIISSiteFromList (Get-Content CreateIISSiteFromListTest.lst) "QA" "FOO2016-Portal" $false "" 668 c:\temp
GetHostNamesFromList (Get-Content CreateIISSiteFromListTest.lst) "QA" "FOO2016-Portal" $false "pending-"
