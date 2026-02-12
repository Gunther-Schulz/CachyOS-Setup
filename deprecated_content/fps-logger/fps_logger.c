/*
 * Minimal GLX FPS logger: prints timestamp and FPS every 0.1 seconds.
 * Build: cc -o fps_logger fps_logger.c -lGL -lX11
 * Run: ./fps_logger 2>&1 | tee -a ~/fps.log
 */
#define _POSIX_C_SOURCE 199309L
#include <X11/Xlib.h>
#include <X11/Xatom.h>
#include <X11/keysym.h>
#include <GL/gl.h>
#include <GL/glx.h>
#include <stdio.h>
#include <time.h>
#include <unistd.h>
#include <signal.h>

static volatile int running = 1;
static void on_sig(int sig) { (void)sig; running = 0; }

int main(void) {
  Display *dpy = XOpenDisplay(NULL);
  if (!dpy) { fprintf(stderr, "XOpenDisplay failed\n"); return 1; }

  int attrib[] = { GLX_RGBA, GLX_DEPTH_SIZE, 16, GLX_DOUBLEBUFFER, None };
  XVisualInfo *vi = glXChooseVisual(dpy, 0, attrib);
  if (!vi) { fprintf(stderr, "glXChooseVisual failed\n"); return 1; }

  Colormap cmap = XCreateColormap(dpy, RootWindow(dpy, vi->screen), vi->visual, AllocNone);
  XSetWindowAttributes swa = { .colormap = cmap, .event_mask = ExposureMask | KeyPressMask };
  Window win = XCreateWindow(dpy, RootWindow(dpy, vi->screen), 0, 0, 64, 64, 0,
                             vi->depth, InputOutput, vi->visual, CWColormap | CWEventMask, &swa);
  /* Keep window above others so it isn't throttled when not focused */
  Atom net_wm_state = XInternAtom(dpy, "_NET_WM_STATE", False);
  Atom above = XInternAtom(dpy, "_NET_WM_STATE_ABOVE", False);
  if (net_wm_state != None && above != None) {
    XChangeProperty(dpy, win, net_wm_state, XA_ATOM, 32, PropModeReplace,
                    (unsigned char *)&above, 1);
  }
  XMapWindow(dpy, win);
  XStoreName(dpy, win, "fps_logger");

  GLXContext ctx = glXCreateContext(dpy, vi, NULL, True);
  glXMakeCurrent(dpy, win, ctx);

  signal(SIGINT, on_sig);
  signal(SIGTERM, on_sig);

  struct timespec t0, t1;
  clock_gettime(CLOCK_MONOTONIC, &t0);
  unsigned long frames = 0;
  const double interval = 0.1; /* 10 Hz */

  while (running) {
    glXSwapBuffers(dpy, win);
    frames++;
    clock_gettime(CLOCK_MONOTONIC, &t1);
    double elapsed = (t1.tv_sec - t0.tv_sec) + (t1.tv_nsec - t0.tv_nsec) / 1e9;
    if (elapsed >= interval) {
      double fps = frames / elapsed;
      if (fps < 50.0)
        printf("%.1f\n", fps);
      fflush(stdout);
      t0 = t1;
      frames = 0;
    }
  }

  glXMakeCurrent(dpy, None, NULL);
  glXDestroyContext(dpy, ctx);
  XDestroyWindow(dpy, win);
  XCloseDisplay(dpy);
  return 0;
}
