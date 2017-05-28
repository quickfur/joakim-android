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

module ndk_helper.tapCamera;
import core.stdc.math : atan2f, isnan, sinf, sqrtf, cosf;

const float TRANSFORM_FACTOR = 15.0f;
const float TRANSFORM_FACTORZ = 10.0f;

const float MOMENTUM_FACTOR_DECREASE = 0.85f;
const float MOMENTUM_FACTOR_DECREASE_SHIFT = 0.9f;
const float MOMENTUM_FACTOR = 0.8f;
const float MOMENTUM_FACTOR_THRESHOLD = 0.001f;

/******************************************************************
 * Camera control helper struct with a tap gesture
 * This struct is mainly used for 3D space camera control in samples.
 *
 */
struct TapCamera
{
private:
    //Trackball
    float[2] vec_ball_center_ = [ 0.0f, 0.0f ];
    float ball_radius_ = 0.75f;
    float[4] quat_ball_now_ = [ 0.0f, 0.0f, 0.0f, 1.0f ];
    float[4] quat_ball_down_ = [ 0.0f, 0.0f, 0.0f, 1.0f ];
    float[2] vec_ball_now_ = [ 0.0f, 0.0f ];
    float[2] vec_ball_down_ = [ 0.0f, 0.0f ];
    float[4] quat_ball_rot_ = [ 0.0f, 0.0f, 0.0f, 1.0f ];

    bool dragging_;
    bool pinching_;

    //Pinch related info
    float[2] vec_pinch_start_ = [ 0.0f, 0.0f ];
    float[2] vec_pinch_start_center_ = [ 0.0f, 0.0f ];
    float pinch_start_distance_SQ_ = 0.0f;

    //Camera shift
    float[3] vec_offset_ = [ 0.0f, 0.0f, 0.0f ];
    float[3] vec_offset_now_ = [ 0.0f, 0.0f, 0.0f ];

    //Camera Rotation
    float camera_rotation_ = 0.0f;
    float camera_rotation_start_ = 0.0f;
    float camera_rotation_now_ = 0.0f;

    //Momentum support
    bool momentum_;
    float[2] vec_drag_delta_ = [ 0.0f, 0.0f ];
    float[2] vec_last_input_;
    float[3] vec_offset_last_;
    float[3] vec_offset_delta_ = [ 0.0f, 0.0f, 0.0f ];
    float momemtum_steps_ = 0.0f;

    float[2] vec_flip_ = [ 0.0f, 0.0f ];
    float flip_z_ = -1.0f;

    float[4][4] mat_rotation_ = [[ 1.0f, 0.0f, 0.0f, 0.0f ], [ 0.0f, 1.0f, 0.0f, 0.0f ],
                                 [ 0.0f, 0.0f, 1.0f, 0.0f ], [ 0.0f, 0.0f, 0.0f, 1.0f ]];
    float[4][4] mat_transform_;

    float[3] vec_pinch_transform_factor_ = [ 1.0f, 1.0f, 1.0f ];

    float[3] PointOnSphere( ref float[2] point )
    {
        float[3] ball_mouse;
        float mag;
        float[2] vec = (point[] - vec_ball_center_[]) / ball_radius_;
        mag = vec[0]^^2 + vec[1]^^2;
        if( mag > 1.0f )
        {
            float scale = 1.0f / sqrtf( mag );
            vec[] *= scale;
            ball_mouse = vec ~ 0.0f;
        }
        else
        {
            ball_mouse = vec ~ sqrtf( 1.0f - mag );
        }
        return ball_mouse;
    }

