# Log in to Azure and set subscription
Connect-AzAccount -UseDeviceAuthentication
Set-AzContext -SubscriptionId "32799573-f5bc-43dc-860e-b885e84f8fd2"

Write-Host "Hello! Welcome to Azure!" -ForegroundColor Green

# Define variables
$subscriptionId = (Get-AzContext).Subscription.Id
$resourceGroupName     = "containerapps-rg"
$location              = "eastasia"
$acrName               = "eastasiaregistry"
$environmentName       = "containerapps-env"
$nginxappName          = "nginx-leave-application-portal"
$phpfpmappName         = "php-fpm"
$nginxrepo             = "docker-nginx-leaveapplicationportal"
Write-Host "Nginx Image Name: $nginxrepo" -ForegroundColor Green
$phpfpmrepo            = "docker-php-leaveapplicationportal"
Write-Host "php-fpm Image Name: $phpfpmrepo" -ForegroundColor Green
$nginxdockerfileName   = "Dockerfile.nginx"
$phpfpmdockerfileName  = "Dockerfile.php-fpm"
$loganalyticsName      = "leaveapplicationportal"
$logDest               = "log-analytics"

# Create resource group if it doesn’t exist
if (-not (Get-AzResourceGroup -Name $resourceGroupName -ErrorAction SilentlyContinue)) {
    New-AzResourceGroup -Name $resourceGroupName -Location $location
}
else {
    Write-Host "Resource Group '$resourceGroupName' already exists." -ForegroundColor Yellow
}

# Create Azure Container Registry (ACR) if it doesn’t exist
if (-not (Get-AzContainerRegistry -Name $acrName -ErrorAction SilentlyContinue)) {
    New-AzContainerRegistry -ResourceGroupName $resourceGroupName -Name $acrName -Sku Basic -Location $location
}
else {
    Write-Host "Azure Container Registry '$acrName' already exists." -ForegroundColor Yellow
}

# Enable admin user for the new registry
Update-AzContainerRegistry -Name $acrName -ResourceGroupName $resourceGroupName -EnableAdminUser

# Get ACR credentials
$acr = Get-AzContainerRegistry -ResourceGroupName $resourceGroupName -Name $acrName
# Remove any trailing slash so that concatenation is correct
$acrLoginServer = $acr.LoginServer.TrimEnd('/')
Write-Host "ACR Login Server: $acrLoginServer" -ForegroundColor Green
$acrCred = Get-AzContainerRegistryCredential -ResourceGroupName $resourceGroupName -Name $acrName
$acrUsername = $acrCred.Username
$acrPassword = $acrCred.Password

#$securestring = ConvertTo-SecureString -String $acrPassword -AsPlainText -Force
# log in to ACR using Docker CLI for local docker host
docker login $acrLoginServer -u $acrUsername -p $acrPassword

# Build and push container images to ACR
docker build -t $nginxrepo -f $nginxdockerfileName .
docker tag $nginxrepo $acrLoginServer/docker-nginx-leaveapplicationportal:v1.2
$nginxImage = "$acrLoginServer/docker-nginx-leaveapplicationportal:v1.2"
docker push $nginxImage

docker build -t $phpfpmrepo -f $phpfpmdockerfileName .
docker tag $phpfpmrepo $acrLoginServer/docker-php-leaveapplicationportal:v1.2
$phpfpmImage = "$acrLoginServer/docker-php-leaveapplicationportal:v1.2"
docker push $phpfpmImage

# Create Log Analytics workspace if it doesn't already exist
if (-not (Get-AzOperationalInsightsWorkspace -ResourceGroupName $resourceGroupName -Name $loganalyticsName -ErrorAction SilentlyContinue)) {
    New-AzOperationalInsightsWorkspace -ResourceGroupName $resourceGroupName -Name $loganalyticsName -Location $location
}
else {
    Write-Host "Log Analytics workspace '$loganalyticsName' already exists." -ForegroundColor Yellow
}

$workspace = Get-AzOperationalInsightsWorkspace -ResourceGroupName $resourceGroupName -Name $loganalyticsName
$customerId = $workspace.CustomerId
$keys = Get-AzOperationalInsightsWorkspaceSharedKey -ResourceGroupName $resourceGroupName -Name $loganalyticsName
$primaryKey = $keys.PrimarySharedKey
$workloadProfile = New-AzContainerAppWorkloadProfileObject -Name "Consumption" -Type "Consumption"

# Create Container Apps Environment if it doesn't already exist
if (-not (Get-AzContainerAppManagedEnv -ResourceGroupName $resourceGroupName -Name $environmentName -ErrorAction SilentlyContinue)) {
    New-AzContainerAppManagedEnv -ResourceGroupName $resourceGroupName -Name $environmentName -Location $location `
        -AppLogConfigurationDestination $logDest `
        -LogAnalyticConfigurationCustomerId $customerId `
        -LogAnalyticConfigurationSharedKey $primaryKey `
        -VnetConfigurationInternal:$false `
        -WorkloadProfile $workloadProfile
}
else {
    Write-Host "Container App Managed Environment '$environmentName' already exists." -ForegroundColor Yellow
}

$env = Get-AzContainerAppManagedEnv -ResourceGroupName $resourceGroupName -Name $environmentName
$envId = $env.Id

# Define a function to generate a random password.
#function New-RandomPassword {
#    param (
#        [int]$Length = 16
#    )
#    # Define the character set for the password.
#    $chars = 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789!@#$%^&*()-_=+'
#    $passwordChars = -join (1..$Length | ForEach-Object {
#        $randomIndex = Get-Random -Minimum 0 -Maximum $chars.Length
#        $chars[$randomIndex]
#    })
#    return $passwordChars
#}

# Generate a password of 20 characters.
#$passwordValue = New-RandomPassword -Length 20
#Write-Output "Generated Secret Password: $passwordValue"

# Create ACR credential and secret for the container-apps
$secret = New-AzContainerAppSecretObject -Name "acrpassword" -Value $acrPassword
$registryCredential = New-AzContainerAppRegistryCredentialObject -Server $acrLoginServer -Username $acrUsername -PasswordSecretRef "acrpassword" 

# Create PHP-FPM Container App with internal ingress
$phpfpmappTemp = New-AzContainerAppTemplateObject -Image $phpfpmImage -Name $phpfpmappName -ResourceCpu 1.0 -ResourceMemory "2.0Gi" 
$phpfpmingress  = New-AzContainerAppConfigurationObject -IngressExternal:$False -IngressTargetPort 9000 -IngressTransport "tcp" -Registry $registryCredential -Secret $secret

# Deploy PHP-FPM Container App
New-AzContainerApp -ResourceGroupName $resourceGroupName -Name $phpfpmappName -Location $location -EnvironmentId $envId -Configuration $phpfpmingress -TemplateContainer $phpfpmappTemp -SubscriptionId $subscriptionId

# Create Nginx Container App with external ingress
$nginxappTemp = New-AzContainerAppTemplateObject -Image $nginxImage -Name $nginxappName -ResourceCpu 1.0 -ResourceMemory "2.0Gi"
$nginxingress = New-AzContainerAppConfigurationObject -IngressExternal:$true -IngressTargetPort 80 -IngressTransport "http" -Registry $registryCredential -Secret $secret

# Deploy Nginx Container App
New-AzContainerApp -ResourceGroupName $resourceGroupName -Name $nginxappName -Location $location -EnvironmentId $envId -Configuration $nginxingress -TemplateContainer $nginxappTemp -SubscriptionId $subscriptionId

Write-Host "Congrats! Containers are ready to use!" -ForegroundColor Green

