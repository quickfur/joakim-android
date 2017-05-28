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

module ndk_helper.perfMonitor;
import core.sys.posix.sys.time : gettimeofday, time_t, timeval;

const int NUM_SAMPLES = 100;

/******************************************************************
 * Helper struct for performance monitoring and get current tick time
 */
struct PerfMonitor
{
private:
    float current_FPS_;
    time_t tv_last_sec_;

    double last_tick_ = 0.0;
    int tickindex_;
    double ticksum_ = 0.0;
    double[NUM_SAMPLES] ticklist_ = 0.0;

    double UpdateTick( double current_tick )
    {
        ticksum_ -= ticklist_[tickindex_];
        ticksum_ += current_tick;
        ticklist_[tickindex_] = current_tick;
        tickindex_ = (tickindex_ + 1) % NUM_SAMPLES;

        return ticksum_ / NUM_SAMPLES;
    }

public:
    bool Update( ref float fFPS )
    {
        timeval Time;
        gettimeofday( &Time, null );

        double time = Time.tv_sec + Time.tv_usec * 1.0 / 1000000.0;
        double tick = time - last_tick_;
        double d = UpdateTick( tick );
        last_tick_ = time;

        if( Time.tv_sec - tv_last_sec_ >= 1 )
        {
            current_FPS_ = 1.0 / d;
            tv_last_sec_ = Time.tv_sec;
            fFPS = current_FPS_;
            return true;
        }
        else
        {
            fFPS = current_FPS_;
            return false;
        }
    }

    static double GetCurrentTime()
    {
        timeval time;
        gettimeofday( &time, null );
        double ret = time.tv_sec + time.tv_usec * 1.0 / 1000000.0;
        return ret;
    }
}
