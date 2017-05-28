/*
 * Copyright 2013 The Android Open Source Project
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *      http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

module ndk_helper.JNIHelper;
import core.stdc.stdarg : va_end, va_list, va_start;
import core.sys.posix.pthread : pthread_mutex_destroy, pthread_mutex_init,
                      pthread_mutex_lock, pthread_mutex_t, pthread_mutex_unlock;
import GLES2.gl2, jni;
import android.asset_manager, android.log : __android_log_vprint, android_LogPriority;
import android.native_activity : ANativeActivity;
import std.conv : to;

const(char)* CLASS_NAME = "android/app/NativeActivity";

int LOGI(const(char)* fmt, ...)
{
    va_list arg_list;
    va_start(arg_list, fmt);
    int result = __android_log_vprint(android_LogPriority.ANDROID_LOG_INFO, JNIHelper.GetInstance.GetAppName, fmt, arg_list);
    va_end(arg_list);
    return result;
}

int LOGW(const(char)* fmt, ...)
{
    va_list arg_list;
    va_start(arg_list, fmt);
    int result = __android_log_vprint(android_LogPriority.ANDROID_LOG_WARN, JNIHelper.GetInstance.GetAppName, fmt, arg_list);
    va_end(arg_list);
    return result;
}

int LOGE(const(char)* fmt, ...)
{
    va_list arg_list;
    va_start(arg_list, fmt);
    int result = __android_log_vprint(android_LogPriority.ANDROID_LOG_ERROR, JNIHelper.GetInstance.GetAppName, fmt, arg_list);
    va_end(arg_list);
    return result;
}

/******************************************************************
 * Helper functions for JNI calls
 * This class wraps JNI calls and provides handy interface calling commonly used features
 * in Java SDK.
 * Such as
 * - loading graphics files (e.g. PNG, JPG)
 * - character code conversion
 * - retrieving system properties which only supported in Java SDK
 *
 * NOTE: To use this class, add NDKHelper.java as a corresponding helper in Java code
 */
class JNIHelper
{
private:
    string app_name_;

    ANativeActivity* activity_;
    jobject jni_helper_java_ref_;
    jclass jni_helper_java_class_;

    //mutex for synchronization
    //This class uses singleton pattern and can be invoked from multiple threads,
    //each method locks the mutex for thread safety
    pthread_mutex_t mutex_;

//---------------------------------------------------------------------------
//Misc implementations
//---------------------------------------------------------------------------
    jstring GetExternalFilesDirJString( JNIEnv* env )
    {
        if( activity_ == null )
        {
            LOGI( "JNIHelper has not been initialized. Call init() to initialize the helper" );
            return null;
        }

        // Invoking getExternalFilesDir() java API
        jclass cls_Env = (*env).FindClass( env, CLASS_NAME );
        jmethodID mid = (*env).GetMethodID( env, cls_Env, "getExternalFilesDir",
                "(Ljava/lang/String;)Ljava/io/File;" );
        jobject obj_File = (*env).CallObjectMethod( env, activity_.clazz, mid, null );
        jclass cls_File = (*env).FindClass( env, "java/io/File" );
        jmethodID mid_getPath = (*env).GetMethodID( env, cls_File, "getPath", "()Ljava/lang/String;" );
        jstring obj_Path = cast(jstring) (*env).CallObjectMethod( env, obj_File, mid_getPath );

        return obj_Path;
    }

    jclass RetrieveClass( JNIEnv* jni, const(char)* class_name )
    {
        jclass activity_class = (*jni).FindClass( jni, CLASS_NAME );
        jmethodID get_class_loader = (*jni).GetMethodID( jni, activity_class,
                                "getClassLoader", "()Ljava/lang/ClassLoader;" );
        jobject cls = (*jni).CallObjectMethod( jni, activity_.clazz, get_class_loader );
        jclass class_loader = (*jni).FindClass( jni, "java/lang/ClassLoader" );
        jmethodID find_class = (*jni).GetMethodID( jni, class_loader, "loadClass",
                "(Ljava/lang/String;)Ljava/lang/Class;" );

        jstring str_class_name = (*jni).NewStringUTF( jni, class_name );
        jclass class_retrieved = cast(jclass) (*jni).CallObjectMethod( jni, cls, find_class, str_class_name );
        (*jni).DeleteLocalRef( jni, str_class_name );
        return class_retrieved;
    }

