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

import EGL.egl : EGL_SUCCESS;
import GLES2.gl2;
import android.input : AINPUT_EVENT_TYPE_MOTION, AInputEvent, AInputEvent_getType;
import android.looper : ALooper_pollAll;
import android.sensor;
import android_native_app_glue;
import jni : JNIEnv, jclass, jmethodID;
import ndk_helper.GLContext : GLContext;
import ndk_helper.JNIHelper : JNIHelper, LOGI;
import ndk_helper.gestureDetector, ndk_helper.perfMonitor : PerfMonitor;
import ndk_helper.tapCamera : TapCamera;
import TeapotRenderer : TeapotRenderer;

enum HELPER_CLASS_NAME = "com/sample/helper/NDKHelper"; //Class name of helper function
enum USE_NDK_PROFILER = false;
//-------------------------------------------------------------------------
//Shared state for our app.
//-------------------------------------------------------------------------
struct Engine
{
private:
    TeapotRenderer renderer_;

    GLContext* gl_context_;

    bool initialized_resources_;
    bool has_focus_;

    DoubletapDetector doubletap_detector_;
    PinchDetector pinch_detector_;
    DragDetector drag_detector_;
    PerfMonitor monitor_;

    TapCamera tap_camera_;

    android_app* app_;

    ASensorManager* sensor_manager_;
    const(ASensor)* accelerometer_sensor_;
    ASensorEventQueue* sensor_event_queue_;

    void UpdateFPS( float fFPS )
    {
        JNIEnv *jni;
        (*app_.activity.vm).AttachCurrentThread( app_.activity.vm, &jni, null );

        //Default class retrieval
        jclass clazz = (*jni).GetObjectClass( jni, app_.activity.clazz );
        jmethodID methodID = (*jni).GetMethodID( jni, clazz, "updateFPS", "(F)V" );
        (*jni).CallVoidMethod( jni, app_.activity.clazz, methodID, fFPS );

        (*app_.activity.vm).DetachCurrentThread(app_.activity.vm);
        return;
    }

    void ShowUI()
    {
        JNIEnv *jni;
        (*app_.activity.vm).AttachCurrentThread( app_.activity.vm, &jni, null );

        //Default class retrieval
        jclass clazz = (*jni).GetObjectClass( jni, app_.activity.clazz );
        jmethodID methodID = (*jni).GetMethodID( jni, clazz, "showUI", "()V" );
        (*jni).CallVoidMethod( jni, app_.activity.clazz, methodID );

        (*app_.activity.vm).DetachCurrentThread(app_.activity.vm);
        return;
    }

    void TransformPosition( ref float[2] vec )
    {
        vec = [ 2.0f, 2.0f ] * vec[]
                / [ gl_context_.GetScreenWidth(), gl_context_.GetScreenHeight() ]
                - [ 1.0f, 1.0f ];
    }

public:
    /**
     * Process the next main command.
     */
    static void HandleCmd( android_app* app, int cmd )
    {
        Engine* eng = cast(Engine*) app.userData;
        switch( cmd )
        {
        case APP_CMD_SAVE_STATE:
            break;
        case APP_CMD_INIT_WINDOW:
            // The window is being shown, get it ready.
            if( app.window != null )
            {
                eng.InitDisplay();
                eng.DrawFrame();
            }
            break;
        case APP_CMD_TERM_WINDOW:
            // The window is being hidden or closed, clean it up.
            eng.TermDisplay();
            eng.has_focus_ = false;
            break;
        case APP_CMD_STOP:
            break;
        case APP_CMD_GAINED_FOCUS:
            eng.ResumeSensors();
            //Start animation
            eng.has_focus_ = true;
            break;
        case APP_CMD_LOST_FOCUS:
            eng.SuspendSensors();
            // Also stop animating.
            eng.has_focus_ = false;
            eng.DrawFrame();
            break;
        case APP_CMD_LOW_MEMORY:
            //Free up GL resources
            eng.TrimMemory();
            break;
        default:
            break;
        }
    }

