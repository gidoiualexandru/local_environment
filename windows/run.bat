@echo off
rem Must be run as Administrator

setlocal enabledelayedexpansion
cd /d "%~dp0"

echo C    echo Downloading Podman installer from %PODMAN_URL% ...
    %POWERSHELL% "Invoke-WebRequest -Uri '%PODMAN_URL%' -OutFile '%INSTALLER%'"

    echo Installing Podman...
    start /wait "" "%INSTALLER%" /S
    if not %errorlevel%==0 (
        echo Failed to install Podman
        exit /b 1
    )

    rem Update PATH to include Podman
    set "PATH=%PATH%;C:\Program Files\RedHat\Podman"strative privileges...
>nul 2>&1 net session
if %errorlevel% neq 0 (
    echo This script must be run as Administrator. Please re-run this .bat as Administrator.
    pause
    exit /b 1
)

rem helper: run a PowerShell command and capture output
set "POWERSHELL=powershell -NoProfile -ExecutionPolicy Bypass -Command"

echo Ensuring WSL2 is available...

rem Try wsl --status first to check if WSL is already working
wsl --status >nul 2>&1
if %errorlevel% equ 0 (
    echo WSL is already installed and working.
    goto :wsl_ok
)

echo Installing WSL using wsl --install command...
wsl --install --no-distribution >nul 2>&1

rem After install, try enabling required features directly
echo Enabling Windows features for WSL...
dism.exe /online /enable-feature /featurename:Microsoft-Windows-Subsystem-Linux /all /norestart >nul
dism.exe /online /enable-feature /featurename:VirtualMachinePlatform /all /norestart >nul

echo Installing WSL2 Linux kernel update...
set "KERNEL_MSI=%TEMP%\wsl_update.msi"
if not exist "%KERNEL_MSI%" (
    echo Downloading WSL2 kernel update package...
    powershell -Command "& { $ProgressPreference = 'SilentlyContinue'; Invoke-WebRequest -Uri 'https://wslstorestorage.blob.core.windows.net/wslblob/wsl_update_x64.msi' -OutFile '%KERNEL_MSI%' }"
)

echo Installing kernel update...
start /wait msiexec.exe /i "%KERNEL_MSI%" /quiet /norestart
if exist "%KERNEL_MSI%" del /f /q "%KERNEL_MSI%"

echo Setting WSL default version to 2...
wsl --set-default-version 2 >nul 2>&1

echo Installing Ubuntu distribution (this might take a few minutes)...
wsl --install -d Ubuntu >nul 2>&1

rem Check if WSL is working now
wsl --status >nul 2>&1
if %errorlevel% neq 0 (
    echo.
    echo WSL installation requires a system restart to complete.
    echo Please restart your computer and run this script again.
    echo.
    choice /C YN /M "Do you want to restart now"
    if !errorlevel! equ 1 (
        shutdown /r /t 10 /c "Restarting to complete WSL installation"
        exit /b 0
    ) else (
        echo Please restart manually and run this script again.
        pause
        exit /b 1
    )
)

:wsl_ok
echo WSL 2 is now installed and enabled.

echo WSL 2 is now installed and enabled.

rem Install Chocolatey if missing
where choco >nul 2>&1
if %errorlevel% neq 0 (
    echo Chocolatey not found. Installing Chocolatey...
    %POWERSHELL% "[System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072; iex ((New-Object System.Net.WebClient).DownloadString('https://community.chocolatey.org/install.ps1'))"
    set "PATH=%PATH%;%ALLUSERSPROFILE%\chocolatey\bin"
) else (
    echo Chocolatey already installed.
)

rem Ensure Git
where git >nul 2>&1
if %errorlevel% neq 0 (
    echo Git not found. Installing via Chocolatey...
    choco install git -y --no-progress
) else (
    echo Git found.
)

