require 'formula'

class Macgpg2 < Formula
  url 'ftp://ftp.gnupg.org/gcrypt/gnupg/gnupg-2.0.22.tar.bz2'
  homepage 'http://www.gnupg.org/'
  sha1 '9ba9ee288e9bf813e0f1e25cbe06b58d3072d8b8'
  
  depends_on 'libiconv'
  depends_on 'gettext'
  depends_on 'pth'
  depends_on 'libusb-compat'
  depends_on 'libgpg-error'
  depends_on 'libassuan'
  depends_on 'libgcrypt'
  depends_on 'libksba'
  depends_on 'zlib'
  depends_on 'pinentry'
  depends_on 'adns'
  
  keep_install_names true
  
  def patches
    { :p1 => [DATA],
      :p0 => ["#{HOMEBREW_PREFIX}/Library/Formula/Patches/IDEA/gnupg2.patch",
              "#{HOMEBREW_PREFIX}/Library/Formula/Patches/gnupg2/cacheid.patch",
              "#{HOMEBREW_PREFIX}/Library/Formula/Patches/gnupg2/keysize.patch",
              "#{HOMEBREW_PREFIX}/Library/Formula/Patches/gnupg2/socket.patch",
              "#{HOMEBREW_PREFIX}/Library/Formula/Patches/gnupg2/MacGPG2VersionString.patch",
              "#{HOMEBREW_PREFIX}/Library/Formula/Patches/gnupg2/options.skel.patch"] }
  end

  def install
    (var+'run').mkpath
    ENV.universal_binary if ARGV.build_universal?
    # Make sure that deployment target is 10.6+ so the lib works
    # on 10.6 and up not only on host system os x version.
    ENV.macosxsdk("10.6")
    
    ENV.build_32_bit
    
    # so we don't use Clang's internal stdint.h
    ENV['gl_cv_absolute_stdint_h'] = "#{MacOS.sdk_path}/usr/include/stdint.h"
    
    # It's necessary to add the -rpath to the LDFLAGS, otherwise
    # programs can't link to libraries using @rpath.
    ENV.prepend 'LDFLAGS', '-headerpad_max_install_names'
    ENV.prepend 'LDFLAGS', "-Wl,-rpath,@loader_path/../lib -Wl,-rpath,#{HOMEBREW_PREFIX}/lib"
    # Set the flags so the build uses our 10.6 libcurl instead of the OS X one,
    # otherwise MacGPG2 won't work properly on 10.6
    ENV.prepend 'LDFLAGS', "-L#{HOMEBREW_PREFIX}/curl-10.6/lib -lcurl"
    ENV['_libcurl_config'] = "#{HOMEBREW_PREFIX}/curl-10.6/bin/curl-config"
    ENV.append 'LDFLAGS', '-lresolv'
        
    final_install_directory = "/usr/local/MacGPG2"
    
    inreplace 'g10/keygen.c', 'max=4096', 'max=8192'
    
    system "./configure", "--prefix=#{prefix}",
                          "--disable-maintainer-mode",
                          "--disable-dependency-tracking",
                          "--enable-symcryptrun",
                          "--enable-standard-socket",
                          "--with-pinentry-pgm=#{final_install_directory}/libexec/pinentry-mac.app/Contents/MacOS/pinentry-mac",
                          "--with-agent-pgm=#{final_install_directory}/bin/gpg-agent",
                          "--with-scdaemon-pgm=#{final_install_directory}/libexec/scdaemon",
                          "--disable-gpgsm", # We don't include it in the installation, no need to build it.
                          "--with-dirmngr-pgm=#{final_install_directory}/bin/dirmngr", # It's not possible to disable it, so at least have the right path. 
                          "--with-libgpg-error-prefix=#{HOMEBREW_PREFIX}",
                          "--with-libgcrypt-prefix=#{HOMEBREW_PREFIX}",
                          "--with-libassuan-prefix=#{HOMEBREW_PREFIX}",
                          "--with-ksba-prefix=#{HOMEBREW_PREFIX}",
                          "--with-pth-prefix=#{HOMEBREW_PREFIX}",
                          "--with-zlib=#{HOMEBREW_PREFIX}",
                          "--with-libiconv-prefix=#{HOMEBREW_PREFIX}",
                          "--with-libintl-prefix=#{HOMEBREW_PREFIX}",
                          "--with-libcurl=#{HOMEBREW_PREFIX}/curl-10.6",
                          "--with-adns=#{HOMEBREW_PREFIX}"
    
    system "make"
    system "make check"
    system "make install"
    
    # Homebrew doesn't like touching libexec for some reason.
    # That's why we have to manually symlink.
    # Also uninstalling wouldn't take care of libexec, so I've pachted keg.rb
    Pathname.new("#{HOMEBREW_PREFIX}/libexec/gnupg-pcsc-wrapper").make_relative_symlink("#{prefix}/libexec/gnupg-pcsc-wrapper")
    Pathname.new("#{HOMEBREW_PREFIX}/libexec/gpg2keys_curl").make_relative_symlink("#{prefix}/libexec/gpg2keys_curl")
    Pathname.new("#{HOMEBREW_PREFIX}/libexec/gpg2keys_finger").make_relative_symlink("#{prefix}/libexec/gpg2keys_finger")
    Pathname.new("#{HOMEBREW_PREFIX}/libexec/gpg2keys_hkp").make_relative_symlink("#{prefix}/libexec/gpg2keys_hkp")
    Pathname.new("#{HOMEBREW_PREFIX}/libexec/gpg2keys_ldap").make_relative_symlink("#{prefix}/libexec/gpg2keys_ldap")
    Pathname.new("#{HOMEBREW_PREFIX}/libexec/scdaemon").make_relative_symlink("#{prefix}/libexec/scdaemon")
  end