    void BallUpdate()
    {
        if( dragging_ )
        {
            float[3] vec_from = PointOnSphere( vec_ball_down_ );
            float[3] vec_to = PointOnSphere( vec_ball_now_ );

            float[3] vec =
                [vec_from[1] * vec_to[2] - vec_from[2] * vec_to[1],
                 vec_from[2] * vec_to[0] - vec_from[0] * vec_to[2],
                 vec_from[0] * vec_to[1] - vec_from[1] * vec_to[0]]; //Cross product
            float w = vec_from[0] * vec_to[0] + vec_from[1] * vec_to[1] +
                      vec_from[2] * vec_to[2]; //Dot product

            float[4] qDrag = vec ~ w;

            float[4] quatMultiply(float[4] first, float[4] second)
            {
                float[4] ret;
                ret[0] = first[0] * second[3] + first[1] * second[2] -
                         first[2] * second[1] + first[3] * second[0];
                ret[1] = -first[0] * second[2] + first[1] * second[3] +
                         first[2] * second[0] + first[3] * second[1];
                ret[2] = first[0] * second[1] - first[1] * second[0] +
                         first[2] * second[3] + first[3] * second[2];
                ret[3] = -first[0] * second[0] - first[1] * second[1] -
                         first[2] * second[2] + first[3] * second[3];
                return ret;
            }
            qDrag = quatMultiply(qDrag, quat_ball_down_);
            quat_ball_now_ = quatMultiply(quat_ball_rot_, qDrag);
        }

        // set mat_rotation_ using quat_ball_now_
        float x2 = quat_ball_now_[0] * quat_ball_now_[0] * 2.0f;
        float y2 = quat_ball_now_[1] * quat_ball_now_[1] * 2.0f;
        float z2 = quat_ball_now_[2] * quat_ball_now_[2] * 2.0f;
        float xy = quat_ball_now_[0] * quat_ball_now_[1] * 2.0f;
        float yz = quat_ball_now_[1] * quat_ball_now_[2] * 2.0f;
        float zx = quat_ball_now_[2] * quat_ball_now_[0] * 2.0f;
        float xw = quat_ball_now_[0] * quat_ball_now_[3] * 2.0f;
        float yw = quat_ball_now_[1] * quat_ball_now_[3] * 2.0f;
        float zw = quat_ball_now_[2] * quat_ball_now_[3] * 2.0f;

        mat_rotation_ = [[1.0f - y2 - z2, xy - zw, zx + yw, 0.0f],
                         [xy + zw, 1.0f - z2 - x2, yz - xw, 0.0f],
                         [zx - yw, yz + xw, 1.0f - x2 - y2, 0.0f],
                         [ 0.0f, 0.0f, 0.0f, 1.0f]];
    }

    void InitParameters()
    {
        //Init parameters
        vec_offset_ = [ 0.0f, 0.0f, 0.0f ];
        vec_offset_now_ = [ 0.0f, 0.0f, 0.0f ];

        quat_ball_rot_ = [ 0.0f, 0.0f, 0.0f, 1.0f ];
        quat_ball_now_ = [ 0.0f, 0.0f, 0.0f, 1.0f ];
        mat_rotation_ = [[ 1.0f, 0.0f, 0.0f, 0.0f ], [ 0.0f, 1.0f, 0.0f, 0.0f ],
                         [ 0.0f, 0.0f, 1.0f, 0.0f ], [ 0.0f, 0.0f, 0.0f, 1.0f ]];
        camera_rotation_ = 0.0f;

        vec_drag_delta_ = [ 0.0f, 0.0f ];
        vec_offset_delta_ = [ 0.0f, 0.0f, 0.0f ];

        momentum_ = false;
    }

public:
    void BeginDrag( ref const float[2] v )
    {
        if( dragging_ )
            EndDrag();

        if( pinching_ )
            EndPinch();

        float[2] vec = v[] * vec_flip_[];
        vec_ball_now_ = vec;
        vec_ball_down_ = vec_ball_now_;

        dragging_ = true;
        momentum_ = false;
        vec_last_input_ = vec;
        vec_drag_delta_ = [ 0.0f, 0.0f ];
    }

    void EndDrag()
    {
        quat_ball_down_ = quat_ball_now_;
        quat_ball_rot_ = [ 0.0f, 0.0f, 0.0f, 1.0f ];

        dragging_ = false;
        momentum_ = true;
        momemtum_steps_ = 1.0f;
    }

    void Drag( ref const float[2] v )
    {
        if( !dragging_ )
            return;

        float[2] vec = v[] * vec_flip_[];
        vec_ball_now_ = vec;

        vec_drag_delta_ = vec_drag_delta_[] * MOMENTUM_FACTOR + (vec[] - vec_last_input_[]);
        vec_last_input_ = vec;
    }