rem Ensure Podman is installed
echo Checking for Podman installation...
where podman >nul 2>&1
if %errorlevel% neq 0 (
    echo Podman not installed. Installing Podman...
    echo Installing Podman via winget...
    winget install -e --id RedHat.Podman --accept-source-agreements --accept-package-agreements
    if %errorlevel% neq 0 (
        echo Failed to install Podman via winget
        pause
        exit /b 1
    )
    
    echo Refreshing environment PATH...
    setx PATH "%PATH%;C:\Program Files\RedHat\Podman" /M
    set "PATH=%PATH%;C:\Program Files\RedHat\Podman"

    echo Installing Podman (this may take a few minutes)...
    powershell -NoProfile -ExecutionPolicy Bypass -File "%PS_SCRIPT%"
    if %errorlevel% neq 0 (
        echo Failed to install Podman
        type "%PS_SCRIPT%"
        pause
        exit /b 1
    )
    del "%PS_SCRIPT%" >nul 2>&1

    echo Waiting for Podman installation to complete...
    timeout /t 10 /nobreak >nul

        %POWERSHELL% "Invoke-WebRequest -Uri '%PODMAN_URL%' -OutFile '%INSTALLER%'"
        
        echo Installing Podman...
        start /wait "" "%INSTALLER%" /S
        if %errorlevel% neq 0 (
            echo Failed to install Podman
            pause
            exit /b 1
        )
        del /f /q "%INSTALLER%" >nul 2>&1
    )
    
    echo Setting up Podman machine...
    
    rem Ensure WSL2 is set as default
    echo Setting WSL2 as default...
    wsl --set-default-version 2
    
    rem Clean up any existing podman machine
    echo Cleaning up existing Podman machine...
    wsl --unregister podman-machine-default >nul 2>&1
    wsl --shutdown >nul 2>&1
    
    echo Initializing Podman machine...
    podman machine init --cpus 2 --memory 2048 --disk-size 20
    if %errorlevel% neq 0 (
        echo Failed to initialize Podman machine. Trying troubleshooting steps...
        
        rem Additional troubleshooting
        echo Resetting Winsock...
        netsh winsock reset
        
        echo Retrying Podman machine initialization...
        podman machine init --cpus 2 --memory 2048 --disk-size 20
        if %errorlevel% neq 0 (
            echo Failed to initialize Podman machine even after troubleshooting
            pause
            exit /b 1
        )
    )
    
    echo Setting Podman machine to rootful mode...
    podman machine set --rootful

    echo Starting Podman machine...
    podman machine start
    if %errorlevel% neq 0 (
        echo Failed to start Podman machine
        pause
        exit /b 1
    )
    
    echo Waiting for Podman machine to be fully ready...
    timeout /t 15 /nobreak >nul
    
    echo Verifying Podman setup...
    podman version
    if %errorlevel% neq 0 (
        echo Failed to verify Podman installation
        pause
        exit /b 1
    )
    
    echo Checking WSL status...
    wsl -l -v
    
    echo Podman was installed and initialized successfully.
) else (
    echo Podman is already installed.
    echo Checking Podman machine status...
    echo Checking Podman machine status...
    podman machine list | findstr "Currently running" >nul 2>&1
    if %errorlevel% neq 0 (
        echo Starting Podman machine...
        podman machine start
        timeout /t 5 /nobreak >nul
    )
)

rem Function to validate password
:validate_pass
set "_pw=%~1"
set "_len=0"
set "_valid=0"
setlocal enabledelayedexpansion
:count_loop
if defined _pw (
    set "_pw=!_pw:~1!"
    set /a "_len+=1"
    goto count_loop
)
endlocal & set "_len=%_len%"

if %_len% geq 15 exit /b 0

rem If not long enough, check complexity
set "hasLower="
set "hasUpper="
set "hasDigit="
set "hasSpecial="
set "_pwd=%~1"
setlocal enabledelayedexpansion
for /f "delims=" %%C in ('cmd /u /c echo !_pwd! ^| find /v ""') do (
    set "chars=%%C"
    if "!chars!" neq "" (
        echo !chars!| findstr /r "[a-z]" >nul && set hasLower=1
        echo !chars!| findstr /r "[A-Z]" >nul && set hasUpper=1
        echo !chars!| findstr /r "[0-9]" >nul && set hasDigit=1
        echo !chars!| findstr /r "[!@#$%%^&*_\-\[\]\(\)]" >nul && set hasSpecial=1
    )
)
if defined hasLower if defined hasUpper if defined hasDigit if defined hasSpecial (
    endlocal & exit /b 0
) else (
    endlocal & exit /b 1
)

rem Main script continues

echo  =================================================================
echo  ================= local environment installer ===================
echo  ====================== peviitor.ro ==============================
echo  =================================================================

set /p SOLR_USER=Enter the Solr username: 

:get_password
%POWERSHELL% "[Console]::Error.Write('Enter the Solr password (input hidden): '); $pwd = Read-Host -AsSecureString; $BSTR = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($pwd); [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($BSTR)" > "%TEMP%\pwd.txt"
set /p SOLR_PASS=<"%TEMP%\pwd.txt"
del "%TEMP%\pwd.txt"

