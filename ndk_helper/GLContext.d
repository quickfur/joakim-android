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

module ndk_helper.GLContext;
import EGL.egl, EGL.eglplatform : EGLint;
import GLES2.gl2 : glGetString, GL_EXTENSIONS;
import android.native_window : ANativeWindow, ANativeWindow_setBuffersGeometry;
import ndk_helper.JNIHelper : LOGW, LOGI;

/******************************************************************
 * OpenGL context handler
 * The struct handles OpenGL and EGL context based on Android activity life cycle
 * The caller needs to call corresponding methods for each activity life cycle events as it's done in sample codes.
 *
 * Also the struct initializes OpenGL ES3 when the compatible driver is installed in the device.
 * getGLVersion() returns 3.0~ when the device supports OpenGLES3.0
 *
 * Thread safety: OpenGL context is expecting used within dedicated single thread,
 * thus GLContext struct is not designed as a thread-safe
 */
struct GLContext
{
private:
    //EGL configurations
    ANativeWindow* window_;
    EGLDisplay display_ = EGL_NO_DISPLAY;
    EGLSurface surface_ = EGL_NO_SURFACE;
    EGLContext context_ = EGL_NO_CONTEXT;
    EGLConfig config_;

    //Screen parameters
    int screen_width_;
    int screen_height_;
    int color_size_;
    int depth_size_;

    //Flags
    bool gles_initialized_;
    bool egl_context_initialized_;
    bool es3_supported_;
    float gl_version_;
    bool context_valid_;

    void InitGLES()
    {
        if( gles_initialized_ )
            return;
        /* maybe port later
        //Initialize OpenGL ES 3 if available
        //
        const char* versionStr = (const char*) glGetString( GL_VERSION );
        if( strstr( versionStr, "OpenGL ES 3." ) && gl3stubInit() )
        {
            es3_supported_ = true;
            gl_version_ = 3.0f;
        }
        else*/
        {
            gl_version_ = 2.0f;
        }

        gles_initialized_ = true;
    }

    void Terminate()
    {
        if( display_ != EGL_NO_DISPLAY )
        {
            eglMakeCurrent( display_, EGL_NO_SURFACE, EGL_NO_SURFACE, EGL_NO_CONTEXT );
            if( context_ != EGL_NO_CONTEXT )
            {
                eglDestroyContext( display_, context_ );
            }

            if( surface_ != EGL_NO_SURFACE )
            {
                eglDestroySurface( display_, surface_ );
            }
            eglTerminate( display_ );
        }

        display_ = EGL_NO_DISPLAY;
        context_ = EGL_NO_CONTEXT;
        surface_ = EGL_NO_SURFACE;
        context_valid_ = false;
    }

    bool InitEGLSurface()
    {
        display_ = eglGetDisplay( EGL_DEFAULT_DISPLAY );
        eglInitialize( display_, null, null );

        /*
         * Here specify the attributes of the desired configuration.
         * Below, we select an EGLConfig with at least 8 bits per color
         * component compatible with on-screen windows
         */
        const EGLint[] attribs = [ EGL_RENDERABLE_TYPE,
                EGL_OPENGL_ES2_BIT, //Request opengl ES2.0
                EGL_SURFACE_TYPE, EGL_WINDOW_BIT, EGL_BLUE_SIZE, 8, EGL_GREEN_SIZE, 8,
                EGL_RED_SIZE, 8, EGL_DEPTH_SIZE, 24, EGL_NONE ];
        color_size_ = 8;
        depth_size_ = 24;

        EGLint num_configs;
        eglChooseConfig( display_, attribs.ptr, &config_, 1, &num_configs );

        if( !num_configs )
        {
            //Fall back to 16bit depth buffer
            const EGLint[] double_attribs = [ EGL_RENDERABLE_TYPE,
                    EGL_OPENGL_ES2_BIT, //Request opengl ES2.0
                    EGL_SURFACE_TYPE, EGL_WINDOW_BIT, EGL_BLUE_SIZE, 8, EGL_GREEN_SIZE, 8,
                    EGL_RED_SIZE, 8, EGL_DEPTH_SIZE, 16, EGL_NONE ];
            eglChooseConfig( display_, double_attribs.ptr, &config_, 1, &num_configs );
            depth_size_ = 16;
        }

        if( !num_configs )
        {
            LOGW( "Unable to retrieve EGL config" );
            return false;
        }

        surface_ = eglCreateWindowSurface( display_, config_, window_, null );
        eglQuerySurface( display_, surface_, EGL_WIDTH, &screen_width_ );
        eglQuerySurface( display_, surface_, EGL_HEIGHT, &screen_height_ );

        /* EGL_NATIVE_VISUAL_ID is an attribute of the EGLConfig that is
         * guaranteed to be accepted by ANativeWindow_setBuffersGeometry().
         * As soon as we picked a EGLConfig, we can safely reconfigure the
         * ANativeWindow buffers to match, using EGL_NATIVE_VISUAL_ID. */
        EGLint format;
        eglGetConfigAttrib( display_, config_, EGL_NATIVE_VISUAL_ID, &format );
        ANativeWindow_setBuffersGeometry( window_, 0, 0, format );

        return true;
    }

