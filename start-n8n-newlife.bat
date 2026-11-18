@echo off
setlocal EnableExtensions
title NewLife - start n8n with the ngrok address

rem ===== your public address (ngrok) =====
set "WEBHOOK_URL=https://venue-lubricant-cruelly.ngrok-free.dev/"
rem =======================================

echo.
echo  NewLife: restarting n8n in Docker with
echo  WEBHOOK_URL=%WEBHOOK_URL%
echo.

docker info >nul 2>&1
if errorlevel 1 (
  echo  Docker Desktop is not running. Open Docker Desktop, wait until it says "Engine running", then run this file again.
  goto :end
)

rem ---- find the current n8n container: the one named "n8n", otherwise the first container whose image is n8n ----
set "OLD="
for /f "delims=" %%c in ('docker ps -a --filter "name=^/?n8n$" --format "{{.Names}}"') do set "OLD=%%c"
if not defined OLD (
  for /f "tokens=1" %%c in ('docker ps -a --format "{{.Names}} {{.Image}}" ^| findstr /i "n8n" ^| findstr /v /i /b "n8n-backup-"') do if not defined OLD set "OLD=%%c"
)
if not defined OLD (
  echo  No n8n container was found. Nothing was changed. Send a screenshot of Docker Desktop's Containers list to Claude.
  goto :end
)
echo  Found your n8n container: %OLD%

for /f "delims=" %%i in ('docker inspect -f "{{.Config.Image}}" %OLD%') do set "IMG=%%i"
for /f "delims=" %%m in ('docker inspect -f "{{len .Mounts}}" %OLD%') do set "MOUNTS=%%m"
set "NET=bridge"
for /f "tokens=1" %%n in ('docker inspect -f "{{range $k, $v := .NetworkSettings.Networks}}{{$k}} {{end}}" %OLD%') do set "NET=%%n"
set "BACKUP=n8n-backup-%RANDOM%"

rem ---- keep every old setting except the wrong address ----
docker inspect -f "{{range .Config.Env}}{{println .}}{{end}}" %OLD% > "%TEMP%\n8n-old.env"
findstr /v /i /b /c:"WEBHOOK_URL=" "%TEMP%\n8n-old.env" | findstr /v /i /c:"your-domain" > "%TEMP%\n8n-keep.env"

echo  Stopping it and keeping it as a backup named %BACKUP% (nothing is deleted)...
docker update --restart=no %OLD% >nul
docker stop %OLD% >nul
docker rename %OLD% %BACKUP%
if errorlevel 1 (
  echo  Could not rename the old container. Nothing else was changed.
  goto :end
)

if "%MOUNTS%"=="0" (
  rem the workflows live inside the old container itself: copy it into an image so the new one has them
  echo  Your data is stored inside the container; copying it into the new one...
  docker commit %BACKUP% n8n-newlife-data >nul
  set "IMG=n8n-newlife-data"
  set "DATA="
) else (
  set "DATA=--volumes-from %BACKUP%"
)

echo  Starting the new n8n container...
docker run -d --name n8n --restart unless-stopped --network %NET% -p 5678:5678 %DATA% --env-file "%TEMP%\n8n-keep.env" -e WEBHOOK_URL=%WEBHOOK_URL% -e GENERIC_TIMEZONE=Asia/Tehran -e TZ=Asia/Tehran %IMG% >nul
if errorlevel 1 (
  echo.
  echo  The new container did not start. Putting your old one back...
  docker rename %BACKUP% %OLD%
  docker start %OLD% >nul
  echo  Your old n8n is running again. Send this window's text to Claude.
  goto :end
)

rem ---- start ngrok too, if it is installed and not already running ----
tasklist /fi "imagename eq ngrok.exe" | find /i "ngrok.exe" >nul
if errorlevel 1 (
  where ngrok >nul 2>&1
  if not errorlevel 1 (
    echo  Starting ngrok in its own window - keep that window open.
    start "ngrok - keep open" ngrok http 5678
  ) else (
    echo  Start ngrok yourself in another window:  ngrok http 5678
  )
) else (
  echo  ngrok is already running.
)

echo  Waiting for n8n to start...
timeout /t 20 /nobreak >nul
set "UP="
for /f "delims=" %%r in ('docker ps -q --filter "name=^/?n8n$" --filter "status=running"') do set "UP=%%r"
if not defined UP (
  echo.
  echo  The new n8n stopped by itself. Its last lines:
  docker logs --tail 15 n8n
  echo  Putting your old n8n back...
  docker rm n8n >nul
  docker rename %BACKUP% %OLD%
  docker start %OLD% >nul
  echo  Your old n8n is running again. Send this window's text to Claude.
  goto :end
)
echo.
echo  ---- last lines from n8n ----
docker logs --tail 8 n8n
echo  -----------------------------
echo.
echo  Done. Now:
echo   1. Open http://localhost:5678 and turn the NewLife workflow OFF and ON.
echo   2. Send /start to the bot from @AvidMechanic.
echo   3. Your page: %WEBHOOK_URL%webhook/newlife
echo.
echo  Your old container is kept, stopped, as %BACKUP%. Once everything works you can delete it in Docker Desktop.

:end
echo.
pause
