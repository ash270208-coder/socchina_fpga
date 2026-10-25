@echo off
REM ===========================================================================
REM run_tb.cmd -- one-shot ModelSim regression for the AWB + gamma chain
REM
REM   run it from anywhere:  tools\wb_tune\run_tb.cmd
REM
REM steps:
REM   1. gen_awb_vectors.py  -> bit-exact python twin writes vectors\*.hex
REM   2. compile the REAL  user_source/hdl_source/awb.v + divider_seq.v
REM      + gamma_lut.v   (the ones the TD project actually synthesises,
REM      NOT the stale copy under src\)
REM   3. run tb_wb_gray.v, pixel-by-pixel compare, print PASS / FAIL
REM
REM ASCII only on purpose: cmd.exe mangles UTF-8 batch files.
REM (docs: docs\WB_GRAY_TUNING.md)
REM ===========================================================================
setlocal

set "MS=E:\Modelsim\win64"
if not exist "%MS%\vlog.exe" (
    echo [ERROR] ModelSim not found at "%MS%\vlog.exe"
    echo         edit the MS variable at the top of this file
    exit /b 1
)

pushd "%~dp0..\.."
set "ROOT=%CD%"
popd
set "HDL=%ROOT%\lab_ex1_mipi_hdmi_SC500_720P+vpp\lab_ex1_mipi_hdmi+vpp\user_source\hdl_source"

cd /d "%~dp0"

echo.
echo === step 1/3 : generate vectors ===
python gen_awb_vectors.py
if errorlevel 1 goto :fail

echo.
echo === step 2/3 : compile RTL + TB ===
REM vlib cannot create nested dirs, so make the parent first
if not exist "msim" mkdir msim
if not exist "msim\work" "%MS%\vlib.exe" msim\work
"%MS%\vmap.exe" work msim\work >nul
"%MS%\vlog.exe" -quiet -work work "%HDL%\awb.v" "%HDL%\divider_seq.v" "%HDL%\gamma_lut.v" tb_wb_gray.v
if errorlevel 1 goto :fail

echo.
echo === step 3/3 : run ===
"%MS%\vsim.exe" -c -do "run -all; quit -f" work.tb_wb_gray
if errorlevel 1 goto :fail

echo.
echo DONE. Look for "*** TB PASS ***" above.
exit /b 0

:fail
echo.
echo [FAILED] see the messages above
exit /b 1