    bool InitEGLContext()
    {
        const EGLint[] context_attribs = [ EGL_CONTEXT_CLIENT_VERSION, 2, //Request opengl ES2.0
                EGL_NONE ];
        context_ = eglCreateContext( display_, config_, null, context_attribs.ptr );

        if( eglMakeCurrent( display_, surface_, surface_, context_ ) == EGL_FALSE )
        {
            LOGW( "Unable to eglMakeCurrent" );
            return false;
        }

        context_valid_ = true;
        return true;
    }

    ~this()
    {
        Terminate();
    }
public:
    static GLContext* GetInstance()
    {
        //Singleton
        static GLContext instance;

        return &instance;
    }

    bool Init( ANativeWindow* window )
    {
        if( egl_context_initialized_ )
            return true;

        //
        //Initialize EGL
        //
        window_ = window;
        InitEGLSurface();
        InitEGLContext();
        InitGLES();

        egl_context_initialized_ = true;

        return true;
    }

    EGLint Swap()
    {
        auto b = eglSwapBuffers( display_, surface_ );
        if( !b )
        {
            EGLint err = eglGetError();
            if( err == EGL_BAD_SURFACE )
            {
                //Recreate surface
                InitEGLSurface();
                return EGL_SUCCESS; //Still consider glContext is valid
            }
            else if( err == EGL_CONTEXT_LOST || err == EGL_BAD_CONTEXT )
            {
                //Context has been lost!!
                context_valid_ = false;
                Terminate();
                InitEGLContext();
            }
            return err;
        }
        return EGL_SUCCESS;
    }

    bool Invalidate()
    {
        Terminate();

        egl_context_initialized_ = false;
        return true;
    }

    void Suspend()
    {
        if( surface_ != EGL_NO_SURFACE )
        {
            eglDestroySurface( display_, surface_ );
            surface_ = EGL_NO_SURFACE;
        }
    }

    EGLint Resume( ANativeWindow* window )
    {
        if( egl_context_initialized_ == false )
        {
            Init( window );
            return EGL_SUCCESS;
        }

        int original_width = screen_width_;
        int original_height = screen_height_;

        //Create surface
        window_ = window;
        surface_ = eglCreateWindowSurface( display_, config_, window_, null );
        eglQuerySurface( display_, surface_, EGL_WIDTH, &screen_width_ );
        eglQuerySurface( display_, surface_, EGL_HEIGHT, &screen_height_ );

        if( screen_width_ != original_width || screen_height_ != original_height )
        {
            //Screen resized
            LOGI( "Screen resized" );
        }

        if( eglMakeCurrent( display_, surface_, surface_, context_ ) == EGL_TRUE )
            return EGL_SUCCESS;

        EGLint err = eglGetError();
        LOGW( "Unable to eglMakeCurrent %d", err );

        if( err == EGL_CONTEXT_LOST )
        {
            //Recreate context
            LOGI( "Re-creating egl context" );
            InitEGLContext();
        }
        else
        {
            //Recreate surface
            Terminate();
            InitEGLSurface();
            InitEGLContext();
        }

        return err;
    }

    int GetScreenWidth()
    {
        return screen_width_;
    }
    int GetScreenHeight()
    {
        return screen_height_;
    }

    int GetBufferColorSize()
    {
        return color_size_;
    }
    int GetBufferDepthSize()
    {
        return depth_size_;
    }
    float GetGLVersion()
    {
        return gl_version_;
    }
    bool CheckExtension( const(char)* extension )
    {
        import std.algorithm.searching : find;
        import std.conv : to;
        import std.string : empty;
        if( extension == null )
            return false;
        string extensions = to!string( cast(char*) glGetString( GL_EXTENSIONS ) );
        string str = to!string( extension ) ~ " ";

        if( !find( extensions, str ).empty )
        {
            return true;
        }

        return false;
    }
}