    this()
    {
        pthread_mutex_init( &mutex_, null );
    }

    ~this()
    {
        pthread_mutex_lock( &mutex_ );

        JNIEnv *env;
        (*activity_.vm).AttachCurrentThread( activity_.vm, &env, null );

        (*env).DeleteGlobalRef( env, jni_helper_java_ref_ );
        (*env).DeleteGlobalRef( env, jni_helper_java_class_ );

        (*activity_.vm).DetachCurrentThread(activity_.vm);

        pthread_mutex_destroy( &mutex_ );
    }

public:
    /*
     * To load your own Java classes, JNIHelper requires to be initialized with a ANativeActivity handle.
     * This methods need to be called before any call to the helper class.
     * Static member of the class
     *
     * arguments:
     * in: activity, pointer to ANativeActivity. Used internally to set up JNI environment
     * in: helper_class_name, pointer to Java side helper class name. (e.g. "com/sample/helper/NDKHelper" in samples )
     */
    static void Init( ANativeActivity* activity, const(char)* helper_class_name )
    {
        JNIHelper helper = GetInstance();
        pthread_mutex_lock( &helper.mutex_ );

        helper.activity_ = activity;

        JNIEnv *env;
        (*helper.activity_.vm).AttachCurrentThread( helper.activity_.vm, &env, null );

        //Retrieve app name
        jclass android_content_Context = (*env).GetObjectClass( env, helper.activity_.clazz );
        jmethodID midGetPackageName = (*env).GetMethodID( env, android_content_Context, "getPackageName",
                "()Ljava/lang/String;" );

        jstring packageName = cast(jstring) (*env).CallObjectMethod( env, helper.activity_.clazz,
                midGetPackageName );
        const(char)* appname = (*env).GetStringUTFChars( env, packageName, null );
        helper.app_name_ = to!string( appname );

        jclass cls = helper.RetrieveClass( env, helper_class_name );
        helper.jni_helper_java_class_ = cast(jclass) (*env).NewGlobalRef( env, cls );

        jmethodID constructor = (*env).GetMethodID( env, helper.jni_helper_java_class_, "<init>", "()V" );
        helper.jni_helper_java_ref_ = (*env).NewObject( env, helper.jni_helper_java_class_, constructor );
        helper.jni_helper_java_ref_ = (*env).NewGlobalRef( env, helper.jni_helper_java_ref_ );

        (*env).ReleaseStringUTFChars( env, packageName, appname );
        (*helper.activity_.vm).DetachCurrentThread(helper.activity_.vm);

        pthread_mutex_unlock( &helper.mutex_ );
    }

    /*
     * Retrieve the singleton object of the helper.
     * Static member of the class

     * Methods in the class are designed as thread safe.
     */
    static JNIHelper GetInstance()
    {
        import std.concurrency : initOnce;
        __gshared static JNIHelper helper;
        return initOnce!helper(new JNIHelper);
    }

