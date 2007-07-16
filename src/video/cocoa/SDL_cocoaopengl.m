/*
    SDL - Simple DirectMedia Layer
    Copyright (C) 1997-2006 Sam Lantinga

    This library is free software; you can redistribute it and/or
    modify it under the terms of the GNU Lesser General Public
    License as published by the Free Software Foundation; either
    version 2.1 of the License, or (at your option) any later version.

    This library is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
    Lesser General Public License for more details.

    You should have received a copy of the GNU Lesser General Public
    License along with this library; if not, write to the Free Software
    Foundation, Inc., 51 Franklin St, Fifth Floor, Boston, MA  02110-1301  USA

    Sam Lantinga
    slouken@libsdl.org
*/
#include "SDL_config.h"

#include "SDL_cocoavideo.h"

/* NSOpenGL implementation of SDL OpenGL support */

#if SDL_VIDEO_OPENGL_CGL
#include <OpenGL/CGLTypes.h>

#include "SDL_loadso.h"
#include "SDL_opengl.h"


#define DEFAULT_OPENGL  "/System/Library/Frameworks/OpenGL.framework/Libraries/libGL.dylib"

/* This is implemented in Mac OS X 10.3 and above */
#if MAC_OS_X_VERSION_MAX_ALLOWED < MAC_OS_X_VERSION_10_3
@implementation NSOpenGLContext(CGLContextAccess)
- (CGLContextObj)CGLContextObj;
{
    return _contextAuxiliary;
}
@end
#endif /* < 10.3 */

int
Cocoa_GL_LoadLibrary(_THIS, const char *path)
{
    if (_this->gl_config.driver_loaded) {
        if (path) {
            SDL_SetError("OpenGL library already loaded");
            return -1;
        } else {
            ++_this->gl_config.driver_loaded;
            return 0;
        }
    }
    if (path == NULL) {
        path = SDL_getenv("SDL_OPENGL_LIBRARY");
    }
    if (path == NULL) {
        path = DEFAULT_OPENGL;
    }
    _this->gl_config.dll_handle = SDL_LoadObject(path);
    if (!_this->gl_config.dll_handle) {
        return -1;
    }
    SDL_strlcpy(_this->gl_config.driver_path, path,
                SDL_arraysize(_this->gl_config.driver_path));
    _this->gl_config.driver_loaded = 1;
    return 0;
}

void *
Cocoa_GL_GetProcAddress(_THIS, const char *proc)
{
    return SDL_LoadFunction(_this->gl_config.dll_handle, proc);
}

static void
Cocoa_GL_UnloadLibrary(_THIS)
{
    if (_this->gl_config.driver_loaded > 0) {
        if (--_this->gl_config.driver_loaded > 0) {
            return;
        }
        SDL_UnloadObject(_this->gl_config.dll_handle);
        _this->gl_config.dll_handle = NULL;
    }
}

static int
Cocoa_GL_Initialize(_THIS)
{
    if (_this->gl_data) {
        ++_this->gl_data->initialized;
        return 0;
    }

    _this->gl_data =
        (struct SDL_GLDriverData *) SDL_calloc(1,
                                               sizeof(struct
                                                      SDL_GLDriverData));
    if (!_this->gl_data) {
        SDL_OutOfMemory();
        return -1;
    }
    _this->gl_data->initialized = 1;

    if (Cocoa_GL_LoadLibrary(_this, NULL) < 0) {
        return -1;
    }
    return 0;
}

static void
Cocoa_GL_Shutdown(_THIS)
{
    if (!_this->gl_data || (--_this->gl_data->initialized > 0)) {
        return;
    }

    Cocoa_GL_UnloadLibrary(_this);

    SDL_free(_this->gl_data);
    _this->gl_data = NULL;
}

int
Cocoa_GL_SetupWindow(_THIS, SDL_Window * window)
{
    if (Cocoa_GL_Initialize(_this) < 0) {
        return -1;
    }
    return 0;
}

void
Cocoa_GL_CleanupWindow(_THIS, SDL_Window * window)
{
    Cocoa_GL_Shutdown(_this);
}

