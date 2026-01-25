@echo off
echo Deploying all contracts locally...
make deploy-all-local
if %errorlevel% neq 0 (
    echo Deployment failed with error code %errorlevel%
    pause
    exit /b %errorlevel%
)

echo.
echo Deployment successful! Now resetting database...
cd /d E:\zuno-marketplace-abis
pnpm db:reset
if %errorlevel% neq 0 (
    echo Database reset failed with error code %errorlevel%
    pause
    exit /b %errorlevel%
)

echo.
echo All done!
pause
