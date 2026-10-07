@echo off
setlocal
call "%~dp0..\tools\vsdevcmd.cmd" x86
if errorlevel 1 exit /b %errorlevel%
set "INPUT_ROOT=%~dp0..\third_party\DeadSpace2008CompleteInputFix"
set "TEST_BUILD=%TEMP%\ds1k-input-tests"
if not exist "%TEST_BUILD%" mkdir "%TEST_BUILD%"
pushd "%TEST_BUILD%"
cl.exe /nologo /MT /O2 /EHsc /std:c++17 /W4 /Fe:controller-tests.exe ^
  "%INPUT_ROOT%\tests\controller_transform_tests.cpp" ^
  "%INPUT_ROOT%\src\payload\controller_transform.cpp"
if errorlevel 1 goto failed
controller-tests.exe
if errorlevel 1 goto failed
cl.exe /nologo /MT /O2 /EHsc /std:c++17 /W4 /Fe:mouse-tests.exe ^
  "%INPUT_ROOT%\tests\mouse_transform_tests.cpp" ^
  "%INPUT_ROOT%\src\payload\mouse_transform.cpp"
if errorlevel 1 goto failed
mouse-tests.exe
if errorlevel 1 goto failed
popd
exit /b 0
:failed
popd
exit /b 1
