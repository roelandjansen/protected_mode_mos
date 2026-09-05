rem echo off
cls
REM SHIPPING.MOS CONTAINS THE ACTUAL CODE THAT IS SHIPPING.
REM VERSION 5 UPDATE 6.
path=%PATH%;c:\bin
set TMP=c:\TMP
mkdir %TMP%

set INCLUDE=..\..\..\include;..\include
set LIB=..\..\..\lib;..\libs

REM ====== The Kernel =====
cd latest
del $*.*
del *.obj

REM make -f KERNEL.MAK $$EVAL.SYS
REM ren $$EVAL.SYS $$MOS.SYS

REM this was for internal R & D use only.
make -f KERNEL.MAK $$MOS.SYS
if ERRORLEVEL 1 exit 1

rem cd ..
REM =======================

rem cd mos5src
make -f MAKEUTIL.MAK all
if ERRORLEVEL 1 exit 1
ren MOXCPTSK.COM COMMAND.COM
rem make -f MAKETERM.MAK all
ren __*.* $$*.*
ren _*.sys $*.sys
cd ..

cd import
make -f IMPORT.MAK IMPORT.EXE
if ERRORLEVEL 1 exit 1
cd ..

rem cd export
rem make -f EXPORT.MAK EXPORT.EXE
rem cd ..