call :validate_pass "%SOLR_PASS%"
if %errorlevel% neq 0 (
    echo Password must be at least 15 characters OR contain lowercase, uppercase, digit, and special ^(!@#$%%^&*_-[]^(^)^). Please try again.
    goto get_password
)

echo.
echo  =================================================================
echo  ===================== use those credentials =====================
echo  ====================== for SOLR login ===========================
echo  =================================================================
echo You entered user: %SOLR_USER%
echo You entered password: [hidden]

set "PEVIITOR_DIR=%USERPROFILE%\peviitor"
if exist "%PEVIITOR_DIR%" (
    echo Removing existing %PEVIITOR_DIR% ...
    rmdir /s /q "%PEVIITOR_DIR%"
)

rem Stop and remove containers if present
for %%C in (apache-container solr-container data-migration deploy-fe) do (
    for /f "usebackq delims=" %%I in (`podman ps -aq -f "name=%%C" 2^>nul`) do (
        if not "%%I"=="" (
            echo Stopping and removing container %%C...
            podman stop %%I >nul 2>&1
            podman rm %%I >nul 2>&1
        )
    )
)

rem Remove network if exists
podman network ls --format "{{.Name}}" | findstr /x "mynetwork" >nul 2>&1
if %errorlevel% equ 0 (
    echo Removing existing network mynetwork...
    podman network rm mynetwork >nul 2>&1
)

echo Creating network mynetwork with subnet 172.168.0.0/16...
podman network create --subnet=172.168.0.0/16 mynetwork >nul 2>&1

set "REPO=peviitor-ro/search-engine"
set "ASSET_NAME=build.zip"
set "TARGET_DIR=%PEVIITOR_DIR%"

echo Fetching download link for %ASSET_NAME% from GitHub repo %REPO% latest release...
for /f "usebackq delims=" %%U in (`%POWERSHELL% "(Invoke-RestMethod -Uri 'https://api.github.com/repos/%REPO%/releases/latest').assets | Where-Object { $_.name -eq '%ASSET_NAME%' } | Select-Object -ExpandProperty browser_download_url"`) do set "DOWNLOAD_URL=%%U"

if not defined DOWNLOAD_URL (
    echo ERROR: Could not find download URL for %ASSET_NAME% in the latest release.
    pause
    exit /b 1
)

echo Download URL found: %DOWNLOAD_URL%
set "TMP_FILE=%TEMP%\%ASSET_NAME%"
echo Downloading %ASSET_NAME% to temporary folder...
%POWERSHELL% "Invoke-WebRequest -Uri '%DOWNLOAD_URL%' -OutFile '%TMP_FILE%'"

echo Extracting archive to %TARGET_DIR%...
if not exist "%TARGET_DIR%" mkdir "%TARGET_DIR%"
%POWERSHELL% "Expand-Archive -Path '%TMP_FILE%' -DestinationPath '%TARGET_DIR%' -Force"
del /f /q "%TMP_FILE%" >nul 2>&1

if exist "%TARGET_DIR%\build\.htaccess" (
    echo Removing %TARGET_DIR%\build\.htaccess
    del /f /q "%TARGET_DIR%\build\.htaccess"
)

echo Cloning API repo to %TARGET_DIR%\build\api...
git clone --depth 1 --branch master --single-branch https://github.com/peviitor-ro/api.git "%TARGET_DIR%\build\api"

echo Creating api.env file...
(
echo LOCAL_SERVER = 172.168.0.10:8983
echo PROD_SERVER = zimbor.go.ro
echo BACK_SERVER = https://api.laurentiumarian.ro/
echo SOLR_USER = %SOLR_USER%
echo SOLR_PASS = %SOLR_PASS%
) > "%TARGET_DIR%\build\api\api.env"

echo Starting apache-container with Podman...
podman run --name apache-container --network mynetwork --ip 172.168.0.11 --restart=always -d -p 8081:80 -v "%TARGET_DIR%\build:/var/www/html" alexstefan1702/php-apache

echo Updating swagger-ui URL inside apache-container...
podman exec apache-container sh -c "sed -i 's|url: \"http://localhost:8080/api/v0/swagger.json\"|url: \"http://localhost:8081/api/v0/swagger.json\"|g' /var/www/swagger-ui/swagger-initializer.js"
podman restart apache-container

rem Solr container setup
set "CORE_NAME=auth"
set "CORE_NAME_2=jobs"
set "CORE_NAME_3=logo"
set "CONTAINER_NAME=solr-container"
set "SOLR_PORT=8983"

set "SOLR_DATA_HOST=%USERPROFILE%\peviitor\solr\core\data"
if not exist "%SOLR_DATA_HOST%" (
    echo Creating Solr data directory at %SOLR_DATA_HOST%
    mkdir "%SOLR_DATA_HOST%"
)

echo Starting Solr container on port %SOLR_PORT% using Podman...
podman run --name %CONTAINER_NAME% --network mynetwork --ip 172.168.0.10 --restart=always -d -p %SOLR_PORT%:%SOLR_PORT% -v "%SOLR_DATA_HOST%:/var/solr/data:Z" solr:latest

echo Waiting for Solr to start (15 seconds)...
timeout /t 15 /nobreak >nul

echo Creating Solr cores: %CORE_NAME%, %CORE_NAME_2%, %CORE_NAME_3%
for %%K in (%CORE_NAME% %CORE_NAME_2% %CORE_NAME_3%) do (
    podman exec %CONTAINER_NAME% bin/solr create_core -c %%K
)

rem Add fields to Solr cores using PowerShell to handle JSON
%POWERSHELL% "@'
{
    \"add-field\": [{
        \"name\": \"job_link\",
        \"type\": \"text_general\",
        \"stored\": true,
        \"indexed\": true,
        \"multiValued\": true,
        \"uninvertible\": true
    }]
}
'@ | Out-File -FilePath '%TEMP%\field.json' -Encoding UTF8"

