@echo off
cd /d "F:\Claude Cowork\Code\PackTimes" || (
  echo ERROR: Could not find the PackTimes project folder. Nothing was pushed.
  pause
  exit /b 1
)
git add .
git commit -m "Update app"
git push
pause