SDL_GLContext
Cocoa_GL_CreateContext(_THIS, SDL_Window * window)
{
    NSAutoreleasePool *pool;
    SDL_VideoDisplay *display = SDL_GetDisplayFromWindow(window);
    SDL_DisplayData *displaydata = (SDL_DisplayData *)display->driverdata;
    NSOpenGLPixelFormatAttribute attr[32];
    NSOpenGLPixelFormat *fmt;
    NSOpenGLContext *context;
    int i = 0;

    pool = [[NSAutoreleasePool alloc] init];

    if (window->flags & SDL_WINDOW_FULLSCREEN) {
        attr[i++] = NSOpenGLPFAFullScreen;
    }

    attr[i++] = NSOpenGLPFAColorSize;
    attr[i++] = SDL_BYTESPERPIXEL(display->current_mode.format)*8;

    attr[i++] = NSOpenGLPFADepthSize;
    attr[i++] = _this->gl_config.depth_size;

    if (_this->gl_config.double_buffer) {
        attr[i++] = NSOpenGLPFADoubleBuffer;
    }

    if (_this->gl_config.stereo) {
        attr[i++] = NSOpenGLPFAStereo;
    }

    if (_this->gl_config.stencil_size) {
        attr[i++] = NSOpenGLPFAStencilSize;
        attr[i++] = _this->gl_config.stencil_size;
    }

    if ((_this->gl_config.accum_red_size +
         _this->gl_config.accum_green_size +
         _this->gl_config.accum_blue_size +
         _this->gl_config.accum_alpha_size) > 0) {
        attr[i++] = NSOpenGLPFAAccumSize;
        attr[i++] = _this->gl_config.accum_red_size + _this->gl_config.accum_green_size + _this->gl_config.accum_blue_size + _this->gl_config.accum_alpha_size;
    }

    if (_this->gl_config.multisamplebuffers) {
        attr[i++] = NSOpenGLPFASampleBuffers;
        attr[i++] = _this->gl_config.multisamplebuffers;
    }

    if (_this->gl_config.multisamplesamples) {
        attr[i++] = NSOpenGLPFASamples;
        attr[i++] = _this->gl_config.multisamplesamples;
        attr[i++] = NSOpenGLPFANoRecovery;
    }

    if (_this->gl_config.accelerated > 0) {
        attr[i++] = NSOpenGLPFAAccelerated;
    }

    attr[i++] = NSOpenGLPFAScreenMask;
    attr[i++] = CGDisplayIDToOpenGLDisplayMask(displaydata->display);
    attr[i] = 0;

    fmt = [[NSOpenGLPixelFormat alloc] initWithAttributes:attr];
    if (fmt == nil) {
        SDL_SetError ("Failed creating OpenGL pixel format");
        [pool release];
        return NULL;
    }

    context = [[NSOpenGLContext alloc] initWithFormat:fmt shareContext:nil];

    [fmt release];

    if (context == nil) {
        SDL_SetError ("Failed creating OpenGL context");
        [pool release];
        return NULL;
    }

    /*
     * Wisdom from Apple engineer in reference to UT2003's OpenGL performance:
     *  "You are blowing a couple of the internal OpenGL function caches. This
     *  appears to be happening in the VAO case.  You can tell OpenGL to up
     *  the cache size by issuing the following calls right after you create
     *  the OpenGL context.  The default cache size is 16."    --ryan.
     */

    #ifndef GLI_ARRAY_FUNC_CACHE_MAX
    #define GLI_ARRAY_FUNC_CACHE_MAX 284
    #endif

    #ifndef GLI_SUBMIT_FUNC_CACHE_MAX
    #define GLI_SUBMIT_FUNC_CACHE_MAX 280
    #endif

    {
        long cache_max = 64;
        CGLContextObj ctx = [context CGLContextObj];
        CGLSetParameter (ctx, GLI_SUBMIT_FUNC_CACHE_MAX, &cache_max);
        CGLSetParameter (ctx, GLI_ARRAY_FUNC_CACHE_MAX, &cache_max);
    }

    /* End Wisdom from Apple Engineer section. --ryan. */

    [pool release];

    if ( Cocoa_GL_MakeCurrent(_this, window, context) < 0 ) {
        Cocoa_GL_DeleteContext(_this, context);
        return NULL;
    }

    return context;
}

int
Cocoa_GL_MakeCurrent(_THIS, SDL_Window * window, SDL_GLContext context)
{
    NSAutoreleasePool *pool;

    pool = [[NSAutoreleasePool alloc] init];

    if (context) {
        SDL_WindowData *windowdata = (SDL_WindowData *)window->driverdata;
        NSOpenGLContext *nscontext = (NSOpenGLContext *)context;

        if (window->flags & SDL_WINDOW_FULLSCREEN) {
            [nscontext setFullScreen];
        } else {
            [nscontext setView:[windowdata->window contentView]];
            [nscontext update];
        }
        [nscontext makeCurrentContext];
    } else {
        [NSOpenGLContext clearCurrentContext];
    }

    [pool release];
    return 0;
}

int
Cocoa_GL_SetSwapInterval(_THIS, int interval)
{
    NSAutoreleasePool *pool;
    NSOpenGLContext *nscontext;
    long value;
    int status;

    pool = [[NSAutoreleasePool alloc] init];

    nscontext = [NSOpenGLContext currentContext];
    if (nscontext != nil) {
        value = interval;
        [nscontext setValues:&value forParameter:NSOpenGLCPSwapInterval];
        status = 0;
    } else {
        SDL_SetError("No current OpenGL context");
        status = -1;
    }

    [pool release];
    return status;
}

int
Cocoa_GL_GetSwapInterval(_THIS)
{
    NSAutoreleasePool *pool;
    NSOpenGLContext *nscontext;
    long value;
    int status;

    pool = [[NSAutoreleasePool alloc] init];

    nscontext = [NSOpenGLContext currentContext];
    if (nscontext != nil) {
        [nscontext getValues:&value forParameter:NSOpenGLCPSwapInterval];
        status = (int)value;
    } else {
        SDL_SetError("No current OpenGL context");
        status = -1;
    }

    [pool release];
    return status;
}

void
Cocoa_GL_SwapWindow(_THIS, SDL_Window * window)
{
    NSAutoreleasePool *pool;
    NSOpenGLContext *nscontext;

    pool = [[NSAutoreleasePool alloc] init];

    /* FIXME: Do we need to get the context for the window? */
    nscontext = [NSOpenGLContext currentContext];
    if (nscontext != nil) {
        [nscontext flushBuffer];
    }

    [pool release];
}

void
Cocoa_GL_DeleteContext(_THIS, SDL_GLContext context)
{
    NSAutoreleasePool *pool;
    NSOpenGLContext *nscontext = (NSOpenGLContext *)context;

    pool = [[NSAutoreleasePool alloc] init];

    [nscontext clearDrawable];
    [nscontext release];

    [pool release];
}

#endif /* SDL_VIDEO_OPENGL_CGL */

/* vi: set ts=4 sw=4 expandtab: */