podman cp "%TEMP%\field.json" %CONTAINER_NAME%:/tmp/field.json
podman exec %CONTAINER_NAME% curl -X POST -H "Content-Type: application/json" --data-binary @/tmp/field.json "http://localhost:%SOLR_PORT%/solr/%CORE_NAME_2%/schema"

rem Add more fields and copy fields (simplified for brevity, repeat for others)
rem Create security.json
%POWERSHELL% "@'
{
    \"authentication\": {
        \"blockUnknown\": true,
        \"class\": \"solr.BasicAuthPlugin\",
        \"credentials\": { \"solr\": \"IV0EHq1OnNrj6gvRCwvFwTrZ1+z1oBbnQdiVC3otuq0= Ndd7LKvVBAaZIF0QAVi1ekCfAJXr1GGfLtRUXhgrF8c=\" },
        \"realm\": \"My Solr users\",
        \"forwardCredentials\": false
    },
    \"authorization\": {
        \"class\": \"solr.RuleBasedAuthorizationPlugin\",
        \"permissions\": [ { \"name\": \"security-edit\", \"role\": \"admin\" } ],
        \"user-role\": { \"solr\": \"admin\" }
    }
}
'@ | Out-File -FilePath '%CD%\security.json' -Encoding UTF8"

echo Copying security.json into Solr container and restarting container...
podman cp "%CD%\security.json" %CONTAINER_NAME%:/var/solr/data/security.json
podman restart %CONTAINER_NAME%

rem Install Java if missing
where java >nul 2>&1
if %errorlevel% neq 0 (
    echo Java not found. Installing OpenJDK 11 via Chocolatey...
    choco install openjdk11 -y --no-progress
) else (
    echo Java is installed:
    java -version
)

rem Install JMeter
set "JMETER_HOME=%USERPROFILE%\apache-jmeter-5.6.3"
if not exist "%JMETER_HOME%" (
    echo Installing JMeter 5.6.3...
    set "JMETER_URL=https://dlcdn.apache.org/jmeter/binaries/apache-jmeter-5.6.3.zip"
    set "ZIPFILE=%TEMP%\apache-jmeter-5.6.3.zip"
    %POWERSHELL% "Invoke-WebRequest -Uri '%JMETER_URL%' -OutFile '%ZIPFILE%'"
    %POWERSHELL% "Expand-Archive -Path '%ZIPFILE%' -DestinationPath '%USERPROFILE%' -Force"
    del /f /q "%ZIPFILE%" >nul 2>&1
    echo JMeter installed to %JMETER_HOME%
) else (
    echo JMeter already installed at %JMETER_HOME%
)

set "JMETER_LIB_EXT=%JMETER_HOME%\lib\ext"
set "JMETER_LIB=%JMETER_HOME%\lib"
set "PLUGIN_MGR_JAR=%JMETER_LIB_EXT%\jmeter-plugins-manager-1.10.jar"