    /**
     * Process the next input event.
     */
    static int HandleInput( android_app* app, AInputEvent* event )
    {
        Engine* eng = cast(Engine*) app.userData;
        if( AInputEvent_getType( event ) == AINPUT_EVENT_TYPE_MOTION )
        {
            GESTURE_STATE doubleTapState = eng.doubletap_detector_.Detect( event );
            GESTURE_STATE dragState = eng.drag_detector_.Detect( event );
            GESTURE_STATE pinchState = eng.pinch_detector_.Detect( event );

            //Double tap detector has a priority over other detectors
            if( doubleTapState == GESTURE_STATE_ACTION )
            {
                //Detect double tap
                eng.tap_camera_.Reset( true );
            }
            else
            {
                //Handle drag state
                if( dragState & GESTURE_STATE_START )
                {
                    //Otherwise, start dragging
                    float[2] v = [ 0.0f, 0.0f ];
                    eng.drag_detector_.GetPointer( v );
                    eng.TransformPosition( v );
                    eng.tap_camera_.BeginDrag( v );
                }
                else if( dragState & GESTURE_STATE_MOVE )
                {
                    float[2] v = [ 0.0f, 0.0f ];
                    eng.drag_detector_.GetPointer( v );
                    eng.TransformPosition( v );
                    eng.tap_camera_.Drag( v );
                }
                else if( dragState & GESTURE_STATE_END )
                {
                    eng.tap_camera_.EndDrag();
                }

                //Handle pinch state
                if( pinchState & GESTURE_STATE_START )
                {
                    //Start new pinch
                    float[2] v1 = [ 0.0f, 0.0f ];
                    float[2] v2 = [ 0.0f, 0.0f ];
                    eng.pinch_detector_.GetPointers( v1, v2 );
                    eng.TransformPosition( v1 );
                    eng.TransformPosition( v2 );
                    eng.tap_camera_.BeginPinch( v1, v2 );
                }
                else if( pinchState & GESTURE_STATE_MOVE )
                {
                    //Multi touch
                    //Start new pinch
                    float[2] v1 = [ 0.0f, 0.0f ];
                    float[2] v2 = [ 0.0f, 0.0f ];
                    eng.pinch_detector_.GetPointers( v1, v2 );
                    eng.TransformPosition( v1 );
                    eng.TransformPosition( v2 );
                    eng.tap_camera_.Pinch( v1, v2 );
                }
            }
            return 1;
        }
        return 0;
    }

    this(GLContext* gl_context)
    {
        doubletap_detector_ = new DoubletapDetector;
        pinch_detector_ = new PinchDetector;
        drag_detector_ = new DragDetector;
        gl_context_ = gl_context;
    }

    void SetState( android_app* state )
    {
        app_ = state;
        doubletap_detector_.SetConfiguration( app_.config );
        drag_detector_.SetConfiguration( app_.config );
        pinch_detector_.SetConfiguration( app_.config );
    }

    /**
     * Initialize an EGL context for the current display.
     */
    int InitDisplay()
    {
        if( !initialized_resources_ )
        {
            gl_context_.Init( app_.window );
            LoadResources();
            initialized_resources_ = true;
        }
        else
        {
            // initialize OpenGL ES and EGL
            if( EGL_SUCCESS != gl_context_.Resume( app_.window ) )
            {
                UnloadResources();
                LoadResources();
            }
        }

        ShowUI();

        // Initialize GL state.
        glEnable( GL_CULL_FACE );
        glEnable( GL_DEPTH_TEST );
        glDepthFunc( GL_LEQUAL );

        //Note that screen size might have been changed
        glViewport( 0, 0, gl_context_.GetScreenWidth(), gl_context_.GetScreenHeight() );
        renderer_.UpdateViewport();

        tap_camera_.SetFlip( 1.0f, -1.0f, -1.0f );
        tap_camera_.SetPinchTransformFactor( 2.0f, 2.0f, 8.0f );

        return 0;
    }

    void LoadResources()
    {
        renderer_.Init();
        renderer_.Bind( &tap_camera_ );
    }

    void UnloadResources()
    {
        renderer_.Unload();
    }

