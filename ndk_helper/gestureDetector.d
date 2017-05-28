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

module ndk_helper.gestureDetector;
import android.configuration : AConfiguration, AConfiguration_getDensity;
import android.input;
import ndk_helper.JNIHelper : LOGI;
import std.algorithm : remove;

//--------------------------------------------------------------------------------
// Constants
//--------------------------------------------------------------------------------
const int DOUBLE_TAP_TIMEOUT = 300_000_000;
const int TAP_TIMEOUT = 180_000_000;
const int DOUBLE_TAP_SLOP = 100;
const int TOUCH_SLOP = 8;

enum
{
    GESTURE_STATE_NONE = 0,
    GESTURE_STATE_START = 1,
    GESTURE_STATE_MOVE = 2,
    GESTURE_STATE_END = 4,
    GESTURE_STATE_ACTION = (GESTURE_STATE_START | GESTURE_STATE_END),
}
alias int GESTURE_STATE;

/******************************************************************
 * Base class of Gesture Detectors
 * GestureDetectors handles input events and detect gestures
 * Note that different detectors may detect gestures with an event at
 * same time. The caller needs to manage gesture priority accordingly
 *
 */
class GestureDetector
{
protected:
    float dp_factor_ = 1.0f;
public:
    void SetConfiguration( AConfiguration* config )
    {
        dp_factor_ = 160.0f / AConfiguration_getDensity( config );
    }

    GESTURE_STATE Detect( const(AInputEvent)* motion_event )
    {
        return GESTURE_STATE_NONE;
    }
}

/******************************************************************
 * Tap gesture detector
 * Returns GESTURE_STATE_ACTION when a tap gesture is detected
 *
 */
class TapDetector: GestureDetector
{
private:
    int down_pointer_id_;
    float down_x_;
    float down_y_;
public:
    override GESTURE_STATE Detect( const(AInputEvent)* motion_event )
    {
        if( AMotionEvent_getPointerCount( motion_event ) > 1 )
        {
            //Only support single touch
            return false;
        }

        int action = AMotionEvent_getAction( motion_event );
        uint flags = action & AMOTION_EVENT_ACTION_MASK;
        switch( flags )
        {
        case AMOTION_EVENT_ACTION_DOWN:
            down_pointer_id_ = AMotionEvent_getPointerId( motion_event, 0 );
            down_x_ = AMotionEvent_getX( motion_event, 0 );
            down_y_ = AMotionEvent_getY( motion_event, 0 );
            break;
        case AMOTION_EVENT_ACTION_UP:
        {
            long eventTime = AMotionEvent_getEventTime( motion_event );
            long downTime = AMotionEvent_getDownTime( motion_event );
            if( eventTime - downTime <= TAP_TIMEOUT )
            {
                if( down_pointer_id_ == AMotionEvent_getPointerId( motion_event, 0 ) )
                {
                    float x = AMotionEvent_getX( motion_event, 0 ) - down_x_;
                    float y = AMotionEvent_getY( motion_event, 0 ) - down_y_;
                    if( x * x + y * y < TOUCH_SLOP * TOUCH_SLOP * dp_factor_ )
                    {
                        LOGI( "TapDetector: Tap detected" );
                        return GESTURE_STATE_ACTION;
                    }
                }
            }
            break;
        }
        default:
            break;
        }
        return GESTURE_STATE_NONE;
    }
}

/******************************************************************
 * Double-tap gesture detector
 * Returns GESTURE_STATE_ACTION when a double-tap gesture is detected
 *
 */
class DoubletapDetector: GestureDetector
{
private:
    TapDetector tap_detector_;
    long last_tap_time_;
    float last_tap_x_;
    float last_tap_y_;
public:
    this()
    {
        tap_detector_ = new TapDetector;
    }

