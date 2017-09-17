ldc2 -mtriple=armv7-none-linux-android -I../../ -c ../../ndk_helper/GLContext.d
ldc2 -mtriple=armv7-none-linux-android -I../../ -c ../../ndk_helper/JNIHelper.d
ldc2 -mtriple=armv7-none-linux-android -I../../ -c ../../ndk_helper/gestureDetector.d
ldc2 -mtriple=armv7-none-linux-android -I../../ -c ../../ndk_helper/perfMonitor.d
ldc2 -mtriple=armv7-none-linux-android -I../../ -c ../../ndk_helper/shader.d
ldc2 -mtriple=armv7-none-linux-android -I../../ -c ../../ndk_helper/tapCamera.d

ldc2 -mtriple=armv7-none-linux-android -I../../ -Ijni/ -Jjni/ -c jni/TeapotNativeActivity.d
ldc2 -mtriple=armv7-none-linux-android -I../../ -Jjni/ -c jni/TeapotRenderer.d
ldc2 -mtriple=armv7-none-linux-android -I../../ -c ../../android/sensor.d

ldc2 -mtriple=armv7-none-linux-android -I../../ -c ../../android_native_app_glue.d

%CC% -Wl,-soname,libTeapotNativeActivity.so -shared --sysroot=%NDK%\platforms\android-21\arch-arm TeapotNativeActivity.o sensor.o TeapotRenderer.o android_native_app_glue.o GLContext.o JNIHelper.o gestureDetector.o perfMonitor.o shader.o tapCamera.o %RTDIR%\lib\libphobos2-ldc.a %RTDIR%\lib\libdruntime-ldc.a -gcc-toolchain %NDK%\toolchains\arm-linux-androideabi-4.9\prebuilt\windows-x86_64 -fuse-ld=bfd.exe -target armv7-none-linux-androideabi -llog -landroid -lEGL -lGLESv2 -o libTeapotNativeActivity.so