    void Update()
    {
        if( momentum_ )
        {
            float momenttum_steps = momemtum_steps_;

            //Momentum rotation
            float[2] v = vec_drag_delta_;
            float[2] reset = [ 0.0f, 0.0f ];
            BeginDrag( reset ); //NOTE:This call reset _VDragDelta
            float[2] flipV = v[] * vec_flip_[];
            Drag( flipV );

            //Momentum shift
            vec_offset_[] += vec_offset_delta_[];

            BallUpdate();
            EndDrag();

            //Decrease deltas
            vec_drag_delta_ = v[] * MOMENTUM_FACTOR_DECREASE;
            vec_offset_delta_[] *= MOMENTUM_FACTOR_DECREASE_SHIFT;

            //Count steps
            momemtum_steps_ = momenttum_steps * MOMENTUM_FACTOR_DECREASE;
            if( momemtum_steps_ < MOMENTUM_FACTOR_THRESHOLD )
            {
                momentum_ = false;
            }
        }
        else
        {
            vec_drag_delta_[] *= MOMENTUM_FACTOR;
            vec_offset_delta_[] *= MOMENTUM_FACTOR;
            BallUpdate();
        }

        float[3] vec = vec_offset_[] + vec_offset_now_[];
        float[3] vec_tmp = [ TRANSFORM_FACTOR, -TRANSFORM_FACTOR, TRANSFORM_FACTORZ ];

        vec[] *= vec_tmp[] * vec_pinch_transform_factor_[];

        mat_transform_ = [[ 1.0f, 0.0f, 0.0f, vec[0] ], [ 0.0f, 1.0f, 0.0f, vec[1] ],
                          [ 0.0f, 0.0f, 1.0f, vec[2] ], [ 0.0f, 0.0f, 0.0f, 1.0f ]];
    }

    ref float[4][4] GetRotationMatrix()
    {
        return mat_rotation_;
    }

    ref float[4][4] GetTransformMatrix()
    {
        return mat_transform_;
    }

    void BeginPinch( ref const float[2] v1, ref const float[2] v2 )
    {
        if( dragging_ )
            EndDrag();

        if( pinching_ )
            EndPinch();

        float[2] empty = [ 0.0f, 0.0f ];
        BeginDrag( empty );

        vec_pinch_start_center_ = (v1[] + v2[]) / 2.0f;

        float[2] vec = v1[] - v2[];
        float x_diff = vec[0];
        float y_diff = vec[1];

        pinch_start_distance_SQ_ = x_diff * x_diff + y_diff * y_diff;
        camera_rotation_start_ = atan2f( y_diff, x_diff );
        camera_rotation_now_ = 0.0f;

        pinching_ = true;
        momentum_ = false;

        //Init momentum factors
        vec_offset_delta_ = [ 0.0f, 0.0f, 0.0f ];
    }

    void EndPinch()
    {
        pinching_ = false;
        momentum_ = true;
        momemtum_steps_ = 1.0f;
        vec_offset_[] += vec_offset_now_[];
        camera_rotation_ += camera_rotation_now_;
        vec_offset_now_ = [ 0.0f, 0.0f, 0.0f ];

        camera_rotation_now_ = 0.0f;

        EndDrag();
    }

    void Pinch( ref const float[2] v1, ref const float[2] v2 )
    {
        if( !pinching_ )
            return;

        //Update momentum factor
        vec_offset_last_ = vec_offset_now_;

        float[2] vec = v1[] - v2[];
        float x_diff = vec[0];
        float y_diff = vec[1];

        float fDistanceSQ = x_diff * x_diff + y_diff * y_diff;

        float f = pinch_start_distance_SQ_ / fDistanceSQ;
        if( f < 1.0f )
            f = -1.0f / f + 1.0f;
        else
            f = f - 1.0f;
        if( isnan( f ) )
            f = 0.0f;

        vec = (v1[] + v2[]) / 2.0f - vec_pinch_start_center_[];
        vec_offset_now_ = vec ~ (flip_z_ * f) ;

        //Update momentum factor
        vec_offset_delta_ = vec_offset_delta_[] * MOMENTUM_FACTOR
                + (vec_offset_now_[] - vec_offset_last_[]);

        //
        //Update ration quaternion
        float fRotation = atan2f( y_diff, x_diff );
        camera_rotation_now_ = fRotation - camera_rotation_start_;

        //Trackball rotation
        quat_ball_rot_ = [ 0.0f, 0.0f, sinf( -camera_rotation_now_ * 0.5f ),
                           cosf( -camera_rotation_now_ * 0.5f ) ];
    }

    void SetFlip( const float x, const float y, const float z )
    {
        vec_flip_ = [ x, y ];
        flip_z_ = z;
    }

    void SetPinchTransformFactor( const float x, const float y, const float z )
    {
        vec_pinch_transform_factor_ = [ x, y, z ];
    }

    void Reset( const bool bAnimate )
    {
        InitParameters();
        Update();
    }
}
