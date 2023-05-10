<#

.SYNOPSIS 
  This function queries the AlternateMailboxes node within a user's AutoDiscover response. This version now supports Modern Auth. For the basic Auth version of this script, use  Get-AlternateMailboxes_BasicAuth.ps1.
  
  Requirements:
  Depends on ExchangeOnlineManagement module
   

  Version: March 9, 2023
  Version: 09-05-2023 AAV Get Token from Connect-ExchangeOnline session instead, fix Invoke-WebRequest


.DESCRIPTION
  This function queries the AlternateMailboxes node within a user's AutoDiscover response. See the link for details.

  Author:
  Mike Crowley
  https://BaselineTechnologies.com

.EXAMPLE
.\Get-AlternateMailboxes -SMTPAddress mike@example.com

.LINK
https://mikecrowley.us/2017/12/08/querying-msexchdelegatelistlink-in-exchange-online-with-powershell/

.LINK
https://www.michev.info/blog/post/4249/connecting-to-exchange-online-powershell-by-passing-an-access-token

#>



Function Get-AlternateMailboxes {
  Param(
    [parameter(Mandatory = $true)]
    [string]$SMTPAddress,
    [parameter(Mandatory = $true)]
    [string]$Token
  )

  $AutoDiscoverRequest = @"
      <soap:Envelope xmlns:a="http://schemas.microsoft.com/exchange/2010/Autodiscover" 
              xmlns:wsa="http://www.w3.org/2005/08/addressing" 
              xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" 
              xmlns:soap="http://schemas.xmlsoap.org/soap/envelope/">
        <soap:Header>
          <a:RequestedServerVersion>Exchange2013</a:RequestedServerVersion>
          <wsa:Action>http://schemas.microsoft.com/exchange/2010/Autodiscover/Autodiscover/GetUserSettings</wsa:Action>
          <wsa:To>https://autodiscover.exchange.microsoft.com/autodiscover/autodiscover.svc</wsa:To>
        </soap:Header>
        <soap:Body>
          <a:GetUserSettingsRequestMessage xmlns:a="http://schemas.microsoft.com/exchange/2010/Autodiscover">
            <a:Request>
              <a:Users>
                <a:User>
                  <a:Mailbox>$SMTPAddress</a:Mailbox>
                </a:User>
              </a:Users>
              <a:RequestedSettings>
                <a:Setting>UserDisplayName</a:Setting>
                <a:Setting>UserDN</a:Setting>
                <a:Setting>UserDeploymentId</a:Setting>
                <a:Setting>MailboxDN</a:Setting>
                <a:Setting>AlternateMailboxes</a:Setting>
              </a:RequestedSettings>
            </a:Request>
          </a:GetUserSettingsRequestMessage>
        </soap:Body>
      </soap:Envelope>
"@
  
# Other attributes available here: https://learn.microsoft.com/en-us/dotnet/api/microsoft.exchange.webservices.autodiscover.usersettingname?view=exchange-ews-api

  $Headers = @{
    'X-AnchorMailbox' = $SMTPAddress
    'Authorization'   = $Token
  }

  $WebResponse = Invoke-WebRequest -Uri "https://autodiscover-s.outlook.com/autodiscover/autodiscover.svc"  -Method Post -Body $AutoDiscoverRequest -ContentType 'text/xml; charset=utf-8' -Headers $Headers -UseBasicParsing
  [System.Xml.XmlDocument]$XMLResponse = $WebResponse.Content
  $RequestedSettings = $XMLResponse.Envelope.Body.GetUserSettingsResponseMessage.Response.UserResponses.UserResponse.UserSettings.UserSetting
  return $RequestedSettings.AlternateMailboxes.AlternateMailbox
}

Function Test-ExchangeOnlineConnection {
  <#
  Dependens: no
  0.1. AAV 2019-05-31 Function Created
  0.2. AAV 09-02-2023 Try-Catch added. Upgraded to support EXO_v3 command
  #>
  try{
      $s = Get-ConnectionInformation   | Where-Object {$_.TokenStatus -eq "Active" -and $_.State -eq "Connected"} | Sort-Object Id  | Select-Object -First 1
      if ($s) {Return $true} else  {Return $false}
  }   
  Catch{
      Return $_
  } 
}

if (-not (Test-ExchangeOnlineConnection)) {
  Import-Module -name ExchangeOnlineManagement -ErrorAction SilentlyContinue
  Connect-ExchangeOnline
}

# Get any existing contexts
$context = [Microsoft.Exchange.Management.ExoPowershellSnapin.ConnectionContextFactory]::GetAllConnectionContexts()
# Get an existing token from the cache
$EOLToken = $context[0].TokenProvider.GetValidTokenFromCache("Get-Mailbox").AuthorizationHeader
#Or generate a new one 
#$context[0].TokenProvider.GetAccessToken()

# You'll be promted to type a user SMTP Address
Get-AlternateMailboxes -Token $EOLToken
