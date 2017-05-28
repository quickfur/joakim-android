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

//--------------------------------------------------------------------------------
// Renderer for teapots
//--------------------------------------------------------------------------------
module TeapotRenderer;

import core.stdc.math : cosf, sinf;
import GLES2.gl2;
import ndk_helper.JNIHelper : LOGI;
import ndk_helper.shader : CompileShader, LinkProgram;
import ndk_helper.tapCamera : TapCamera;
//--------------------------------------------------------------------------------
// Teapot model data
//--------------------------------------------------------------------------------
mixin(import("teapot.inl.d"));

enum CLASS_NAME = "android/app/NativeActivity";
enum APPLICATION_CLASS_NAME = "com/sample/teapot/TeapotApplication";

const(GLvoid)* BUFFER_OFFSET(uint i) { return cast(GLvoid *)null + i; }

struct TEAPOT_VERTEX
{
    float[3] pos;
    float[3] normal;
}

enum SHADER_ATTRIBUTES
{
    ATTRIB_VERTEX, ATTRIB_NORMAL, ATTRIB_UV,
}

struct SHADER_PARAMS
{
    GLuint program_;
    GLuint light0_;
    GLuint material_diffuse_;
    GLuint material_ambient_;
    GLuint material_specular_;

    GLuint matrix_projection_;
    GLuint matrix_view_;
}

struct TEAPOT_MATERIALS
{
    float[3] diffuse_color;
    float[4] specular_color;
    float[3] ambient_color;
}

struct TeapotRenderer
{
private:
    int num_indices_;
    int num_vertices_;
    GLuint ibo_;
    GLuint vbo_;

    SHADER_PARAMS shader_param_;
    bool LoadShaders( SHADER_PARAMS* params, const(char)* strVsh, const(char)* strFsh )
    {
        GLuint program;
        GLuint vert_shader, frag_shader;

        // Create shader program
        program = glCreateProgram();
        LOGI( "Created Shader %d", program );

        // Create and compile vertex shader
        if( !CompileShader( &vert_shader, GL_VERTEX_SHADER, strVsh ) )
        {
            LOGI( "Failed to compile vertex shader" );
            glDeleteProgram( program );
            return false;
        }

        // Create and compile fragment shader
        if( !CompileShader( &frag_shader, GL_FRAGMENT_SHADER, strFsh ) )
        {
            LOGI( "Failed to compile fragment shader" );
            glDeleteProgram( program );
            return false;
        }

        // Attach vertex shader to program
        glAttachShader( program, vert_shader );

        // Attach fragment shader to program
        glAttachShader( program, frag_shader );

        // Bind attribute locations
        // this needs to be done prior to linking
        glBindAttribLocation( program, SHADER_ATTRIBUTES.ATTRIB_VERTEX, "myVertex" );
        glBindAttribLocation( program, SHADER_ATTRIBUTES.ATTRIB_NORMAL, "myNormal" );
        glBindAttribLocation( program, SHADER_ATTRIBUTES.ATTRIB_UV, "myUV" );

        // Link program
        if( !LinkProgram( program ) )
        {
            LOGI( "Failed to link program: %d", program );

            if( vert_shader )
            {
                glDeleteShader( vert_shader );
                vert_shader = 0;
            }
            if( frag_shader )
            {
                glDeleteShader( frag_shader );
                frag_shader = 0;
            }
            if( program )
            {
                glDeleteProgram( program );
            }

            return false;
        }

        // Get uniform locations
        params.matrix_projection_ = glGetUniformLocation( program, "uPMatrix" );
        params.matrix_view_ = glGetUniformLocation( program, "uMVMatrix" );

        params.light0_ = glGetUniformLocation( program, "vLight0" );
        params.material_diffuse_ = glGetUniformLocation( program, "vMaterialDiffuse" );
        params.material_ambient_ = glGetUniformLocation( program, "vMaterialAmbient" );
        params.material_specular_ = glGetUniformLocation( program, "vMaterialSpecular" );

        // Release vertex and fragment shaders
        if( vert_shader )
            glDeleteShader( vert_shader );
        if( frag_shader )
            glDeleteShader( frag_shader );

        params.program_ = program;
        return true;
    }

    float[4][4] mat_projection_;
    float[4][4] mat_view_;
    float[4][4] mat_model_;

    TapCamera* camera_;