if not exist "%PLUGIN_MGR_JAR%" (
    echo Downloading JMeter Plugins Manager...
    %POWERSHELL% "Invoke-WebRequest -Uri 'https://jmeter-plugins.org/get/' -OutFile '%PLUGIN_MGR_JAR%'"
)

set "CMDRUNNER_JAR=%JMETER_LIB%\cmdrunner-2.3.jar"
if not exist "%CMDRUNNER_JAR%" (
    echo Downloading CmdRunner...
    %POWERSHELL% "Invoke-WebRequest -Uri 'https://repo1.maven.org/maven2/kg/apc/cmdrunner/2.3/cmdrunner-2.3.jar' -OutFile '%CMDRUNNER_JAR%'"
)

echo Installing JMeter Plugins Manager command-line tool...
java -cp "%PLUGIN_MGR_JAR%" org.jmeterplugins.repository.PluginManagerCMDInstaller

rem Get new Solr credentials
set /p NEW_USER=Enter new Solr username (mandatory): 

:get_new_pass
%POWERSHELL% "[Console]::Error.Write('Enter new Solr password (input hidden): '); $pwd = Read-Host -AsSecureString; $BSTR = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($pwd); [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($BSTR)" > "%TEMP%\new_pwd.txt"
set /p NEW_PASS=<"%TEMP%\new_pwd.txt"
del "%TEMP%\new_pwd.txt"

call :validate_pass "%NEW_PASS%"
if %errorlevel% neq 0 (
    echo Password must be at least 15 characters OR contain lowercase, uppercase, digit, and special ^(!@#$%%^&*_-[]^(^)^). Please try again.
    goto get_new_pass
)

set "OLD_USER=solr"
set "OLD_PASS=SolrRocks"

rem Set new user
%POWERSHELL% "@{ 'set-user' = @{ '%NEW_USER%' = '%NEW_PASS%' } } | ConvertTo-Json -Compress | Out-File -FilePath '%TEMP%\auth.json' -Encoding UTF8"
curl -s -u %OLD_USER%:%OLD_PASS% -X POST -H "Content-Type: application/json" --data @"%TEMP%\auth.json" "http://localhost:%SOLR_PORT%/solr/admin/authentication"

rem Set user role
%POWERSHELL% "@{ 'set-user-role' = @{ '%NEW_USER%' = @('admin') } } | ConvertTo-Json -Compress | Out-File -FilePath '%TEMP%\authz.json' -Encoding UTF8"
curl -s -u %OLD_USER%:%OLD_PASS% -X POST -H "Content-Type: application/json" --data @"%TEMP%\authz.json" "http://localhost:%SOLR_PORT%/solr/admin/authorization"

rem Run JMeter migration
set "MIGRATION_JMX=%~dp0migration.jmx"
if exist "%JMETER_HOME%\bin\jmeter.bat" (
    call "%JMETER_HOME%\bin\jmeter.bat" -n -t "%MIGRATION_JMX%" -Duser=%NEW_USER% -Dpass=%NEW_PASS%
)

rem Delete old user
%POWERSHELL% "@{ 'delete-user' = @('%OLD_USER%') } | ConvertTo-Json -Compress | Out-File -FilePath '%TEMP%\deluser.json' -Encoding UTF8"
curl -s -u %NEW_USER%:%NEW_PASS% -X POST -H "Content-Type: application/json" --data @"%TEMP%\deluser.json" "http://localhost:%SOLR_PORT%/solr/admin/authentication"

echo.
echo Important Information:
echo SOLR is running on http://localhost:%SOLR_PORT%/solr/
echo UI is running on http://localhost:8081/
echo swagger-ui is running on http://localhost:8081/swagger-ui/
echo JMeter is installed and configured.
echo Local username and password for SOLR: %NEW_USER% / [hidden]

rem Cleanup
del /f /q "%CD%\security.json" "%TEMP%\*.json" 2>nul

echo Launching Google Chrome with URLs...
set "CHROME=C:\Program Files\Google\Chrome\Application\chrome.exe"
if exist "%CHROME%" (
    start "" "%CHROME%" "http://localhost:8081/api/v0/random"
    start "" "%CHROME%" "http://localhost:8983/solr/#/jobs/query"
    start "" "%CHROME%" "http://localhost:8081/swagger-ui"
    start "" "%CHROME%" "http://localhost:8081/"
) else (
    echo Google Chrome not found at '%CHROME%'. Please open the URLs manually.
)

echo Script execution completed.
pause
exit /b 0
