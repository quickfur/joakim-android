ldmd2 -I../../ -c ../../ndk_helper/GLContext.d
ldmd2 -I../../ -c ../../ndk_helper/JNIHelper.d
ldmd2 -I../../ -c ../../ndk_helper/gestureDetector.d
ldmd2 -I../../ -c ../../ndk_helper/perfMonitor.d
ldmd2 -I../../ -c ../../ndk_helper/shader.d
ldmd2 -I../../ -c ../../ndk_helper/tapCamera.d

ldmd2 -I../../ -Ijni/ -Jjni/ -c jni/TeapotNativeActivity.d
ldmd2 -I../../ -Jjni/ -c jni/TeapotRenderer.d
ldmd2 -I../../ -c ../../android/sensor.d

ldmd2 -I../../ -c ../../android_native_app_glue.d

mkdir libs\%APK_DIR%

%CC% -Wl,-soname,libTeapotNativeActivity.so -shared --sysroot=%NDK%\platforms\android-21\%NDK_ARCH% TeapotNativeActivity.o sensor.o TeapotRenderer.o android_native_app_glue.o GLContext.o JNIHelper.o gestureDetector.o perfMonitor.o shader.o tapCamera.o %RTDIR%\lib\libphobos2-ldc.a %RTDIR%\lib\libdruntime-ldc.a -gcc-toolchain %NDK%\toolchains\%NDK_LINKER%\prebuilt\windows-x86_64 -fuse-ld=bfd.exe -target %TRIPLE% -llog -landroid -lEGL -lGLESv2 -o libs\%APK_DIR%\libTeapotNativeActivity.so
