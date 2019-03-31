# If you have a number of bindings and environments, specifying bindings using the "IIS web site and application pool" feature quickly gets complicated.  This module allows us to specify all the bindings and certificates in a clean and simple manner.
# Note - does not currently support SNI, only the normal certificate bindings where you have one cert per IP address.


$ErrorActionPreference = "Stop"
function ImportModuleWebAdministration()
{
	try
	{
		Add-PSSnapin WebAdministration -ErrorAction SilentlyContinue
		Import-Module WebAdministration -ErrorAction SilentlyContinue
	}
	catch 
	{
		# This catch is necessary to avoid the "Add-PSSnapin : An item with the same key has already been added" you will get when running under Octopus.  For some reason "-ErrorAction SilentlyContinue" won't ignore this.
	}
}

# For PowerShell 2.  https://stackoverflow.com/a/41946169/24267
function IsNullOrWhitespace($str)
{
    if ($str)
    {
        return ($str -replace " ","" -replace "`t","").Length -eq 0
    }
    else
    {
        return $TRUE
    }
}

# The format of the list isn't JSON or XML because wanted it to be as human-readable as possible
function GetBindingsFromList($listOfSites, $environment, $siteNameRoot, $addWWWDomains, $prefixForAllDomains)
{
	$foundBindings = $false
	$bindings = @()
	$arrayOfSites = $listOfSites -split '[\r\n]'
	$lineNumber = 0
	$bindingsHeader = "[Bindings-$environment]"
	ForEach ($_ In $arrayOfSites) {
		$lineNumber++
		if (IsNullOrWhiteSpace($_)) {
			continue
		}
		if ($_.StartsWith("#")) {
			continue # Comment line, skip it
		}
		if ($_ -eq ($bindingsHeader)) {
			$foundBindings = $true
		}
		elseif ($foundBindings) {
			if ($_.StartsWith("[")) {
				break
			}
			$splitBinding = $_ -split '[,]+' | %{$_.Trim()}
			if ($splitBinding.length -ne 4) {
				throw "Missing a field in config line $lineNumber.  Expecting 4 fields: $_"
			}
			if ($splitBinding[0] -eq $siteNameRoot) {
				$ipAddress, $port = $splitBinding[2].split(":")
				$protocol = $splitBinding[1]
				if ($port -and ($protocol -eq "HTTP/HTTPS"))
				{
					throw "Can't have HTTP/HTPS and a port since HTTP and HTTPS must be on separate ports: $ipaddress"
				}
				if ($protocol -ne "HTTP/HTTPS" -and $protocol -ne "HTTP" -and $protocol -ne "HTTPS")
				{
					throw "Expecting HTTP/HTTPS, HTTP or HTTPS in second field of this line: $protocol"
				}
				if ($protocol -eq "HTTP/HTTPS" -or $protocol -eq "HTTP")
				{
					$tmpPort = if ($port) {$port} else {80}
					$bindings += @{protocol="http";bindingInformation="$($ipaddress):$($tmpPort):$prefixForAllDomains$($splitBinding[3])"}
					if ($addWWWDomains)
					{
						$bindings += @{protocol="http";bindingInformation="$($ipaddress):$($tmpPort):$($prefixForAllDomains)www.$($splitBinding[3])"}
					}
				}
				if ($protocol -eq "HTTP/HTTPS" -or $protocol -eq "HTTPS")
				{
					$tmpPort = if ($port) {$port} else {443}
					$bindings += @{protocol="https";bindingInformation="$($ipaddress):$($tmpPort):$prefixForAllDomains$($splitBinding[3])"}
					if ($addWWWDomains)
					{
						$bindings += @{protocol="https";bindingInformation="$($ipaddress):$($tmpPort):$($prefixForAllDomains)www.$($splitBinding[3])"}
					}
				}
			}
		}
	}
	if ($bindings.length -eq 0)
	{
		if (!$foundBindings)
		{
		 throw "$bindingsHeader not found in the list of sites"
		}
		else
		{
			throw "$bindingsHeader does not contain site named $siteNameRoot in the list of sites."
		}
	}
	return $bindings
}

function GetSSLCertificateThumbprintFromList($listOfSites, $environment, $ipaddress)
{
	$found = $false
	$arrayOfSites = $listOfSites -split '[\r\n]'
	ForEach ($_ In $arrayOfSites) {
		if ($_ -eq ("[SSLCertificateThumbprints]")) {
			$found = $true
		}
		elseif ($found) {
			if ($_.StartsWith("[")) {
				return $null
			}
			$splitBinding = $_ -split '[,\s]+'
			if ($splitBinding[0] -eq $environment -and $splitBinding[1] -eq $ipaddress) {
				return $splitBinding[2].Replace(" ", "")
			}
		}
	}
	return $bindings
}