end

__END__
# fix runtime data location
# http://git.gnupg.org/cgi-bin/gitweb.cgi?p=gnupg.git;a=commitdiff;h=c3f08dc
diff --git a/common/homedir.c b/common/homedir.c
index 5f2e31e..d797b68 100644
--- a/common/homedir.c
+++ b/common/homedir.c
@@ -365,7 +365,7 @@ dirmngr_socket_name (void)
     }
   return name;
 #else /*!HAVE_W32_SYSTEM*/
-  return "/var/run/dirmngr/socket";
+  return "/usr/local/MacGPG2/var/run/dirmngr/socket";
 #endif /*!HAVE_W32_SYSTEM*/
 }
 
diff --git a/common/homedir.c b/common/homedir.c
index bdce3d1..4cc4ab9 100644
--- a/common/homedir.c
+++ b/common/homedir.c
@@ -338,6 +338,37 @@ gnupg_localedir (void)
     }
   return name;
 #else /*!HAVE_W32_SYSTEM*/
+  char path[3096];
+  uint32_t size = sizeof(path);
+  if (_NSGetExecutablePath(path, &size) != 0)
+      printf("buffer too small to get executable path; need size %u\n", size);
+  
+  char actualpath [PATH_MAX];
+  char *ptr;
+  ptr = realpath(path, actualpath);
+  // Find the last / in the path. 
+  char *c = strrchr(ptr, (int)'/');
+  // Set the post to the / in the path.
+  int pos = c - ptr;
+  // Only copy the without the executable name.
+  char *dirname_path = malloc((pos * sizeof(char)) + 1);
+  memcpy(dirname_path, ptr, pos);
+  dirname_path[pos+1] = '\0';
+  /* Check if ../share/locale exists. If so, use that path
+   * otherwise try LOCALEDIR.
+   */
+  char *locale_path = NULL;
+  asprintf(&locale_path, "%s/../share/locale", dirname_path);
+  // The path contains relative parts, so let's make them absolute.
+  char complete_path[PATH_MAX];
+  char *final_dir;
+  final_dir = realpath(locale_path, complete_path);
+  char *real_dir = complete_path == NULL ? final_dir : complete_path;
+  // Test if the locale dir exists.
+  struct stat s;
+  if(stat(real_dir, &s) == 0 && s.st_mode & S_IFDIR)
+      return real_dir;
+  // Not found, return the fixed localedir.
   return LOCALEDIR;
 #endif /*!HAVE_W32_SYSTEM*/
 }

diff --git a/common/homedir.c b/common/homedir.c
index 48f1e75..d7898d8 100644
--- a/common/homedir.c
+++ b/common/homedir.c
@@ -21,6 +21,11 @@
 #include <stdlib.h>
 #include <errno.h>
 #include <fcntl.h>
