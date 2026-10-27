Description: FreeBSD input integration (patch-src__kbd.c).
Origin: FreeBSD ports, https://raw.githubusercontent.com/freebsd/freebsd-ports/0433da2a516ae48cce1e2d59e97df4ebbef43afe/x11-drivers/xf86-input-keyboard/files/patch-src__kbd.c
 Adapted by StepBSD to the upstream 1.9.0 context (input-thread conditional).
Forwarded: not-needed

--- a/src/kbd.c
+++ b/src/kbd.c
@@ -24,6 +24,7 @@
 #include <X11/Xproto.h>
 
 #include "xf86.h"
+#include "xf86Priv.h"
 #include "atKeynames.h"
 #include "xf86Privstr.h"
 
@@ -382,6 +383,9 @@
     }
     pKbd->KbdOff(pInfo, what);
     device->public.on = FALSE;
+    /* Non-console devices must be closed before the next login. */
+    if (pInfo->fd != xf86Info.consoleFd)
+        close(pInfo->fd);
     break;
 
   default:
