# azurecontainerapps
Automate the processes of creation, management of Azure Container Registry (ACR) and deployment of Azure Container Apps (ACA) by powershell script. Note that me used secret-based authentication from ACR credentials instead of managed identity, considered imitate the scene of building and pushing docker images to ACR via on-premise docker host and configure the ACA to pull and deploy the docker images. Docker, powershell and Az module should be well prepared in the environment. 

  1. Clone the repository to your docker host
  2. Navigate to your repository directory.
  3. Type 'pwsh' to launch powershell session
  4. Ensure deployment.ps1, dockerfile for nginx and php-fpm are inside the current path, type ./deployment.ps1 to commence the automation process, handling image build, push operations, and ACA configuration .  



