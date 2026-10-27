Description: FreeBSD platform integration (patch-hw_xfree86_common_xf86str.h).
Origin: FreeBSD ports, https://raw.githubusercontent.com/freebsd/freebsd-ports/0433da2a516ae48cce1e2d59e97df4ebbef43afe/x11-servers/xorg-server/files/patch-hw_xfree86_common_xf86str.h
Forwarded: not-needed (BSD platform integration)

--- a/hw/xfree86/common/xf86str.h
+++ b/hw/xfree86/common/xf86str.h
@@ -249,7 +249,7 @@ typedef struct _DriverRec {
  */
 
 /* Tolerate prior #include <linux/input.h> */
-#if defined(__linux__)
+#if defined(__linux__) || defined(__FreeBSD__)
 #undef BUS_NONE
 #undef BUS_PCI
 #undef BUS_SBUS