    override GESTURE_STATE Detect( const(AInputEvent)* motion_event )
    {
        if( AMotionEvent_getPointerCount( motion_event ) > 1 )
        {
            //Only support single double tap
            return false;
        }

        auto tap_detected = tap_detector_.Detect( motion_event );

        int action = AMotionEvent_getAction( motion_event );
        uint flags = action & AMOTION_EVENT_ACTION_MASK;
        switch( flags )
        {
        case AMOTION_EVENT_ACTION_DOWN:
        {
            long eventTime = AMotionEvent_getEventTime( motion_event );
            if( eventTime - last_tap_time_ <= DOUBLE_TAP_TIMEOUT )
            {
                float x = AMotionEvent_getX( motion_event, 0 ) - last_tap_x_;
                float y = AMotionEvent_getY( motion_event, 0 ) - last_tap_y_;
                if( x * x + y * y < DOUBLE_TAP_SLOP * DOUBLE_TAP_SLOP * dp_factor_ )
                {
                    LOGI( "DoubletapDetector: Doubletap detected" );
                    return GESTURE_STATE_ACTION;
                }
            }
            break;
        }
        case AMOTION_EVENT_ACTION_UP:
            if( tap_detected )
            {
                last_tap_time_ = AMotionEvent_getEventTime( motion_event );
                last_tap_x_ = AMotionEvent_getX( motion_event, 0 );
                last_tap_y_ = AMotionEvent_getY( motion_event, 0 );
            }
            break;
        default:
            break;
        }
        return GESTURE_STATE_NONE;
    }

    override void SetConfiguration( AConfiguration* config )
    {
        dp_factor_ = 160.0f / AConfiguration_getDensity( config );
        tap_detector_.SetConfiguration( config );
    }
}

/******************************************************************
 * Pinch gesture detector
 * Returns pinch gesture state when a pinch gesture is detected
 * The class handles multiple touches more than 2
 * When the finger 1,2,3 are tapped and then finger 1 is released,
 * the detector start new pinch gesture with finger 2 & 3.
 */
class PinchDetector: GestureDetector
{
private:
    int FindIndex( const(AInputEvent)* event, int id )
    {
        int count = AMotionEvent_getPointerCount( event );
        for( uint i = 0; i < count; ++i )
        {
            if( id == AMotionEvent_getPointerId( event, i ) )
                return i;
        }
        return -1;
    }

    const(AInputEvent)* event_;
    int[] vec_pointers_;
public:
    override GESTURE_STATE Detect( const(AInputEvent)* event )
    {
        GESTURE_STATE ret = GESTURE_STATE_NONE;
        int action = AMotionEvent_getAction( event );
        uint flags = action & AMOTION_EVENT_ACTION_MASK;
        event_ = event;

        int count = AMotionEvent_getPointerCount( event );
        switch( flags )
        {
        case AMOTION_EVENT_ACTION_DOWN:
            vec_pointers_ ~=  AMotionEvent_getPointerId( event, 0 );
            break;
        case AMOTION_EVENT_ACTION_POINTER_DOWN:
        {
            int iIndex = (action & AMOTION_EVENT_ACTION_POINTER_INDEX_MASK)
                >> AMOTION_EVENT_ACTION_POINTER_INDEX_SHIFT;
            vec_pointers_ ~= AMotionEvent_getPointerId( event, iIndex );
            if( count == 2 )
            {
                //Start new pinch
                ret = GESTURE_STATE_START;
            }
        }
            break;
        case AMOTION_EVENT_ACTION_UP:
            vec_pointers_.length--;
            break;
        case AMOTION_EVENT_ACTION_POINTER_UP:
        {
            int index = (action & AMOTION_EVENT_ACTION_POINTER_INDEX_MASK)
                >> AMOTION_EVENT_ACTION_POINTER_INDEX_SHIFT;
            int released_pointer_id = AMotionEvent_getPointerId( event, index );

            int i = 0;
            for( ; i < vec_pointers_.length; ++i )
            {
                if( vec_pointers_[i] == released_pointer_id )
                {
                    vec_pointers_ = vec_pointers_.remove( i );
                    break;
                }
            }

            if( i <= 1 )
            {
                //Reset pinch or drag
                if( count != 2 )
                {
                    //Start new pinch
                    ret = GESTURE_STATE_START | GESTURE_STATE_END;
                }
            }
        }
            break;
        case AMOTION_EVENT_ACTION_MOVE:
            switch( count )
            {
            case 1:
                break;
            default:
                //Multi touch
                ret = GESTURE_STATE_MOVE;
                break;
            }
            break;
        case AMOTION_EVENT_ACTION_CANCEL:
            break;
        default:
            break;
        }

        return ret;
    }

