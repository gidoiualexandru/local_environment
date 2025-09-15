@echo off
rem Must be run as Administrator

setlocal enabledelayedexpansion
cd /d "%~dp0"

rem --- Admin check ---
>nul 2>&1 net session
if %errorlevel% neq 0 (
    echo This script must be run as Administrator. Please re-run this .bat as Administrator.
    pause
    exit /b 1
)

rem --- Helper: PowerShell runner ---
set "POWERSHELL=powershell -NoProfile -ExecutionPolicy Bypass -Command"

rem --- Ensure WSL 2 is installed and enabled BEFORE Podman ---
echo Ensuring WSL 2 is installed and enabled...
wsl --status >nul 2>&1
if %errorlevel% neq 0 (
    echo Enabling Windows features for WSL...
    dism.exe /online /enable-feature /featurename:Microsoft-Windows-Subsystem-Linux /all /norestart >nul
    dism.exe /online /enable-feature /featurename:VirtualMachinePlatform /all /norestart >nul

    echo Installing WSL2 Linux kernel update...
    set "KERNEL_MSI=%TEMP%\wsl_update.msi"
    if not exist "%KERNEL_MSI%" (
        %POWERSHELL% "& { $ProgressPreference='SilentlyContinue'; Invoke-WebRequest -Uri 'https://wslstorestorage.blob.core.windows.net/wslblob/wsl_update_x64.msi' -OutFile '%KERNEL_MSI%' }"
    )
    start /wait msiexec.exe /i "%KERNEL_MSI%" /quiet /norestart
    if exist "%KERNEL_MSI%" del /f /q "%KERNEL_MSI%"

    echo Setting WSL default version to 2...
    wsl --set-default-version 2 >nul 2>&1

    echo Attempting to install Ubuntu distribution (optional)...
    wsl --install -d Ubuntu >nul 2>&1

    echo Verifying WSL installation...
    wsl --status >nul 2>&1
    if %errorlevel% neq 0 (
        echo.
        echo WSL installation likely requires a system restart to complete.
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
)

echo WSL 2 is installed and enabled.

rem --- Install Chocolatey if missing ---
where choco >nul 2>&1
if %errorlevel% neq 0 (
    echo Chocolatey not found. Installing Chocolatey...
    %POWERSHELL% "[System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072; iex ((New-Object System.Net.WebClient).DownloadString('https://community.chocolatey.org/install.ps1'))"
    set "PATH=%PATH%;%ALLUSERSPROFILE%\chocolatey\bin"
) else (
    echo Chocolatey already installed.
)

rem --- Ensure Git ---
where git >nul 2>&1
if %errorlevel% neq 0 (
    echo Git not found. Installing via Chocolatey...
    choco install git -y --no-progress
) else (
    echo Git found.
)

rem --- Install Podman on Windows (winget with choco fallback) ---
where podman >nul 2>&1
if %errorlevel% neq 0 (
    echo Podman not found. Installing Podman...
    where winget >nul 2>&1
    if %errorlevel% equ 0 (
        winget install -e --id RedHat.Podman --accept-source-agreements --accept-package-agreements
        if %errorlevel% neq 0 (
            echo winget failed. Trying Chocolatey...
            choco install podman -y --no-progress
        )
    ) else (
        echo winget not available. Using Chocolatey...
        choco install podman -y --no-progress
    )

    echo Refreshing environment PATH if needed...
    set "PODMAN_DIR=C:\Program Files\RedHat\Podman"
    if exist "%PODMAN_DIR%\podman.exe" (
        setx PATH "%PATH%;%PODMAN_DIR%" /M >nul
        set "PATH=%PATH%;%PODMAN_DIR%"
    )

    echo Waiting for Podman installation to settle...
    timeout /t 5 /nobreak >nul
) else (
    echo Podman is already installed.
)

rem --- Initialize and start Podman machine (WSL backend) ---
rem Ensure WSL2 default version (idempotent)
wsl --set-default-version 2 >nul 2>&1

echo Checking Podman machine...
for /f "delims=" %%M in ('podman machine list --format "{{.Name}}" 2^>nul') do set "PM_NAME=%%M"
if not defined PM_NAME (
    echo Initializing Podman machine...
    podman machine init --cpus 2 --memory 2048 --disk-size 20
    if %errorlevel% neq 0 (
        echo Failed to initialize Podman machine.
        pause
        exit /b 1
    )
)

echo Ensuring Podman machine is running...
podman machine list --format "{{.Running}}" | findstr /r /c:"true" >nul 2>&1
if %errorlevel% neq 0 (
    podman machine start
    if %errorlevel% neq 0 (
        echo Failed to start Podman machine.
        pause
        exit /b 1
    )
)

podman version >nul 2>&1
if %errorlevel% neq 0 (
    echo Podman verification failed.
    pause
    exit /b 1
)

echo  =================================================================
echo  ================= local environment installer ===================
echo  ====================== peviitor.ro ==============================
echo  =================================================================

rem --- Password validation function ---
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

rem --- Prompt mandatory Solr username/password ---
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

rem --- Prepare workspace ---
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

rem Remove old network if exists
podman network ls --format "{{.Name}}" | findstr /x "mynetwork" >nul 2>&1
if %errorlevel% equ 0 (
    echo Removing existing network mynetwork...
    podman network rm mynetwork >nul 2>&1
)

echo Creating network mynetwork with subnet 172.168.0.0/16...
podman network create --subnet=172.168.0.0/16 mynetwork >nul 2>&1

rem --- Download latest build.zip and extract ---
set "REPO=peviitor-ro/search-engine"
set "ASSET_NAME=build.zip"
set "TARGET_DIR=%PEVIITOR_DIR%"

echo Fetching download link for %ASSET_NAME% from GitHub repo %REPO% latest release...
for /f "usebackq delims=" %%U in (`%POWERSHELL% "(Invoke-RestMethod -Uri 'https://api.github.com/repos/%REPO%/releases/latest').assets ^| Where-Object { $_.name -eq '%ASSET_NAME%' } ^| Select-Object -ExpandProperty browser_download_url"`) do set "DOWNLOAD_URL=%%U"
if not defined DOWNLOAD_URL (
    echo ERROR: Could not find download URL for %ASSET_NAME% in the latest release.
    pause
    exit /b 1
)

echo Download URL found: %DOWNLOAD_URL%
set "TMP_FILE=%TEMP%\%ASSET_NAME%"
echo Downloading %ASSET_NAME% to temporary folder...
%POWERSHELL% "& { $ProgressPreference='SilentlyContinue'; Invoke-WebRequest -Uri '%DOWNLOAD_URL%' -OutFile '%TMP_FILE%' }"

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

rem --- Start Apache container ---
echo Starting apache-container with Podman...
podman run --name apache-container --network mynetwork --ip 172.168.0.11 --restart=always -d -p 8081:80 -v "%TARGET_DIR%\build:/var/www/html" alexstefan1702/php-apache

echo Updating swagger-ui URL inside apache-container...
podman exec apache-container sh -c "sed -i 's|url: \"http://localhost:8080/api/v0/swagger.json\"|url: \"http://localhost:8081/api/v0/swagger.json\"|g' /var/www/swagger-ui/swagger-initializer.js"
podman restart apache-container

rem --- Solr container setup ---
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

rem --- Helper to POST JSON into Solr via curl inside container ---
set "TMP_JSON=%TEMP%\solr_post.json"

rem Add fields to jobs core
%POWERSHELL% "@'
{
  "add-field": [{"name": "job_link", "type": "text_general", "stored": true, "indexed": true, "multiValued": true, "uninvertible": true}]
}
'@ | Out-File -FilePath '%TMP_JSON%' -Encoding UTF8"
podman cp "%TMP_JSON%" %CONTAINER_NAME%:/tmp/post.json
podman exec %CONTAINER_NAME% curl -s -X POST -H "Content-Type: application/json" --data-binary @/tmp/post.json "http://localhost:%SOLR_PORT%/solr/%CORE_NAME_2%/schema"

%POWERSHELL% "@'
{
  "add-field": [{"name": "job_title", "type": "text_general", "stored": true, "indexed": true, "multiValued": true, "uninvertible": true}]
}
'@ | Out-File -FilePath '%TMP_JSON%' -Encoding UTF8"
podman cp "%TMP_JSON%" %CONTAINER_NAME%:/tmp/post.json
podman exec %CONTAINER_NAME% curl -s -X POST -H "Content-Type: application/json" --data-binary @/tmp/post.json "http://localhost:%SOLR_PORT%/solr/%CORE_NAME_2%/schema"

%POWERSHELL% "@'
{
  "add-field": [{"name": "company", "type": "text_general", "stored": true, "indexed": true, "multiValued": true, "uninvertible": true}]
}
'@ | Out-File -FilePath '%TMP_JSON%' -Encoding UTF8"
podman cp "%TMP_JSON%" %CONTAINER_NAME%:/tmp/post.json
podman exec %CONTAINER_NAME% curl -s -X POST -H "Content-Type: application/json" --data-binary @/tmp/post.json "http://localhost:%SOLR_PORT%/solr/%CORE_NAME_2%/schema"

%POWERSHELL% "@'
{
  "add-field": [{"name": "company_str", "type": "string", "stored": true, "indexed": true, "multiValued": false, "uninvertible": true}]
}
'@ | Out-File -FilePath '%TMP_JSON%' -Encoding UTF8"
podman cp "%TMP_JSON%" %CONTAINER_NAME%:/tmp/post.json
podman exec %CONTAINER_NAME% curl -s -X POST -H "Content-Type: application/json" --data-binary @/tmp/post.json "http://localhost:%SOLR_PORT%/solr/%CORE_NAME_2%/schema"

%POWERSHELL% "@'
{
  "add-field": [{"name": "hiringOrganization.name", "type": "text_general", "stored": true, "indexed": true, "multiValued": true, "uninvertible": true}]
}
'@ | Out-File -FilePath '%TMP_JSON%' -Encoding UTF8"
podman cp "%TMP_JSON%" %CONTAINER_NAME%:/tmp/post.json
podman exec %CONTAINER_NAME% curl -s -X POST -H "Content-Type: application/json" --data-binary @/tmp/post.json "http://localhost:%SOLR_PORT%/solr/%CORE_NAME_2%/schema"

%POWERSHELL% "@'
{
  "add-field": [{"name": "country", "type": "text_general", "stored": true, "indexed": true, "multiValued": true, "uninvertible": true}]
}
'@ | Out-File -FilePath '%TMP_JSON%' -Encoding UTF8"
podman cp "%TMP_JSON%" %CONTAINER_NAME%:/tmp/post.json
podman exec %CONTAINER_NAME% curl -s -X POST -H "Content-Type: application/json" --data-binary @/tmp/post.json "http://localhost:%SOLR_PORT%/solr/%CORE_NAME_2%/schema"

%POWERSHELL% "@'
{
  "add-field": [{"name": "city", "type": "text_general", "stored": true, "indexed": true, "multiValued": true, "uninvertible": true}]
}
'@ | Out-File -FilePath '%TMP_JSON%' -Encoding UTF8"
podman cp "%TMP_JSON%" %CONTAINER_NAME%:/tmp/post.json
podman exec %CONTAINER_NAME% curl -s -X POST -H "Content-Type: application/json" --data-binary @/tmp/post.json "http://localhost:%SOLR_PORT%/solr/%CORE_NAME_2%/schema"

%POWERSHELL% "@'
{
  "add-field": [{"name": "county", "type": "text_general", "stored": true, "indexed": true, "multiValued": true, "uninvertible": true}]
}
'@ | Out-File -FilePath '%TMP_JSON%' -Encoding UTF8"
podman cp "%TMP_JSON%" %CONTAINER_NAME%:/tmp/post.json
podman exec %CONTAINER_NAME% curl -s -X POST -H "Content-Type: application/json" --data-binary @/tmp/post.json "http://localhost:%SOLR_PORT%/solr/%CORE_NAME_2%/schema"

rem Copy-field rules
%POWERSHELL% "@'
{ "add-copy-field": { "source": "job_link", "dest": "_text_" } }
'@ | Out-File -FilePath '%TMP_JSON%' -Encoding UTF8"
podman cp "%TMP_JSON%" %CONTAINER_NAME%:/tmp/post.json
podman exec %CONTAINER_NAME% curl -s -X POST -H "Content-Type: application/json" --data-binary @/tmp/post.json "http://localhost:%SOLR_PORT%/solr/%CORE_NAME_2%/schema"

%POWERSHELL% "@'
{ "add-copy-field": { "source": "job_title", "dest": "_text_" } }
'@ | Out-File -FilePath '%TMP_JSON%' -Encoding UTF8"
podman cp "%TMP_JSON%" %CONTAINER_NAME%:/tmp/post.json
podman exec %CONTAINER_NAME% curl -s -X POST -H "Content-Type: application/json" --data-binary @/tmp/post.json "http://localhost:%SOLR_PORT%/solr/%CORE_NAME_2%/schema"

%POWERSHELL% "@'
{ "add-copy-field": { "source": "company", "dest": ["_text_", "company_str", "hiringOrganization.name"] } }
'@ | Out-File -FilePath '%TMP_JSON%' -Encoding UTF8"
podman cp "%TMP_JSON%" %CONTAINER_NAME%:/tmp/post.json
podman exec %CONTAINER_NAME% curl -s -X POST -H "Content-Type: application/json" --data-binary @/tmp/post.json "http://localhost:%SOLR_PORT%/solr/%CORE_NAME_2%/schema"

%POWERSHELL% "@'
{ "add-copy-field": { "source": "hiringOrganization.name", "dest": "hiringOrganization.name_str" } }
'@ | Out-File -FilePath '%TMP_JSON%' -Encoding UTF8"
podman cp "%TMP_JSON%" %CONTAINER_NAME%:/tmp/post.json
podman exec %CONTAINER_NAME% curl -s -X POST -H "Content-Type: application/json" --data-binary @/tmp/post.json "http://localhost:%SOLR_PORT%/solr/%CORE_NAME_2%/schema"

%POWERSHELL% "@'
{ "add-copy-field": { "source": "country", "dest": "_text_" } }
'@ | Out-File -FilePath '%TMP_JSON%' -Encoding UTF8"
podman cp "%TMP_JSON%" %CONTAINER_NAME%:/tmp/post.json
podman exec %CONTAINER_NAME% curl -s -X POST -H "Content-Type: application/json" --data-binary @/tmp/post.json "http://localhost:%SOLR_PORT%/solr/%CORE_NAME_2%/schema"

%POWERSHELL% "@'
{ "add-copy-field": { "source": "city", "dest": "_text_" } }
'@ | Out-File -FilePath '%TMP_JSON%' -Encoding UTF8"
podman cp "%TMP_JSON%" %CONTAINER_NAME%:/tmp/post.json
podman exec %CONTAINER_NAME% curl -s -X POST -H "Content-Type: application/json" --data-binary @/tmp/post.json "http://localhost:%SOLR_PORT%/solr/%CORE_NAME_2%/schema"

rem Add url field to logo core
%POWERSHELL% "@'
{
  "add-field": [{"name": "url", "type": "text_general", "stored": true, "indexed": true, "multiValued": true, "uninvertible": true}]
}
'@ | Out-File -FilePath '%TMP_JSON%' -Encoding UTF8"
podman cp "%TMP_JSON%" %CONTAINER_NAME%:/tmp/post.json
podman exec %CONTAINER_NAME% curl -s -X POST -H "Content-Type: application/json" --data-binary @/tmp/post.json "http://localhost:%SOLR_PORT%/solr/%CORE_NAME_3%/schema"

rem Configure security.json with default solr user
set "SEC_JSON=%CD%\security.json"
%POWERSHELL% "@'
{
  "authentication": {
    "blockUnknown": true,
    "class": "solr.BasicAuthPlugin",
    "credentials": { "solr": "IV0EHq1OnNrj6gvRCwvFwTrZ1+z1oBbnQdiVC3otuq0= Ndd7LKvVBAaZIF0QAVi1ekCfAJXr1GGfLtRUXhgrF8c=" },
    "realm": "My Solr users",
    "forwardCredentials": false
  },
  "authorization": {
    "class": "solr.RuleBasedAuthorizationPlugin",
    "permissions": [ { "name": "security-edit", "role": "admin" } ],
    "user-role": { "solr": "admin" }
  }
}
'@ | Out-File -FilePath '%SEC_JSON%' -Encoding UTF8"

podman cp "%SEC_JSON%" %CONTAINER_NAME%:/var/solr/data/security.json
podman restart %CONTAINER_NAME%

rem Add suggest component and handler to jobs core
%POWERSHELL% "@'
{
  "add-searchcomponent": {
    "name": "suggest",
    "class": "solr.SuggestComponent",
    "suggester": {
      "name": "jobTitleSuggester",
      "lookupImpl": "FuzzyLookupFactory",
      "dictionaryImpl": "DocumentDictionaryFactory",
      "field": "job_title",
      "suggestAnalyzerFieldType": "text_general",
      "buildOnCommit": true,
      "buildOnStartup": false
    }
  }
}
'@ | Out-File -FilePath '%TMP_JSON%' -Encoding UTF8"
podman cp "%TMP_JSON%" %CONTAINER_NAME%:/tmp/post.json
podman exec %CONTAINER_NAME% curl -s -X POST -H "Content-Type: application/json" --data-binary @/tmp/post.json "http://localhost:%SOLR_PORT%/solr/%CORE_NAME_2%/config"

%POWERSHELL% "@'
{
  "add-requesthandler": {
    "name": "/suggest",
    "class": "solr.SearchHandler",
    "startup": "lazy",
    "defaults": {
      "suggest": true,
      "suggest.dictionary": "jobTitleSuggester",
      "suggest.count": 10
    },
    "components": ["suggest"]
  }
}
'@ | Out-File -FilePath '%TMP_JSON%' -Encoding UTF8"
podman cp "%TMP_JSON%" %CONTAINER_NAME%:/tmp/post.json
podman exec %CONTAINER_NAME% curl -s -X POST -H "Content-Type: application/json" --data-binary @/tmp/post.json "http://localhost:%SOLR_PORT%/solr/%CORE_NAME_2%/config"

podman restart %CONTAINER_NAME%

echo Solr container setup completed.

rem --- Ensure Java ---
where java >nul 2>&1
if %errorlevel% neq 0 (
    echo Java not found. Installing OpenJDK 11 via Chocolatey...
    choco install openjdk11 -y --no-progress
) else (
    echo Java is installed:
    java -version
)

rem --- Install JMeter 5.6.3 ---
set "JMETER_HOME=%USERPROFILE%\apache-jmeter-5.6.3"
if not exist "%JMETER_HOME%" (
    echo Installing JMeter 5.6.3...
    set "JMETER_URL=https://dlcdn.apache.org/jmeter/binaries/apache-jmeter-5.6.3.zip"
    set "ZIPFILE=%TEMP%\apache-jmeter-5.6.3.zip"
    %POWERSHELL% "& { $ProgressPreference='SilentlyContinue'; Invoke-WebRequest -Uri '%JMETER_URL%' -OutFile '%ZIPFILE%' }"
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
    %POWERSHELL% "& { $ProgressPreference='SilentlyContinue'; Invoke-WebRequest -Uri 'https://jmeter-plugins.org/get/' -OutFile '%PLUGIN_MGR_JAR%' }"
)
set "CMDRUNNER_JAR=%JMETER_LIB%\cmdrunner-2.3.jar"
if not exist "%CMDRUNNER_JAR%" (
    echo Downloading CmdRunner...
    %POWERSHELL% "& { $ProgressPreference='SilentlyContinue'; Invoke-WebRequest -Uri 'https://repo1.maven.org/maven2/kg/apc/cmdrunner/2.3/cmdrunner-2.3.jar' -OutFile '%CMDRUNNER_JAR%' }"
)

echo Installing JMeter Plugins Manager command-line tool...
java -cp "%PLUGIN_MGR_JAR%" org.jmeterplugins.repository.PluginManagerCMDInstaller

rem --- Mandatory new Solr user/pass to replace default ---
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

rem Set new user and role
%POWERSHELL% "@{ 'set-user' = @{ '%NEW_USER%' = '%NEW_PASS%' } } | ConvertTo-Json -Compress | Out-File -FilePath '%TMP_JSON%' -Encoding UTF8"
curl -s -u %OLD_USER%:%OLD_PASS% -X POST -H "Content-Type: application/json" --data @"%TMP_JSON%" "http://localhost:%SOLR_PORT%/solr/admin/authentication" >nul

%POWERSHELL% "@{ 'set-user-role' = @{ '%NEW_USER%' = @('admin') } } | ConvertTo-Json -Compress | Out-File -FilePath '%TMP_JSON%' -Encoding UTF8"
curl -s -u %OLD_USER%:%OLD_PASS% -X POST -H "Content-Type: application/json" --data @"%TMP_JSON%" "http://localhost:%SOLR_PORT%/solr/admin/authorization" >nul

rem --- Run JMeter migration ---
set "MIGRATION_JMX=%~dp0migration.jmx"
if exist "%JMETER_HOME%\bin\jmeter.bat" (
    call "%JMETER_HOME%\bin\jmeter.bat" -n -t "%MIGRATION_JMX%" -Duser=%NEW_USER% -Dpass=%NEW_PASS%
)

rem Delete old default solr user
%POWERSHELL% "@{ 'delete-user' = @('%OLD_USER%') } | ConvertTo-Json -Compress | Out-File -FilePath '%TMP_JSON%' -Encoding UTF8"
curl -s -u %NEW_USER%:%NEW_PASS% -X POST -H "Content-Type: application/json" --data @"%TMP_JSON%" "http://localhost:%SOLR_PORT%/solr/admin/authentication" >nul

rem --- Info and UX ---
echo.
echo =================================================================
echo ===================== IMPORTANT INFORMATION =====================
echo.
echo SOLR is running on http://localhost:%SOLR_PORT%/solr/
echo UI is running on http://localhost:8081/
echo swagger-ui is running on http://localhost:8081/swagger-ui/
echo JMeter is installed and configured.
echo Local username and password for SOLR: %NEW_USER% / [hidden]
echo.

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

rem --- Cleanup ---
del /f /q "%SEC_JSON%" "%TMP_JSON%" "%CD%\jmeter.log" 2>nul

echo Script execution completed.
pause
exit /b 0