    /**
     * Just the current frame in the display.
     */
    void DrawFrame()
    {
        float fFPS;
        if( monitor_.Update( fFPS ) )
        {
            UpdateFPS( fFPS );
        }
        renderer_.Update( monitor_.GetCurrentTime() );

        // Just fill the screen with a color.
        glClearColor( 0.5f, 0.5f, 0.5f, 1.0f );
        glClear( GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT );
        renderer_.Render();

        // Swap
        if( EGL_SUCCESS != gl_context_.Swap() )
        {
            UnloadResources();
            LoadResources();
        }
    }

    /**
     * Tear down the EGL context currently associated with the display.
     */
    void TermDisplay()
    {
        gl_context_.Suspend();
    }

    void TrimMemory()
    {
        LOGI( "Trimming memory" );
        gl_context_.Invalidate();
    }

    bool IsReady()
    {
        if( has_focus_ )
            return true;

        return false;
    }

    //-------------------------------------------------------------------------
    //Sensor handlers
    //-------------------------------------------------------------------------
    void InitSensors()
    {
        sensor_manager_ = ASensorManager_getInstance();
        accelerometer_sensor_ = ASensorManager_getDefaultSensor( sensor_manager_,
                ASENSOR_TYPE_ACCELEROMETER );
        sensor_event_queue_ = ASensorManager_createEventQueue( sensor_manager_,
                app_.looper, LOOPER_ID_USER, null, null );
    }

    void ProcessSensors( int id )
    {
        // If a sensor has data, process it now.
        if( id == LOOPER_ID_USER )
        {
            if( accelerometer_sensor_ != null )
            {
                ASensorEvent event;
                while( ASensorEventQueue_getEvents( sensor_event_queue_, &event, 1 ) > 0 )
                {
                }
            }
        }
    }

    void SuspendSensors()
    {
        // When our app loses focus, we stop monitoring the accelerometer.
        // This is to avoid consuming battery while not being used.
        if( accelerometer_sensor_ != null )
        {
            ASensorEventQueue_disableSensor( sensor_event_queue_, accelerometer_sensor_ );
        }
    }

    void ResumeSensors()
    {
        // When our app gains focus, we start monitoring the accelerometer.
        if( accelerometer_sensor_ != null )
        {
            ASensorEventQueue_enableSensor( sensor_event_queue_, accelerometer_sensor_ );
            // We'd like to get 60 events per second (in us).
            ASensorEventQueue_setEventRate( sensor_event_queue_, accelerometer_sensor_,
                    (1000L / 60) * 1000 );
        }
    }
}

Engine g_engine;

void main(){}
/**
 * This is the main entry point of a native application that is using
 * android_native_app_glue.  It runs in its own thread, with its own
 * event loop for receiving input events and doing other things.
 */
extern(C) void android_main( android_app* state )
{
    app_dummy();

    g_engine = Engine(GLContext.GetInstance());
    g_engine.SetState( state );

    //Init helper functions
    JNIHelper.Init( state.activity, HELPER_CLASS_NAME );

    state.userData = &g_engine;
    state.onAppCmd = &Engine.HandleCmd;
    state.onInputEvent = &Engine.HandleInput;

    static if( USE_NDK_PROFILER )
    {
        monstartup("libTeapotNativeActivity.so");
    }

    // Prepare to monitor accelerometer
    g_engine.InitSensors();

    // loop waiting for stuff to do.
    while( 1 )
    {
        // Read all pending events.
        int id;
        int events;
        android_poll_source* source;

        // If not animating, we will block forever waiting for events.
        // If animating, we loop until all events are read, then continue
        // to draw the next frame of animation.
        while( (id = ALooper_pollAll( g_engine.IsReady() ? 0 : -1, null, &events, cast(void**) &source ))
                >= 0 )
        {
            // Process this event.
            if( source != null )
                source.process( state, source );

            g_engine.ProcessSensors( id );

            // Check if we are exiting.
            if( state.destroyRequested != 0 )
            {
                g_engine.TermDisplay();
                return;
            }
        }

        if( g_engine.IsReady() )
        {
            // Drawing is throttled to the screen update rate, so there
            // is no need to do timing here.
            g_engine.DrawFrame();
        }
    }
}
