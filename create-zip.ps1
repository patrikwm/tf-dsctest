rm .\deployrds.zip
Write-Output "Creating deployrds.zip file"
Publish-AzVMDscConfiguration .\deployrds.ps1 -OutputArchivePath '.\deployrds.zip'