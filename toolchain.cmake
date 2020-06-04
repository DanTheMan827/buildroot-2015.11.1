set(CMAKE_SYSTEM_NAME Linux)
set(CMAKE_SYSTEM_PROCESSOR armv7)

set(CMAKE_SYSROOT /buildroot-2015.11.1/output/host/usr/arm-buildroot-linux-gnueabihf/sysroot)
#set(CMAKE_STAGING_PREFIX /home/devel/stage)

set(tools /buildroot-2015.11.1/output/host/usr)
set(CMAKE_C_COMPILER ${tools}/bin/arm-buildroot-linux-gnueabihf-gcc)
set(CMAKE_CXX_COMPILER ${tools}/bin/arm-buildroot-linux-gnueabihf-g++)
set(CMAKE_AR ${tools}/bin/arm-buildroot-linux-gnueabihf-gcc-ar CACHE PATH "" FORCE)
set(CMAKE_RANLIB ${tools}/bin/arm-buildroot-linux-gnueabihf-gcc-ranlib CACHE PATH "" FORCE)

set(CMAKE_FIND_ROOT_PATH_MODE_PROGRAM NEVER)
set(CMAKE_FIND_ROOT_PATH_MODE_LIBRARY ONLY)
set(CMAKE_FIND_ROOT_PATH_MODE_INCLUDE ONLY)
set(CMAKE_FIND_ROOT_PATH_MODE_PACKAGE ONLY)

set(CMAKE_INSTALL_PREFIX /usr)
