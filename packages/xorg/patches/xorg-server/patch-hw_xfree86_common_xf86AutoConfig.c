Description: FreeBSD platform integration (patch-hw_xfree86_common_xf86AutoConfig.c).
Origin: FreeBSD ports, https://raw.githubusercontent.com/freebsd/freebsd-ports/0433da2a516ae48cce1e2d59e97df4ebbef43afe/x11-servers/xorg-server/files/patch-hw_xfree86_common_xf86AutoConfig.c
Forwarded: not-needed (BSD platform integration)

* Try using modesetting driver before falling back to scfb or vesa
*
* Use our scfb driver as fallback instead of Linux's fbdev
*
--- a/hw/xfree86/common/xf86AutoConfig.c
+++ b/hw/xfree86/common/xf86AutoConfig.c
@@ -294,7 +294,7 @@ listPossibleVideoDrivers(XF86MatchedDrivers *md)
     xf86PciMatchDriver(md);
 #endif
 
-#if defined(__linux__)
+#if defined(__linux__) || defined(__FreeBSD__) || defined(__DragonFly__)
     xf86AddMatchedDriver(md, "modesetting");
 #endif
 
@@ -302,8 +302,10 @@ listPossibleVideoDrivers(XF86MatchedDrivers *md)
     /* Fallback to platform default frame buffer driver */
 #if !defined(__linux__) && defined(__sparc__)
     xf86AddMatchedDriver(md, "wsfb");
-#else
+#elif defined(__linux__)
     xf86AddMatchedDriver(md, "fbdev");
+#elif defined(__FreeBSD__)
+    xf86AddMatchedDriver(md, "scfb");
 #endif
 #endif                          /* !__sun */
 
