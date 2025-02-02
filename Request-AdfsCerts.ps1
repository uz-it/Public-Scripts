﻿<#

.SYNOPSIS 
    This tool displays the signing and encrypting certificates published in ADFS' federation metadata as well as the HTTPS ("SSL") certificate used in the connection itself.

    This tool does not authenticate to the server or investigate each ADFS farm node directly. For this, use the ADFS Cert Diag tool

    Version: March 2 2023


.DESCRIPTION
    This tool displays the signing and encrypting certificates published in ADFS' federation metadata as well as the HTTPS ("SSL") certificate used in the connection itself.

    Sample Output with -Display $true (default):    

        SSL (HTTPS) Certificate:

            SSL_Subject:       CN=ADFS.CONTOSO, O=CONTOSO CORP, OID.1.3.6.1.4.1.311.60.2.1.3=US
            SSL_NotAfter:      1/14/2024 6:59:59 PM
            SSL_Thumbprint:    21321F3C2E225480F112A7BC2B3347B58B439842
            SSL_Issuer:        CN=CONTOSO CORP
            SSL_DaysToExpiry:  25
            
        Encryption Certificate:

            Encryption_Subject:     CN=ADFS Encryption - adfs.contoso.com
            Encryption_NotAfter:    7/7/2023 7:05:31 PM
            Encryption_Thumbprint:  0507D8E023B8715FE3F5F4A6421F47A36C6DD3AD
            Encryption_Issuer:      CN=ADFS Encryption - adfs.contoso.com
            Encryption_DaysToExpiry:  129

        Token Signing Certificate:

            PrimarySigning_Subject:     CN=ADFS Signing - adfs.contoso.com
            PrimarySigning_NotAfter:    7/7/2023 7:05:32 PM
            PrimarySigning_Thumbprint:  0507D8E023B8715FE3F5F4A6421F47A36C6DD3AD
            PrimarySigning_Issuer:      CN=ADFS Signing - adfs.contoso.com
            PrimarySigning_DaysToExpiry:  129

        Secondary Token Signing Certificate:

            !! No Secondary Token Signing Certificate Found !!

        
    Sample Output with -Display $false (for use with loops, pipeline, etc): 

            SSL_Subject                   : CN=ADFS.CONTOSO, O=CONTOSO CORP, OID.1.3.6.1.4.1.311.60.2.1.3=US
            SSL_NotAfter                  : 11/14/2023 6:59:59 PM
            SSL_Thumbprint                : 21321F3C2E225480F112A7BC2B3347B58B439842
            SSL_Issuer                    : CN=CONTOSO CORP
            SSL_DaysToExpiry              : 256
            PrimarySigning_Subject        : CN=ADFS Signing - adfs.contoso.com
            PrimarySigning_NotAfter       : 7/5/2023 7:05:32 PM
            PrimarySigning_Thumbprint     : 0507D8E023B8715FE3F5F4A6421F47A36C6DD3AD
            PrimarySigning_Issuer         : CN=ADFS Signing - adfs.contoso.com
            PrimarySigning_DaysToExpiry   : 124
            SecondarySigning_Subject      : 
            SecondarySigning_NotAfter     : 
            SecondarySigning_Thumbprint   : 
            SecondarySigning_Issuer       : 
            SecondarySigning_DaysToExpiry : -738581
            Encryption_Subject            : CN=ADFS Encryption - adfs.contoso.com
            Encryption_NotAfter           : 7/5/2023 7:05:31 PM
            Encryption_Thumbprint         : 0507D8E023B8715FE3F5F4A6421F47A36C6DD3AD
            Encryption_Issuer             : CN=ADFS Encryption - adfs.contoso.com
            Encryption_DaysToExpiry       : 124
    
    NOTE 1: This does not currently support PowerShell v6 or v7 (PowerShell Core)

    NOTE 2: This tool by Microsoft may be handy as well: https://adfshelp.microsoft.com/MetadataExplorer/GetFederationMetadata


    Author:
    Mike Crowley
    http://<>
 

.EXAMPLE
    Request-AdfsCerts -FarmFqdn adfs.contoso.com


.EXAMPLE
    Request-AdfsCerts -FarmFqdn adfs.contoso.com -Display $false


