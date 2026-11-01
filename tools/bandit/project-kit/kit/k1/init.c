/*
 * K1: minimal init for the first kernel boot on the Lumia 1520.
 * - prints a status block on the framebuffer console (tty0) and /dev/kmsg;
 * - turns on the Android USB gadget as a CDC-ACM serial port and streams
 *   the kernel log over it (host: cat /dev/ttyACM0);
 * - refreshes the status every 5 seconds, never exits.
 * Statically linked, no other files needed in the ramdisk.
 */
#include <errno.h>
#include <fcntl.h>
#include <stdarg.h>
#include <stdio.h>
#include <string.h>
#include <sys/mount.h>
#include <sys/stat.h>
#include <sys/sysmacros.h>
#include <sys/wait.h>
#include <unistd.h>

static void out(const char *path, const char *fmt, ...)
{
	char buf[2048];
	va_list ap;
	int fd, n;

	va_start(ap, fmt);
	n = vsnprintf(buf, sizeof(buf), fmt, ap);
	va_end(ap);
	fd = open(path, O_WRONLY | O_NOCTTY);
	if (fd >= 0) {
		write(fd, buf, n);
		close(fd);
	}
}

static void say(const char *fmt, ...)
{
	char buf[1024];
	va_list ap;

	va_start(ap, fmt);
	vsnprintf(buf, sizeof(buf), fmt, ap);
	va_end(ap);
	out("/dev/tty0", "%s", buf);
	out("/dev/kmsg", "K1: %s", buf);
}

static void cat_to_tty(const char *path, int maxlines)
{
	char buf[4096];
	int fd = open(path, O_RDONLY), n, lines = 0;

	if (fd < 0)
		return;
	n = read(fd, buf, sizeof(buf) - 1);
	close(fd);
	if (n <= 0)
		return;
	buf[n] = 0;
	for (char *p = buf; *p && lines < maxlines; p++)
		if (*p == '\n' && ++lines == maxlines)
			p[1] = 0;
	out("/dev/tty0", "%s", buf);
}

static void node(const char *path, mode_t mode, int maj, int min)
{
	mknod(path, mode, makedev(maj, min));
}

static void usb_acm(void)
{
	const char *g = "/sys/class/android_usb/android0";
	char p[128];

	snprintf(p, sizeof(p), "%s/enable", g);
	out(p, "0");
	snprintf(p, sizeof(p), "%s/idVendor", g);
	out(p, "18d1");
	snprintf(p, sizeof(p), "%s/idProduct", g);
	out(p, "d00e");
	snprintf(p, sizeof(p), "%s/iManufacturer", g);
	out(p, "Nokia");
	snprintf(p, sizeof(p), "%s/iProduct", g);
	out(p, "Lumia 1520 K1");
	snprintf(p, sizeof(p), "%s/f_acm/acm_transports", g);
	out(p, "tty");
	snprintf(p, sizeof(p), "%s/functions", g);
	out(p, "acm");
	snprintf(p, sizeof(p), "%s/enable", g);
	out(p, "1");
}

/* Create /dev/<name> from /sys/class/tty/<name>/dev when devtmpfs is absent */
static void node_from_sysfs(const char *name)
{
	char p[96], buf[32];
	int fd, n, maj, min;

	snprintf(p, sizeof(p), "/sys/class/tty/%s/dev", name);
	fd = open(p, O_RDONLY);
	if (fd < 0)
		return;
	n = read(fd, buf, sizeof(buf) - 1);
	close(fd);
	if (n <= 0)
		return;
	buf[n] = 0;
	if (sscanf(buf, "%d:%d", &maj, &min) == 2) {
		snprintf(p, sizeof(p), "/dev/%s", name);
		unlink(p);
		node(p, S_IFCHR | 0600, maj, min);
	}
}

/* Child: copy /proc/kmsg to the ACM serial port forever */
static void kmsg_to_acm(void)
{
	char buf[4096];
	int in, outfd = -1, n;

	if (fork() != 0)
		return;
	in = open("/proc/kmsg", O_RDONLY);
	for (;;) {
		if (outfd < 0) {
			outfd = open("/dev/ttyGS0", O_WRONLY | O_NOCTTY);
			if (outfd < 0) {
				node_from_sysfs("ttyGS0");
				sleep(1);
				continue;
			}
			/* full log once, then follow */
			int all = open("/proc/last_kmsg", O_RDONLY);
			if (all >= 0) {
				write(outfd, "==== last_kmsg ====\r\n", 21);
				while ((n = read(all, buf, sizeof(buf))) > 0)
					write(outfd, buf, n);
				close(all);
				write(outfd, "\r\n==== dmesg ====\r\n", 19);
			}
		}
		n = in >= 0 ? read(in, buf, sizeof(buf)) : -1;
		if (n <= 0) {
			sleep(1);
			continue;
		}
		if (write(outfd, buf, n) < 0) {
			close(outfd);
			outfd = -1;
		}
	}
}

int main(void)
{
	int round = 0;

	mkdir("/dev", 0755);
	mkdir("/proc", 0755);
	mkdir("/sys", 0755);
	mount("proc", "/proc", "proc", 0, NULL);
	mount("sysfs", "/sys", "sysfs", 0, NULL);
	if (mount("devtmpfs", "/dev", "devtmpfs", 0, NULL) != 0) {
		node("/dev/console", S_IFCHR | 0600, 5, 1);
		node("/dev/tty0", S_IFCHR | 0600, 4, 0);
		node("/dev/kmsg", S_IFCHR | 0600, 1, 11);
	}

	say("\n==== Lumia 1520 K1: kernel 3.4 + init alive ====\n");
	usb_acm();
	sleep(2);
	kmsg_to_acm();

	for (;;) {
		out("/dev/tty0", "\n---- K1 status #%d ----\n", round++);
		cat_to_tty("/proc/version", 1);
		cat_to_tty("/proc/uptime", 1);
		cat_to_tty("/sys/devices/system/cpu/online", 1);
		cat_to_tty("/proc/meminfo", 3);
		cat_to_tty("/sys/class/android_usb/android0/state", 1);
		cat_to_tty("/sys/class/power_supply/battery/capacity", 1);
		cat_to_tty("/sys/class/power_supply/battery/voltage_now", 1);
		while (waitpid(-1, NULL, WNOHANG) > 0)
			;
		sleep(5);
	}
	return 0;
}
