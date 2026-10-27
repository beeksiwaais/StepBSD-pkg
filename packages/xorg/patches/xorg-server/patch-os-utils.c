Description: FreeBSD platform integration (patch-os-utils.c).
Origin: FreeBSD ports, https://raw.githubusercontent.com/freebsd/freebsd-ports/0433da2a516ae48cce1e2d59e97df4ebbef43afe/x11-servers/xorg-server/files/patch-os-utils.c
Forwarded: not-needed (BSD platform integration)

--- a/os/utils.c
+++ b/os/utils.c
@@ -471,11 +471,11 @@ GetTimeInMillis(void)
     struct timespec tp;
 
     if (!clockid) {
-#ifdef CLOCK_MONOTONIC_COARSE
-        if (clock_getres(CLOCK_MONOTONIC_COARSE, &tp) == 0 &&
+#ifdef CLOCK_MONOTONIC_FAST
+        if (clock_getres(CLOCK_MONOTONIC_FAST, &tp) == 0 &&
             (tp.tv_nsec / 1000) <= 1000 &&
-            clock_gettime(CLOCK_MONOTONIC_COARSE, &tp) == 0)
-            clockid = CLOCK_MONOTONIC_COARSE;
+            clock_gettime(CLOCK_MONOTONIC_FAST, &tp) == 0)
+            clockid = CLOCK_MONOTONIC_FAST;
         else
 #endif
         if (clock_gettime(CLOCK_MONOTONIC, &tp) == 0)
