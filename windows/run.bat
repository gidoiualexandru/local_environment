@echo off
setlocal
rem Check Git installation
where git>nul 2>&1
IF ERRORLEVEL 1 (echo Git not installed. Install Git and re-run this script. pause exit /b 1)
rem Create directory
if not exist "C:\peviitor" (mkdir C:\peviitor)

rem Check if Docker is installed
where docker >nul 2>&1
IF ERRORLEVEL 1 (
    echo Docker not installed. Install Docker and re-run this script.
    pause
    exit /b 1
)

rem Check if Docker is running
docker info >nul 2>&1
IF ERRORLEVEL 1 (
    echo Docker is installed but not running. Starting Docker Desktop...
    start "" "C:\Program Files\Docker\Docker\Docker Desktop.exe"
)

rem Stop and remove existing docker containers 
docker ps -a --format "{{.Names}}" | findstr /C:"apache-container">nul 2>&1 && (docker stop apache-container && docker rm apache-container)
docker ps -a --format "{{.Names}}" | findstr /C:"solr-container">nul 2>&1 && (docker stop solr-container && docker rm solr-container)
docker ps -a --format "{{.Names}}" | findstr /C:"data-migration">nul 2>&1 && (docker stop data-migration && docker rm data-migration)
docker ps -a --format "{{.Names}}" | findstr /C:"swagger-ui">nul 2>&1 && (docker stop swagger-ui && docker rm swagger-ui)

rem Create Docker Network if not existing 
docker network ls --format "{{.Name}}" | findstr /C:"mynetwork">nul 2>&1 || (docker network create --subnet=172.18.0.0/16 mynetwork) 

docker run --name deploy_fe --network mynetwork --ip 172.18.0.13 --rm -v C:/peviitor:/app/build sebiboga/fe:latest npm run build:local
del /F /Q "c:\peviitor\.htaccess"


rem Clone repositories from GitHub
PowerShell -Command "git clone 'https://github.com/peviitor-ro/solr.git' 'C:\peviitor\solr'"
PowerShell -Command "git clone 'https://github.com/peviitor-ro/api.git' 'C:\peviitor\api'"

rem Running docker containers
docker run --name apache-container --network mynetwork --ip 172.18.0.11 -d -p 8080:80 -v C:/peviitor:/var/www/html sebiboga/php-apache:latest
timeout /T 10
docker run --name solr-container --network mynetwork --ip 172.18.0.10 -d -p 8983:8983 -v "C:\peviitor\solr\core\data:/var/solr/data" solr:latest
:loop
echo Waiting for solr container to be ready...
docker exec solr-container nc -w 5 -z localhost 8983>nul 2>&1
IF ERRORLEVEL 1 (echo Solr server not ready, waiting for 30 seconds before retry... TIMEOUT /T 30 GOTO loop)
rem Run data-migration and removing Docker Image
docker run --name solr-curl-container --network mynetwork --ip 172.18.0.14 --rm alexstefan1702/solr-curl-update
docker rmi alexstefan1702/solr-curl-update 

rem Starting Google Chrome with specific urls
start "" "C:\Program Files\Google\Chrome\Application\chrome.exe" "http://localhost:8080/api/v0/random"
start "" "C:\Program Files\Google\Chrome\Application\chrome.exe" "http://localhost:8983/solr/#/jobs/query"
start "" "C:\Program Files\Google\Chrome\Application\chrome.exe" "http://localhost:8080/swagger-ui"
start "" "C:\Program Files\Google\Chrome\Application\chrome.exe" "http://localhost:8080/"
ENDLOCAL
echo The execution of this script is now completed.
pause