function GetHostNamesFromList($listOfSites, $environment, $siteNameRoot, $addWWWDomains, $prefixForAllDomains)
{
	ImportModuleWebAdministration
	Write-Host "GetHostNamesFromList for $environment, $siteNameRoot"
	if ([string]::IsNullOrEmpty($listOfSites))
	{
		throw "ListOfSites was empty"
	}
	$bindings = GetBindingsFromList $listOfSites $environment $siteNameRoot $addWWWDomains $prefixForAllDomains
	$hostNames = @()
	ForEach ($binding In $bindings)
	{
		$hostName = ($binding.bindingInformation -split ":")[2]
		if ($hostNames -notcontains $hostName)
		{
			$hostNames += $hostName
		}
	}
	Write-Host "Found $($hostNames.length) host names"
	return $hostNames
}

function CreateIISSiteFromList($listOfSites, $environment, $siteNameRoot, $addWWWDomains, $prefixForAllDomains, $octopusReleaseNumber, $folderPath)
{
	ImportModuleWebAdministration
	if ([string]::IsNullOrEmpty($listOfSites))
	{
		throw "ListOfSites was empty"
	}
	Push-Location
	try
	{
		$bindings = GetBindingsFromList $listOfSites $environment $siteNameRoot $addWWWDomains $prefixForAllDomains
		$siteName = "$siteNameRoot $octopusReleaseNumber"
		cd IIS:\AppPools\
		if (Test-Path $siteName -pathType container)
		{
			echo "App pool already exists: $siteName"
		}
		else
		{
			$appPool = New-Item $siteName
			$appPool | Set-ItemProperty -Name "managedRuntimeVersion" -Value "v4.0"
			echo "Created app pool: $siteName"
		}

		cd IIS:\Sites\
		if (Test-Path $siteName -pathType container)
		{
			echo "Website already exists: $siteName"
		}
		else
		{
			
			$iisSite = New-Item $siteName -bindings $bindings -physicalPath $directoryPath
			$iisSite | Set-ItemProperty -Name "applicationPool" -Value $siteName
			$iisSite | Set-ItemProperty -Name "physicalPath" -Value $folderPath
			echo "Created website `"$siteName`" with $($bindings.Length) bindings and path $folderPath"
		}
		SetSSLCertificates $bindings
		
		echo "Starting website `"$siteName`""
		try
		{
			(Get-Item "IIS:\sites\$siteName").Start()
		}
		catch
		{
			if ($_.ToString().indexOf("file already exists") -ge 0)
			{
				echo "Cannot start website '$siteName'.  A website with the same binding is already running, or this website has multiple copies of the same binding."
				Pop-Location
				exit -1
			}
			else
			{
				echo $_
				echo "Wait 30 seconds and try again"
				Start-Sleep -s 30
				(Get-Item "IIS:\sites\$siteName").Start()
			}
		}
		Pop-Location
	}
	catch 
	{
		Pop-Location
		throw
	}
}

# This will not work with SNI, only with normal SSL certs that are assigned per-IP-Address
function SetSSLCertificates($bindings)
{
	$ipaddressesSet = @()
	ForEach ($binding In $bindings)
	{
		if ($binding.protocol -eq "https")
		{
			$ipaddress = ($binding.bindingInformation -split ":")[0]
			if (!($ipaddressesSet -contains $ipaddress))
			{
				$ipaddressesSet += $ipaddress
				$thumbprint = GetSSLCertificateThumbprintFromList $listOfSites $environment $ipaddress
				if ($thumbprint)
				{
					if ($ipaddress -eq "*")
					{
						$ipaddress = "0.0.0.0"
					}
					$cert = get-item cert:\LocalMachine\MY\$thumbprint*
					if (!$cert) {
						throw "Certificate with the thumbprint not found: $thumbprint"
					}
					
					# Verify we can mess with the SSL bindings (https://stackoverflow.com/a/28771136/24267)
					Try
					{
						Get-ChildItem IIS:\SslBindings | out-null
					}
					Catch
					{
						$1stentry = Get-ChildItem HKLM:\SYSTEM\CurrentControlSet\services\HTTP\Parameters\SslBindingInfo | Select-Object -First 1
						$1stentry | New-ItemProperty -Name "SslCertStoreName" -Value "MY" | out-null
						Get-ChildItem IIS:\SslBindings | out-null
					}
					# OK, now we should be able to set them.
					$sslPath = "IIS:\SslBindings\$ipaddress!443"
					if (Test-Path -Path $sslPath)
					{
						$cert | Set-Item -Path $sslPath
					}
					else
					{
						# In PowerShell 2, Set-Item doesn't work if the binding doesn't exist.  It works in later versions.
						$cert | New-Item -Path $sslPath
					}
					echo "Assigned thumbprint $thumbprint to ipaddress $ipaddress"
				}
				else
				{
					throw "No thumbprint found in list for ipaddress $ipaddress"
				}
			}
		}
	}
}

Export-ModuleMember -function CreateIISSiteFromList, GetHostNamesFromList