    /*
     * Read a file from storage.
     * First, the method tries to read the file from an external storage.
     * If it fails to read, it falls back to use assset manager and try to read the file from APK asset.
     *
     * arguments:
     * in: fileName, file name to read
     * out: buffer_ref, pointer to a vector buffer to read a file.
     *      when the call succeeded, the buffer includes contents of specified file
     *      when the call failed, contents of the buffer remains same
     * return:
     * true when file read succeeded
     * false when it failed to read the file
     */
    bool ReadFile( const(char)* fileName, ubyte[]* buffer_ref )
    {
        import std.stdio : File;

        if( activity_ == null )
        {
            LOGI( "JNIHelper has not been initialized.Call init() to initialize the helper" );
            return false;
        }

        //First, try reading from externalFileDir;
        JNIEnv *env;
        jmethodID mid;

        pthread_mutex_lock( &mutex_ );
        (*activity_.vm).AttachCurrentThread( activity_.vm, &env, null );

        jstring str_path = GetExternalFilesDirJString( env );
        const(char)* path = (*env).GetStringUTFChars( env, str_path, null );
        string s = to!string( path );

        if( fileName[0] != '/' )
        {
            s ~= "/";
        }
        s ~= to!string(fileName);
        File f;// = File( s, "b" ); This doesn't actually work for assets,
               // because they're not stored as files
        (*env).ReleaseStringUTFChars( env, str_path, path );
        (*env).DeleteLocalRef( env, str_path );
        (*activity_.vm).DetachCurrentThread(activity_.vm);

        if( f.isOpen )
        {
            LOGI( "reading:%s", s );
            buffer_ref.length = cast(uint) f.size;
            f.rawRead(*buffer_ref);
            f.close();
            pthread_mutex_unlock( &mutex_ );
            return true;
        }
        else
        {
            //Fallback to assetManager
            AAssetManager* assetManager = activity_.assetManager;
            AAsset* assetFile = AAssetManager_open( assetManager, fileName, AASSET_MODE_BUFFER );
            if( !assetFile )
            {
                pthread_mutex_unlock( &mutex_ );
                return false;
            }
            ubyte* data = cast(ubyte*) AAsset_getBuffer( assetFile );
            int size = AAsset_getLength( assetFile );
            if( data == null )
            {
                AAsset_close( assetFile );

                LOGI( "Failed to load:%s", fileName );
                pthread_mutex_unlock( &mutex_ );
                return false;
            }

            *buffer_ref = data[0 .. size];

            AAsset_close( assetFile );
            pthread_mutex_unlock( &mutex_ );
            return true;
        }
    }

    /*
     * Load and create OpenGL texture from given file name.
     * The method invokes BitmapFactory in Java so it can read jpeg/png formatted files
     *
     * The methods creates mip-map and set texture parameters like this,
     * glTexParameterf( GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR_MIPMAP_NEAREST );
     * glTexParameterf( GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR );
     * glGenerateMipmap( GL_TEXTURE_2D );
     *
     * arguments:
     * in: file_name, file name to read, PNG&JPG is supported
     * return:
     * OpenGL texture name when the call succeeded
     * When it failed to load the texture, it returns -1
     */
    uint LoadTexture( const(char)* file_name )
    {
        if( activity_ == null )
        {
            LOGI( "JNIHelper has not been initialized. Call init() to initialize the helper" );
            return 0;
        }

        JNIEnv *env;
        jmethodID mid;

        pthread_mutex_lock( &mutex_ );
        (*activity_.vm).AttachCurrentThread( activity_.vm, &env, null );

        jstring name = (*env).NewStringUTF( env, file_name );

        GLuint tex;
        glGenTextures( 1, &tex );
        glBindTexture( GL_TEXTURE_2D, tex );

        glTexParameterf( GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR_MIPMAP_NEAREST );
        glTexParameterf( GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR );

        mid = (*env).GetMethodID( env, jni_helper_java_class_, "loadTexture", "(Ljava/lang/String;)Z" );
        jboolean ret = (*env).CallBooleanMethod( env, jni_helper_java_ref_, mid, name );
        if( !ret )
        {
            glDeleteTextures( 1, &tex );
            tex = -1;
            LOGI( "Texture load failed %s", file_name );
        }

        //Generate mipmap
        glGenerateMipmap( GL_TEXTURE_2D );

        (*env).DeleteLocalRef( env, name );
        (*activity_.vm).DetachCurrentThread(activity_.vm);
        pthread_mutex_unlock( &mutex_ );

        return tex;
    }

