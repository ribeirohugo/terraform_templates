@echo off
setlocal enabledelayedexpansion

REM Runs terraform fmt + tflint --fix against every terraform_template directory.

where terraform >nul 2>nul
if errorlevel 1 (
  echo tflint-fix: terraform not found in PATH
  exit /b 1
)

where tflint >nul 2>nul
if errorlevel 1 (
  echo tflint-fix: tflint not found in PATH
  exit /b 1
)

set dirs=web_application_gcp_sa_key\terraform_template web_application_gcp_sa_key_bootstrap\terraform_template web_application_wif\terraform_template web_application_wif_bootstrap\terraform_template
set status=0

for %%d in (%dirs%) do (
  echo ==^> Fixing %%d

  terraform fmt -recursive "%%d"
  if errorlevel 1 set status=1

  pushd "%%d"
  tflint --init >nul 2>nul
  tflint --recursive --fix
  if errorlevel 1 set status=1
  popd
)

exit /b %status%