    bool GetPointers( ref float[2] v1, ref float[2] v2 )
    {
        if( vec_pointers_.length < 2 )
            return false;

        int index = FindIndex( event_, vec_pointers_[0] );
        if( index == -1 )
            return false;

        float x = AMotionEvent_getX( event_, index );
        float y = AMotionEvent_getY( event_, index );

        index = FindIndex( event_, vec_pointers_[1] );
        if( index == -1 )
            return false;

        float x2 = AMotionEvent_getX( event_, index );
        float y2 = AMotionEvent_getY( event_, index );

        v1 = [ x, y ];
        v2 = [ x2, y2 ];

        return true;
    }
}

/******************************************************************
 * Drag gesture detector
 * Returns drag gesture state when a drag-tap gesture is detected
 *
 */
class DragDetector: GestureDetector
{
private:
    int FindIndex( const(AInputEvent)* event, int id )
    {
        int count = AMotionEvent_getPointerCount( event );
        for( uint i = 0; i < count; ++i )
        {
            if( id == AMotionEvent_getPointerId( event, i ) )
                return i;
        }
        return -1;
    }

    const(AInputEvent)* event_;
    int[] vec_pointers_;
public:
    override GESTURE_STATE Detect( const(AInputEvent)* event )
    {
        GESTURE_STATE ret = GESTURE_STATE_NONE;
        int action = AMotionEvent_getAction( event );
        int index = (action & AMOTION_EVENT_ACTION_POINTER_INDEX_MASK)
            >> AMOTION_EVENT_ACTION_POINTER_INDEX_SHIFT;
        uint flags = action & AMOTION_EVENT_ACTION_MASK;
        event_ = event;

        int count = AMotionEvent_getPointerCount( event );
        switch( flags )
        {
        case AMOTION_EVENT_ACTION_DOWN:
            vec_pointers_ ~= AMotionEvent_getPointerId( event, 0 );
            ret = GESTURE_STATE_START;
            break;
        case AMOTION_EVENT_ACTION_POINTER_DOWN:
            vec_pointers_ ~= AMotionEvent_getPointerId( event, index );
            break;
        case AMOTION_EVENT_ACTION_UP:
            vec_pointers_.length--;
            ret = GESTURE_STATE_END;
            break;
        case AMOTION_EVENT_ACTION_POINTER_UP:
        {
            int released_pointer_id = AMotionEvent_getPointerId( event, index );

            int i = 0;
            for( ; i < vec_pointers_.length; ++i )
            {
                if( vec_pointers_[i] == released_pointer_id )
                {
                    vec_pointers_ = vec_pointers_.remove( i );
                    break;
                }
            }

            if( i <= 1 )
            {
                //Reset pinch or drag
                if( count == 2 )
                {
                    ret = GESTURE_STATE_START;
                }
            }
            break;
        }
        case AMOTION_EVENT_ACTION_MOVE:
            switch( count )
            {
            case 1:
                //Drag
                ret = GESTURE_STATE_MOVE;
                break;
            default:
                break;
            }
            break;
        case AMOTION_EVENT_ACTION_CANCEL:
            break;
        default:
            break;
        }

        return ret;
    }

    bool GetPointer( ref float[2] v )
    {
        if( vec_pointers_.length < 1 )
        {
            return false;
        }
        int iIndex = FindIndex( event_, vec_pointers_[0] );
        if( iIndex == -1 )
        {
            return false;
        }

        float x = AMotionEvent_getX( event_, iIndex );
        float y = AMotionEvent_getY( event_, iIndex );

        v = [ x, y ];

        return true;
    }
}