    float[4][4] matrixMultiply(float[4][4] first, float[4][4] second)
    {
        float[4][4] result;
        foreach( i; 0 .. 4)
        {
            foreach( k; 0 .. 4)
            {
                result[i][k] = first[i][0] * second[0][k] + first[i][1] * second[1][k] + first[i][2] * second[2][k] + first[i][3] * second[3][k];
            }
        }
        return result;
    }

public:
    ~this()
    {
        Unload();
    }

    void Init()
    {
        import std.math : PI;

        //Settings
        glFrontFace( GL_CCW );

        //Load shader
        LoadShaders( &shader_param_, "Shaders/VS_ShaderPlain.vsh",
                "Shaders/ShaderPlain.fsh" );

        //Create Index buffer
        num_indices_ = teapotIndices.length;
        glGenBuffers( 1, &ibo_ );
        glBindBuffer( GL_ELEMENT_ARRAY_BUFFER, ibo_ );
        glBufferData( GL_ELEMENT_ARRAY_BUFFER, num_indices_ * ushort.sizeof,
                      teapotIndices.ptr, GL_STATIC_DRAW );
        glBindBuffer( GL_ELEMENT_ARRAY_BUFFER, 0 );

        //Create VBO
        num_vertices_ = teapotPositions.length / 3;
        int iStride = TEAPOT_VERTEX.sizeof;
        int iIndex = 0;
        TEAPOT_VERTEX[] p = new TEAPOT_VERTEX[num_vertices_];
        for( int i = 0; i < num_vertices_; ++i )
        {
            p[i].pos[0] = teapotPositions[iIndex];
            p[i].pos[1] = teapotPositions[iIndex + 1];
            p[i].pos[2] = teapotPositions[iIndex + 2];

            p[i].normal[0] = teapotNormals[iIndex];
            p[i].normal[1] = teapotNormals[iIndex + 1];
            p[i].normal[2] = teapotNormals[iIndex + 2];
            iIndex += 3;
        }
        glGenBuffers( 1, &vbo_ );
        glBindBuffer( GL_ARRAY_BUFFER, vbo_ );
        glBufferData( GL_ARRAY_BUFFER, iStride * num_vertices_, p.ptr, GL_STATIC_DRAW );
        glBindBuffer( GL_ARRAY_BUFFER, 0 );

        destroy(p);

        UpdateViewport();
        mat_model_  = [[ 1.0f, 0.0f, 0.0f, 0.0f ], [ 0.0f, 1.0f, 0.0f, 0.0f ],
                       [ 0.0f, 0.0f, 1.0f, -15.0f ], [ 0.0f, 0.0f, 0.0f, 1.0f ]];

        float[4][4] mat  = [[ 1.0f, 0.0f, 0.0f, 0.0f ],
                            [ 0.0f, cosf(PI/3), sinf(PI/3), 0.0f ],
                            [ 0.0f, -sinf(PI/3), cosf(PI/3), 0.0f ],
                            [ 0.0f, 0.0f, 0.0f, 1.0f ]];
        mat_model_ = matrixMultiply(mat, mat_model_);
    }