    /*
     * Convert string from character code other than UTF-8
     *
     * arguments:
     *  in: str, pointer to a string which is encoded other than UTF-8
     *  in: encoding, pointer to a character encoding string.
     *  The encoding string can be any valid java.nio.charset.Charset name
     *  e.g. "UTF-16", "Shift_JIS"
     * return: converted input string as an UTF-8 string
     */
    string ConvertString( const(char)* str, const(char)* encode )
    {
        import core.stdc.string : strlen;

        if( activity_ == null )
        {
            LOGI( "JNIHelper has not been initialized. Call init() to initialize the helper" );
            return "";
        }

        JNIEnv *env;

        pthread_mutex_lock( &mutex_ );
        (*activity_.vm).AttachCurrentThread( activity_.vm, &env, null );

        int iLength = strlen( str );

        jbyteArray array = (*env).NewByteArray( env, iLength );
        (*env).SetByteArrayRegion( env, array, 0, iLength, cast(const(jbyte)*) str );

        jstring strEncode = (*env).NewStringUTF( env, encode );

        jclass cls = (*env).FindClass( env, "java/lang/String" );
        jmethodID ctor = (*env).GetMethodID( env, cls, "<init>", "([BLjava/lang/String;)V" );
        jstring object = cast(jstring) (*env).NewObject( env, cls, ctor, array, strEncode );

        const(char)*cparam = (*env).GetStringUTFChars( env, object, null );

        string s = to!string( cparam );

        (*env).ReleaseStringUTFChars( env, object, cparam );
        (*env).DeleteLocalRef( env, strEncode );
        (*env).DeleteLocalRef( env, object );
        (*activity_.vm).DetachCurrentThread(activity_.vm);
        pthread_mutex_unlock( &mutex_ );

        return s;
    }

    /*
     * Retrieve external file directory through JNI call
     *
     * return: string containing external file diretory
     */
    string GetExternalFilesDir()
    {
        if( activity_ == null )
        {
            LOGI( "JNIHelper has not been initialized. Call init() to initialize the helper" );
            return "";
        }

        pthread_mutex_lock( &mutex_ );

        //First, try reading from externalFileDir;
        JNIEnv *env;
        jmethodID mid;

        (*activity_.vm).AttachCurrentThread( activity_.vm, &env, null );

        jstring strPath = GetExternalFilesDirJString( env );
        const(char)* path = (*env).GetStringUTFChars( env, strPath, null );
        string s = to!string( path );

        (*env).ReleaseStringUTFChars( env, strPath, path );
        (*env).DeleteLocalRef( env, strPath );
        (*activity_.vm).DetachCurrentThread(activity_.vm);

        pthread_mutex_unlock( &mutex_ );
        return s;
    }

    /*
     * Audio helper
     * Retrieves native audio buffer size which is required to achieve low latency audio
     *
     * return: Native audio buffer size which is a hint to achieve low latency audio
     * If the API is not supported (API level < 17), it returns 0
     */
    int GetNativeAudioBufferSize()
    {
        if( activity_ == null )
        {
            LOGI( "JNIHelper has not been initialized. Call init() to initialize the helper" );
            return 0;
        }

        JNIEnv *env;
        jmethodID mid;

        pthread_mutex_lock( &mutex_ );
        (*activity_.vm).AttachCurrentThread( activity_.vm, &env, null );

        mid = (*env).GetMethodID( env, jni_helper_java_class_, "getNativeAudioBufferSize", "()I" );
        int i = (*env).CallIntMethod( env, jni_helper_java_ref_, mid );
        (*activity_.vm).DetachCurrentThread(activity_.vm);
        pthread_mutex_unlock( &mutex_ );

        return i;
    }

    /*
     * Audio helper
     * Retrieves native audio sample rate which is required to achieve low latency audio
     *
     * return: Native audio sample rate which is a hint to achieve low latency audio
     */
    int GetNativeAudioSampleRate()
    {
        if( activity_ == null )
        {
            LOGI( "JNIHelper has not been initialized. Call init() to initialize the helper" );
            return 0;
        }

        JNIEnv *env;
        jmethodID mid;

        pthread_mutex_lock( &mutex_ );
        (*activity_.vm).AttachCurrentThread( activity_.vm, &env, null );

        mid = (*env).GetMethodID( env, jni_helper_java_class_, "getNativeAudioSampleRate", "()I" );
        int i = (*env).CallIntMethod( env, jni_helper_java_ref_, mid );
        (*activity_.vm).DetachCurrentThread(activity_.vm);
        pthread_mutex_unlock( &mutex_ );

        return i;
    }

    /*
     * Retrieves application bundle name
     *
     * return: pointer to an app name string
     *
     */
    const(char)* GetAppName()
    {
        return app_name_.ptr;
    }
}