.LINK
    https://github.com/Mike-Crowley

#>


function Request-AdfsCerts {
    param (
        [string]$FarmFqdn,
        [string]$Display = $true
    )   
    if (Test-NetConnection -ComputerName $FarmFqdn -Port 443 -InformationLevel Quiet -Verbose) {

        $url = "https://$FarmFqdn/FederationMetadata/2007-06/FederationMetadata.xml"
        $global:UnsupportedPowerShell = $false

        #ignore ssl warnings
        if ($PSVersionTable.PSEdition -eq "core") { $global:UnsupportedPowerShell -eq $true }
        else { [Net.ServicePointManager]::ServerCertificateValidationCallback = { $true } }

        #Make HTTPS connection and get content
        $request = [Net.HttpWebRequest]::Create($url)
        $request.Host = $FarmFqdn
        $request.AllowAutoRedirect = $false
        #$request.Headers.Add("UserAgent", 'User-Agent: Mozilla/5.0 (Windows NT 10.0; Microsoft Windows 10.0.22621; en-US) PowerShell/7.3.3') # optional
        $response = $request.GetResponse()

        $HttpsCertBytes = $request.ServicePoint.Certificate.GetRawCertData()
        $contentStream = $response.GetResponseStream()
        $reader = [IO.StreamReader]::new($contentStream)
        $content = $reader.ReadToEnd()
        $reader.Close()
        $contentStream.Close()
        $response.Close()

        #Extract HTTPS cert (ADFS Calls this the "SSL" cert)  
        $CertInBase64 = [convert]::ToBase64String($HttpsCertBytes)
        $SSLCert_x509 = [Security.Cryptography.X509Certificates.X509Certificate2]([System.Convert]::FromBase64String($CertInBase64))

        #Parse FederationMetadata for certs
        $KeyDescriptors = ([xml]$content).EntityDescriptor.SPSSODescriptor.KeyDescriptor

        $PrimarySigningCert_base64 = ([array]($KeyDescriptors | where use -eq 'signing').KeyInfo)[0].X509Data.X509Certificate
        $PrimarySigningCert_x509 = [Security.Cryptography.X509Certificates.X509Certificate2][System.Convert]::FromBase64String($PrimarySigningCert_base64)    
    
        $SecondarySigningCert_base64 = ([array]($KeyDescriptors | where use -eq 'signing').KeyInfo)[1].X509Data.X509Certificate
        $SecondarySigningCert_x509 = [Security.Cryptography.X509Certificates.X509Certificate2][System.Convert]::FromBase64String($SecondarySigningCert_base64)    

        $EncryptionCert_base64 = ($KeyDescriptors | where use -eq 'encryption').KeyInfo.X509Data.X509Certificate
        $EncryptionCert_x509 = [Security.Cryptography.X509Certificates.X509Certificate2][System.Convert]::FromBase64String($EncryptionCert_base64) 

        $Now = Get-Date    
    
        $CertReportObject = [pscustomobject]@{            
            SSL_Subject                   = $SSLCert_x509.Subject             
            SSL_NotAfter                  = $SSLCert_x509.NotAfter           
            SSL_Thumbprint                = $SSLCert_x509.Thumbprint       
            SSL_Issuer                    = $SSLCert_x509.Issuer               
            SSL_DaysToExpiry              = ($SSLCert_x509.NotAfter - $Now).Days 
                                        
            PrimarySigning_Subject        = $PrimarySigningCert_x509.Subject       
            PrimarySigning_NotAfter       = $PrimarySigningCert_x509.NotAfter      
            PrimarySigning_Thumbprint     = $PrimarySigningCert_x509.Thumbprint    
            PrimarySigning_Issuer         = $PrimarySigningCert_x509.Issuer        
            PrimarySigning_DaysToExpiry   = ($PrimarySigningCert_x509.NotAfter - $Now).Days  

            SecondarySigning_Subject      = $SecondarySigningCert_x509.Subject      
            SecondarySigning_NotAfter     = $SecondarySigningCert_x509.NotAfter     
            SecondarySigning_Thumbprint   = $SecondarySigningCert_x509.Thumbprint   
            SecondarySigning_Issuer       = $SecondarySigningCert_x509.Issuer       
            SecondarySigning_DaysToExpiry = ($SecondarySigningCert_x509.NotAfter - $Now).Days  

            Encryption_Subject            = $EncryptionCert_x509.Subject       
            Encryption_NotAfter           = $EncryptionCert_x509.NotAfter      
            Encryption_Thumbprint         = $EncryptionCert_x509.Thumbprint    
            Encryption_Issuer             = $EncryptionCert_x509.Issuer        
            Encryption_DaysToExpiry       = ($EncryptionCert_x509.NotAfter - $Now).Days  
        }

        if ($Display -eq $true) {

            cls

            if ($UnsupportedPowerShell -eq $true) { Write-Host "Functionality is limited with invalid HTTPS certificates in this version of PowerShell. `nhttps://github.com/PowerShell/PowerShell/issues/17340" -ForegroundColor Red }

            Write-Host "    `nSSL (HTTPS) Certificate:`n" -ForegroundColor Green
            Write-Host "    SSL_Subject:     " $CertReportObject.SSL_Subject
            Write-Host "    SSL_NotAfter:    " $CertReportObject.SSL_NotAfter
            Write-Host "    SSL_Thumbprint:  " $CertReportObject.SSL_Thumbprint
            Write-Host "    SSL_Issuer:      " $CertReportObject.SSL_Issuer
            Write-Host "    SSL_DaysToExpiry: " -NoNewline
            Write-Host  $CertReportObject.SSL_DaysToExpiry -ForegroundColor Cyan

            Write-Host "    `nEncryption Certificate:`n" -ForegroundColor DarkMagenta
            Write-Host "    EncryptionSigning_Subject:     " $CertReportObject.Encryption_Subject
            Write-Host "    EncryptionSigning_NotAfter:    " $CertReportObject.Encryption_NotAfter 
            Write-Host "    EncryptionSigning_Thumbprint:  " $CertReportObject.Encryption_Thumbprint
            Write-Host "    EncryptionSigning_Issuer:      " $CertReportObject.Encryption_Issuer
            Write-Host "    EncryptionSigning_DaysToExpiry: " -NoNewline
            Write-Host $CertReportObject.Encryption_DaysToExpiry -ForegroundColor Cyan

            Write-Host "    `nToken Signing Certificate:`n" -ForegroundColor Yellow
            Write-Host "    PrimarySigning_Subject:     " $CertReportObject.PrimarySigning_Subject
            Write-Host "    PrimarySigning_NotAfter:    " $CertReportObject.PrimarySigning_NotAfter 
            Write-Host "    PrimarySigning_Thumbprint:  " $CertReportObject.PrimarySigning_Thumbprint
            Write-Host "    PrimarySigning_Issuer:      " $CertReportObject.PrimarySigning_Issuer
            Write-Host "    PrimarySigning_DaysToExpiry: " -NoNewline
            Write-Host $CertReportObject.PrimarySigning_DaysToExpiry -ForegroundColor Cyan

            Write-Host "`nSecondary Token Signing Certificate:`n" -ForegroundColor DarkYellow
        
            if ($null -ne $CertReportObject.SecondarySigning_Subject) {
                Write-Host "    SecondarySigning_Subject:     " $CertReportObject.SecondarySigning_Subject
                Write-Host "    SecondarySigning_NotAfter:    " $CertReportObject.SecondarySigning_NotAfter 
                Write-Host "    SecondarySigning_Thumbprint:  " $CertReportObject.SecondarySigning_Thumbprint
                Write-Host "    SecondarySigning_Issuer:      " $CertReportObject.SecondarySigning_Issuer
                Write-Host "    SecondarySigning_DaysToExpiry: " -NoNewline
                Write-Host $CertReportObject.SecondarySigning_DaysToExpiry -ForegroundColor Cyan
            }
            else { Write-Host "    !! No Secondary Token Signing Certificate Found !!`n" }

            Write-Host "`n"
        }
        else {
            return $CertReportObject
        }
    } 
    else { Write-Warning "Cannot connect to: $FarmFqdn" }
}


Request-AdfsCerts -FarmFqdn adfs.contoso.com -Display $true