    void Render()
    {
        //
        // Feed Projection and Model View matrices to the shaders
        float[4][4] mat_vp = matrixMultiply(mat_projection_, mat_view_);

        // Bind the VBO
        glBindBuffer( GL_ARRAY_BUFFER, vbo_ );

        int iStride = TEAPOT_VERTEX.sizeof;
        // Pass the vertex data
        glVertexAttribPointer( SHADER_ATTRIBUTES.ATTRIB_VERTEX, 3, GL_FLOAT,
                               GL_FALSE, iStride, BUFFER_OFFSET( 0 ) );
        glEnableVertexAttribArray( SHADER_ATTRIBUTES.ATTRIB_VERTEX );

        glVertexAttribPointer( SHADER_ATTRIBUTES.ATTRIB_NORMAL, 3, GL_FLOAT,
                               GL_FALSE, iStride, BUFFER_OFFSET( 3 * GLfloat.sizeof ) );
        glEnableVertexAttribArray( SHADER_ATTRIBUTES.ATTRIB_NORMAL );

        // Bind the IB
        glBindBuffer( GL_ELEMENT_ARRAY_BUFFER, ibo_ );

        glUseProgram( shader_param_.program_ );

        TEAPOT_MATERIALS material = { [ 1.0f, 0.5f, 0.5f ], [ 1.0f, 1.0f, 1.0f, 10.0f ],
                                      [0.1f, 0.1f, 0.1f ], };

        //Update uniforms
        glUniform4f( shader_param_.material_diffuse_, material.diffuse_color[0],
                material.diffuse_color[1], material.diffuse_color[2], 1.0f );

        glUniform4f( shader_param_.material_specular_, material.specular_color[0],
                material.specular_color[1], material.specular_color[2],
                material.specular_color[3] );
        //
        //using glUniform3fv here was troublesome
        //
        glUniform3f( shader_param_.material_ambient_, material.ambient_color[0],
                material.ambient_color[1], material.ambient_color[2] );

        void transposeMatrix4(ref float[4][4] matrix)
        {
            void swapPair(ref float[4][4] mat, uint x, uint y)
            {
                float temp = mat[x][y];
                mat[x][y] = mat[y][x];
                mat[y][x] = temp;
            }
            swapPair(matrix, 0, 1);
            swapPair(matrix, 0, 2);
            swapPair(matrix, 0, 3);
            swapPair(matrix, 1, 3);
            swapPair(matrix, 2, 1);
            swapPair(matrix, 2, 3);
        }

        transposeMatrix4(mat_vp);
        glUniformMatrix4fv( shader_param_.matrix_projection_, 1, GL_FALSE,
                            cast(const(GLfloat)*) mat_vp.ptr );
        transposeMatrix4(mat_vp);
        transposeMatrix4(mat_view_);
        glUniformMatrix4fv( shader_param_.matrix_view_, 1, GL_FALSE,
                            cast(const(GLfloat)*) mat_view_.ptr );
        transposeMatrix4(mat_view_);
        glUniform3f( shader_param_.light0_, 100.0f, -200.0f, -600.0f );

        glDrawElements( GL_TRIANGLES, num_indices_, GL_UNSIGNED_SHORT, BUFFER_OFFSET(0) );

        glBindBuffer( GL_ARRAY_BUFFER, 0 );
        glBindBuffer( GL_ELEMENT_ARRAY_BUFFER, 0 );
    }

    void Update( float dTime )
    {
        const float CAM_Z = 700.0f;

        mat_view_  = [[ 1.0f, 0.0f, 0.0f, 0.0f ], [ 0.0f, 1.0f, 0.0f, 0.0f ],
                      [ 0.0f, 0.0f, 1.0f, -CAM_Z ], [ 0.0f, 0.0f, 0.0f, 1.0f ]];

        if( camera_ )
        {
            camera_.Update();
            mat_view_ = matrixMultiply(
                        matrixMultiply(camera_.GetTransformMatrix(), mat_view_),
                        matrixMultiply(camera_.GetRotationMatrix(), mat_model_)
                        );
        }
        else
        {
            mat_view_ = matrixMultiply(mat_view_, mat_model_);
        }
    }

    bool Bind( TapCamera* camera )
    {
        camera_ = camera;
        return true;
    }

    void Unload()
    {
        if( vbo_ )
        {
            glDeleteBuffers( 1, &vbo_ );
            vbo_ = 0;
        }

        if( ibo_ )
        {
            glDeleteBuffers( 1, &ibo_ );
            ibo_ = 0;
        }

        if( shader_param_.program_ )
        {
            glDeleteProgram( shader_param_.program_ );
            shader_param_.program_ = 0;
        }
    }

    void UpdateViewport()
    {
        //Init Projection matrices
        int[4] viewport;
        glGetIntegerv( GL_VIEWPORT, viewport.ptr );
        float fAspect = cast(float) viewport[2] / cast(float) viewport[3];

        const float CAM_NEAR = 5.0f;
        const float CAM_FAR = 10_000.0f;
        bool bRotate = false;
        mat_projection_  = [[ 2.0f*CAM_NEAR/fAspect, 0.0f, 0.0f, 0.0f ],
                            [ 0.0f, 2.0f*CAM_NEAR/1.0f, 0.0f, 0.0f ],
                            [ 0.0f, 0.0f, (CAM_FAR + CAM_NEAR)/(CAM_NEAR - CAM_FAR), 2.0f*CAM_FAR*CAM_NEAR/(CAM_NEAR - CAM_FAR) ],
                            [ 0.0f, 0.0f, -1.0f, 0.0f ]];
    }
}
