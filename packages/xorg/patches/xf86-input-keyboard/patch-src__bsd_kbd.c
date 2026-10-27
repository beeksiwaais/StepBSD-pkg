Description: FreeBSD input integration (patch-src__bsd_kbd.c).
Origin: FreeBSD ports, https://raw.githubusercontent.com/freebsd/freebsd-ports/0433da2a516ae48cce1e2d59e97df4ebbef43afe/x11-drivers/xf86-input-keyboard/files/patch-src__bsd_kbd.c
Forwarded: not-needed

Index: src/bsd_kbd.c
--- a/src/bsd_kbd.c
+++ b/src/bsd_kbd.c
@@ -237,6 +237,12 @@
 #endif
 	}
     }
+/*
+ * Switch keyboards which are not attached to console in RAW mode
+ */
+#if defined (SYSCONS_SUPPORT) || defined (PCVT_SUPPORT)
+	ioctl(pInfo->fd, KDSKBMODE, K_RAW);
+#endif
     return Success;
 }
 