+#include <limits.h>
+#include <stdio.h>
+#include <stdint.h>
+#include <string.h>
+#include <sys/stat.h>
 
 #ifdef HAVE_W32_SYSTEM
 #include <shlobj.h>

diff --git a/common/i18n.c b/common/i18n.c
index db5ddf5..c34fcc7 100644
--- a/common/i18n.c
+++ b/common/i18n.c
@@ -37,7 +37,7 @@ i18n_init (void)
 #else
 # ifdef ENABLE_NLS
   setlocale (LC_ALL, "" );
-  bindtextdomain (PACKAGE_GT, LOCALEDIR);
+  bindtextdomain (PACKAGE_GT, gnupg_localedir ());
   textdomain (PACKAGE_GT);
 # endif
 #endif

diff --git a/common/homedir.c b/common/homedir.c
index e40f18d..f587b62 100644
--- a/common/homedir.c
+++ b/common/homedir.c
@@ -282,7 +282,7 @@ gnupg_libexecdir (void)
 #ifdef HAVE_W32_SYSTEM
   return w32_rootdir ();
 #else /*!HAVE_W32_SYSTEM*/
-  return GNUPG_LIBEXECDIR;
+  return "/usr/local/MacGPG2/libexec";
 #endif /*!HAVE_W32_SYSTEM*/
 }

diff --git a/common/homedir.c b/common/homedir.c
index efb45a6..f0c1508 100644
--- a/common/homedir.c
+++ b/common/homedir.c
@@ -261,7 +261,7 @@ gnupg_sysconfdir (void)
     }
   return name;
 #else /*!HAVE_W32_SYSTEM*/
-  return GNUPG_SYSCONFDIR;
+  return "/usr/local/MacGPG2/etc/gnupg";
 #endif /*!HAVE_W32_SYSTEM*/
 }
 
@@ -272,7 +272,7 @@ gnupg_bindir (void)
 #ifdef HAVE_W32_SYSTEM
   return w32_rootdir ();
 #else /*!HAVE_W32_SYSTEM*/
-  return GNUPG_BINDIR;
+  return "/usr/local/MacGPG2/bin";
 #endif /*!HAVE_W32_SYSTEM*/
 }
 
@@ -305,7 +305,7 @@ gnupg_libdir (void)
     }
   return name;
 #else /*!HAVE_W32_SYSTEM*/
-  return GNUPG_LIBDIR;
+  return "/usr/local/MacGPG2/lib";
 #endif /*!HAVE_W32_SYSTEM*/
 }
 
@@ -325,7 +325,7 @@ gnupg_datadir (void)
     }
   return name;
 #else /*!HAVE_W32_SYSTEM*/
-  return GNUPG_DATADIR;
+  return "/usr/local/MacGPG2/share/gnupg";
 #endif /*!HAVE_W32_SYSTEM*/
 }

diff --git a/scd/Makefile.in b/scd/Makefile.in
index d065933..07d922d 100644
--- a/scd/Makefile.in
+++ b/scd/Makefile.in
@@ -92,7 +92,7 @@ host_triplet = @host@
 DIST_COMMON = $(srcdir)/Makefile.am $(srcdir)/Makefile.in \
 	$(top_srcdir)/am/cmacros.am
 @HAVE_DOSISH_SYSTEM_FALSE@am__append_1 = -DGNUPG_BINDIR="\"$(bindir)\""            \
-@HAVE_DOSISH_SYSTEM_FALSE@               -DGNUPG_LIBEXECDIR="\"$(libexecdir)\""    \
+@HAVE_DOSISH_SYSTEM_FALSE@               -DGNUPG_LIBEXECDIR="\"/usr/local/MacGPG2/libexec\""    \
 @HAVE_DOSISH_SYSTEM_FALSE@               -DGNUPG_LIBDIR="\"$(libdir)/@PACKAGE@\""  \
 @HAVE_DOSISH_SYSTEM_FALSE@               -DGNUPG_DATADIR="\"$(datadir)/@PACKAGE@\"" \
 @HAVE_DOSISH_SYSTEM_FALSE@               -DGNUPG_SYSCONFDIR="\"$(sysconfdir)/@PACKAGE@\""
