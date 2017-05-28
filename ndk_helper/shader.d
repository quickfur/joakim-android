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

module ndk_helper.shader;
import core.stdc.stdlib : malloc, free;
import GLES2.gl2;
import ndk_helper.JNIHelper : JNIHelper, LOGI;

enum DEBUG = true;

/******************************************************************
 * CompileShader() with vector
 *
 * arguments:
 *  out: shader, shader variable
 *  in: type, shader type (i.e. GL_VERTEX_SHADER/GL_FRAGMENT_SHADER)
 *  in: data, source vector
 * return: true if a shader compilation succeeded, false if it failed
 *
 */
bool CompileShader( GLuint *shader, const GLenum type, ref ubyte[] data )
{
    if( !data.length )
        return false;

    const(GLchar)*source = cast(GLchar *) &data[0];
    int iSize = data.length;
    return CompileShader( shader, type, source, iSize );
}

/******************************************************************
 * CompileShader() with buffer
 *
 * arguments:
 *  out: shader, shader variable
 *  in: type, shader type (i.e. GL_VERTEX_SHADER/GL_FRAGMENT_SHADER)
 *  in: source, source buffer
 *  in: iSize, buffer size
 * return: true if a shader compilation succeeded, false if it failed
 *
 */
bool CompileShader( GLuint *shader,
        const GLenum type,
        const(GLchar)*source,
        const int iSize )
{
    if( source == null || iSize <= 0 )
        return false;

    *shader = glCreateShader( type );
    glShaderSource( *shader, 1, &source, &iSize ); //Not specifying 3rd parameter (size) could be troublesome..

    glCompileShader( *shader );

    static if (DEBUG)
    {
        GLint logLength;
        glGetShaderiv( *shader, GL_INFO_LOG_LENGTH, &logLength );
        if( logLength > 0 )
        {
            GLchar *log = cast(GLchar *) malloc( logLength );
            glGetShaderInfoLog( *shader, logLength, &logLength, log );
            LOGI( "Shader compile log:\n%s", log );
            free( log );
        }
    }

    GLint status;
    glGetShaderiv( *shader, GL_COMPILE_STATUS, &status );
    if( status == 0 )
    {
        glDeleteShader( *shader );
        return false;
    }

    return true;
}

/******************************************************************
 * CompileShader() with filename
 *
 * arguments:
 *  out: shader, shader variable
 *  in: type, shader type (i.e. GL_VERTEX_SHADER/GL_FRAGMENT_SHADER)
 *  in: strFilename, filename
 * return: true if a shader compilation succeeded, false if it failed
 *
 */
bool CompileShader( GLuint *shader, const GLenum type, const(char)*strFileName )
{
    ubyte[] data;
    bool b = JNIHelper.GetInstance().ReadFile( strFileName, &data );
    if( !b )
    {
        LOGI( "Can not open a file:%s", strFileName );
        return false;
    }

    return CompileShader( shader, type, data );
}

/******************************************************************
 * CompileShader() with map_parameters helps patching on a shader on the fly.
 *
 * arguments:
 *  out: shader, shader variable
 *  in: type, shader type (i.e. GL_VERTEX_SHADER/GL_FRAGMENT_SHADER)
 *  in: mapParameters
 *      For a example,
 *      map : %KEY% -> %VALUE% replaces all %KEY% entries in the given shader code to %VALUE"
 * return: true if a shader compilation succeeded, false if it failed
 *
 */
bool CompileShader( GLuint *shader,
        const GLenum type,
        const(char)*str_file_name,
        ref const string[string] map_parameters )
{
    import std.conv : to;

    ubyte[] data;
    if( !JNIHelper.GetInstance().ReadFile( str_file_name, &data ) )
    {
        LOGI( "Can not open a file:%s", str_file_name );
        return false;
    }

    const char REPLACEMENT_TAG = '*';
    //Fill-in parameters
    string str = to!string(data);
    char[] str_replacement_map = new char[data.length];
    str_replacement_map[] = ' ';

    /* maybe port later
    while( it != itEnd )
    {
        size_t pos = 0;
        while( (pos = str.find( it->first, pos )) != std::string::npos )
        {
            //Check if the sub string is already touched

            size_t replaced_pos = str_replacement_map.find( REPLACEMENT_TAG, pos );
            if( replaced_pos == std::string::npos || replaced_pos > pos )
            {

                str.replace( pos, it->first.length(), it->second );
                str_replacement_map.replace( pos, it->first.length(), it->first.length(),
                        REPLACEMENT_TAG );
                pos += it->second.length();
            }
            else
            {
                //The replacement target has been touched by other tag, skipping them
                pos += it->second.length();
            }
        }
        it++;
    }*/

    LOGI( "Patched Shader:\n%s", str );

    ubyte[] v = cast(ubyte[])str;
    return CompileShader( shader, type, v );
}

/******************************************************************
 * LinkProgram()
 *
 * arguments:
 *  in: program, program
 * return: true if a shader linkage succeeded, false if it failed
 *
 */
bool LinkProgram( const GLuint prog )
{
    GLint status;

    glLinkProgram( prog );

    static if (DEBUG)
    {
        GLint logLength;
        glGetProgramiv( prog, GL_INFO_LOG_LENGTH, &logLength );
        if( logLength > 0 )
        {
            GLchar *log = cast(GLchar *) malloc( logLength );
            glGetProgramInfoLog( prog, logLength, &logLength, log );
            LOGI( "Program link log:\n%s", log );
            free( log );
        }
    }

    glGetProgramiv( prog, GL_LINK_STATUS, &status );
    if( status == 0 )
    {
        LOGI( "Program link failed\n" );
        return false;
    }

    return true;
}

/******************************************************************
 * validateProgram()
 *
 * arguments:
 *  in: program, program
 * return: true if a shader validation succeeded, false if it failed
 *
 */
bool ValidateProgram( const GLuint prog )
{
    GLint logLength, status;

    glValidateProgram( prog );
    glGetProgramiv( prog, GL_INFO_LOG_LENGTH, &logLength );
    if( logLength > 0 )
    {
        GLchar *log = cast(GLchar *) malloc( logLength );
        glGetProgramInfoLog( prog, logLength, &logLength, log );
        LOGI( "Program validate log:\n%s", log );
        free( log );
    }

    glGetProgramiv( prog, GL_VALIDATE_STATUS, &status );
    if( status == 0 )
        return false;

    return true;
}
